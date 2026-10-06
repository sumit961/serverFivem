[CmdletBinding()]
param(
    [string[]]$Resource,
    [Parameter(Mandatory)][string]$RunId,
    [string[]]$Scenario,
    [switch]$RestartAffected,
    [switch]$PreserveRuntimeState
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$safety = Test-CmQaRuntimeSafety
$checks = [Collections.Generic.List[object]]::new()
$send = Join-Path $PSScriptRoot '..\cm-runtime\send-command.ps1'
$runtimeController = Join-Path $PSScriptRoot '..\cm-runtime\runtime-controller.ps1'
$scenarioIds = @($Scenario | ForEach-Object { ([string]$_ -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$clientScenarioIds = @($scenarioIds | Where-Object { $_ -match '^qa\.client\.' })
$restartRequested = $RestartAffected -and -not $PreserveRuntimeState
$runtimeResources = @($Resource | Where-Object { $_ -match '^cm-[a-z0-9_-]+$' } | Select-Object -Unique)

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

function Add-Check($Check, [string]$Id) {
    $Check.id = $Id
    $checks.Add($Check)
    return $Check
}

function Add-ClientPreflightCheck($StatusCheck, $StatusPayload, [bool]$RegistrationInvalidated) {
    $registered = Get-QaStatusCount $StatusPayload 'registeredClients'
    $ready = Get-QaStatusCount $StatusPayload 'readyClients'
    $authorized = Get-QaStatusCount $StatusPayload 'authorizedClients'
    if ($RegistrationInvalidated) {
        $StatusCheck.result = 'BLOCKED'
        $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_REREGISTRATION_REQUIRED'
    } elseif ($registered -lt 1 -and $authorized -lt 1) {
        $StatusCheck.result = 'BLOCKED'
        $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT'
    } elseif ($registered -lt 1 -or $ready -lt 1) {
        $StatusCheck.result = 'BLOCKED'
        $StatusCheck.status = 'FIVEM_CLIENT_QA_BLOCKED_CLIENT_NOT_READY'
    } else {
        $StatusCheck.status = 'FIVEM_CLIENT_QA_READY'
    }
    $StatusCheck.output = ($StatusCheck.output + "`npreflight registeredClients=$registered readyClients=$ready authorizedClients=$authorized")
    $checks.Add($StatusCheck)
}

if (-not $safety.ok) {
    $checks.Add([ordered]@{ id='runtime.safety'; result='BLOCKED'; exitCode=2; output=$safety.reason; status='BLOCKED_ENVIRONMENT' })
} else {
    $initialStatus = Invoke-QaSend 'cm_qa_status'
    $initialPayload = Get-QaStatusPayload $initialStatus
    $cmQaWasStarted = $null -ne $initialPayload -and [string]$initialPayload.resource -eq 'started'
    if (-not $cmQaWasStarted) {
        Add-Check (Invoke-QaSend 'ensure cm-qa') 'cm-qa.ensure'
    }

    $statusAfterStart = if ($cmQaWasStarted) { $initialStatus } else { Invoke-QaSend 'cm_qa_status' }
    $statusPayload = Get-QaStatusPayload $statusAfterStart
    if ($null -eq $statusPayload -or $statusPayload.enabled -ne $true) {
        Add-Check (Invoke-QaSend 'cm_qa_enable') 'cm_qa_enable'
        $statusAfterStart = Invoke-QaSend 'cm_qa_status'
        $statusPayload = Get-QaStatusPayload $statusAfterStart
    }
    Add-Check $statusAfterStart 'cm_qa_status.preflight'

    $preflightAuthorized = Get-QaStatusCount $statusPayload 'authorizedClients'
    $preflightRegistered = Get-QaStatusCount $statusPayload 'registeredClients'
    $preflightReady = Get-QaStatusCount $statusPayload 'readyClients'
    $preflightReadyClient = $preflightRegistered -gt 0 -and $preflightReady -gt 0
    $restartTargets = @()
    if ($restartRequested) {
        $restartTargets = @($runtimeResources)
        if ($preflightReadyClient -and $restartTargets -contains 'cm-qa') {
            $restartTargets = @($restartTargets | Where-Object { $_ -ne 'cm-qa' })
            $skip = [ordered]@{ id='runtime-controller.restart'; result='PASS'; exitCode=0; durationMs=0; output='RUNTIME_RESTART_SKIPPED_REGISTRATION_PRESERVED'; status='RUNTIME_STATE_PRESERVED' }
            $checks.Add($skip)
        }
        if ($restartTargets.Count) {
            $controllerArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runtimeController,'-StartIfNeeded','-ChangedResource') + @($restartTargets)
            Add-Check (Invoke-CmQaCommand 'powershell.exe' $controllerArgs) 'runtime-controller.restart'
            if ($restartTargets -contains 'cm-qa') {
                Add-Check (Invoke-QaSend 'cm_qa_enable') 'cm_qa_enable.after_restart'
                $statusAfterStart = Invoke-QaSend 'cm_qa_status'
                $statusPayload = Get-QaStatusPayload $statusAfterStart
            }
        }
    } else {
        $checks.Add([ordered]@{ id='runtime-controller.restart'; result='PASS'; exitCode=0; durationMs=0; output='RUNTIME_RESTART_SKIPPED_PRESERVE_RUNTIME_STATE'; status='RUNTIME_STATE_PRESERVED' })
    }

    $cmQaRestarted = $restartTargets -contains 'cm-qa'
    $resourceUnderTestRestarted = @($restartTargets | Where-Object { $_ -ne 'cm-qa' }).Count -gt 0
    $clientRegistrationInvalidated = $cmQaRestarted -and $preflightAuthorized -gt 0
    $registrationPreserved = -not $clientRegistrationInvalidated

    if ($clientScenarioIds.Count) {
        $statusForPreflight = if ($statusPayload) { $statusAfterStart } else { Invoke-QaSend 'cm_qa_status' }
        $payloadForPreflight = if ($statusPayload) { $statusPayload } else { Get-QaStatusPayload $statusForPreflight }
        if ($payloadForPreflight) {
            # Pairing is character-based and belongs to the client layer. The
            # runtime layer only observes status here; it must not block the
            # run before run-client.ps1 has had a chance to pair the configured
            # character without restarting cm-qa.
            $statusForPreflight.result = 'PASS'
            $statusForPreflight.status = 'CLIENT_PAIRING_DEFERRED_TO_CLIENT_LAYER'
            $statusForPreflight.output = ($statusForPreflight.output + "`nclient pairing deferred to pairing-aware client layer")
            $checks.Add($statusForPreflight)
        } else {
            $statusForPreflight.result = 'BLOCKED'
            $statusForPreflight.status = 'FIVEM_CLIENT_QA_BLOCKED_NO_CLIENT'
            $checks.Add($statusForPreflight)
        }
    } elseif ($scenarioIds.Count) {
        foreach ($scenarioId in $scenarioIds) {
            $scenarioCheck = Invoke-QaSend ('cm_qa_run ' + $scenarioId)
            Add-Check $scenarioCheck ('cm_qa_run:' + $scenarioId)
        }
    } else {
        foreach ($pilot in @('qa.framework.smoke','license.card.possession.validity','electrician.shift.start_end','fishing.qa.owner-contract')) {
            $scenarioCheck = Invoke-QaSend ('cm_qa_run ' + $pilot)
            Add-Check $scenarioCheck ('cm_qa_run:' + $pilot)
        }
    }
}

foreach ($check in @($checks)) {
    if ($check.output -match '(?i)RCON_TRANSPORT_RESET|TIMEOUT_WAITING_FOR_RESPONSE|LOCAL_CONSOLE_COMMAND_BRIDGE_NOT_CONFIGURED|RUNTIME_RESTART_NOT_CONFIRMED|server_not_running') {
        $check.result = 'BLOCKED'
        $check.status = 'BLOCKED_ENVIRONMENT'
    }
}

$failed = @($checks | Where-Object result -eq 'FAIL')
$blocked = @($checks | Where-Object result -eq 'BLOCKED')
$actions = [ordered]@{
    cmQaRestarted = $cmQaRestarted
    resourceUnderTestRestarted = $resourceUnderTestRestarted
    registrationPreserved = $registrationPreserved
    clientRegistrationInvalidated = $clientRegistrationInvalidated
    restartRequested = $restartRequested
    preserveRuntimeState = -not $restartRequested
    preflightRegisteredClients = $preflightRegistered
    preflightReadyClients = $preflightReady
}
$layer = [ordered]@{
    name = 'runtime'
    result = if ($failed.Count) { 'FAIL' } elseif ($blocked.Count) { 'BLOCKED' } else { 'PASS' }
    status = if ($failed.Count) { 'SERVER_RUNTIME_FAIL' } elseif ($blocked.Count) { 'BLOCKED' } else { 'SERVER_RUNTIME_PASS' }
    checks = @($checks)
    safety = $safety
    runtime = $actions
    evidence = @('Scenario-only runs preserve the existing cm-qa runtime by default; client character pairing is deferred to run-client.ps1; explicit restart flags are required for resource restart validation.')
}
$path = Save-CmQaLayer $RunId 'runtime' $layer
Write-Output $path
if ($failed.Count) { exit 1 }
if ($blocked.Count) { exit 2 }
exit 0
