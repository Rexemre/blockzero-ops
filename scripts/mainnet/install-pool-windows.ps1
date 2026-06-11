# Internal: install bz-pool-miner for blockzero-ops.
param(
    [string]$Address = "",
    [string]$WorkerName = "pc",
    [string]$InstallDir = "$env:LOCALAPPDATA\BlockZero\pool",
    [string]$Version = "latest",
    [string]$Repo = "Rexemre/blockzero-ops",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$BinDir = Join-Path $InstallDir "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$ExePath = Join-Path $BinDir "bz-pool-miner.exe"
$ConfPath = Join-Path $InstallDir "miner.conf"

function Get-MinerRelease {
    param([string]$Ver)
    if ($Ver -eq "latest") {
        $rels = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases"
        $rel = $rels | Where-Object { $_.tag_name -like "pool-miner-v*" } | Select-Object -First 1
        if (-not $rel) { throw "No pool-miner-v* release found in $Repo" }
    } else {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/tags/$Ver"
    }
    $exe = $rel.assets | Where-Object { $_.name -eq "bz-pool-miner.exe" } | Select-Object -First 1
    if (-not $exe) { throw "bz-pool-miner.exe not found in release $($rel.tag_name)" }
    return @{ Tag = $rel.tag_name; Assets = $rel.assets; ExeUrl = $exe.browser_download_url }
}

function Write-MinerConf {
    param([string]$Addr, [string]$Worker, [int]$Threads)
    $cores = [Environment]::ProcessorCount
    if ($Threads -le 0) { $Threads = [Math]::Max(1, [Math]::Min(16, $cores)) }
    @"
# BLOZ pool miner - managed by blockzero-ops
POOL_URL=wss://pool.bloz.org/stratum
BZ1_ADDRESS=$Addr
WORKER_NAME=$Worker
THREADS=$Threads
"@ | Set-Content -Path $ConfPath -Encoding ASCII
}

if ((Test-Path $ExePath) -and -not $Force) {
    Write-Host "Pool miner already installed: $ExePath"
} else {
    $info = Get-MinerRelease -Ver $Version
    Write-Host "Downloading bz-pool-miner ($($info.Tag))..."
    Invoke-WebRequest -Uri $info.ExeUrl -OutFile $ExePath -UseBasicParsing
    foreach ($dll in @("libssl-3-x64.dll", "libcrypto-3-x64.dll")) {
        $asset = $info.Assets | Where-Object { $_.name -eq $dll } | Select-Object -First 1
        if ($asset) {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path $BinDir $dll) -UseBasicParsing
        }
    }
    Write-Host "OK: $ExePath"
}

if ($Address) {
    if ($Address -notmatch "^bz1") { throw "Address must start with bz1" }
    Write-MinerConf -Addr $Address -Worker $WorkerName -Threads 0
}
