# Test whether the Block Zero testnet seed is reachable from this machine.
param(
    [string]$SeedHost = "217.160.46.61",
    [int]$Port = 18210,
    [int]$TimeoutMs = 5000
)

$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $iar = $tcp.BeginConnect($SeedHost, $Port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
    if ($ok -and $tcp.Connected) {
        Write-Host "OK: ${SeedHost}:${Port} is reachable (TCP connect succeeded)."
        exit 0
    }
    Write-Host "FAIL: ${SeedHost}:${Port} timed out after ${TimeoutMs}ms."
    Write-Host ""
    Write-Host "If the VPS node is running (systemctl status blockzero-testnet), open TCP $Port"
    Write-Host "in the IONOS cloud firewall: my.ionos.de -> Server & Cloud -> Netzwerk ->"
    Write-Host "Firewall-Richtlinien -> policy assigned to server -> add inbound TCP $Port."
    exit 1
}
catch {
    Write-Host "FAIL: ${SeedHost}:${Port} - $_"
    exit 1
}
finally {
    $tcp.Close()
}
