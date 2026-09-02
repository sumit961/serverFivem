[CmdletBinding()] param([int]$Tail=100,[string]$Resource,[switch]$Follow)
. (Join-Path $PSScriptRoot 'Common.ps1')
$log=Get-CmConsoleLog (Read-CmRuntimeConfig); if(-not $log){throw 'CURRENT_FXSERVER_CONSOLE_LOG_NOT_FOUND'}
Write-Output "CONSOLE_LOG $($log.FullName)"
if($Follow -and -not $Resource){Get-Content -LiteralPath $log.FullName -Tail $Tail -Wait | ForEach-Object {Protect-CmRuntimeText $_}; exit}
$lines=Get-Content -LiteralPath $log.FullName -Tail $Tail
if($Resource){$safe=[regex]::Escape($Resource);$lines=$lines|Where-Object{$_ -match "(?i)(\[$safe\]|$safe|script:$safe)"}}
$lines|ForEach-Object{Protect-CmRuntimeText $_}
