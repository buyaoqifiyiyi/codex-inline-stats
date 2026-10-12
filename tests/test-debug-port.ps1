$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'SelectDebugPort.ps1')
function Assert($condition, $label) { if (-not $condition) { throw $label } }
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::IPv6Loopback, 0)
$listener.Server.DualMode = $false
$listener.Server.ExclusiveAddressUse = $true
$listener.Start()
try {
    $occupied = $listener.LocalEndpoint.Port
    Assert (-not (Test-DebugPortFree $occupied)) 'IPv6-only listener must block candidate even when IPv4 is free'
    $chosen = Select-DebugPort $occupied
    Assert ($chosen -ne $occupied) 'Occupied port must be replaced'
    Assert (Test-DebugPortFree $chosen) 'Replacement is available on both loopback families'
    Assert ((Select-DebugPort $chosen) -eq $chosen) 'Available configured port remains unchanged'
} finally { $listener.Stop() }
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Server.ExclusiveAddressUse = $true
$listener.Start()
try { Assert (-not (Test-DebugPortFree $listener.LocalEndpoint.Port)) 'IPv4-only occupancy also rejected' }
finally { $listener.Stop() }
Write-Output 'PASS: IPv4 and IPv6 exclusive binding, occupied-port fallback, free-port reuse'
