[CmdletBinding()]
param(
    [string]$Resource,
    [switch]$Changed,
    [ValidateSet('All','Static','Runtime','Server','UI','Client')][string]$Layer = 'All',
    [string]$Scenario,
    [switch]$RestartAffected,
    [switch]$RuntimeValidation,
    [switch]$PreserveRuntimeState
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Get-CmQaRepoRoot

$scenarioIds = @($Scenario -split ',' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
$resources = [Collections.Generic.List[string]]::new()
if ($Resource) { $resources.Add($Resource) }
if ($Changed) {
    foreach ($item in Get-CmQaResourcesFromPaths (Get-CmQaChangedPaths)) { $resources.Add($item) }
}
if ($scenarioIds.Count) {
    foreach ($scenarioId in $scenarioIds) {
        $scenarioResource = Get-CmQaScenarioResource $scenarioId
        if ($scenarioResource) { $resources.Add($scenarioResource) }
    }
}
if ($resources.Count -eq 0) { throw 'Choose -Resource <cm-resource> or -Changed.' }
$resources = @($resources | Where-Object { $_ -match '^[a-z0-9_-]+$' } | Sort-Object -Unique)
$runtimeResources = if ($scenarioIds.Count) {
    @($scenarioIds | ForEach-Object { Get-CmQaScenarioResource $_ } | Where-Object { $_ } | Sort-Object -Unique)
} else { @($resources) }
$restartRequested = $RestartAffected -or $RuntimeValidation
$preserveRuntime = $PreserveRuntimeState -or -not $restartRequested
$runId = Get-CmQaRunId
$runDir = Get-CmQaRunDirectory $runId
$startedAt = (Get-Date).ToUniversalTime().ToString('o')

function Invoke-LayerScript([string]$Script, [string[]]$Arguments) {
    $path = Join-Path $PSScriptRoot $Script
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path @Arguments | ForEach-Object { Write-Output $_ }
}

$doStatic = $Layer -in @('All','Static')
$doRuntime = $Layer -in @('All','Runtime','Server')
$doUi = $Layer -in @('All','UI')
$doClient = $Layer -eq 'Client' -or ($Layer -eq 'All' -and (($Scenario -and ($Scenario -match '(?i)client|physical')) -or @($resources | Where-Object { $_ -ne 'cm-qa' }).Count))

if ($doStatic) {
    $staticArgs = [Collections.Generic.List[string]]::new()
    $staticArgs.Add('-Resource'); $staticArgs.Add('cm-qa'); $staticArgs.Add('-RunId'); $staticArgs.Add($runId)
    foreach ($item in $resources) { $staticArgs.Add('-TargetResource'); $staticArgs.Add($item) }
    Invoke-LayerScript 'run-static.ps1' @($staticArgs)
}
if ($doRuntime) {
    $runtimeArgs = [Collections.Generic.List[string]]::new()
    $runtimeArgs.Add('-RunId'); $runtimeArgs.Add($runId)
    foreach ($item in $runtimeResources) { $runtimeArgs.Add('-Resource'); $runtimeArgs.Add($item) }
    if ($scenarioIds.Count) { $runtimeArgs.Add('-Scenario'); $runtimeArgs.Add(($scenarioIds -join ',')) }
    if ($restartRequested) { $runtimeArgs.Add('-RestartAffected') } else { $runtimeArgs.Add('-PreserveRuntimeState') }
    Invoke-LayerScript 'run-runtime.ps1' @($runtimeArgs)
}
if ($doUi) {
    foreach ($item in $resources) {
        $fixture = Join-Path $PSScriptRoot ('fixtures\ui\' + $item)
        if (Test-Path -LiteralPath $fixture) { Invoke-LayerScript 'run-ui.ps1' @('-Resource',$item,'-RunId',$runId) }
        else { Save-CmQaLayer $runId ('ui-' + $item) ([ordered]@{ name='ui'; resource=$item; result='PASS'; status='NOT_REQUIRED'; checks=@(); evidence=@('No UI fixture is registered for this resource.') }) | Out-Null }
    }
}
if ($doClient) {
    $clientArgs = [Collections.Generic.List[string]]::new()
    $clientArgs.Add('-RunId'); $clientArgs.Add($runId)
    if ($scenarioIds.Count) { $clientArgs.Add('-Scenario'); $clientArgs.Add(($scenarioIds -join ',')) }
    Invoke-LayerScript 'run-client.ps1' @($clientArgs)
}

$manifest = [ordered]@{ runId=$runId; startedAt=$startedAt; requestedLayer=$Layer; resources=$resources; scenario=$scenarioIds; runtimeResources=$runtimeResources; restartRequested=$restartRequested; preserveRuntimeState=$preserveRuntime }
Write-CmQaJson (Join-Path $runDir 'manifest.json') $manifest
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'report.ps1') -RunId $runId | ForEach-Object { Write-Output $_ }
$latest = Get-Content -Raw -LiteralPath (Join-Path (Get-CmQaOutputRoot) 'latest.json') | ConvertFrom-Json
Rotate-CmQaArtifacts
if ($latest.result -eq 'FAIL') { exit 1 }
if ($latest.result -eq 'BLOCKED') { exit 2 }
exit 0
