[CmdletBinding()]
param([Parameter(Mandatory, Position=0)][string]$Command)

. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Read-CmRuntimeConfig

if ($config.developmentOnly -ne $true) { throw 'Safety stop: developmentOnly must be true.' }
if ([string]$config.host -notin @('127.0.0.1', 'localhost', '::1')) { throw 'Safety stop: automatic RCon is loopback-only.' }
$arsenalCommandAllowed = $Command -match '^cm_arsenal_(?:start|cancel|status)$' -or
    $Command -match '^cm_arsenal_check(?:\s+[A-Za-z0-9:_.-]{1,80})?$'
if ($Command -notmatch '^(status|refresh)$' -and
    $Command -notmatch '^(ensure|restart|start|stop)\s+(cm-[a-z0-9_-]+|rn-vehicleshop)$' -and
    -not $arsenalCommandAllowed) { throw 'COMMAND_NOT_ALLOWLISTED' }

$secretName = [string]$config.rconPasswordEnvironmentVariable
$password = [Environment]::GetEnvironmentVariable($secretName)
if ([string]::IsNullOrWhiteSpace($password)) {
    Write-Output 'LOCAL_CONSOLE_COMMAND_BRIDGE_NOT_CONFIGURED'
    Write-Output "Set the $secretName environment variable for this PowerShell session, configure rcon_password manually in ignored server.local.cfg, and keep the FXServer UDP endpoint locally firewalled."
    return
}

$port = [int]$config.fivemPort
if ($port -lt 1 -or $port -gt 65535) { throw 'INVALID_FIVEM_UDP_PORT' }
$timeout = if ($config.PSObject.Properties.Name -contains 'rconResponseTimeoutMilliseconds') { [int]$config.rconResponseTimeoutMilliseconds } else { 1500 }
if ($timeout -lt 100 -or $timeout -gt 10000) { throw 'INVALID_RCON_RESPONSE_TIMEOUT' }

function Test-RconlogAvailable {
    $log = Get-CmConsoleLog $config
    if (-not $log) { return $false }
    $lines = Get-Content -LiteralPath $log.FullName -Tail 5000 -ErrorAction SilentlyContinue
    $lastStarted = -1; $lastStopped = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '(?i)Started resource rconlog') { $lastStarted = $index }
        if ($lines[$index] -match '(?i)Stopping resource rconlog|Stopped resource rconlog') { $lastStopped = $index }
    }
    return ($lastStarted -ge 0 -and $lastStarted -gt $lastStopped)
}

# Cfx/FXServer uses the Quake-style UDP out-of-band format. The source sends
# exact-length datagrams: four 0xFF prefix bytes plus UTF-8/ASCII command text,
# with no length field, request ID, packet type, login step, or terminator.
$requestText = "rcon $password $Command"
$requestBody = [Text.Encoding]::UTF8.GetBytes($requestText)
$request = [byte[]]::new(4 + $requestBody.Length)
for ($index = 0; $index -lt 4; $index++) { $request[$index] = 0xFF }
[Array]::Copy($requestBody, 0, $request, 4, $requestBody.Length)

$responses = [Collections.Generic.List[string]]::new()
$commandLog = if ($arsenalCommandAllowed) { Get-CmConsoleLog $config } else { $null }
$commandLogOffset = if ($commandLog) { [int64]$commandLog.Length } else { 0 }
$client = [Net.Sockets.UdpClient]::new()
try {
    $client.Client.ReceiveTimeout = $timeout
    $client.Connect([string]$config.host, $port)
    $sent = $client.Send($request, $request.Length)
    if ($sent -ne $request.Length) { Write-Output 'INVALID_RESPONSE'; return }

    $deadline = [DateTime]::UtcNow.AddMilliseconds($timeout)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $remote = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
            $datagram = $client.Receive([ref]$remote)
        } catch [Net.Sockets.SocketException] {
            if ($_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut) { break }
            throw
        }
        if (-not $datagram -or $datagram.Length -lt 1) { continue }
        $offset = 0
        if ($datagram.Length -ge 4 -and $datagram[0] -eq 0xFF -and $datagram[1] -eq 0xFF -and $datagram[2] -eq 0xFF -and $datagram[3] -eq 0xFF) { $offset = 4 }
        $text = [Text.Encoding]::UTF8.GetString($datagram, $offset, $datagram.Length - $offset).TrimEnd([char]0, "`r", "`n")
        $text = [regex]::Replace($text, '^print(?:\r?\n|\s)', '')
        if ($text -match '(?i)invalid password|bad rcon|rcon.*disabled|not authorized') { Write-Output 'AUTH_OR_RCON_FAILURE'; return }
        if ($text) { $responses.Add((Protect-CmRuntimeText $text)) }
    }

    if ($arsenalCommandAllowed -and -not $responses.Count -and $commandLog) {
        # Database-backed commands can finish after the UDP response window;
        # read their authoritative console result from this command's offset.
        Start-Sleep -Milliseconds 1500
        $stream = [IO.File]::Open($commandLog.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $commandLogOffset = [Math]::Min($commandLogOffset, $stream.Length)
            $stream.Seek($commandLogOffset, [IO.SeekOrigin]::Begin) | Out-Null
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 4096, $true)
            try { $newLogText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
        $resultPattern = if ($Command -eq 'cm_arsenal_status') { 'ARSENAL RESUPPLY' } elseif ($Command -eq 'cm_arsenal_start') { 'ARSENAL START' } elseif ($Command -eq 'cm_arsenal_cancel') { 'ARSENAL CANCEL' } else { 'ARSENAL INVARIANT' }
        $arsenalLines = @($newLogText -split "`r?`n" | Where-Object { $_ -match "\[cm-law\].*$([regex]::Escape($resultPattern))" })
        if (-not $arsenalLines.Count) {
            $arsenalLines = @(Get-Content -LiteralPath $commandLog.FullName -Tail 100 -ErrorAction SilentlyContinue | Where-Object { $_ -match "\[cm-law\].*$([regex]::Escape($resultPattern))" })
        }
        if ($arsenalLines.Count) { $responses.Add((Protect-CmRuntimeText $arsenalLines[-1])) }
    }

    $state = Read-CmRuntimeState
    $state.commandsSent += @([ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); command=$Command; transport='FiveM UDP OOB'; host=[string]$config.host; port=$port })
    Write-CmRuntimeState $state

    $statusUnavailable = $Command -eq 'status' -and -not (Test-RconlogAvailable) -and ($responses.Count -eq 0 -or ($responses -join "`n") -match '(?i)no such command\s+status')
    if ($statusUnavailable) {
        Write-Output 'RCON_TRANSPORT_OK_BUT_RCONLOG_STATUS_UNAVAILABLE'
    } elseif ($responses.Count) {
        Write-Output 'SUCCESSFUL_SEND'
        $responses | Select-Object -Unique | Write-Output
    } else {
        Write-Output 'TIMEOUT_WAITING_FOR_RESPONSE'
    }
} finally {
    if ($requestBody) { [Array]::Clear($requestBody, 0, $requestBody.Length) }
    if ($request) { [Array]::Clear($request, 0, $request.Length) }
    $requestText = $null; $password = $null; $client.Dispose()
}
