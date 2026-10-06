[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Resource,
    [string]$RunId
)

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$RunId = if ($RunId) { $RunId } else { Get-CmQaRunId }
$repo = Get-CmQaRepoRoot
$entry = Get-ChildItem -LiteralPath (Join-Path $repo 'resources') -Directory -Recurse -Filter $Resource -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'ui\index.html' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
$checks = [Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $entry)) {
    $checks.Add([ordered]@{ id='ui.entry'; result='BLOCKED'; reason='NUI_ENTRY_NOT_FOUND' })
} else {
    $css = Get-ChildItem -LiteralPath (Split-Path $entry) -Filter '*.css' -File | Get-Content -Raw
    if ($css -match '(?i)(?:-webkit-)?backdrop-filter\s*:') {
        $checks.Add([ordered]@{ id='ui.prohibited-backdrop-filter'; result='FAIL'; reason='backdrop-filter_is_forbidden' })
    }
    $node = Join-Path $PSScriptRoot 'ui\run-browser.js'
    $browser = Invoke-CmQaCommand 'node' @($node, '--root', $repo, '--resource', $Resource, '--output', (Get-CmQaOutputRoot))
    $browser.id = 'browser:' + $Resource
    $checks.Add($browser)
}

$failed = @($checks | Where-Object result -eq 'FAIL')
$blocked = @($checks | Where-Object result -eq 'BLOCKED')
$layer = [ordered]@{
    name = 'ui'
    result = if ($failed.Count) { 'FAIL' } elseif ($blocked.Count) { 'BLOCKED' } else { 'PASS' }
    status = if ($failed.Count) { 'UI_AUTOMATION_FAIL' } elseif ($blocked.Count) { 'BLOCKED' } else { 'UI_AUTOMATION_PASS' }
    checks = @($checks)
    screenshots = @(Get-ChildItem -LiteralPath (Join-Path (Get-CmQaOutputRoot) ('screenshots\' + $Resource)) -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    visualReview = 'VISUAL_REVIEW_NOT_RUN'
}
$path = Save-CmQaLayer $RunId 'ui' $layer
Write-Output $path
if ($failed.Count) { exit 1 }
if ($blocked.Count) { exit 2 }
exit 0
