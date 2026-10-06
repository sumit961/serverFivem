[CmdletBinding()]
param(
    [string]$Resource,
    [string[]]$TargetResource,
    [Parameter(Mandatory)][string]$RunId
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$repo = Get-CmQaRepoRoot
$checks = [Collections.Generic.List[object]]::new()
$baselineIssues = [Collections.Generic.List[object]]::new()
$unrelatedIssues = [Collections.Generic.List[object]]::new()
$newFailures = [Collections.Generic.List[object]]::new()

function Add-StaticCheck($Check) { $checks.Add([pscustomobject]$Check) }
function Add-ClassifiedIssue($Classification, $Tool, $Evidence, $IssueId) {
    $item = [ordered]@{ classification=$Classification; tool=$Tool; evidence=$Evidence }
    if ($IssueId) { $item.baselineId = $IssueId }
    if ($Classification -eq 'KNOWN_BASELINE_FAILURE') { $baselineIssues.Add($item) }
    elseif ($Classification -eq 'UNRELATED_DIRTY_WORKTREE_FAILURE') { $unrelatedIssues.Add($item) }
    else { $newFailures.Add($item) }
}

$gitCheck = Invoke-CmQaCommand 'git' @('-C', $repo, 'diff', '--check')
$gitViolations = @($gitCheck.output -split "`r?`n" | ForEach-Object { Get-CmQaPathFromDiffCheck $_ } | Where-Object { $_ })
foreach ($violation in $gitViolations) {
    $baseline = Get-CmQaBaselineIssue 'git-diff-check' ("$($violation.path):$($violation.line): $($violation.message)")
    if ($baseline) {
        $classification = if ($baseline.PSObject.Properties.Name -contains 'classification' -and $baseline.classification) { [string]$baseline.classification } else { 'KNOWN_BASELINE_FAILURE' }
        Add-ClassifiedIssue $classification 'git-diff-check' ("$($violation.path):$($violation.line): $($violation.message)") $baseline.id
    } else {
        $relevant = $false
        foreach ($target in @($TargetResource)) { if ($violation.path -match ('^resources/[^/]+/' + [regex]::Escape($target) + '/')) { $relevant = $true } }
        $classification = if ($relevant) { 'NEW_FAILURE' } else { 'UNRELATED_DIRTY_WORKTREE_FAILURE' }
        Add-ClassifiedIssue $classification 'git-diff-check' ("$($violation.path):$($violation.line): $($violation.message)") $null
    }
}
$gitResult = if (@($newFailures | Where-Object tool -eq 'git-diff-check').Count) { 'FAIL' } elseif ($gitCheck.exitCode -ne 0) { 'PASS_WITH_BASELINE_ISSUES' } else { 'PASS' }
Add-StaticCheck ([ordered]@{ id='git.diff-check'; result=$gitResult; exitCode=if($gitResult -eq 'FAIL'){1}else{0}; output=$gitCheck.output; classifications=@($gitViolations | ForEach-Object { $_.path }) })

$serverConfig = Get-Content -Raw -LiteralPath (Join-Path $repo 'server.cfg')
$qaServer = Get-Content -Raw -LiteralPath (Join-Path $repo 'resources\[dev]\cm-qa\server\main.lua')
$rconBridge = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools\cm-runtime\send-command.ps1')
Add-StaticCheck ([ordered]@{ id='security.qa-not-production-ensured'; result=if($serverConfig -match '(?m)^\s*ensure\s+cm-qa\s*$'){'FAIL'}else{'PASS'}; exitCode=if($serverConfig -match '(?m)^\s*ensure\s+cm-qa\s*$'){1}else{0}; output='cm-qa is not ensured by server.cfg' })
Add-StaticCheck ([ordered]@{ id='security.qa-console-only'; result=if($qaServer -match 'consoleOnly\(source\)' -and $qaServer -match 'commandAllowed\(source'){ 'PASS' } else { 'FAIL' }; exitCode=if($qaServer -match 'consoleOnly\(source\)' -and $qaServer -match 'commandAllowed\(source'){0}else{1}; output='QA commands require source=0' })
Add-StaticCheck ([ordered]@{ id='security.qa-fail-closed'; result=if($qaServer -match "GetConvar\('cm_environment', 'production'\) == 'development'" -and $qaServer -match 'qaState'){ 'PASS' } else { 'FAIL' }; exitCode=if($qaServer -match "GetConvar\('cm_environment', 'production'\) == 'development'" -and $qaServer -match 'qaState'){0}else{1}; output='QA requires development environment and internal enable state' })
Add-StaticCheck ([ordered]@{ id='security.rcon-exact-qa-allowlist'; result=if($rconBridge -match '\$qaCommandAllowed' -and $rconBridge -match 'cm_qa_\(\?:enable' -and $rconBridge -match 'COMMAND_NOT_ALLOWLISTED'){ 'PASS' } else { 'FAIL' }; exitCode=if($rconBridge -match '\$qaCommandAllowed' -and $rconBridge -match 'cm_qa_\(\?:enable' -and $rconBridge -match 'COMMAND_NOT_ALLOWLISTED'){0}else{1}; output='RCon bridge retains exact command allowlist' })

$resourceFiles = @()
if ($Resource -eq 'cm-qa') { $resourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'resources\[dev]\cm-qa') -Recurse -File) }
$toolFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'tools\cm-qa') -Recurse -File)
$psFiles = @($resourceFiles + $toolFiles | Where-Object Extension -eq '.ps1')
$luaFiles = @($resourceFiles | Where-Object Extension -eq '.lua')
$jsFiles = @($resourceFiles + $toolFiles | Where-Object Extension -eq '.js')
foreach ($file in $psFiles) {
    $errors = @()
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors) | Out-Null
    Add-StaticCheck ([ordered]@{ id='powershell.syntax:' + $file.Name; result=if($errors.Count -eq 0){'PASS'}else{'FAIL'}; exitCode=if($errors.Count -eq 0){0}else{1}; output=(($errors | ForEach-Object Message) -join '; ') })
}
foreach ($file in $luaFiles) { $check=Invoke-CmQaCommand 'luac' @('-p',$file.FullName); $check.id='luac:'+$file.Name; Add-StaticCheck $check }
foreach ($file in $jsFiles) { $check=Invoke-CmQaCommand 'node' @('--check',$file.FullName); $check.id='node.syntax:'+$file.Name; Add-StaticCheck $check }

