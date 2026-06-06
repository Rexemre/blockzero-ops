# Reset a solo/forked MAINNET datadir and re-sync to the public Block Zero mainnet.
# Usage (PowerShell):
#   .\resync-mainnet.ps1
#
# Keeps the wallet; wipes chain data, chainstate and the (stale) txindex.

param(
    [string]$DataDir = "$env:LOCALAPPDATA\BlockZeroMainnet",
    [string]$BinDir = "$env:LOCALAPPDATA\BlockZero\bin"
)

. "$PSScriptRoot\chain-identity.ps1"

$ErrorActionPreference = "Stop"

$cli = Join-Path $BinDir "bitcoin-cli.exe"
$daemon = Join-Path $BinDir "bitcoind.exe"

Write-Host "Block Zero mainnet resync"
Write-Host "Datadir: $DataDir"
if ($OfficialGenesis -like "PENDING*") {
    Write-Host ""
    Write-Host "WARNING: chain-identity.ps1 still has a placeholder genesis hash."
    Write-Host "The mainnet genesis must be published first - see blockzero-docs/mainnet-launch.md"
}
Write-Host ""

if (Get-Process bitcoind -ErrorAction SilentlyContinue) {
    Write-Host "Stopping bitcoind..."
    try { & $cli -datadir="$DataDir" "-rpcport=$RpcPort" stop | Out-Null } catch {}
    Start-Sleep -Seconds 5
    Get-Process bitcoind -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Mainnet chain data lives in the datadir root (no testnet3 subdir).
Write-Host "Removing local chain data (wallet is kept)..."
Remove-Item -Recurse -Force (Join-Path $DataDir "blocks") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $DataDir "chainstate") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $DataDir "indexes") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $DataDir "peers.dat") -ErrorAction SilentlyContinue
Remove-Item -Force (Join-Path $DataDir "mempool.dat") -ErrorAction SilentlyContinue

@"
server=1
txindex=1

[main]
listen=1
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=$RpcPort
addnode=$SeedNode
"@ | Set-Content -Path (Join-Path $DataDir "bitcoin.conf") -Encoding ASCII

Write-Host "Starting bitcoind..."
Start-Process -FilePath $daemon -ArgumentList "-datadir=$DataDir" -WindowStyle Hidden

Write-Host "Waiting for peers and sync (up to 2 minutes)..."
$deadline = (Get-Date).AddMinutes(2)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    try {
        $peers = [int](& $cli -datadir="$DataDir" "-rpcport=$RpcPort" getconnectioncount)
        $height = [int](& $cli -datadir="$DataDir" "-rpcport=$RpcPort" getblockcount)
        $genesis = & $cli -datadir="$DataDir" "-rpcport=$RpcPort" getblockhash 0
        Write-Host "  peers=$peers height=$height"
        if ($peers -ge 1 -and $OfficialGenesis -notlike "PENDING*" -and $genesis -eq $OfficialGenesis) {
            Write-Host ""
            Write-Host "Synced to public mainnet at height $height."
            Write-Host "Genesis: $genesis"
            exit 0
        }
        if ($peers -ge 1 -and $height -eq 0) {
            Write-Host ""
            Write-Host "Connected at genesis (height 0). Safe to mine on the public chain."
            exit 0
        }
    } catch {
        Write-Host "  waiting for RPC..."
    }
}

Write-Host ""
Write-Host "Sync not complete yet. Check connectivity to $SeedNode."
exit 1
