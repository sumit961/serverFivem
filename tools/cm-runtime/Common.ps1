Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CmRuntimePaths {
    $toolRoot = Split-Path -Parent $PSScriptRoot
    $repoRoot = (Resolve-Path (Join-Path $toolRoot '..')).Path
    [pscustomobject]@{ ToolRoot=$PSScriptRoot; RepoRoot=$repoRoot; StateRoot=(Join-Path $repoRoot 'agent-docs\runtime'); StatePath=(Join-Path $repoRoot 'agent-docs\runtime\RUNTIME_STATE.json') }
}

function Read-CmRuntimeConfig {
    $paths = Get-CmRuntimePaths
    $example = Get-Content -Raw -LiteralPath (Join-Path $paths.ToolRoot 'runtime.example.json') | ConvertFrom-Json
    $localPath = Join-Path $paths.ToolRoot 'runtime.local.json'
    if (Test-Path -LiteralPath $localPath) {
        $local = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json
        foreach ($property in $local.PSObject.Properties) { $example.($property.Name) = $property.Value }
    }
    $txData = if ($example.txDataPath) { $example.txDataPath } else { Split-Path -Parent $paths.RepoRoot }
    if (-not [IO.Path]::IsPathRooted($txData)) { $txData = Join-Path $paths.RepoRoot $txData }
    $example.txDataPath = [IO.Path]::GetFullPath($txData)
    if (-not $example.serverDataRoot) { $example.serverDataRoot = $paths.RepoRoot }
    if (-not $example.txAdminProfile) {
        $profiles = Get-ChildItem -LiteralPath $example.txDataPath -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'config.json') }
        if ($profiles.Count -eq 1) { $example.txAdminProfile = $profiles[0].Name } elseif ($profiles.Name -contains 'default') { $example.txAdminProfile = 'default' }
    }
    if (-not $example.logDirectory -and $example.txAdminProfile) { $example.logDirectory = Join-Path $example.txDataPath "$($example.txAdminProfile)\logs" }
    if ($example.logDirectory -and -not [IO.Path]::IsPathRooted($example.logDirectory)) { $example.logDirectory = Join-Path $paths.RepoRoot $example.logDirectory }
    if (-not $example.fxServerPath) {
        $roots = @((Split-Path -Parent $example.txDataPath), $example.txDataPath)
        $candidate = Get-ChildItem -LiteralPath $roots -Filter FXServer.exe -File -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($candidate) { $example.fxServerPath = $candidate.FullName }
    }
    return $example
}

function Get-CmFxProcesses {
    $cim = @(Get-CimInstance Win32_Process -Filter "Name='FXServer.exe'" -ErrorAction SilentlyContinue)
    if ($cim.Count) { return $cim }
    @(Get-Process -Name FXServer -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ ProcessId=$_.Id; ParentProcessId=$null; ExecutablePath=$(try {$_.Path}catch{$null}); CommandLine=$null } })
}

function Get-CmOwnedProcesses($Config) {
    $tx = [IO.Path]::GetFullPath($Config.txDataPath).TrimEnd('\')
    $profilePattern = '(?i)(?:serverProfile|profile)[=\s]+["'']?{0}' -f [regex]::Escape([string]$Config.txAdminProfile)
    $configuredExe = if ($Config.fxServerPath) { [IO.Path]::GetFullPath([string]$Config.fxServerPath) } else { $null }
    @(Get-CmFxProcesses | Where-Object { ($_.CommandLine -and (($_.CommandLine -like "*$tx*") -or ($Config.txAdminProfile -and $_.CommandLine -match $profilePattern))) -or ($configuredExe -and $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath) -eq $configuredExe) })
}

function Get-CmConsoleLog($Config) {
    if (-not $Config.logDirectory -or -not (Test-Path -LiteralPath $Config.logDirectory)) { return $null }
    $preferred = Join-Path $Config.logDirectory 'fxserver.log'
    if (Test-Path -LiteralPath $preferred) { return Get-Item -LiteralPath $preferred }
    Get-ChildItem -LiteralPath $Config.logDirectory -File -Filter 'fxserver*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Protect-CmRuntimeText([string]$Text) {
    if ($null -eq $Text) { return '' }
    $result = $Text
    foreach ($pattern in @('(?im)^.*(?:password|passwd|secret|token|api[_-]?key|license[_-]?key)\s*[:=].*$','(?i)(mysql(?:\+\w+)?://)[^\s]+','(?i)(authorization:\s*)(?:bearer\s+)?[^\s]+')) { $result = [regex]::Replace($result,$pattern,'[REDACTED]') }
    $result
}

function Read-CmRuntimeState {
    $path = (Get-CmRuntimePaths).StatePath
    if (Test-Path -LiteralPath $path) { return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json }
    [pscustomobject]@{ schemaVersion=1; executionId=$null; status='idle'; startTimestamp=$null; process=$null; logPath=$null; logStartOffset=0; changedResources=@(); commandsSent=@(); errorsFound=@(); repairsAttempted=@() }
}

function Write-CmRuntimeState($State) {
    $paths = Get-CmRuntimePaths
    New-Item -ItemType Directory -Force -Path $paths.StateRoot | Out-Null
    $State.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $json = ($State | ConvertTo-Json -Depth 12) + [Environment]::NewLine
    $temp = $paths.StatePath + '.tmp'
    [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false)); Move-Item -Force -LiteralPath $temp -Destination $paths.StatePath
}

function New-CmExecutionId {
    $prefix = 'runtime-' + (Get-Date -Format yyyyMMdd)
    $stateRoot = (Get-CmRuntimePaths).StateRoot
    $numbers = @(Get-ChildItem -LiteralPath $stateRoot -File -ErrorAction SilentlyContinue | Where-Object Name -Like "$prefix*" | ForEach-Object { if ($_.BaseName -match '(\d{3})$') { [int]$Matches[1] } })
    $state = Read-CmRuntimeState
    if ($state.executionId -match "^$([regex]::Escape($prefix))-(\d{3})$") { $numbers += [int]$Matches[1] }
    $next = if ($numbers.Count) { [int](($numbers | Measure-Object -Maximum).Maximum) + 1 } else { 1 }
    '{0}-{1:D3}' -f $prefix, $next
}
