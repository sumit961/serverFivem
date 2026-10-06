[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [string[]]$Scenario
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$checks = [Collections.Generic.List[object]]::new()
$safety = Test-CmQaRuntimeSafety
$send = Join-Path $PSScriptRoot '..\cm-runtime\send-command.ps1'
$driver = Join-Path $PSScriptRoot 'client-driver.ps1'
$screens = Join-Path (Get-CmQaOutputRoot) 'client-screenshots'
$scenarioIds = @($Scenario | ForEach-Object { ([string]$_ -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$runtimePath = Join-Path (Get-CmQaRunDirectory $RunId) 'runtime.json'
$runtimeActions = $null
if (Test-Path -LiteralPath $runtimePath) {
    try { $runtimeActions = (Get-Content -Raw -LiteralPath $runtimePath | ConvertFrom-Json).runtime } catch { $runtimeActions = $null }
}
$registrationInvalidated = $null -ne $runtimeActions -and $runtimeActions.clientRegistrationInvalidated -eq $true
$pairingSummary = [ordered]@{ configuredCharacterId=$null; connected=$false; paired=$false; ready=$false; status='QA_CHARACTER_NOT_CONFIGURED' }
$pairBlockStatus = $null

function Invoke-QaSend([string]$Command) {
    return Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$send,$Command)
}

function Get-QaStatusPayload($Check) {
    if (-not $Check -or -not $Check.output) { return $null }
    $line = @($Check.output -split "`r?`n" | Where-Object { $_ -match '\[CM-QA\] STATUS\s+' } | Select-Object -Last 1)
    if (-not $line) { return $null }
    $json = [regex]::Replace([string]$line, '^.*\[CM-QA\] STATUS\s+', '')
    try { return $json | ConvertFrom-Json } catch { return $null }
}

function Get-QaStatusCount($Payload, [string]$Name) {
    if ($null -eq $Payload -or $Payload.PSObject.Properties.Name -notcontains $Name) { return 0 }
    return [int]$Payload.$Name
}

function Wait-QaScenarioReady([string]$ScenarioId) {
    $expected = if ($ScenarioId -eq 'qa.client.input-smoke') { 'E_PRESS' } elseif ($ScenarioId -eq 'qa.client.hold-smoke') { 'E_HOLD' } else { 'E_HOLD' }
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $statusCheck = Invoke-QaSend 'cm_qa_status'
        $payload = Get-QaStatusPayload $statusCheck
        $active = if ($payload -and $payload.PSObject.Properties.Name -contains 'activeClient') { $payload.activeClient } else { $null }
        if ($active -and [string]$active.scenario -eq $ScenarioId -and [string]$active.phase -eq 'ACTIVE' -and [string]$active.expectedInput -eq $expected) {
            return [ordered]@{ id='client.scenario.ready:' + $ScenarioId; result='PASS'; status='FIVEM_CLIENT_QA_ACTIVE_EXPECTING_' + $expected; output=('phase=ACTIVE; expectedInput={0}' -f $expected) }
        }
        Start-Sleep -Milliseconds 250
    }
    return [ordered]@{ id='client.scenario.ready:' + $ScenarioId; result='BLOCKED'; status='FIVEM_CLIENT_QA_SCENARIO_NOT_READY'; output=('Expected ACTIVE/{0} was not reported within 10 seconds.' -f $expected) }
}

function Invoke-PhysicalDriver([string[]]$Arguments) {
    $driverArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$driver) + $Arguments
    $result = Invoke-CmQaCommand 'powershell.exe' $driverArguments
    if ($result.result -ne 'PASS') { throw ([string]$result.output) }
    return $result
}

function Get-QaConfiguredCharacter {
    $config = Read-CmQaRuntimeConfig
    if ($null -eq $config -or $config.PSObject.Properties.Name -notcontains 'qa' -or $null -eq $config.qa) { return $null }
    $qa = $config.qa
    if ($qa.PSObject.Properties.Name -notcontains 'characterId' -or $null -eq $qa.characterId) { return $null }
    try {
        $candidate = [int64]$qa.characterId
        if ($candidate -ge 1 -and $candidate -le 2147483647 -and [math]::Truncate([double]$candidate) -eq [double]$candidate) { return $candidate }
    } catch { }
    return $null
}

function Test-QaAutoPairEnabled {
    $config = Read-CmQaRuntimeConfig
    return $null -ne $config -and $config.PSObject.Properties.Name -contains 'qa' -and $null -ne $config.qa -and $config.qa.PSObject.Properties.Name -contains 'autoPair' -and $config.qa.autoPair -eq $true
}

function Ensure-QaClientPairing {
    $configuredCharacterId = Get-QaConfiguredCharacter
    if ($configuredCharacterId) { $pairingSummary.configuredCharacterId = $configuredCharacterId }

    $initial = Invoke-QaSend 'cm_qa_status'
    $initialPayload = Get-QaStatusPayload $initial
    $registered = Get-QaStatusCount $initialPayload 'registeredClients'
    $ready = Get-QaStatusCount $initialPayload 'readyClients'
    $serverPairing = if ($initialPayload -and $initialPayload.PSObject.Properties.Name -contains 'pairing') { $initialPayload.pairing } else { $null }
    $exactExistingPair = $ready -ge 1 -and $registered -ge 1 -and ($null -eq $configuredCharacterId -or ($serverPairing -and [int64]$serverPairing.pairedCharacterId -eq $configuredCharacterId))
    if ($exactExistingPair) {
        $pairingSummary.connected = $true
        $pairingSummary.paired = $null -ne $configuredCharacterId
        $pairingSummary.ready = $true
        $pairingSummary.status = 'QA_CLIENT_PAIR_REUSED'
        $checks.Add([ordered]@{ id='client.pairing'; result='PASS'; status='QA_CLIENT_PAIR_REUSED'; output='registeredClients and readyClients already satisfy the configured pairing.' })
        return $true
    }

    if (-not $configuredCharacterId) {
        $script:pairBlockStatus = 'QA_CHARACTER_NOT_CONFIGURED'
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status='QA_CHARACTER_NOT_CONFIGURED'; output='Set qa.autoPair=true and qa.characterId in ignored tools/cm-runtime/runtime.local.json. No character was guessed.' })
        return $false
    }
    if (-not (Test-QaAutoPairEnabled)) {
        $script:pairBlockStatus = 'QA_CLIENT_NOT_PAIRED'
        $pairingSummary.status = 'QA_CHARACTER_AUTO_PAIR_DISABLED'
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status='QA_CHARACTER_AUTO_PAIR_DISABLED'; output='qa.characterId is configured but qa.autoPair is false.' })
        return $false
    }

    $pairRequest = Invoke-QaSend ('cm_qa_pair_character ' + $configuredCharacterId)
    if ($pairRequest.output -match 'QA_CLIENT_PAIR_AMBIGUOUS') {
        $script:pairBlockStatus = 'QA_CLIENT_NOT_PAIRED'
        $pairingSummary.status = 'QA_CLIENT_PAIR_AMBIGUOUS'
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status='QA_CLIENT_PAIR_AMBIGUOUS'; output=$pairRequest.output })
        return $false
    }
    if ($pairRequest.output -match 'QA_CLIENT_CHARACTER_NOT_CONNECTED') {
        $script:pairBlockStatus = 'QA_CLIENT_NOT_CONNECTED'
        $pairingSummary.status = 'QA_CLIENT_NOT_CONNECTED'
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status='QA_CLIENT_NOT_CONNECTED'; output=$pairRequest.output })
        return $false
    }
    if ($pairRequest.output -notmatch 'QA_CLIENT_PAIR_REQUESTED') {
        $script:pairBlockStatus = 'QA_CLIENT_NOT_PAIRED'
        $pairingSummary.status = 'QA_CLIENT_NOT_PAIRED'
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status='QA_CLIENT_NOT_PAIRED'; output=$pairRequest.output })
        return $false
    }

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $statusCheck = Invoke-QaSend 'cm_qa_status'
        $statusPayload = Get-QaStatusPayload $statusCheck
        $registered = Get-QaStatusCount $statusPayload 'registeredClients'
        $ready = Get-QaStatusCount $statusPayload 'readyClients'
        $serverPairing = if ($statusPayload -and $statusPayload.PSObject.Properties.Name -contains 'pairing') { $statusPayload.pairing } else { $null }
        $pairingSummary.connected = $null -ne $serverPairing -and $serverPairing.connected -eq $true
        $pairingSummary.paired = $null -ne $serverPairing -and $serverPairing.paired -eq $true
        $pairingSummary.ready = $registered -eq 1 -and $ready -eq 1
        if ($pairingSummary.ready -and $pairingSummary.paired) {
            $pairingSummary.status = 'QA_CLIENT_PAIR_READY'
            $checks.Add([ordered]@{ id='client.pairing'; result='PASS'; status='QA_CLIENT_PAIR_READY'; output=('configuredCharacterId={0}; registeredClients={1}; readyClients={2}' -f $configuredCharacterId,$registered,$ready) })
            return $true
        }
        if ($serverPairing -and $serverPairing.state -eq 'not_connected') { break }
        if ($serverPairing -and $serverPairing.state -eq 'ambiguous') { $pairingSummary.status = 'QA_CLIENT_PAIR_AMBIGUOUS'; break }
        Start-Sleep -Milliseconds 500
    }

    if ($pairingSummary.connected -and $pairingSummary.paired) {
        $script:pairBlockStatus = 'QA_CLIENT_NOT_READY'
        $pairingSummary.status = 'QA_CLIENT_NOT_READY'
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status='QA_CLIENT_NOT_READY'; output='Exact character pairing was found, but the readiness handshake did not complete within 15 seconds.' })
    } else {
        $script:pairBlockStatus = 'QA_CLIENT_NOT_PAIRED'
        if (-not $pairingSummary.status -or $pairingSummary.status -eq 'QA_CHARACTER_NOT_CONFIGURED') { $pairingSummary.status = 'QA_CLIENT_NOT_PAIRED' }
        $checks.Add([ordered]@{ id='client.pairing'; result='BLOCKED'; status=$pairingSummary.status; output='The configured character was not paired to a ready client.' })
    }
    return $false
}

