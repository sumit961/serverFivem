[CmdletBinding()] param([switch]$NoWait)
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-CmRuntimeConfig
if ($config.developmentOnly -ne $true) { throw 'Safety stop: developmentOnly must be true.' }
$owned = @(Get-CmOwnedProcesses $config)
if ($owned.Count) {
    $log=Get-CmConsoleLog $config;$state=Read-CmRuntimeState;$state.executionId=New-CmExecutionId;$state.status='running';$state.startTimestamp=(Get-Date).ToUniversalTime().ToString('o');$state.process=[ordered]@{id=$owned[0].ProcessId;executable=$config.fxServerPath;profile=$config.txAdminProfile};$state.logPath=$(if($log){$log.FullName}else{$null});$state.logStartOffset=$(if($log){$log.Length}else{0});$state.commandsSent=@();$state.errorsFound=@();$state.repairsAttempted=@();Write-CmRuntimeState $state
    $lastRun="# Last runtime run`n`n- Execution ID: $($state.executionId)`n- Started: $($state.startTimestamp)`n- Result: SERVER_ALREADY_RUNNING`n- Process: $($owned[0].ProcessId)`n- Console: $($state.logPath)`n";[IO.File]::WriteAllText((Join-Path (Get-CmRuntimePaths).StateRoot 'LAST_RUN.md'),$lastRun,[Text.UTF8Encoding]::new($false))
    Write-Output 'SERVER_ALREADY_RUNNING'; & (Join-Path $PSScriptRoot 'server-status.ps1'); exit 0
}
if (-not $config.txAdminProfile) { throw 'No txAdmin development profile was found. Set txAdminProfile in tools/cm-runtime/runtime.local.json.' }
if (-not $config.fxServerPath -or -not (Test-Path -LiteralPath $config.fxServerPath)) { throw 'FXServer.exe was not discovered. Copy runtime.example.json to runtime.local.json and set fxServerPath to the local development artifact.' }
$log = Get-CmConsoleLog $config; $offset = if ($log) { $log.Length } else { 0 }; $id = New-CmExecutionId
$process = Start-Process -FilePath $config.fxServerPath -ArgumentList @('+set','serverProfile',$config.txAdminProfile) -WorkingDirectory (Split-Path -Parent $config.fxServerPath) -WindowStyle Hidden -PassThru
$state = Read-CmRuntimeState; $state.executionId=$id; $state.status='starting'; $state.startTimestamp=(Get-Date).ToUniversalTime().ToString('o'); $state.process=[ordered]@{ id=$process.Id; executable=$config.fxServerPath; profile=$config.txAdminProfile }; $state.logPath=$(if($log){$log.FullName}else{$null}); $state.logStartOffset=$offset; $state.commandsSent=@(); $state.errorsFound=@(); $state.repairsAttempted=@(); Write-CmRuntimeState $state
Write-Output "TXADMIN_STARTED executionId=$id processId=$($process.Id)"
$lastRun="# Last runtime run`n`n- Execution ID: $id`n- Started: $($state.startTimestamp)`n- Result: TXADMIN_STARTED`n- Process: $($process.Id)`n- Console: $($state.logPath)`n";[IO.File]::WriteAllText((Join-Path (Get-CmRuntimePaths).StateRoot 'LAST_RUN.md'),$lastRun,[Text.UTF8Encoding]::new($false))
if (-not $NoWait) { & (Join-Path $PSScriptRoot 'wait-ready.ps1') -TimeoutSeconds ([int]$config.startupTimeoutSeconds) }
