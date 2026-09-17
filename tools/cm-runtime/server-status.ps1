[CmdletBinding()] param([switch]$Json)
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-CmRuntimeConfig; $owned = @(Get-CmOwnedProcesses $config); $all = @(Get-CmFxProcesses); $log = Get-CmConsoleLog $config
$ownedIds = @($owned | ForEach-Object { $_.ProcessId })
$otherIds = @($all | Where-Object { $_.ProcessId -notin $ownedIds } | ForEach-Object { $_.ProcessId })
$result = [ordered]@{ status=$(if ($owned.Count) {'SERVER_RUNNING'} else {'SERVER_NOT_RUNNING'}); ownedProcessIds=$ownedIds; unrelatedFxServerProcessIds=$otherIds; profile=$config.txAdminProfile; logPath=$(if ($log) {$log.FullName} else {$null}); logLastWriteUtc=$(if ($log) {$log.LastWriteTimeUtc.ToString('o')} else {$null}) }
if ($Json) { $result | ConvertTo-Json -Depth 5 } else { $result.GetEnumerator() | ForEach-Object { '{0}: {1}' -f $_.Key, ($_.Value -join ', ') } }