$lifecycleTest = Join-Path $repo 'tools\cm-qa\tests\lifecycle.tests.ps1'
$lifecycle = Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$lifecycleTest)
$lifecycle.id = 'qa.lifecycle.regression'
Add-StaticCheck $lifecycle

$orchestrationTest = Join-Path $repo 'tools\cm-qa\tests\orchestration.tests.ps1'
$orchestration = Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$orchestrationTest)
$orchestration.id = 'qa.harness.registration-preserved-between-scenarios'
Add-StaticCheck $orchestration

$ownerContractTest = Join-Path $repo 'tools\cm-qa\tests\owner-contract.tests.ps1'
$ownerContract = Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ownerContractTest)
$ownerContract.id = 'qa.owner-contract.regression'
Add-StaticCheck $ownerContract

$pairingTest = Join-Path $repo 'tools\cm-qa\tests\pairing.tests.ps1'
$pairing = Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$pairingTest)
$pairing.id = 'qa.harness.character-pairing'
Add-StaticCheck $pairing

$windowDiscoveryTest = Join-Path $repo 'tools\cm-qa\tests\window-discovery.tests.ps1'
$windowDiscovery = Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$windowDiscoveryTest)
$windowDiscovery.id = 'qa.harness.window-discovery'
Add-StaticCheck $windowDiscovery

$python = Get-CmQaPython
$validate = Invoke-CmQaCommand $python @((Join-Path $repo 'tools\cm-validate\validate.py'))
$validate.id = 'cm-validate'
$validatorBaseline = Get-CmQaBaselineIssue 'cm-validate' $validate.output
if ($validatorBaseline -and $validate.exitCode -ne 0) {
    Add-ClassifiedIssue 'KNOWN_BASELINE_FAILURE' 'cm-validate' $validate.output $validatorBaseline.id
    $validate.result = 'PASS_WITH_BASELINE_ISSUES'; $validate.exitCode = 0
} elseif ($validate.exitCode -ne 0) { Add-ClassifiedIssue 'NEW_FAILURE' 'cm-validate' $validate.output $null }
Add-StaticCheck $validate

$scanner = Invoke-CmQaCommand $python @((Join-Path $repo 'tools\cm-fivem-map\scan.py'), '--root', $repo, '--out', (Join-Path $repo 'cm-agent-out'), '--check')
$scanner.id = 'cm-fivem-map.check'
if ($scanner.exitCode -ne 0) { Add-ClassifiedIssue 'NEW_FAILURE' 'cm-fivem-map' $scanner.output $null }
Add-StaticCheck $scanner

$failed = @($checks | Where-Object result -eq 'FAIL')
$blocked = @($checks | Where-Object result -eq 'BLOCKED')
$layerResult = if ($failed.Count -or $newFailures.Count) { 'FAIL' } elseif ($blocked.Count) { 'BLOCKED' } elseif ($baselineIssues.Count -or $unrelatedIssues.Count) { 'PASS_WITH_BASELINE_ISSUES' } else { 'PASS' }
$layer = [ordered]@{ name='static'; result=$layerResult; status=if($layerResult -eq 'FAIL'){'STATIC_FAIL'}elseif($layerResult -eq 'BLOCKED'){'BLOCKED'}else{'STATIC_PASS'}; checks=@($checks); baselineIssues=@($baselineIssues); unrelatedDirtyWork=@($unrelatedIssues); newFailures=@($newFailures); evidence=@('git diff --check is correlated by file; known baseline issues remain visible and are not treated as new regressions.') }
$path=Save-CmQaLayer $RunId 'static' $layer
Write-Output $path
if ($layerResult -eq 'FAIL') { exit 1 }
if ($layerResult -eq 'BLOCKED') { exit 2 }
exit 0
