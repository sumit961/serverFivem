[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'lib\qa-common.ps1')
. (Join-Path $PSScriptRoot '..\cm-runtime\Common.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Get-CmQaRepoRoot
$runtimeRoot = Join-Path $repo 'tools\cm-runtime'
$localPath = Join-Path $runtimeRoot 'runtime.local.json'
$examplePath = Join-Path $runtimeRoot 'runtime.example.json'
$events = [Collections.Generic.List[object]]::new()

if (-not (Test-Path -LiteralPath $localPath)) {
    Copy-Item -LiteralPath $examplePath -Destination $localPath
    $events.Add([ordered]@{ id='RUNTIME_LOCAL_CREATED'; result='PASS'; detail='Copied runtime.example.json to ignored runtime.local.json.' })
}

$config = Read-CmRuntimeConfig
$json = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json
foreach ($name in @('fxServerPath','txDataPath','serverDataRoot','txAdminProfile','logDirectory')) {
    if ($config.PSObject.Properties.Name -contains $name -and $config.$name) { $json.$name = $config.$name }
}
if ($json.PSObject.Properties.Name -notcontains 'qa' -or $null -eq $json.qa) {
    $json | Add-Member -MemberType NoteProperty -Name 'qa' -Value ([pscustomobject]@{ autoPair = $false; characterId = $null })
} else {
    if ($json.qa.PSObject.Properties.Name -notcontains 'autoPair') { $json.qa | Add-Member -MemberType NoteProperty -Name 'autoPair' -Value $false }
    if ($json.qa.PSObject.Properties.Name -notcontains 'characterId') { $json.qa | Add-Member -MemberType NoteProperty -Name 'characterId' -Value $null }
}
$json.developmentOnly = ($config.developmentOnly -eq $true)
$json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $localPath -Encoding utf8

$qaConfigured = $false
$qaCharacterId = $null
if ($config.PSObject.Properties.Name -contains 'qa' -and $null -ne $config.qa -and $config.qa.PSObject.Properties.Name -contains 'characterId' -and $null -ne $config.qa.characterId) {
    try {
        $candidate = [int64]$config.qa.characterId
        if ($candidate -ge 1 -and $candidate -le 2147483647 -and ([math]::Truncate([double]$candidate) -eq [double]$candidate)) {
            $qaConfigured = $true
            $qaCharacterId = $candidate
        }
    } catch { $qaConfigured = $false }
}
$qaAutoPair = $config.PSObject.Properties.Name -contains 'qa' -and $null -ne $config.qa -and $config.qa.PSObject.Properties.Name -contains 'autoPair' -and $config.qa.autoPair -eq $true
if (-not $qaConfigured) {
    $events.Add([ordered]@{ id='QA_CHARACTER_NOT_CONFIGURED'; result='BLOCKED'; status='QA_CHARACTER_NOT_CONFIGURED'; detail='Set qa.autoPair=true and the intended authoritative character ID in ignored tools/cm-runtime/runtime.local.json. Do not use a source ID or guess a character.' })
} elseif (-not $qaAutoPair) {
    $events.Add([ordered]@{ id='QA_CHARACTER_AUTO_PAIR_DISABLED'; result='BLOCKED'; status='QA_CHARACTER_AUTO_PAIR_DISABLED'; detail=('Character ID {0} is configured, but qa.autoPair is false. Set qa.autoPair=true to enable local pairing.' -f $qaCharacterId) })
} else {
    $events.Add([ordered]@{ id='QA_CHARACTER_CONFIGURED'; result='PASS'; status='QA_CHARACTER_CONFIGURED'; characterId=$qaCharacterId; detail='Configured character ID is bounded and auto-pairing is enabled; no source or identifier was stored.' })
}

$safety = Test-CmQaRuntimeSafety
$events.Add([ordered]@{ id='RUNTIME_SAFETY'; result=if($safety.ok){'PASS'}else{'BLOCKED'}; detail=$safety.reason })
$serverCfg = Get-Content -Raw -LiteralPath (Join-Path $repo 'server.cfg')
$devConfigured = $serverCfg -match '(?m)^\s*set\s+cm_environment\s+[''\"]development[''\"]\s*$'
$events.Add([ordered]@{ id='SERVER_ENVIRONMENT_DEVELOPMENT'; result=if($devConfigured){'PASS'}else{'BLOCKED'}; detail='server.cfg must set cm_environment to development.' })

$secretName = [string]$config.rconPasswordEnvironmentVariable
$secretPresent = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($secretName))
$events.Add([ordered]@{ id='RCON_PASSWORD_ENVIRONMENT'; result=if($secretPresent){'PASS'}else{'BLOCKED'}; status=if($secretPresent){'RCON_PASSWORD_ENVIRONMENT_PRESENT'}else{'RCON_PASSWORD_ENVIRONMENT_MISSING'}; detail=if($secretPresent){'Environment variable is present; value was not printed or stored.'}else{"Set $secretName in this PowerShell session; do not place it in runtime.local.json."} })
$localServerCfg = Join-Path $repo 'server.local.cfg'
$serverRconLine = if(Test-Path -LiteralPath $localServerCfg){ Select-String -LiteralPath $localServerCfg -Pattern '^\s*(?:set\s+)?rcon_password\s+(.+?)\s*$' | Select-Object -First 1 } else { $null }
$serverPasswordMatches = $false
if($serverRconLine -and $secretPresent){ $serverPasswordMatches = ($serverRconLine.Matches[0].Groups[1].Value.Trim().Trim('"') -eq [Environment]::GetEnvironmentVariable($secretName)) }
$events.Add([ordered]@{ id='RCON_SERVER_CONFIGURATION'; result=if($serverPasswordMatches){'PASS'}else{'BLOCKED'}; status=if($serverPasswordMatches){'RCON_SERVER_PASSWORD_MATCH'}else{'RCON_SERVER_PASSWORD_NOT_VERIFIED'}; detail=if($serverPasswordMatches){'Ignored local server configuration contains a matching RCon password; secret value was not printed.'}else{'server.local.cfg must contain the matching rcon_password for the configured environment variable.'} })
$portListeners=@(Get-NetUDPEndpoint -LocalPort ([int]$config.fivemPort) -ErrorAction SilentlyContinue)
$sendBridge=Join-Path $repo 'tools\cm-runtime\send-command.ps1'
$rconProbe=Invoke-CmQaCommand 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sendBridge,'cm_qa_status')
$bridgeReachable=$rconProbe.output -match 'SUCCESSFUL_SEND'
$events.Add([ordered]@{ id='RCON_GAME_PORT'; result=if($bridgeReachable -or $portListeners.Count){'PASS'}else{'BLOCKED'}; status=if($bridgeReachable){'RCON_BRIDGE_REACHABLE'}elseif($portListeners.Count){'GAME_PORT_LISTENING'}else{'GAME_PORT_NOT_LISTENING'}; detail=if($bridgeReachable){'The allowlisted local RCon bridge successfully reached the development server; the OS UDP probe did not expose a listener.'}elseif($portListeners.Count){'Configured local game UDP port has a listener.'}else{'No local UDP listener was found and the allowlisted RCon bridge did not receive a response.'}; probeOutput=$rconProbe.output })

