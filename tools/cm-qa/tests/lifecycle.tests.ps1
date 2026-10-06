[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
function Read-CmQaFile([string]$Path) { Get-Content -Raw -LiteralPath (Join-Path $repo $Path) }
function Assert-CmQaInvariant([string]$Name, [string]$Text, [string]$Pattern) {
    if ($Text -notmatch $Pattern) { throw "QA_LIFECYCLE_REGRESSION_FAIL: $Name" }
}

$client = Read-CmQaFile 'resources\[dev]\cm-qa\client\runner.lua'
$server = Read-CmQaFile 'resources\[dev]\cm-qa\server\main.lua'
$runner = Read-CmQaFile 'resources\[dev]\cm-qa\server\runner.lua'
$html = Read-CmQaFile 'resources\[dev]\cm-qa\ui\index.html'
$css = Read-CmQaFile 'resources\[dev]\cm-qa\ui\style.css'
$js = Read-CmQaFile 'resources\[dev]\cm-qa\ui\app.js'

Assert-CmQaInvariant 'client-default-unregistered' $client 'registered\s*=\s*false'
Assert-CmQaInvariant 'client-default-no-run' $client 'activeRunId\s*=\s*nil'
Assert-CmQaInvariant 'central-cleanup' $client 'function ResetCmQaClientState'
Assert-CmQaInvariant 'resource-stop-cleanup' $client 'onResourceStop'
Assert-CmQaInvariant 'dedicated-prompt-owner' $client "QA_PROMPT_OWNER\s*=\s*'cm-qa:test'"
Assert-CmQaInvariant 'authoritative-registration-event' $client 'cm-qa:client:registrationState'
Assert-CmQaInvariant 'server-run-id-check' $runner 'payload\.runId.*active\.runId'
Assert-CmQaInvariant 'targeted-start-event' $runner "TriggerClientEvent\('cm-qa:client:startScenario', sourceId"
Assert-CmQaInvariant 'registration-revocation' $server 'cm-qa:client:registrationState.*false'
Assert-CmQaInvariant 'hidden-html-root' $html 'id="qa-root" class="hidden"'
Assert-CmQaInvariant 'hidden-css-root' $css '#qa-root\.hidden\s*\{\s*display:\s*none\s*!important'
Assert-CmQaInvariant 'transparent-html-body' $css 'html, body\s*\{[^}]*background:\s*transparent\s*!important'
Assert-CmQaInvariant 'idle-pointer-events' $css 'body\s*\{[^}]*pointer-events:\s*none'
if ($client -match "SendNUIMessage\(\{ action = 'qaOpen'") { throw 'QA_LIFECYCLE_REGRESSION_FAIL: physical-smoke-opens-nui' }
Assert-CmQaInvariant 'nui-reset' $js 'action\s*===\s*''qaReset'''
Assert-CmQaInvariant 'reset-clears-root-style' $js 'root\.removeAttribute\(''style''\)'
Assert-CmQaInvariant 'reset-clears-text' $js 'title\.textContent\s*=\s*'''''
Assert-CmQaInvariant 'reset-clears-inline-backgrounds' $js 'removeProperty\(''background-color''\)'

Write-Output 'QA_LIFECYCLE_REGRESSION_PASS'