function Add-ClientBlock($StatusCheck, $Payload) {
    if ($pairBlockStatus) {
        $StatusCheck.result = 'BLOCKED'; $StatusCheck.status = $pairBlockStatus
    } elseif ($registrationInvalidated) {
        $StatusCheck.result = 'BLOCKED'; $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_REREGISTRATION_REQUIRED'
    } elseif ($null -eq $Payload) {
        $StatusCheck.result = 'BLOCKED'; $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT'
    } elseif ((Get-QaStatusCount $Payload 'registeredClients') -lt 1 -and (Get-QaStatusCount $Payload 'authorizedClients') -lt 1) {
        $StatusCheck.result = 'BLOCKED'; $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT'
    } elseif ((Get-QaStatusCount $Payload 'registeredClients') -lt 1 -or (Get-QaStatusCount $Payload 'readyClients') -lt 1) {
        $StatusCheck.result = 'BLOCKED'; $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_CLIENT_NOT_READY'
    } else {
        $StatusCheck.status = 'FIVEM_CLIENT_QA_READY'
    }
    $checks.Add($StatusCheck)
    return $StatusCheck.status -eq 'FIVEM_CLIENT_QA_READY'
}

function Add-RegistrationAfterCheck([string]$ScenarioId) {
    $after = Invoke-QaSend 'cm_qa_status'
    $payload = Get-QaStatusPayload $after
    $after.id = 'client.registration.after:' + $ScenarioId
    if ($null -eq $payload -or (Get-QaStatusCount $payload 'registeredClients') -lt 1 -or (Get-QaStatusCount $payload 'readyClients') -lt 1) {
        $after.result = 'FAIL'
        $after.status = 'FIVEM_CLIENT_QA_REGISTRATION_LOST'
    } else {
        $after.status = 'FIVEM_CLIENT_QA_REGISTRATION_PRESERVED'
    }
    $checks.Add($after)
}

