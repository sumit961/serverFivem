[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repo 'tools\cm-qa\lib\window-discovery.ps1')

function New-SyntheticWindow([string]$Name, [int]$Score, [bool]$Accepted=$true, [bool]$Visible=$true, [int]$Width=1280, [int]$Height=720) {
    return [pscustomobject]@{ name=$Name; score=$Score; accepted=$Accepted; visible=$Visible; clientWidth=$Width; clientHeight=$Height; hwndValue=$Score; process=$Name; title=$Name; class='grcWindow'; pid=$Score }
}
function Assert-Window([string]$Name, [bool]$Condition) { if (-not $Condition) { throw "QA_WINDOW_DISCOVERY_REGRESSION_FAIL: $Name" } }

$one = Select-CmQaWindowCandidate @((New-SyntheticWindow 'FiveM_b3258_GTAProcess' 155))
Assert-Window 'one-valid-fivem-window-selected' ($one.status -eq 'CLIENT_WINDOW_FOUND' -and $one.selected.name -eq 'FiveM_b3258_GTAProcess')

$launcher = New-SyntheticWindow 'FiveM' 75
$renderer = New-SyntheticWindow 'FiveM_b3258_GTAProcess' 155
$family = Select-CmQaWindowCandidate @($launcher,$renderer)
Assert-Window 'launcher-plus-renderer-prefers-renderer' ($family.status -eq 'CLIENT_WINDOW_FOUND' -and $family.selected.name -eq 'FiveM_b3258_GTAProcess')

$hidden = Select-CmQaWindowCandidate @((New-SyntheticWindow 'FiveM_b3258_GTAProcess' 155 $true $false))
Assert-Window 'hidden-helper-rejected' ($hidden.status -eq 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_NOT_FOUND')

$cef = Select-CmQaWindowCandidate @((New-SyntheticWindow 'FiveM_ChromeBrowser' 155 $false))
Assert-Window 'cef-helper-rejected' ($cef.status -eq 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_NOT_FOUND')

$vscode = Select-CmQaWindowCandidate @((New-SyntheticWindow 'Code' 155 $false))
Assert-Window 'vscode-fivem-title-rejected' ($vscode.status -eq 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_NOT_FOUND')

$ambiguous = Select-CmQaWindowCandidate @((New-SyntheticWindow 'FiveM_b3258_GTAProcess' 155),(New-SyntheticWindow 'FiveM_b3258_GTAProcess' 155))
Assert-Window 'equivalent-renderers-ambiguous' ($ambiguous.status -eq 'CLIENT_DRIVER_BLOCKED_AMBIGUOUS_FIVEM_WINDOW')

$none = Select-CmQaWindowCandidate @()
Assert-Window 'no-valid-window-not-found' ($none.status -eq 'CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_NOT_FOUND')

$driver = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools\cm-qa\client-driver.ps1')
Assert-Window 'enum-windows-used' ($driver -match 'EnumWindows')
Assert-Window 'sendinput-used' ($driver -match 'SendInput')
Assert-Window 'foreground-verified' ($driver -match 'CLIENT_DRIVER_BLOCKED_FOCUS_FAILED' -and $driver -match 'IsForeground')
Assert-Window 'attach-thread-input-supported' ($driver -match 'AttachThreadInput')
Assert-Window 'keyup-finally-safety' ($driver -match 'finally' -and $driver -match 'SendKey\(\$vk,\$true\)')
Assert-Window 'stale-window-rediscovery' ($driver -match 'FIVEM_WINDOW_STALE' -and $driver -match 'Get-CmQaWindowSelection')
if ($driver -match 'MainWindowTitle.*FiveM') { throw 'QA_WINDOW_DISCOVERY_REGRESSION_FAIL: old-title-only-rule-present' }

Write-Output 'QA_WINDOW_DISCOVERY_REGRESSION_PASS qa.harness.window-discovery'
