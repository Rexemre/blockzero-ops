# Block Zero testnet miner (Windows, native binaries — NOT WSL)
# Usage:
#   .\mine-testnet.ps1              # start node + mine
#   .\mine-testnet.ps1 -Status      # show height and balance
#   .\mine-testnet.ps1 -Stop        # stop bitcoind
#
# Requires bitcoind.exe and bitcoin-cli.exe on PATH or in -BinDir.

param(
    [string]$BinDir = "",
    [string]$DataDir = "$env:LOCALAPPDATA\BlockZero\testnet3",
    [string]$WalletName = "mining",
    [int]$MaxTries = 500000000,
    [switch]$Status,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"

function Find-Exe([string]$Name) {
    if ($BinDir) {
        $p = Join-Path $BinDir $Name
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "Cannot find $Name. Set -BinDir or add Block Zero bin to PATH. See quickstart-mining.md"
}

function Invoke-Cli([string[]]$Args) {
    $cli = Find-Exe "bitcoin-cli.exe"
    & $cli -testnet -datadir="$DataDir" -rpcport=18211 @Args
}

if ($Stop) {
    try { Invoke-Cli @("stop") | Out-Null; Write-Host "bitcoind stopped." }
    catch { Write-Host "bitcoind was not running." }
    exit 0
}

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
}

$conf = Join-Path $DataDir "bitcoin.conf"
if (-not (Test-Path $conf)) {
    $example = Join-Path $PSScriptRoot "bitcoin.conf.example"
    if (Test-Path $example) {
        Copy-Item $example $conf
        Write-Host "Created $conf from example."
    } else {
        throw "Missing bitcoin.conf in $DataDir"
    }
}

$daemon = Find-Exe "bitcoind.exe"
$running = Get-Process bitcoind -ErrorAction SilentlyContinue

if (-not $running) {
    Write-Host "Starting bitcoind (native Windows, testnet)..."
    & $daemon -testnet -datadir="$DataDir" -daemon
    Start-Sleep -Seconds 6
}

try { Invoke-Cli @("loadwallet", $WalletName) 2>$null | Out-Null } catch {}
try {
    Invoke-Cli @("createwallet", $WalletName) | Out-Null
    Write-Host "Created wallet '$WalletName'."
} catch {
    # wallet may already exist
}

$addr = Invoke-Cli @("-rpcwallet=$WalletName", "getnewaddress")
$height = Invoke-Cli @("getblockcount")

if ($Status) {
    $bal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
    Write-Host "Height: $height"
    Write-Host "Mining address: $addr"
    Write-Host "Immature TBLOZ: $($bal.mine.immature)"
    exit 0
}

Write-Host "Chain height: $height"
Write-Host "Mining to: $addr"
Write-Host "Press Ctrl+C to stop mining (node keeps running). Use -Stop to shut down bitcoind."
Write-Host ""

while ($true) {
    $height = [int](Invoke-Cli @("getblockcount"))
    Write-Host "$(Get-Date -Format 'HH:mm:ss') height=$height mining..."
    $result = Invoke-Cli @("-rpcwallet=$WalletName", "generatetoaddress", "1", $addr, "$MaxTries")
    if ($result -match '[0-9a-f]{64}') {
        Write-Host "Block found: $result"
        $height = Invoke-Cli @("getblockcount")
        if ([int]$height -gt 0) {
            $bal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
            Write-Host "New height: $height | immature TBLOZ: $($bal.mine.immature)"
        }
    }
    Start-Sleep -Seconds 2
}
