[CmdletBinding()]
param([string[]]$ChangedResource, [switch]$StartIfNeeded)

. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-CmRuntimeConfig
if (Test-Path (Join-Path $PSScriptRoot '..\cm-autopilot\STOP')) { Write-Output 'AUTOPILOT_STOP_REQUESTED'; exit 0 }
if (-not @(Get-CmOwnedProcesses $config).Count) {
    if ($StartIfNeeded) { & (Join-Path $PSScriptRoot 'start-server.ps1') } else { Write-Output 'SERVER_NOT_RUNNING'; exit 1 }
}
$state = Read-CmRuntimeState
if ($ChangedResource) { $state.changedResources = @($ChangedResource | Select-Object -Unique); Write-CmRuntimeState $state }

function Read-LogWindow([string]$Path, [int64]$Offset) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $Offset = [Math]::Min($Offset, $stream.Length); $stream.Seek($Offset, [IO.SeekOrigin]::Begin) | Out-Null
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

foreach ($resource in @($state.changedResources)) {
    if ($resource -notmatch '^(cm-[a-z0-9_-]+|rn-vehicleshop)$') { throw "Unsafe resource name: $resource" }
    $log = Get-CmConsoleLog $config; if (-not $log) { throw 'CURRENT_FXSERVER_CONSOLE_LOG_NOT_FOUND' }
    $offset = [int64]$log.Length
    $bridgeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'send-command.ps1') "restart $resource" 2>&1
    $bridgeOutput | ForEach-Object { Write-Output (Protect-CmRuntimeText ([string]$_)) }
    if ($LASTEXITCODE -ne 0) { throw "RCon bridge process failed with exit code $LASTEXITCODE" }
    Start-Sleep -Seconds ([int]$config.consoleObservationSeconds)
    $window = Read-LogWindow $log.FullName $offset
    $stopped = $window -match "(?im)(?:Stopping|Stopped) resource $([regex]::Escape($resource))\b"
    $started = $window -match "(?im)Started resource $([regex]::Escape($resource))\b"
    if (-not ($stopped -and $started)) { Write-Output "RUNTIME_RESTART_NOT_CONFIRMED resource=$resource"; exit 3 }
    Write-Output "RUNTIME_RESTART_CONFIRMED resource=$resource"
    & (Join-Path $PSScriptRoot 'read-errors.ps1') -FromOffset $offset
    if ($LASTEXITCODE -eq 2) { Write-Output "CODEX_REPAIR_REQUIRED resource=$resource"; exit 2 }
}
Write-Output 'RUNTIME_CONSOLE_CLEAN'
Write-Output 'MANUAL_FIVEM_GAMEPLAY_TEST_REQUIRED_FOR_CLIENT_VISUAL_OR_INTERACTION_BEHAVIOR'
