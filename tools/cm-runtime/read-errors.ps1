[CmdletBinding()]
param([int64]$FromOffset = -1, [switch]$NoWrite)
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-CmRuntimeConfig
$log = Get-CmConsoleLog $config
if (-not $log) { throw 'CURRENT_FXSERVER_CONSOLE_LOG_NOT_FOUND' }
$state = Read-CmRuntimeState
if ($FromOffset -lt 0) { $FromOffset = [int64]$state.logStartOffset }
$stream = [IO.File]::Open($log.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
try { $bytes = [byte[]]::new([int]$stream.Length); $read = 0; while ($read -lt $bytes.Length) { $count = $stream.Read($bytes, $read, $bytes.Length - $read); if ($count -eq 0) { break }; $read += $count } } finally { $stream.Dispose() }
$FromOffset = [Math]::Min($FromOffset, $bytes.Length)
$text = [Text.Encoding]::UTF8.GetString($bytes, $FromOffset, $bytes.Length - $FromOffset)
$lines = $text -split "`r?`n"
$pattern = '(?i)SCRIPT ERROR|DATABASE NOT READY|stack traceback|attempt to (?:call|index)|No such export|Failed to start resource|Could not load|Duplicate entry|Unknown column|doesn''t exist|Query:|Unhandled|\bERROR\b'
$blocks = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) {
        $start = [Math]::Max(0, $i - 1); $end = [Math]::Min($lines.Count - 1, $i + 8)
        $block = Protect-CmRuntimeText ($lines[$start..$end] -join "`n")
        if ($block -notmatch '(?i)warning only|asset.*warning|Server list query returned an error') { $blocks += $block }
        $i = $end
    }
}
$entries = @()
foreach ($block in @($blocks | Select-Object -Unique)) {
    $resource = 'unknown'; if ($block -match '(?i)(?:script:|resource\s+|\[)(cm-[a-z0-9_-]+)') { $resource = $Matches[1] }
    $source = $null; if ($block -match '([\w./\\-]+\.(?:lua|js|ts)):(\d+)') { $source = "$($Matches[1]):$($Matches[2])" }
    $databaseAction = $block -match '(?i)Unknown column|doesn''t exist|Duplicate entry|DATABASE NOT READY'
    $entries += [ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); resource=$resource; error=($block -split "`n" | Where-Object { $_ -match $pattern } | Select-Object -First 1); stack=$block; likelySource=$source; query=$(if ($block -match '(?im)^.*Query:.*$') { $Matches[0] } else { $null }); classification=$(if($databaseAction){'DATABASE_ACTION_REQUIRED'}else{'CODE_RUNTIME_ERROR'}) }
}
if (-not $NoWrite) {
    $path = Join-Path (Get-CmRuntimePaths).StateRoot 'ERRORS.md'
    $body = "# Runtime errors`n`nExecution: $($state.executionId)`nLog: $($log.FullName)`nFrom byte offset: $FromOffset`nScanned: $((Get-Date).ToUniversalTime().ToString('o'))`n`n"
    if (-not $entries.Count) { $body += 'No blocking errors found in this execution window.' }
    foreach ($entry in $entries) {
        $body += ('## {0} - {1}' -f $entry.resource, $entry.timestamp) + "`n`n"
        $body += ('- Error: {0}' -f $entry.error) + "`n" + ('- Likely source: {0}' -f $entry.likelySource) + "`n`n"
        $body += ('- Classification: {0}' -f $entry.classification) + "`n`n"
        $body += '```text' + "`n" + $entry.stack + "`n" + '```' + "`n`n"
    }
    [IO.File]::WriteAllText($path, $body, [Text.UTF8Encoding]::new($false)); $state.errorsFound = $entries; $state.logStartOffset = $bytes.Length; Write-CmRuntimeState $state
}
if ($entries.Count) { $entries | ConvertTo-Json -Depth 6; exit 2 }
Write-Output 'NO_BLOCKING_RUNTIME_ERRORS'
