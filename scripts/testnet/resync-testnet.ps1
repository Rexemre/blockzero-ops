# Reset a solo/forked testnet datadir and re-sync to the public Block Zero testnet.
# Usage (PowerShell):
#   .\resync-testnet.ps1
#
# Before resync on Windows: start the WSL bridge node (see quickstart-mining.md)
# or ensure the VPS seed 217.160.46.61:18210 is reachable.

param(
    [string]$DataDir = "$env:LOCALAPPDATA\BlockZero",
    [string]$BinDir = "$env:LOCALAPPDATA\BlockZero\bin"
)

$ErrorActionPreference = "Stop"
$OfficialGenesis = "f58130b19cdf3d03b22c5a67a6509b00750b2d8975ee9d889d5b613aaae5296e"
$OfficialBlock1 = "7a28c3b91ddd8404a13a2557eb0e1f8bee664ffc7e7a0a90fb4473f762e6ec79"

$cli = Join-Path $BinDir "bitcoin-cli.exe"
$daemon = Join-Path $BinDir "bitcoind.exe"

Write-Host "Block Zero testnet resync"
Write-Host "Datadir: $DataDir"
Write-Host ""

if (Get-Process bitcoind -ErrorAction SilentlyContinue) {
    Write-Host "Stopping bitcoind..."
    try { & $cli -testnet -datadir="$DataDir" -rpcport=18211 stop | Out-Null } catch {}
    Start-Sleep -Seconds 5
    Get-Process bitcoind -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$chainDir = Join-Path $DataDir "testnet3"
Write-Host "Removing local chain data (wallet is kept)..."
Remove-Item -Recurse -Force (Join-Path $chainDir "blocks") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $chainDir "chainstate") -ErrorAction SilentlyContinue

@"
server=1
txindex=1

[test]
listen=0
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=18211
addnode=217.160.46.61:18210
"@ | Set-Content -Path (Join-Path $DataDir "bitcoin.conf") -Encoding UTF8

Write-Host "Starting bitcoind..."
Start-Process -FilePath $daemon -ArgumentList "-testnet", "-datadir=$DataDir" -WindowStyle Hidden

Write-Host "Waiting for peers and sync (up to 2 minutes)..."
$deadline = (Get-Date).AddMinutes(2)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    try {
        $peers = [int](& $cli -testnet -datadir="$DataDir" -rpcport=18211 getconnectioncount)
        $height = [int](& $cli -testnet -datadir="$DataDir" -rpcport=18211 getblockcount)
        $genesis = & $cli -testnet -datadir="$DataDir" -rpcport=18211 getblockhash 0
        Write-Host "  peers=$peers height=$height"
        if ($peers -ge 1 -and $genesis -eq $OfficialGenesis) {
            if ($height -ge 1) {
                $b1 = & $cli -testnet -datadir="$DataDir" -rpcport=18211 getblockhash 1
                if ($b1 -eq $OfficialBlock1) {
                    Write-Host ""
                    Write-Host "Synced to public testnet at height $height."
                    Write-Host "Block 1: $b1"
                    exit 0
                }
            }
            if ($height -eq 0 -and $peers -ge 1) {
                Write-Host ""
                Write-Host "Connected to network at genesis. Safe to mine block 1 on the public chain."
                exit 0
            }
        }
    } catch {
        Write-Host "  waiting for RPC..."
    }
}

Write-Host ""
Write-Host "Sync not complete yet."
Write-Host "Check: bitcoin-cli -testnet -datadir=`"$DataDir`" getconnectioncount  (need >= 1)"
Write-Host "On Windows, start the WSL bridge first:"
Write-Host "  wsl -e bash -lc 'bitcoind -testnet -datadir=/home/marlon/.bzero -daemon'"
Write-Host "Or wait until VPS seed 217.160.46.61:18210 is reachable."
exit 1
