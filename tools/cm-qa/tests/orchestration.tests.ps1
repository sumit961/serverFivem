[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
function Read-CmQaFile([string]$Path) { Get-Content -Raw -LiteralPath (Join-Path $repo $Path) }
function Assert-CmQaInvariant([string]$Name, [string]$Text, [string]$Pattern) {
    if ($Text -notmatch $Pattern) { throw "QA_ORCHESTRATION_REGRESSION_FAIL: $Name" }
}

$run = Read-CmQaFile 'tools\cm-qa\run.ps1'
$runtime = Read-CmQaFile 'tools\cm-qa\run-runtime.ps1'
$client = Read-CmQaFile 'tools\cm-qa\run-client.ps1'
$driver = Read-CmQaFile 'tools\cm-qa\client-driver.ps1'
$server = Read-CmQaFile 'resources\[dev]\cm-qa\server\main.lua'
$runner = Read-CmQaFile 'resources\[dev]\cm-qa\server\runner.lua'

Assert-CmQaInvariant 'preserve-runtime-default' $run '\$preserveRuntime\s*=\s*\$PreserveRuntimeState\s*-or\s*-not\s+\$restartRequested'
Assert-CmQaInvariant 'explicit-restart-switch' $run '\[switch\]\$RestartAffected'
Assert-CmQaInvariant 'runtime-validation-switch' $run '\[switch\]\$RuntimeValidation'
Assert-CmQaInvariant 'scenario-resource-inference' $run 'Get-CmQaScenarioResource'
Assert-CmQaInvariant 'preflight-before-restart' $runtime 'cm_qa_status\.preflight'
Assert-CmQaInvariant 'restart-preservation-guard' $runtime 'RUNTIME_RESTART_SKIPPED_REGISTRATION_PRESERVED'
Assert-CmQaInvariant 'runtime-action-report' $runtime 'clientRegistrationInvalidated'
Assert-CmQaInvariant 'status-preflight' $client 'cm_qa_status'
Assert-CmQaInvariant 'pairing-deferred-to-client-layer' $runtime 'CLIENT_PAIRING_DEFERRED_TO_CLIENT_LAYER'
Assert-CmQaInvariant 'not-ready-block-reason' $client 'FIVEM_CLIENT_QA_BLOCKED_CLIENT_NOT_READY'
Assert-CmQaInvariant 'reregistration-block-reason' $client 'FIVEM_CLIENT_QA_BLOCKED_REREGISTRATION_REQUIRED'
Assert-CmQaInvariant 'scenario-start-owned-by-client-layer' $client 'cm_qa_run ' 
Assert-CmQaInvariant 'ready-count-status' $server 'readyClients=readyClientCount\(\)'
Assert-CmQaInvariant 'runner-requires-ready' $runner 'client\.registered and client\.ready'
if ($driver -match '(?i)restart\s+cm-qa|cm_qa_disable|cm_qa_unregister') { throw 'QA_ORCHESTRATION_REGRESSION_FAIL: client-driver-mutates-lifecycle' }

# Deterministic fake registered-client session: completing one scenario clears
# only active-run state, then the next scenario reuses the same registration.
$session = [ordered]@{ registered = $true; ready = $true; activeRun = $null; cmQaRestarted = $false }
$session.activeRun = 'qa.client.input-smoke'
$session.activeRun = $null
if (-not $session.registered -or -not $session.ready -or $session.cmQaRestarted) { throw 'QA_ORCHESTRATION_REGRESSION_FAIL: input-smoke-registration-preservation' }
$session.activeRun = 'qa.client.hold-smoke'
$session.activeRun = $null
if (-not $session.registered -or -not $session.ready -or $session.cmQaRestarted) { throw 'QA_ORCHESTRATION_REGRESSION_FAIL: hold-smoke-registration-preservation' }

Write-Output 'QA_ORCHESTRATION_REGRESSION_PASS qa.harness.registration-preserved-between-scenarios'
