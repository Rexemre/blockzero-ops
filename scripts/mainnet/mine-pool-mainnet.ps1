# BLOZ pool miner (Windows) — uses your BlockZero wallet, connects to pool.bloz.org
# Usage:
#   .\mine-pool-mainnet.ps1              # install + mine (BlockZero address auto)
#   .\mine-pool-mainnet.ps1 -Threads 4   # 4 CPU threads
#   .\mine-pool-mainnet.ps1 -Status      # pool height, fee, stratum status
#   .\mine-pool-mainnet.ps1 -Install     # download miner only
#
# Recommended entry point (wallet + pool in one flow):
#   .\mine-mainnet.ps1 -Pool
#   .\mine-mainnet.ps1 -Pool -Threads 4

param(
    [string]$Address = "",
    [string]$WorkerName = "",
    [string]$PoolUrl = "wss://pool.bloz.org/stratum",
    [string]$InstallDir = "$env:LOCALAPPDATA\BlockZero\pool",
    [string]$BlockZeroDataDir = "$env:LOCALAPPDATA\BlockZeroMainnet",
    [int]$Threads = 0,
    [switch]$Status,
    [switch]$Install,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$BinDir = Join-Path $InstallDir "bin"
$ConfPath = Join-Path $InstallDir "miner.conf"
$ExePath = Join-Path $BinDir "bz-pool-miner.exe"
$PoolApi = "https://pool.bloz.org/api/status"

function Read-ConfValue([string]$Key) {
    if (-not (Test-Path $ConfPath)) { return "" }
    foreach ($line in Get-Content $ConfPath) {
        if ($line -match "^\s*#" -or $line -notmatch "=") { continue }
        $parts = $line -split "=", 2
        if ($parts[0].Trim() -eq $Key) { return $parts[1].Trim() }
    }
    return ""
}

function Get-BlockZeroMiningAddress {
    $addrFile = Join-Path $BlockZeroDataDir "mining-address.txt"
    if (-not (Test-Path $addrFile)) { return "" }
    $addr = (Get-Content $addrFile -Raw).Trim()
    if ($addr -match '^bz1') { return $addr }
    return ""
}

function Get-ThreadCount {
    if ($Threads -gt 0) { return $Threads }
    $fromConf = Read-ConfValue "THREADS"
    if ($fromConf -match "^\d+$" -and [int]$fromConf -gt 0) { return [int]$fromConf }
    return [Math]::Max(1, [Math]::Min(16, [Environment]::ProcessorCount))
}

function Ensure-Installed {
    $installer = $null
    foreach ($c in @(
        (Join-Path $PSScriptRoot "..\..\..\blockzero-pool\scripts\install-pool-windows.ps1"),
        (Join-Path $env:USERPROFILE "blockzero\blockzero-pool\scripts\install-pool-windows.ps1")
    )) {
        if (Test-Path $c) { $installer = $c; break }
    }
    if ($installer) {
        $args = @{ InstallDir = $InstallDir }
        if ($Address) { $args.Address = $Address }
        if ($WorkerName) { $args.WorkerName = $WorkerName }
        if ($Force) { $args.Force = $true }
        & $installer @args
        return
    }
    $repo = "Rexemre/blockzero-pool"
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    if (-not (Test-Path $ExePath) -or $Force) {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -eq "bz-pool-miner.exe" } | Select-Object -First 1
        if (-not $asset) { throw "Download bz-pool-miner.exe from https://github.com/$repo/releases" }
        Write-Host "Downloading bz-pool-miner ($($rel.tag_name))..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ExePath -UseBasicParsing
        foreach ($dll in @("libssl-3-x64.dll", "libcrypto-3-x64.dll")) {
            $dllAsset = $rel.assets | Where-Object { $_.name -eq $dll } | Select-Object -First 1
            if ($dllAsset) {
                Invoke-WebRequest -Uri $dllAsset.browser_download_url -OutFile (Join-Path $BinDir $dll) -UseBasicParsing
            }
        }
    }
}

function Save-PoolConfig([string]$Addr, [string]$Worker, [int]$ThreadCount) {
    @"
# BLOZ pool miner - managed by blockzero-ops
# Payout address comes from your BlockZero wallet (mining-address.txt)
POOL_URL=$PoolUrl
BZ1_ADDRESS=$Addr
WORKER_NAME=$Worker
THREADS=$ThreadCount
"@ | Set-Content -Path $ConfPath -Encoding ASCII
}

function Show-PoolStatus {
    try {
        $st = Invoke-RestMethod $PoolApi -TimeoutSec 15
    } catch {
        Write-Host "Could not reach pool API ($PoolApi)"
        Write-Host $_.Exception.Message
        exit 1
    }
    Write-Host "Pool:     $($st.pool)"
    Write-Host "Height:   $($st.height)"
    Write-Host "Peers:    $($st.peers)"
    Write-Host "Stratum:  $($st.stratum)"
    Write-Host "Scheme:   $($st.scheme)"
    Write-Host "Fee:      $($st.fee_percent)%"
    if ($st.pplns) {
        Write-Host "Miners:   $($st.pplns.miners)"
        Write-Host "Shares:   $($st.pplns.total_shares)"
    }
    Write-Host ""
    Write-Host "Dashboard: https://pool.bloz.org"
    $addr = if ($Address) { $Address } else { Read-ConfValue "BZ1_ADDRESS" }
    if (-not $addr) { $addr = Get-BlockZeroMiningAddress }
    $worker = if ($WorkerName) { $WorkerName } else { Read-ConfValue "WORKER_NAME" }
    if (-not $worker) { $worker = "pc" }
    if ($addr -and $worker) {
        Write-Host "Your worker: $addr.$worker"
    }
}

if ($Status) {
    Show-PoolStatus
    exit 0
}

Ensure-Installed

if ($Install) {
    Write-Host "Install complete."
    exit 0
}

if (-not $Address) { $Address = Read-ConfValue "BZ1_ADDRESS" }
if (-not $Address) { $Address = Get-BlockZeroMiningAddress }

if (-not $Address) {
    Write-Host ""
    Write-Host "No BlockZero wallet address found."
    Write-Host "Run this once to create wallet + address, then pool mine:"
    Write-Host "  .\mine-mainnet.ps1 -Pool"
    Write-Host ""
    Write-Host "Or solo setup first:"
    Write-Host "  .\mine-mainnet.ps1"
    exit 1
}

if (-not $WorkerName) { $WorkerName = Read-ConfValue "WORKER_NAME" }
if (-not $WorkerName) { $WorkerName = "pc" }

if (-not (Test-Path $ExePath)) {
    throw "Miner missing at $ExePath - run with -Install"
}

$t = Get-ThreadCount
Save-PoolConfig $Address $WorkerName $t
$worker = "$Address.$WorkerName"

Show-PoolStatus
Write-Host ""
Write-Host "Payout address (BlockZero wallet): $Address"
Write-Host "Starting pool miner..."
Write-Host "Worker: $worker | Threads: $t"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

Push-Location $BinDir
try {
    & $ExePath -o $PoolUrl -u $worker -Threads $t
} finally {
    Pop-Location
}
