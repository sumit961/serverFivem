[CmdletBinding(SupportsShouldProcess)] param()
. (Join-Path $PSScriptRoot 'Common.ps1')
$config=Read-CmRuntimeConfig; $owned=@(Get-CmOwnedProcesses $config); $state=Read-CmRuntimeState
if($state.process -and $state.process.id){$owned=@($owned|Where-Object{$_.ProcessId-eq[int]$state.process.id})}
if (-not $owned.Count) { Write-Output 'SERVER_NOT_RUNNING'; exit 0 }
foreach ($process in $owned) { if ($PSCmdlet.ShouldProcess("FXServer process $($process.ProcessId) for profile $($config.txAdminProfile)",'Stop')) { Stop-Process -Id $process.ProcessId -ErrorAction Stop; Write-Output "SERVER_STOPPED processId=$($process.ProcessId)" } }
$state=Read-CmRuntimeState; $state.status='stopped'; Write-CmRuntimeState $state