function Invoke-PhysicalScenario([string]$ScenarioId) {
    $preflight = Invoke-QaSend 'cm_qa_status'
    $payload = Get-QaStatusPayload $preflight
    $preflight.id = 'client.preflight:' + $ScenarioId
    if (-not (Add-ClientBlock $preflight $payload)) { return }

    $session = Join-Path (Get-CmQaRunDirectory $RunId) 'client-active.json'
    Write-CmQaJson $session ([ordered]@{ active=$true; scenario=$ScenarioId; startedAt=(Get-Date).ToUniversalTime().ToString('o') })
    try {
        $start = Invoke-QaSend ('cm_qa_run ' + $ScenarioId)
        $start.id = 'client.scenario.start:' + $ScenarioId
        if ($start.output -notmatch '"result"\s*:\s*"RUNNING"') {
            $start.result = 'BLOCKED'
            $start.status = if ($start.output -match 'no_registered_ready_client') { 'FIVEM_CLIENT_QA_BLOCKED_CLIENT_NOT_READY' } else { 'FIVEM_CLIENT_QA_SCENARIO_START_FAILED' }
            $checks.Add($start)
            return
        }
        $checks.Add($start)

        $readyCheck = Wait-QaScenarioReady $ScenarioId
        $checks.Add($readyCheck)
        if ($readyCheck.result -ne 'PASS') {
            $cancel = Invoke-QaSend 'cm_qa_cancel'
            $cancel.id = 'client.scenario.ready.cleanup:' + $ScenarioId
            $checks.Add($cancel)
            return
        }

        $safeName = $ScenarioId.Replace('.','-')
        $before = Join-Path $screens ("{0}-before.png" -f $ScenarioId)
        $during = Join-Path $screens ("{0}-during.png" -f $ScenarioId)
        $after = Join-Path $screens ("{0}-after.png" -f $ScenarioId)
        $capture = Invoke-PhysicalDriver @('-Action','Press','-Key','F9','-RunId',$RunId,'-CaptureOnly','-ScreenshotPath',$before)
        $capture.id = 'client.screenshot.before:' + $ScenarioId; $checks.Add($capture)
        if ($ScenarioId -eq 'qa.client.input-smoke') {
            $press = Invoke-PhysicalDriver @('-Action','Press','-Key','E','-RunId',$RunId,'-ScreenshotPath',$during)
            $press.id = 'client.physical.e:' + $ScenarioId; $checks.Add($press)
            Start-Sleep -Milliseconds 500
            $esc = Invoke-PhysicalDriver @('-Action','Press','-Key','ESC','-RunId',$RunId,'-ScreenshotPath',$after)
            $esc.id = 'client.physical.esc:' + $ScenarioId; $checks.Add($esc)
        } elseif ($ScenarioId -eq 'qa.client.hold-smoke') {
            $hold = Invoke-PhysicalDriver @('-Action','Hold','-Key','E','-HoldMilliseconds','3000','-RunId',$RunId,'-ScreenshotPath',$during)
            $hold.id = 'client.physical.e.hold:' + $ScenarioId; $checks.Add($hold)
            $captureAfter = Invoke-PhysicalDriver @('-Action','Press','-Key','F9','-RunId',$RunId,'-CaptureOnly','-ScreenshotPath',$after)
            $captureAfter.id = 'client.screenshot.after:' + $ScenarioId; $checks.Add($captureAfter)
        } elseif ($ScenarioId -eq 'electrician.panel.physical-repair' -or $ScenarioId -eq 'electrician.panel.early-release' -or $ScenarioId -eq 'electrician.panel.shock') {
            Start-Sleep -Milliseconds 1500
            $holdMs = if ($ScenarioId -eq 'electrician.panel.physical-repair') { 3300 } elseif ($ScenarioId -eq 'electrician.panel.shock') { 1000 } else { 500 }
            $hold = Invoke-PhysicalDriver @('-Action','Hold','-Key','E','HoldMilliseconds',([string]$holdMs),'-RunId',$RunId,'-ScreenshotPath',$during)
            $hold.id = 'client.physical.e.hold:' + $ScenarioId; $checks.Add($hold)
            $captureAfter = Invoke-PhysicalDriver @('-Action','Press','-Key','F9','-RunId',$RunId,'-CaptureOnly','-ScreenshotPath',$after)
            $captureAfter.id = 'client.screenshot.after:' + $ScenarioId; $checks.Add($captureAfter)
        } else {
            $checks.Add([ordered]@{ id='client.scenario.unsupported:' + $ScenarioId; result='BLOCKED'; status='MANUAL_JUDGMENT_REQUIRED'; output='No physical client driver contract is registered for this scenario.' })
            return
        }

        $deadline = (Get-Date).AddSeconds(8); $final = $null
        while ((Get-Date) -lt $deadline) {
            $final = Invoke-QaSend 'cm_qa_report'
            if ($final.output -match 'FIVEM_CLIENT_QA_PASS|"result"\s*:\s*"CANCELLED"') { break }
            Start-Sleep -Milliseconds 500
        }
        if ($final) {
            $final.id = 'client.server.assertion:' + $ScenarioId
            if ($ScenarioId -eq 'qa.client.input-smoke' -and $final.output -match '"result"\s*:\s*"CANCELLED"') {
                $final.result = 'PASS'; $final.status = 'FIVEM_CLIENT_QA_CANCELLED_ESCAPE'
            } elseif ($final.output -match 'FIVEM_CLIENT_QA_PASS') {
                $final.result = 'PASS'; $final.status = 'FIVEM_CLIENT_QA_PASS'
            } else {
                $final.result = 'FAIL'; $final.status = 'FIVEM_CLIENT_QA_SCENARIO_TIMEOUT'
            }
            $checks.Add($final)
        }
    } catch {
        $message = $_.Exception.Message
        $status = if ($message -match 'CLIENT_DRIVER_BLOCKED') { 'CLIENT_DRIVER_BLOCKED' } else { 'FIVEM_CLIENT_QA_FAIL' }
        $checks.Add([ordered]@{ id='client.driver:' + $ScenarioId; result=if($status.StartsWith('BLOCKED')){'BLOCKED'}else{'FAIL'}; status=$status; output=$message })
        $cancel = Invoke-QaSend 'cm_qa_cancel'
        $cancel.id = 'client.driver.cleanup:' + $ScenarioId; $checks.Add($cancel)
    } finally {
        if (Test-Path -LiteralPath $session) { Remove-Item -LiteralPath $session -Force -ErrorAction SilentlyContinue }
    }
    Add-RegistrationAfterCheck $ScenarioId
}

