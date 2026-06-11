# BLOZ pool miner (Windows) — no node sync, no wallet setup, just mine.
# Usage:
#   .\mine-pool-mainnet.ps1              # install + mine (asks for bz1 address first time)
#   .\mine-pool-mainnet.ps1 -Status      # pool height, fee, stratum status
#   .\mine-pool-mainnet.ps1 -Install     # download miner only
#   .\mine-pool-mainnet.ps1 -Address bz1... -Threads 8
#
# Payouts go to the bz1 address in your worker name (PPLNS, 2% fee).

param(
    [string]$Address = "",
    [string]$WorkerName = "",
    [string]$PoolUrl = "wss://pool.bloz.org/stratum",
    [string]$InstallDir = "$env:LOCALAPPDATA\BlockZero\pool",
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
    # Standalone: blockzero-ops only (no local blockzero-pool clone)
    $repo = "Rexemre/blockzero-pool"
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    if (-not (Test-Path $ExePath) -or $Force) {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -eq "bz-pool-miner.exe" } | Select-Object -First 1
        if (-not $asset) { throw "Download bz-pool-miner.exe from https://github.com/$repo/releases" }
        Write-Host "Downloading bz-pool-miner ($($rel.tag_name))..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ExePath -UseBasicParsing
    }
    if (-not (Test-Path $ConfPath)) {
        if (-not $Address) {
            Write-Host "Enter your bz1 payout address:"
            $script:Address = Read-Host
        }
        if (-not $WorkerName) { $script:WorkerName = "rig1" }
        $t = Get-ThreadCount
        @"
POOL_URL=$PoolUrl
BZ1_ADDRESS=$Address
WORKER_NAME=$WorkerName
POOL_PASS=x
THREADS=$t
"@ | Set-Content -Path $ConfPath -Encoding ASCII
    }
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
    if (Test-Path $ConfPath) {
        $addr = Read-ConfValue "BZ1_ADDRESS"
        $worker = Read-ConfValue "WORKER_NAME"
        if ($addr -and $worker) {
            Write-Host "Your worker: $addr.$worker"
        }
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
if (-not $WorkerName) { $WorkerName = Read-ConfValue "WORKER_NAME" }
if (-not $WorkerName) { $WorkerName = "rig1" }

if (-not $Address -or $Address -eq "bz1YOURADDRESSHERE") {
    Write-Host "No payout address configured."
    Write-Host "Run: .\mine-pool-mainnet.ps1 -Address bz1YOURADDRESS"
    exit 1
}

if (-not (Test-Path $ExePath)) {
    throw "Miner missing at $ExePath — run with -Install"
}

$t = Get-ThreadCount
$worker = "$Address.$WorkerName"

Show-PoolStatus
Write-Host "Starting miner..."
Write-Host "Worker: $worker | Threads: $t"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

& $ExePath -o $PoolUrl -u $worker -p x -t $t
