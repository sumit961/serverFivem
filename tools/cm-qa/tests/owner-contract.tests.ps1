[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
function Read-CmQaFile([string]$Path) { Get-Content -Raw -LiteralPath (Join-Path $repo $Path) }
function Assert-CmQaInvariant([string]$Name, [string]$Text, [string]$Pattern) {
    if ($Text -notmatch $Pattern) { throw "QA_OWNER_CONTRACT_REGRESSION_FAIL: $Name" }
}

$owner = Read-CmQaFile 'resources\[core]\cm-electrician\server\main.lua'
$fishing = Read-CmQaFile 'resources\[core]\cm-fishing\server\main.lua'
$runner = Read-CmQaFile 'resources\[dev]\cm-qa\server\runner.lua'
$qaMain = Read-CmQaFile 'resources\[dev]\cm-qa\server\main.lua'
$scenarios = Read-CmQaFile 'resources\[dev]\cm-qa\shared\scenarios.lua'

Assert-CmQaInvariant 'development-gate' $owner "GetConvar\('cm_environment', 'production'\) ~= 'development'"
Assert-CmQaInvariant 'qa-enabled-gate' $owner 'GetConvarInt\(''cm_qa_enabled'', 0\) ~= 1'
Assert-CmQaInvariant 'caller-gate' $owner "GetInvokingResource\(\) ~= 'cm-qa'"
Assert-CmQaInvariant 'snapshot-explicit-result' $owner "return true, snapshotOrReason"
Assert-CmQaInvariant 'control-explicit-result' $owner "return false, reason"
Assert-CmQaInvariant 'snapshot-export' $owner "exports\('QaSnapshot'"
Assert-CmQaInvariant 'control-export' $owner "exports\('QaControl'"
if ($owner -match "RegisterNetEvent\('cm-electrician:server:(?:QaSnapshot|QaControl)'") { throw 'QA_OWNER_CONTRACT_REGRESSION_FAIL: qa-contract-network-event' }
Assert-CmQaInvariant 'owner-resource-probe' $runner "OWNER_RESOURCE_NOT_STARTED"
Assert-CmQaInvariant 'missing-export-probe' $runner "OWNER_EXPORT_MISSING"
Assert-CmQaInvariant 'forbidden-probe' $runner "OWNER_EXPORT_FORBIDDEN"
Assert-CmQaInvariant 'character-mismatch-probe' $runner "OWNER_CHARACTER_MISMATCH"
Assert-CmQaInvariant 'bounded-readiness-probe' $runner 'GetGameTimer\(\) \+ 5000'
Assert-CmQaInvariant 'blocked-cleanup' $runner "cancelActive\(reason, 'BLOCKED'\)"
Assert-CmQaInvariant 'cleanup-restores-fixture' $owner 'restoreQaFixture'
Assert-CmQaInvariant 'restart-does-not-restart-qa' $runner 'OWNER_RESOURCE_NOT_STARTED'
Assert-CmQaInvariant 'owner-smoke-scenario' $scenarios "electrician\.qa\.owner-contract"
Assert-CmQaInvariant 'enable-state-shared' $qaMain 'setQaConvar\(true\)'

Assert-CmQaInvariant 'fishing-development-gate' $fishing "GetConvar\('cm_environment', 'production'\) ~= 'development'"
Assert-CmQaInvariant 'fishing-qa-enabled-gate' $fishing 'GetConvarInt\(''cm_qa_enabled'', 0\) ~= 1'
Assert-CmQaInvariant 'fishing-caller-gate' $fishing "GetInvokingResource\(\) ~= 'cm-qa'"
Assert-CmQaInvariant 'fishing-snapshot-export' $fishing "exports\('QaSnapshot'"
Assert-CmQaInvariant 'fishing-control-export' $fishing "exports\('QaControl'"
Assert-CmQaInvariant 'fishing-explicit-result' $fishing 'return false, reason'
Assert-CmQaInvariant 'fishing-state-cleanup' $fishing 'QaState\[key\] = nil'
Assert-CmQaInvariant 'fishing-deterministic-actions' $fishing 'force_next_fish'
if ($fishing -match "RegisterNetEvent\('cm-fishing:server:(?:QaSnapshot|QaControl)'") { throw 'QA_OWNER_CONTRACT_REGRESSION_FAIL: fishing-qa-contract-network-event' }
Assert-CmQaInvariant 'fishing-owner-probe' $runner "fishingSnapshot\(sourceId, expectedCharacterId\)"
Assert-CmQaInvariant 'fishing-owner-control' $runner "fishingControl\('clear'"
Assert-CmQaInvariant 'fishing-owner-scenario' $scenarios "fishing\.qa\.owner-contract"
Assert-CmQaInvariant 'fishing-blocked-cleanup-scenario' $scenarios "fishing\.qa\.blocked-cleanup"
Assert-CmQaInvariant 'fishing-blocked-cleanup-regression' $runner 'blocked_owner_run_cleared_and_runner_ready'

Write-Output 'QA_OWNER_CONTRACT_REGRESSION_PASS'
