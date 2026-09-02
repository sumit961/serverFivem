[CmdletBinding()] param([int]$TimeoutSeconds=0)
. (Join-Path $PSScriptRoot 'Common.ps1')
$config=Read-CmRuntimeConfig;if($TimeoutSeconds-le 0){$TimeoutSeconds=[int]$config.startupTimeoutSeconds};$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$state=Read-CmRuntimeState
while((Get-Date)-lt $deadline){
 if(-not @(Get-CmOwnedProcesses $config).Count){Start-Sleep -Seconds 2;continue};$log=Get-CmConsoleLog $config;if(-not $log){Start-Sleep -Seconds 2;continue}
 $text=Get-Content -Raw -LiteralPath $log.FullName;$start=[Math]::Min([int64]$state.logStartOffset,[Text.Encoding]::UTF8.GetByteCount($text));$recent=if($start-lt $text.Length){$text.Substring([int]$start)}else{''}
 $fatal=$recent-match '(?im)Failed to start resource|Could not load|server thread hitch warning.*fatal|terminat(?:ed|ing)';$loading=$recent-match '(?im)Started resource|Creating script environments|server license key authentication succeeded';$coreOk=$true;foreach($resource in $config.expectedCoreResources){if($recent-notmatch "(?im)Started resource $([regex]::Escape($resource))"){$coreOk=$false}}
 if($loading-and$coreOk-and-not$fatal){$state.status='ready';$state.logPath=$log.FullName;Write-CmRuntimeState $state;Write-Output 'SERVER_READY';exit 0};Start-Sleep -Seconds 2
}
$state.status='startup_failed_or_timed_out';Write-CmRuntimeState $state;Write-Output 'SERVER_STARTUP_FAILED_OR_TIMED_OUT';exit 1
