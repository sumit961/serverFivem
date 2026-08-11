$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$resource = Join-Path $root 'resources\[core]\cm-police'
$failures = [System.Collections.Generic.List[string]]::new()

$luac = Get-Command luac -ErrorAction SilentlyContinue
if (-not $luac) {
    $failures.Add('luac is unavailable')
} else {
    Get-ChildItem -LiteralPath $resource -Recurse -Filter '*.lua' -File | ForEach-Object {
        $raw = Get-Content -LiteralPath $_.FullName -Raw
        $normalized = [regex]::Replace($raw, '`([^`]+)`', "GetHashKey('$1')")
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ("cm-police-validate-$([guid]::NewGuid().ToString('N')).lua")
        [IO.File]::WriteAllText($temporary, $normalized)
        & $luac.Source -p $temporary
        if ($LASTEXITCODE -ne 0) { $failures.Add("Lua syntax: $($_.FullName)") }
        Remove-Item -LiteralPath $temporary -Force
    }
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & $node.Source --check (Join-Path $resource 'html\app.js')
    if ($LASTEXITCODE -ne 0) { $failures.Add('NUI JavaScript syntax') }
}

$manifest = Get-Content -LiteralPath (Join-Path $resource 'fxmanifest.lua') -Raw
[regex]::Matches($manifest, "'([^']+\.(lua|html|css|js))'") | ForEach-Object {
    $relative = $_.Groups[1].Value
    if (-not $relative.StartsWith('@') -and -not $relative.Contains('*') -and
        -not (Test-Path -LiteralPath (Join-Path $resource $relative))) {
        $failures.Add("Missing manifest path: $relative")
    }
}

$source = Get-ChildItem -LiteralPath $resource -Recurse -File -Include '*.lua','*.js' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
foreach ($contract in @(
    'cm-police:server:spikeStripDeployed',
    'cm-police:server:barricadeDeployed',
    'cm-police:server:dashboard',
    'cm-police:server:payImpound',
    'cm-police:server:beginTow',
    'cm-police:server:searchPlayer',
    'cm-police:client:impoundKioskUpdated',
    'cm-police:client:bookingIntake',
    'npcInteraction:show'
)) {
    if (-not ($source -match [regex]::Escape($contract))) { $failures.Add("Missing contract: $contract") }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'cm-police static validation passed.'
