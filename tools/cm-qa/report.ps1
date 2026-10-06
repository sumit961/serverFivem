[CmdletBinding()]
param([string]$RunId)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
Set-StrictMode -Version Latest
$root = Get-CmQaOutputRoot
if (-not $RunId) {
    $latest = Join-Path $root 'latest.json'
    if (-not (Test-Path -LiteralPath $latest)) { throw 'No QA report exists.' }
    $report = Get-Content -Raw -LiteralPath $latest | ConvertFrom-Json
    $RunId = [string]$report.runId
}
$runDir = Get-CmQaRunDirectory $RunId
$layerFiles = @(Get-ChildItem -LiteralPath $runDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'manifest.json')
$layers = [ordered]@{}
$tests = [Collections.Generic.List[object]]::new()
$failures = [Collections.Generic.List[object]]::new()
$baselineIssues = [Collections.Generic.List[object]]::new()
$unrelatedDirtyWork = [Collections.Generic.List[object]]::new()
$resources = [Collections.Generic.List[string]]::new()

foreach ($file in $layerFiles) {
    $layer = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $layers[$name] = $layer
    if ($layer.PSObject.Properties.Name -contains 'tests') { foreach ($test in @($layer.tests)) { $tests.Add($test) } }
    if ($layer.PSObject.Properties.Name -contains 'checks') { foreach ($check in @($layer.checks)) {
        if ($check.id -like 'browser:*' -and $check.output) {
            try { $browserReport = $check.output | ConvertFrom-Json; foreach ($test in @($browserReport.tests)) { $tests.Add($test) } } catch { }
        }
        if ($check.result -eq 'FAIL') { $failures.Add([ordered]@{ layer=$name; id=$check.id; evidence=$check.output; expected='exitCode=0'; actual=$check.result }) }
    } }
    if ($layer.PSObject.Properties.Name -contains 'baselineIssues') { foreach ($item in @($layer.baselineIssues)) { $baselineIssues.Add($item) } }
    if ($layer.PSObject.Properties.Name -contains 'unrelatedDirtyWork') { foreach ($item in @($layer.unrelatedDirtyWork)) { $unrelatedDirtyWork.Add($item) } }
}

$manifestPath = Join-Path $runDir 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    foreach ($resource in @($manifest.resources)) { if ($resource) { $resources.Add([string]$resource) } }
}
foreach ($layer in $layers.Values) {
    if ($layer.PSObject.Properties.Name -contains 'resource' -and $layer.resource) { $resources.Add([string]$layer.resource) }
    if ($layer.PSObject.Properties.Name -contains 'resources') { foreach ($resource in @($layer.resources)) { if ($resource) { $resources.Add([string]$resource) } } }
}
$resources = @($resources | Sort-Object -Unique)
$failed = @($layers.Values | Where-Object result -eq 'FAIL')
$blocked = @($layers.Values | Where-Object result -eq 'BLOCKED')
$overall = if ($failed.Count) { 'FAIL' } elseif ($blocked.Count) { 'BLOCKED' } elseif ($baselineIssues.Count -or $unrelatedDirtyWork.Count -or @($layers.Values | Where-Object result -eq 'PASS_WITH_BASELINE_ISSUES').Count) { 'PASS_WITH_BASELINE_ISSUES' } else { 'PASS' }
$runtimeSummary = if ($layers.Contains('runtime') -and $layers['runtime'].PSObject.Properties.Name -contains 'runtime') { $layers['runtime'].runtime } else { [ordered]@{ cmQaRestarted=$false; resourceUnderTestRestarted=$false; registrationPreserved=$true; clientRegistrationInvalidated=$false } }
$clientSummary = if ($layers.Contains('client') -and $layers['client'].PSObject.Properties.Name -contains 'pairing') { $layers['client'].pairing } else { [ordered]@{ configuredCharacterId=$null; connected=$false; paired=$false; ready=$false; status='NOT_RUN' } }
$report = [ordered]@{
    runId = $RunId
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    result = $overall
    resources = $resources
    runtime = $runtimeSummary
    client = $clientSummary
    layers = $layers
    tests = @($tests)
    failures = @($failures)
    baselineClassification = [ordered]@{
        knownBaselineFailures = @($baselineIssues)
        unrelatedDirtyWorktreeFailures = @($unrelatedDirtyWork)
        newFailures = @($failures)
    }
    manualOnly = @(
        'VISUAL_REVIEW_NOT_RUN',
        'Physical keyboard/mouse input requires the optional local client driver.',
        'Multiplayer QA requires two explicitly registered development clients.',
        'Gameplay owner contracts remain manual/blocked until safe QA snapshots are added.'
    )
}
$latestJson = Join-Path $root 'latest.json'
$latestMd = Join-Path $root 'latest.md'
Write-CmQaJson $latestJson $report
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('# CM QA RESULT: ' + $overall)
$lines.Add('')
$lines.Add(('- Result: **{0}**' -f $overall))
$lines.Add(('- Run: `{0}`' -f $RunId))
$lines.Add('')
$lines.Add('## Layers')
$lines.Add('')
foreach ($entry in $layers.GetEnumerator()) { $lines.Add(('- `{0}`: **{1}** ({2})' -f $entry.Key, $entry.Value.result, $entry.Value.status)) }
$lines.Add('')
$lines.Add('## Failures and blocks')
$lines.Add('')
if ($failures.Count -eq 0) { $lines.Add('- No assertion failures recorded.') } else { foreach ($failure in $failures) { $lines.Add(('- `{0}`: {1}' -f $failure.id, $failure.evidence)) } }
$lines.Add('')
$lines.Add('## Known baseline')
$lines.Add('')
if ($baselineIssues.Count -eq 0) { $lines.Add('- None.') } else { foreach ($item in $baselineIssues) { $lines.Add(('- {0}: {1}' -f $item.baselineId, $item.evidence)) } }
$lines.Add('')
$lines.Add('## Unrelated dirty work')
$lines.Add('')
if ($unrelatedDirtyWork.Count -eq 0) { $lines.Add('- None.') } else { foreach ($item in $unrelatedDirtyWork) { $lines.Add(('- {0}: {1}' -f $item.tool, $item.evidence)) } }
$lines.Add('')
$lines.Add('## Manual remainder')
$lines.Add('')
foreach ($item in $report.manualOnly) { $lines.Add(('- {0}' -f $item)) }
[IO.File]::WriteAllText($latestMd, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output $latestJson
if ($overall -eq 'FAIL') { exit 1 }
if ($overall -eq 'BLOCKED') { exit 2 }
exit 0
