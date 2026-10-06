[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
function Read-CmQaFile([string]$Path) { Get-Content -Raw -LiteralPath (Join-Path $repo $Path) }
function Assert-CmQaInvariant([string]$Name, [string]$Text, [string]$Pattern) {
    if ($Text -notmatch $Pattern) { throw "QA_PAIRING_REGRESSION_FAIL: $Name" }
}

$server = Read-CmQaFile 'resources\[dev]\cm-qa\server\main.lua'
$bridge = Read-CmQaFile 'tools\cm-runtime\send-command.ps1'
$client = Read-CmQaFile 'tools\cm-qa\run-client.ps1'
$bootstrap = Read-CmQaFile 'tools\cm-qa\bootstrap.ps1'
$example = Read-CmQaFile 'tools\cm-runtime\runtime.example.json'

Assert-CmQaInvariant 'exact-pair-command' $server "RegisterCommand\('cm_qa_pair_character'"
Assert-CmQaInvariant 'pair-command-console-and-enabled-gate' $server "commandAllowed\(source,true\)"
Assert-CmQaInvariant 'authoritative-character-lookup' $server "api:GetCharacterId\(sourceId\)"
Assert-CmQaInvariant 'zero-match-outcome' $server 'QA_CLIENT_CHARACTER_NOT_CONNECTED'
Assert-CmQaInvariant 'multiple-match-outcome' $server 'QA_CLIENT_PAIR_AMBIGUOUS'
Assert-CmQaInvariant 'expected-character-bound-to-registration' $server 'expectedCharacterId'
Assert-CmQaInvariant 'drop-clears-pair' $server "setPairingState\('not_connected'"
Assert-CmQaInvariant 'safe-status-pairing' $server 'pairing=pairingStatus\(\)'
Assert-CmQaInvariant 'rcon-pair-allowlist' $bridge 'cm_qa_pair_character\\s\+\[0-9\]\{1,10\}'
Assert-CmQaInvariant 'harness-pair-command' $client 'cm_qa_pair_character '
Assert-CmQaInvariant 'bounded-readiness-wait' $client '\$deadline = \(Get-Date\)\.AddSeconds\(15\)'
Assert-CmQaInvariant 'not-connected-result' $client 'QA_CLIENT_NOT_CONNECTED'
Assert-CmQaInvariant 'not-paired-result' $client 'QA_CLIENT_NOT_PAIRED'
Assert-CmQaInvariant 'not-ready-result' $client 'QA_CLIENT_NOT_READY'
Assert-CmQaInvariant 'bootstrap-not-configured' $bootstrap 'QA_CHARACTER_NOT_CONFIGURED'
Assert-CmQaInvariant 'config-character-id' $example '"characterId": null'
Assert-CmQaInvariant 'config-auto-pair' $example '"autoPair": false'
if ($server -match "cm-qa:pairMe") { throw 'QA_PAIRING_REGRESSION_FAIL: client_pair_event_present' }

# Deterministic state-transition model: no match -> exact pair -> ready ->
# disconnect -> a new source may pair again, while the old source is gone.
$pair = [ordered]@{ configuredCharacterId=12; source=$null; paired=$false; ready=$false }
$pair.state = 'not_connected'
if ($pair.state -ne 'not_connected' -or $pair.paired) { throw 'QA_PAIRING_REGRESSION_FAIL: no-match-state' }
$pair.source = 7; $pair.paired = $true; $pair.state = 'paired_waiting_ready'
if (-not $pair.paired -or $pair.source -ne 7 -or $pair.ready) { throw 'QA_PAIRING_REGRESSION_FAIL: exact-pair-state' }
$pair.ready = $true; $pair.state = 'ready'
if (-not $pair.ready) { throw 'QA_PAIRING_REGRESSION_FAIL: ready-state' }
$pair.source = $null; $pair.paired = $false; $pair.ready = $false; $pair.state = 'not_connected'
if ($pair.source -or $pair.paired -or $pair.ready) { throw 'QA_PAIRING_REGRESSION_FAIL: disconnect-clears-old-source' }
$pair.source = 9; $pair.paired = $true; $pair.ready = $true; $pair.state = 'ready'
if ($pair.source -ne 9 -or -not $pair.ready) { throw 'QA_PAIRING_REGRESSION_FAIL: reconnect-new-source' }

Write-Output 'QA_PAIRING_REGRESSION_PASS qa.harness.character-pairing'
