# Block Zero – Testnet portproxy + firewall setup
# Run this script once as Administrator.
# Re-run after a WSL reboot (WSL IP can change).

$wslIp = (wsl bash -c "hostname -I | cut -d' ' -f1").Trim()
Write-Host "WSL IP: $wslIp"

# Remove any old rule for this port first
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=18210 2>$null

# Add fresh portproxy: Windows 0.0.0.0:18210 -> WSL:18210
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=18210 connectaddress=$wslIp connectport=18210
Write-Host "Portproxy added"

# Windows Firewall: allow inbound TCP 18210
netsh advfirewall firewall delete rule name="BlockZero Testnet P2P" 2>$null
netsh advfirewall firewall add rule name="BlockZero Testnet P2P" dir=in action=allow protocol=TCP localport=18210
Write-Host "Firewall rule added"

Write-Host ""
Write-Host "=== current portproxy ==="
netsh interface portproxy show all

Write-Host ""
Write-Host "Done. Your testnet P2P port 18210 is now forwarded from the internet to WSL."
Write-Host "Public IP: $(Invoke-WebRequest -Uri 'https://ifconfig.me' -UseBasicParsing | Select-Object -ExpandProperty Content)"
Write-Host ""
Write-Host "NEXT: Make sure your router forwards TCP 18210 to this machine's LAN IP."