$owned = @(Get-CmOwnedProcesses $config)
$log = Get-CmConsoleLog $config
$logText = if ($log) { (Get-Content -LiteralPath $log.FullName -Tail 5000 -ErrorAction SilentlyContinue) -join "`n" } else { '' }
$dbReady = $logText -match '(?i)(Started resource oxmysql|oxmysql.*ready|database connection.*ready|mysql.*ready)'
$events.Add([ordered]@{ id='DATABASE'; result=if($dbReady){'PASS'}else{'BLOCKED'}; status=if($dbReady){'DATABASE_READY'}else{'DATABASE_QA_BLOCKED'}; detail=if($dbReady){'Local console log shows the database resource ready.'}else{'No authoritative oxmysql/MySQL ready marker was found in the local console log; no database was started or mutated.'} })
$events.Add([ordered]@{ id='LOCAL_SERVER'; result=if($owned.Count){'PASS'}else{'BLOCKED'}; status=if($owned.Count){'SERVER_RUNNING'}else{'SERVER_NOT_RUNNING'}; detail=if($owned.Count){'Managed local FXServer process discovered.'}else{'Start or reuse the managed local development server before runtime QA.'} })

$result = if (@($events | Where-Object result -eq 'BLOCKED').Count) { 'BLOCKED' } else { 'PASS' }
$output = [ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); result=$result; runtimeLocalPath=$localPath; qa=[ordered]@{ autoPair=$qaAutoPair; characterId=$qaCharacterId }; discovered=[ordered]@{ fxServerPath=$config.fxServerPath; txDataPath=$config.txDataPath; serverDataRoot=$config.serverDataRoot; txAdminProfile=$config.txAdminProfile; logDirectory=$config.logDirectory }; checks=@($events); secretEnvironmentVariable=$secretName }
$outPath = Join-Path (Get-CmQaOutputRoot) 'bootstrap.json'
Write-CmQaJson $outPath $output
$events | ForEach-Object { Write-Output ("{0}: {1} - {2}" -f $_.id,$_.result,$_.detail) }
Write-Output $outPath
if ($result -eq 'BLOCKED') { exit 2 }
exit 0
