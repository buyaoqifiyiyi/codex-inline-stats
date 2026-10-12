# Check both loopback families: Chromium may choose either when it starts.
function Test-DebugPortFree([int]$Port) {
    $sockets = @()
    try {
        foreach ($address in @([Net.IPAddress]::Loopback, [Net.IPAddress]::IPv6Loopback)) {
            $socket = New-Object Net.Sockets.Socket($address.AddressFamily, [Net.Sockets.SocketType]::Stream, [Net.Sockets.ProtocolType]::Tcp)
            $sockets += $socket
            $socket.ExclusiveAddressUse = $true
            if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { $socket.DualMode = $false }
            $socket.Bind((New-Object Net.IPEndPoint($address, $Port)))
            $socket.Listen(1)
        }
        return $true
    } catch [Net.Sockets.SocketException] { return $false }
    finally { foreach ($socket in $sockets) { $socket.Dispose() } }
}
function Select-DebugPort([int]$PreferredPort) {
    if ($PreferredPort -ge 1024 -and $PreferredPort -le 65535 -and (Test-DebugPortFree $PreferredPort)) { return $PreferredPort }
    foreach ($port in (@(19335) + @(1..32 | ForEach-Object { Get-Random -Minimum 20000 -Maximum 49000 }))) {
        if (Test-DebugPortFree $port) { return $port }
    }
    throw 'No free IPv4/IPv6 loopback port found for Codex debugging.'
}
