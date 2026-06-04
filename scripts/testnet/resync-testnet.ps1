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

. "$PSScriptRoot\chain-identity.ps1"

$ErrorActionPreference = "Stop"

$cli = Join-Path $BinDir "bitcoin-cli.exe"
$daemon = Join-Path $BinDir "bitcoind.exe"

Write-Host "Block Zero testnet resync"
Write-Host "Datadir: $DataDir"
if ($OfficialGenesis -like "PENDING*") {
    Write-Host ""
    Write-Host "WARNING: chain-identity.ps1 still has a placeholder genesis hash."
    Write-Host "Mine the testnet genesis first - see blockzero-docs/testnet-reset.md"
}
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
# Wipe blocks, chainstate AND the txindex - a stale txindex points at the old
# chain's best block and makes bitcoind exit with "best block of txindex not found".
Remove-Item -Recurse -Force (Join-Path $chainDir "blocks") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $chainDir "chainstate") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $chainDir "indexes") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $chainDir "peers.dat") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $chainDir "mempool.dat") -ErrorAction SilentlyContinue

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
        if ($peers -ge 1 -and $OfficialGenesis -notlike "PENDING*" -and $genesis -eq $OfficialGenesis) {
            Write-Host ""
            Write-Host "Synced to public testnet at height $height."
            Write-Host "Genesis: $genesis"
            exit 0
        }
        if ($peers -ge 1 -and $height -eq 0) {
            Write-Host ""
            Write-Host "Connected at genesis (height 0). Safe to mine block 1 on the public chain."
            exit 0
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
