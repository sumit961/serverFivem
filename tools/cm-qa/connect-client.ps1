[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$WaitForCharacter
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
. (Join-Path $PSScriptRoot '..\cm-runtime\Common.ps1')
Set-StrictMode -Version Latest
$safety=Test-CmQaRuntimeSafety
if(-not $safety.ok){ throw "FIVEM_CLIENT_QA_BLOCKED: $($safety.reason)" }
$config=Read-CmRuntimeConfig
$port=if($Port -gt 0){$Port}else{[int]$config.fivemPort}
if($port -lt 1 -or $port -gt 65535){throw 'INVALID_LOCAL_FIVEM_PORT'}
$owned=@(Get-CmOwnedProcesses $config)
if(-not $owned.Count){throw 'FIVEM_CLIENT_QA_BLOCKED: local development server is not running.'}
$uri="fivem://connect/127.0.0.1:$port"
Start-Process -FilePath $uri
Write-Output 'FIVEM_CLIENT_CONNECT_STARTED'
Write-Output ("Endpoint=127.0.0.1:{0}" -f $port)
if (-not $WaitForCharacter) {
    Write-Output 'ONE_TIME_SETUP: log into FiveM and create/select the configured QA character. The harness will pair it by character ID; no source ID lookup is required.'
    return
}

$runtimeConfig = Read-CmQaRuntimeConfig
$configuredCharacterId = $null
if ($runtimeConfig -and $runtimeConfig.PSObject.Properties.Name -contains 'qa' -and $runtimeConfig.qa -and $runtimeConfig.qa.PSObject.Properties.Name -contains 'characterId') {
    try {
        $candidate = [int64]$runtimeConfig.qa.characterId
        if ($candidate -ge 1 -and $candidate -le 2147483647) { $configuredCharacterId = $candidate }
    } catch { }
}
if (-not $configuredCharacterId) { throw 'QA_CHARACTER_NOT_CONFIGURED: set qa.autoPair=true and qa.characterId in ignored tools/cm-runtime/runtime.local.json.' }
if (-not ($runtimeConfig.qa.PSObject.Properties.Name -contains 'autoPair' -and $runtimeConfig.qa.autoPair -eq $true)) { throw 'QA_CHARACTER_AUTO_PAIR_DISABLED: set qa.autoPair=true in ignored tools/cm-runtime/runtime.local.json.' }

$send = Join-Path $PSScriptRoot '..\cm-runtime\send-command.ps1'
function Invoke-QaSend([string]$Command) {
    Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$send,$Command)
}

$paired = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $pair = Invoke-QaSend ('cm_qa_pair_character ' + $configuredCharacterId)
    if ($pair.output -match 'QA_CLIENT_PAIR_REQUESTED') { $paired = $true; break }
    if ($pair.output -match 'QA_CLIENT_PAIR_AMBIGUOUS') { throw 'QA_CLIENT_PAIR_AMBIGUOUS' }
    Start-Sleep -Milliseconds 1000
}
if (-not $paired) { throw 'QA_CLIENT_NOT_CONNECTED: log into FiveM and select the configured QA character; no login or character-selection clicks were attempted.' }

for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $status = Invoke-QaSend 'cm_qa_status'
    if ($status.output -match '"registeredClients"\s*:\s*1' -and $status.output -match '"readyClients"\s*:\s*1') {
        Write-Output 'QA_CLIENT_PAIR_READY'
        return
    }
    Start-Sleep -Milliseconds 500
}
throw 'QA_CLIENT_NOT_READY: exact character was paired but the client readiness handshake did not complete within 15 seconds.'
