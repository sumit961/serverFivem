[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnly,
    [string]$Goal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StopRequested = $false
$script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RepoRoot = (Resolve-Path (Join-Path $script:ScriptRoot '..\..')).Path
$script:StateRoot = Join-Path $script:RepoRoot 'agent-docs\autopilot'
$script:StopFile = Join-Path $script:ScriptRoot 'STOP'
$script:ConfigPath = Join-Path $script:ScriptRoot 'config.json'
$script:StatePath = Join-Path $script:StateRoot 'STATE.json'

function Read-JsonFile([string]$Path) {
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Write-Utf8File([string]$Path, [string]$Content) {
    $temporary = "$Path.tmp"
    [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Force -LiteralPath $temporary -Destination $Path
}

function Write-State($State) {
    $State.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    Write-Utf8File $script:StatePath (($State | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

function Get-RepoStatus {
    $lines = & git -C $script:RepoRoot status --short 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git status failed: $($lines -join ' ')" }
    return ($lines -join [Environment]::NewLine)
}

function Protect-LogText([string]$Text) {
    if ($null -eq $Text) { return '' }
    $result = $Text
    $patterns = @(
        '(?im)^.*server\.local\.cfg.*$',
        '(?im)^.*(?:password|passwd|secret|token|api[_-]?key|license[_-]?key)\s*[:=].*$',
        '(?i)(mysql(?:\+\w+)?://)[^\s]+',
        '(?i)(authorization:\s*)(?:bearer\s+)?[^\s]+'
    )
    foreach ($pattern in $patterns) { $result = [regex]::Replace($result, $pattern, '[REDACTED]') }
    return $result
}

function Read-ContextFile([string]$RelativePath) {
    $path = Join-Path $script:RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return "[missing: $RelativePath]" }
    return Get-Content -Raw -LiteralPath $path
}

function New-CyclePrompt([string]$Phase, [int]$Cycle, [string]$PreviousResult) {
    $phasePrompt = switch ($Phase) {
        'planning' { 'tools\cm-autopilot\PLANNER_PROMPT.md' }
        'review' { 'tools\cm-autopilot\REVIEW_PROMPT.md' }
        default { 'tools\cm-autopilot\EXECUTOR_PROMPT.md' }
    }
    $config = Read-JsonFile $script:ConfigPath
    $sections = [ordered]@{
        'CYCLE' = "Cycle: $Cycle`nPhase: $Phase`nMaximum repair attempts per distinct failure: $($config.maxRepairAttempts)"
        'AGENTS.md' = Read-ContextFile 'AGENTS.md'
        'MASTER PROMPT' = Read-ContextFile 'tools\cm-autopilot\MASTER_PROMPT.md'
        'PHASE PROMPT' = Read-ContextFile $phasePrompt
        'CURRENT GOAL' = Read-ContextFile 'agent-docs\autopilot\CURRENT_GOAL.md'
        'APPROVED PLAN' = Read-ContextFile 'agent-docs\autopilot\APPROVED_PLAN.md'
        'STATE' = Read-ContextFile 'agent-docs\autopilot\STATE.json'
        'COMPLETED' = Read-ContextFile 'agent-docs\autopilot\COMPLETED.md'
        'BLOCKED' = Read-ContextFile 'agent-docs\autopilot\BLOCKED.md'
        'DECISIONS' = Read-ContextFile 'agent-docs\autopilot\DECISIONS.md'
        'RUNTIME TESTS' = Read-ContextFile 'agent-docs\autopilot\RUNTIME_TESTS.md'
        'LOCAL RUNTIME STATE' = Read-ContextFile 'agent-docs\runtime\RUNTIME_STATE.json'
        'LOCAL RUNTIME ERRORS' = Read-ContextFile 'agent-docs\runtime\ERRORS.md'
        'LOCAL MANUAL TESTS' = Read-ContextFile 'agent-docs\runtime\MANUAL_TESTS.md'
        'CURRENT GIT STATUS' = Get-RepoStatus
        'PREVIOUS CYCLE RESULT' = $(if ($PreviousResult) { $PreviousResult } else { '[none]' })
    }
    $builder = [System.Text.StringBuilder]::new()
    foreach ($entry in $sections.GetEnumerator()) {
        [void]$builder.AppendLine("===== $($entry.Key) =====")
        [void]$builder.AppendLine([string]$entry.Value)
    }
    return $builder.ToString()
}

function Invoke-CodexCycle([string]$Phase, [int]$Cycle, [string]$PreviousResult) {
    if (Test-Path -LiteralPath $script:StopFile) { $script:StopRequested = $true; return $null }
    $dateFolder = Join-Path $script:ScriptRoot ("logs\" + (Get-Date -Format 'yyyy-MM-dd'))
    $cycleFolder = Join-Path $dateFolder ('cycle-{0:D4}-{1}' -f $Cycle, $Phase)
    New-Item -ItemType Directory -Force -Path $cycleFolder | Out-Null
    $prompt = New-CyclePrompt $Phase $Cycle $PreviousResult
    Write-Utf8File (Join-Path $cycleFolder 'prompt.md') (Protect-LogText $prompt)
    Write-Utf8File (Join-Path $cycleFolder 'before-status.txt') (Protect-LogText (Get-RepoStatus))
    $lastMessage = Join-Path $cycleFolder 'last-message.txt'
    $outputLog = Join-Path $cycleFolder 'codex-output.log'

    Write-Host "`nStarting $Phase cycle $Cycle..." -ForegroundColor Cyan
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $prompt | & codex exec -C $script:RepoRoot --approve-for-me --color never -o $lastMessage - 2>&1 |
            ForEach-Object { $line = Protect-LogText ([string]$_); Add-Content -LiteralPath $outputLog -Value $line -Encoding utf8; Write-Host $line }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    Write-Utf8File (Join-Path $cycleFolder 'exit-code.txt') ([string]$exitCode)
    Write-Utf8File (Join-Path $cycleFolder 'after-status.txt') (Protect-LogText (Get-RepoStatus))
    if ($exitCode -ne 0) { throw "Codex $Phase cycle $Cycle exited with code $exitCode. See $cycleFolder" }
    if (Test-Path -LiteralPath $lastMessage) { return Protect-LogText (Get-Content -Raw -LiteralPath $lastMessage) }
    return '[cycle completed without a final message]'
}

function Set-PlanStatus([string]$Status) {
    $path = Join-Path $script:StateRoot 'APPROVED_PLAN.md'
    $content = Get-Content -Raw -LiteralPath $path
    if ($content -match '(?m)^status\s*=\s*\S+') {
        $content = [regex]::Replace($content, '(?m)^status\s*=\s*\S+', "status = $Status", 1)
    } else {
        $content = "status = $Status`r`n`r`n$content"
    }
    Write-Utf8File $path $content
}

function Reset-GoalState([string]$GoalText) {
    $now = (Get-Date).ToUniversalTime().ToString('o')
    Write-Utf8File (Join-Path $script:StateRoot 'CURRENT_GOAL.md') "# Current goal`r`n`r`n$GoalText`r`n"
    Write-Utf8File (Join-Path $script:StateRoot 'APPROVED_PLAN.md') "status = planning`r`n`r`n# Approved plan`r`n`r`nPlanning has not completed.`r`n"
    foreach ($name in @('COMPLETED.md','BLOCKED.md','DECISIONS.md','RUNTIME_TESTS.md')) {
        $title = [IO.Path]::GetFileNameWithoutExtension($name) -replace '_',' '
        Write-Utf8File (Join-Path $script:StateRoot $name) "# $title`r`n`r`nNo entries for the current goal.`r`n"
    }
    Write-Utf8File (Join-Path $script:StateRoot 'NEXT_IDEAS.md') "# Next ideas`r`n`r`nGenerated only after final review.`r`n"
    $state = [ordered]@{ schemaVersion=1; status='planning'; cycle=0; phase='planning'; currentPlanItem=$null; repairAttempts=@{}; startedAt=$now; updatedAt=$now; lastResult=$null }
    Write-Utf8File $script:StatePath (($state | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

function Confirm-Plan {
    while ($true) {
        Write-Host "`n$(Get-Content -Raw -LiteralPath (Join-Path $script:StateRoot 'APPROVED_PLAN.md'))"
        Write-Host 'Approve this plan?'
        Write-Host '[Y] Start autonomous development'
        Write-Host '[N] Cancel'
        Write-Host '[E] Edit goal/plan'
        $answer = (Read-Host).Trim().ToUpperInvariant()
        if ($answer -eq 'Y') { return 'approve' }
        if ($answer -eq 'N') { return 'cancel' }
        if ($answer -eq 'E') { return 'edit' }
    }
}

try {
    Set-Location $script:RepoRoot
    Write-Host 'CM FIVE M AUTOPILOT' -ForegroundColor Cyan
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI was not found on PATH.' }
    $config = Read-JsonFile $script:ConfigPath
    if ($config.autoPush -ne $false) { throw 'Safety stop: config autoPush must remain false.' }

    if ($DryRun) {
        Write-Host 'Audit/dry-run mode: no Codex cycle will run and persistent state will not change.' -ForegroundColor Yellow
        $required = @('AGENTS.md','tools\cm-autopilot\MASTER_PROMPT.md','tools\cm-autopilot\PLANNER_PROMPT.md','tools\cm-autopilot\EXECUTOR_PROMPT.md','tools\cm-autopilot\REVIEW_PROMPT.md','agent-docs\autopilot\STATE.json','tools\cm-runtime\runtime-controller.ps1','agent-docs\runtime\RUNTIME_STATE.json')
        foreach ($file in $required) { if (-not (Test-Path -LiteralPath (Join-Path $script:RepoRoot $file))) { throw "Missing required file: $file" } }
        $null = Get-RepoStatus
        $null = New-CyclePrompt 'planning' 1 $(if ($Goal) { "Dry-run goal: $Goal" } else { '[dry-run]' })
        Write-Host 'Dry-run passed: configuration, repository access, prompt assembly, and Codex CLI availability are valid.' -ForegroundColor Green
        exit 0
    }

    $state = Read-JsonFile $script:StatePath
    $unfinished = @('planning','pending_approval','approved','executing','review_ready') -contains [string]$state.status
    if ($unfinished) {
        $resume = (Read-Host 'Resume current goal? [Y/N]').Trim().ToUpperInvariant()
        if ($resume -ne 'Y') { Write-Host 'Existing goal left unchanged.'; exit 0 }
    } else {
        if (-not $Goal) { Write-Host "`nWhat do you want to build?"; $Goal = Read-Host }
        if ([string]::IsNullOrWhiteSpace($Goal)) { throw 'A non-empty goal is required.' }
        Reset-GoalState $Goal.Trim()
        $state = Read-JsonFile $script:StatePath
    }

    $previousResult = if ($state.lastResult) { [string]$state.lastResult } else { '' }
    while ($state.status -eq 'planning' -or $state.status -eq 'pending_approval') {
        if ($state.status -eq 'planning') {
            $state.cycle = [int]$state.cycle + 1; Write-State $state
            $previousResult = Invoke-CodexCycle 'planning' $state.cycle $previousResult
            if ($script:StopRequested) { exit 0 }
            $plan = Get-Content -Raw -LiteralPath (Join-Path $script:StateRoot 'APPROVED_PLAN.md')
            if ($plan -notmatch '(?m)^status\s*=\s*pending_approval\s*$') { throw 'Planner did not produce a pending_approval plan.' }
            $state = Read-JsonFile $script:StatePath; $state.status = 'pending_approval'; $state.phase = 'approval'; $state.lastResult = $previousResult; Write-State $state
            if ($PlanOnly) {
                Write-Host 'Planning complete. State is pending approval.' -ForegroundColor Green
                exit 0
            }
        }

        $decision = Confirm-Plan
        if ($decision -eq 'cancel') {
            $state.status = 'cancelled'; $state.phase = 'idle'; Write-State $state
            Write-Host 'Plan cancelled; planning artifacts were preserved.'
            exit 0
        }
        if ($decision -eq 'edit') {
            $Goal = Read-Host 'Enter the revised goal'
            if ([string]::IsNullOrWhiteSpace($Goal)) { throw 'A non-empty revised goal is required.' }
            Reset-GoalState $Goal.Trim()
            $state = Read-JsonFile $script:StatePath
            $previousResult = ''
            continue
        }
        Set-PlanStatus 'approved'
        $state = Read-JsonFile $script:StatePath; $state.status = 'approved'; $state.phase = 'execution'; Write-State $state
    }

    $cyclesThisRun = 0
    while (-not $script:StopRequested) {
        if (Test-Path -LiteralPath $script:StopFile) { Write-Host 'STOP file detected; no new cycle will launch.' -ForegroundColor Yellow; break }
        $state = Read-JsonFile $script:StatePath
        if ($state.status -eq 'complete') { Write-Host 'Approved goal is complete.' -ForegroundColor Green; break }
        if ($state.status -eq 'blocked') { Write-Host 'Goal is blocked; see agent-docs/autopilot/BLOCKED.md.' -ForegroundColor Yellow; break }
        if ($config.maxCycles -gt 0 -and $cyclesThisRun -ge $config.maxCycles) { Write-Host 'Configured cycle limit reached.' -ForegroundColor Yellow; break }
        $phase = if ($state.status -eq 'review_ready') { 'review' } else { 'execution' }
        $state.status = if ($phase -eq 'review') { 'review_ready' } else { 'executing' }
        $state.phase = $phase; $state.cycle = [int]$state.cycle + 1; Write-State $state
        $previousResult = Invoke-CodexCycle $phase $state.cycle $previousResult
        if ($script:StopRequested) { break }
        $state = Read-JsonFile $script:StatePath; $state.lastResult = $previousResult; Write-State $state
        $cyclesThisRun++
        if ($config.cycleDelaySeconds -gt 0) { Start-Sleep -Seconds ([int]$config.cycleDelaySeconds) }
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    $script:StopRequested = $true
    Write-Host "`nAutopilot stopped safely. Run the command again to resume." -ForegroundColor Yellow
    exit 130
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Set-Location $script:RepoRoot
}
