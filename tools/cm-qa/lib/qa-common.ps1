Set-StrictMode -Version Latest

function Get-CmQaRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

function Get-CmQaOutputRoot {
    $root = Join-Path (Get-CmQaRepoRoot) 'cm-agent-out\qa'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Get-CmQaRunId {
    return (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
}

function Get-CmQaRunDirectory([string]$RunId) {
    $path = Join-Path (Get-CmQaOutputRoot) ('runs\' + $RunId)
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Protect-CmQaText([string]$Text) {
    if ($null -eq $Text) { return '' }
    $result = $Text
    foreach ($pattern in @(
        '(?im)^.*server\.local\.cfg.*$',
        '(?im)^.*(?:password|passwd|secret|token|api[_-]?key|license[_-]?key)\s*[:=].*$',
        '(?i)(mysql(?:\+\w+)?://)[^\s]+',
        '(?i)(authorization:\s*)(?:bearer\s+)?[^\s]+'
    )) { $result = [regex]::Replace($result, $pattern, '[REDACTED]') }
    return $result
}

function Write-CmQaJson([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Invoke-CmQaCommand([string]$FilePath, [string[]]$Arguments) {
    $started = Get-Date
    if (-not (Get-Command $FilePath -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $FilePath)) {
        return [ordered]@{ id=$FilePath; result='BLOCKED'; exitCode=2; durationMs=0; output='command_not_found' }
    }
    $output = & $FilePath @Arguments 2>&1 | Out-String
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $safeOutput = (Protect-CmQaText $output).Trim()
    if ($safeOutput.Length -gt 6000) { $safeOutput = '[truncated; showing tail]' + [Environment]::NewLine + $safeOutput.Substring($safeOutput.Length - 6000) }
    return [ordered]@{
        id = ($FilePath + ' ' + ($Arguments -join ' ')).Trim()
        result = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        exitCode = $exitCode
        durationMs = [int]((New-TimeSpan -Start $started -End (Get-Date)).TotalMilliseconds)
        output = $safeOutput
    }
}

function Get-CmQaChangedPaths {
    $paths = [Collections.Generic.List[string]]::new()
    $diff = & git -C (Get-CmQaRepoRoot) diff --name-only HEAD 2>$null
    foreach ($path in @($diff)) { if ($path) { $paths.Add(([string]$path).Replace('\','/')) } }
    $status = & git -C (Get-CmQaRepoRoot) status --porcelain=v1 2>$null
    foreach ($line in @($status)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
        $value = [string]$line
        $path = $value.Substring(3).Trim()
        if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
        $paths.Add($path.Replace('\','/'))
    }
    return @($paths | Sort-Object -Unique)
}

function Get-CmQaResourcesFromPaths([string[]]$Paths) {
    $resources = [Collections.Generic.List[string]]::new()
    foreach ($path in @($Paths)) {
        if ([string]$path -match '^resources/\[[^/]+\]/([^/]+)/') { $resources.Add($Matches[1]) }
    }
    return @($resources | Sort-Object -Unique)
}

function Get-CmQaScenarioResource([string]$Scenario) {
    switch -Regex ($Scenario) {
        '^qa\.' { return 'cm-qa' }
        '^electrician\.' { return 'cm-electrician' }
        '^license\.' { return 'cm-license' }
        '^fishing\.' { return 'cm-fishing' }
        default { return $null }
    }
}

function Read-CmQaRuntimeConfig {
    $path = Join-Path (Get-CmQaRepoRoot) 'tools\cm-runtime\runtime.local.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Read-CmQaBaseline {
    $path = Join-Path (Get-CmQaRepoRoot) 'agent-docs\qa\BASELINE.json'
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ schemaVersion=1; knownIssues=@() } }
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Get-CmQaBaselineIssue([string]$Tool, [string]$Output) {
    $baseline = Read-CmQaBaseline
    foreach ($issue in @($baseline.knownIssues)) {
        $matched = $false
        if ($issue.tool -eq $Tool -and $Output -and $Output -match [regex]::Escape([string]$issue.files[0])) {
            if ($Tool -eq 'cm-validate' -and $Output -match 'ensured resource not found:\s*\[bags\]') { $matched = $true }
            if ($Tool -eq 'git-diff-check' -and $Output -match 'new blank line at EOF') { $matched = $true }
        }
        if ($matched) { return $issue }
    }
    return $null
}

function Get-CmQaPathFromDiffCheck([string]$Line) {
    if (-not $Line) { return $null }
    $match = [regex]::Match($Line, '(?<path>resources/[^:]+|server\.cfg):(?<line>[0-9]+):\s*(?<message>.+)$')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{ path=$match.Groups['path'].Value.Replace('\','/'); line=[int]$match.Groups['line'].Value; message=$match.Groups['message'].Value }
}

function Get-CmQaResourcePaths([string[]]$Resources) {
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($resource in @($Resources)) {
        if ($resource) {
            foreach ($path in Get-CmQaChangedPaths) {
                if ($path -match ('^resources/[^/]+/' + [regex]::Escape($resource) + '/')) { $paths.Add($path) }
            }
        }
    }
    return @($paths | Sort-Object -Unique)
}

function Get-CmQaPython {
    $stored = Join-Path (Get-CmQaRepoRoot) 'graphify-out\.graphify_python'
    if (Test-Path -LiteralPath $stored) {
        $candidate = (Get-Content -Raw -LiteralPath $stored).Trim()
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    $uvCandidate = Join-Path $env:APPDATA 'uv\tools\graphifyy\Scripts\python.exe'
    if (Test-Path -LiteralPath $uvCandidate) { return $uvCandidate }
    return 'python'
}

function Test-CmQaRuntimeSafety {
    $config = Read-CmQaRuntimeConfig
    if ($null -eq $config) { return [ordered]@{ ok=$false; reason='runtime.local.json_missing' } }
    if ($config.developmentOnly -ne $true) { return [ordered]@{ ok=$false; reason='developmentOnly_true_required' } }
    if ([string]$config.host -notin @('127.0.0.1','localhost','::1')) { return [ordered]@{ ok=$false; reason='rcon_must_be_loopback' } }
    return [ordered]@{ ok=$true; reason='development_runtime_verified'; config=$config }
}

function Save-CmQaLayer([string]$RunId, [string]$Layer, $LayerResult) {
    $path = Join-Path (Get-CmQaRunDirectory $RunId) ($Layer + '.json')
    Write-CmQaJson $path $LayerResult
    return $path
}

function Rotate-CmQaArtifacts {
    $root = Get-CmQaOutputRoot
    $runs = Join-Path $root 'runs'
    if (Test-Path -LiteralPath $runs) {
        Get-ChildItem -LiteralPath $runs -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Skip 8 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($folder in @((Join-Path $root 'screenshots'), (Join-Path $root 'client-screenshots'))) {
        if (Test-Path -LiteralPath $folder) {
            Get-ChildItem -LiteralPath $folder -File -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -Skip 40 | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}
