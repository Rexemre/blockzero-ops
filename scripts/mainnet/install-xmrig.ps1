# Block Zero one-line miner installer (Windows) using patched XMRig.
#
#   $env:ADDRESS='bz1qYOURADDRESS'; irm https://raw.githubusercontent.com/Rexemre/blockzero-ops/main/scripts/mainnet/install-xmrig.ps1 | iex
#
# Env: ADDRESS (required), WORKER (default: hostname), POOL (default pool.bloz.org:3334), THREADS
$ErrorActionPreference = "Stop"

$Repo    = if ($env:REPO) { $env:REPO } else { "Rexemre/blockzero-ops" }
$Pool    = if ($env:POOL) { $env:POOL } else { "pool.bloz.org:3334" }
$Address = if ($env:ADDRESS) { $env:ADDRESS } else { $args[0] }
$Worker  = if ($env:WORKER) { $env:WORKER } else { $env:COMPUTERNAME }
$Dir     = Join-Path $env:LOCALAPPDATA "BlockZero\xmrig"

if (-not $Address) { throw "Set your address: `$env:ADDRESS='bz1...'" }
if ($Address -notlike "bz1*") { throw "Address must start with bz1 (got: $Address)" }

# Resolve latest xmrig-v* release tag.
$rels = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases"
$rel  = $rels | Where-Object { $_.tag_name -like "xmrig-v*" } | Select-Object -First 1
if (-not $rel) { throw "No xmrig-v* release found in $Repo" }
$asset = $rel.assets | Where-Object { $_.name -eq "bz-xmrig-windows-x64.zip" } | Select-Object -First 1
if (-not $asset) { throw "No bz-xmrig-windows-x64.zip in $($rel.tag_name) (Windows build may still be in progress)" }

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$zip = Join-Path $Dir "xmrig.zip"
Write-Host "Downloading $($asset.name) ($($rel.tag_name))..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $Dir -Force
$exe = Get-ChildItem -Path $Dir -Recurse -Filter "xmrig.exe" | Select-Object -First 1
if (-not $exe) { throw "xmrig.exe not found after extract" }

$xargs = @("-a","rx/blockzero","-o",$Pool,"-u","$Address.$Worker","-p","x")
if ($env:THREADS) { $xargs += @("-t",$env:THREADS) }

Write-Host ""
Write-Host "Starting XMRig: $Address.$Worker on $Pool"
Write-Host "Tip: run PowerShell as Administrator for huge pages (much higher hashrate)."
& $exe.FullName @xargs