if (-not $safety.ok) {
    $checks.Add([ordered]@{ id='client.safety'; result='BLOCKED'; status='FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT'; output=$safety.reason })
} elseif ($scenarioIds.Count) {
    $pairReady = Ensure-QaClientPairing
    foreach ($scenarioId in $scenarioIds) { Invoke-PhysicalScenario $scenarioId }
} else {
    $status = Invoke-QaSend 'cm_qa_status'
    $payload = Get-QaStatusPayload $status
    $status.id = 'cm_qa_status'
    [void](Add-ClientBlock $status $payload)
}

$failed = @($checks | Where-Object result -eq 'FAIL')
$blocked = @($checks | Where-Object result -eq 'BLOCKED')
$preserved = @($checks | Where-Object { $_.PSObject.Properties.Name -contains 'status' -and $_.status -eq 'FIVEM_CLIENT_QA_REGISTRATION_PRESERVED' }).Count -eq $scenarioIds.Count -and $scenarioIds.Count -gt 0
$layer = [ordered]@{
    name = 'client'
    result = if ($failed.Count) { 'FAIL' } elseif ($blocked.Count) { 'BLOCKED' } else { 'PASS' }
    status = if ($failed.Count) { 'FIVEM_CLIENT_QA_FAIL' } elseif ($blocked.Count) { 'FIVEM_CLIENT_QA_BLOCKED' } else { 'FIVEM_CLIENT_QA_PASS' }
    checks = @($checks)
    scenarios = $scenarioIds
    physicalInput = if ($scenarioIds.Count) { $scenarioIds } else { 'NOT_RUN' }
    registrationPreserved = $preserved
    pairing = $pairingSummary
    screenshots = if (Test-Path -LiteralPath $screens) { @(Get-ChildItem -LiteralPath $screens -Filter "$RunId-*.png" -File | Select-Object -ExpandProperty FullName) } else { @() }
    evidence = @('The driver sends physical Windows key events only to an identified FiveM window while a QA run marker is active; it does not restart, disable, or unregister cm-qa.')
}
$path = Save-CmQaLayer $RunId 'client' $layer
Write-Output $path
if ($failed.Count) { exit 1 }
if ($blocked.Count) { exit 2 }
exit 0
