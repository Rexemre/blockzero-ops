# Download Block Zero testnet binaries for Windows (or use local build).
# Usage:
#   .\install-windows.ps1
#   .\install-windows.ps1 -Version v0.1.0-testnet
#
# After install:
#   $env:Path += ";$env:LOCALAPPDATA\BlockZero\bin"
#   .\mine-testnet.ps1

param(
    [string]$Version = "latest",
    [string]$InstallDir = "$env:LOCALAPPDATA\BlockZero",
    [string]$Repo = "Rexemre/blockzero-core"
)

$ErrorActionPreference = "Stop"
$BinDir = Join-Path $InstallDir "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

function Get-ReleaseAssetUrl {
    param([string]$Ver)
    if ($Ver -eq "latest") {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    } else {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/tags/$Ver"
    }
    # Prefer the full GUI zip (includes bitcoin-qt); fall back to the fast
    # CLI-only zip, which builds much sooner and is enough for mining.
    $zips = $rel.assets | Where-Object { $_.name -match "windows-x64.*\.zip$" }
    $asset = ($zips | Where-Object { $_.name -notmatch "-cli\.zip$" } | Select-Object -First 1)
    if (-not $asset) { $asset = ($zips | Select-Object -First 1) }
    if (-not $asset) {
        throw "No windows-x64 release zip found. Tag a release first (see blockzero-core/.github/workflows/release.yml)."
    }
    return @{ Url = $asset.browser_download_url; Name = $asset.name; Tag = $rel.tag_name }
}

Write-Host "Block Zero Windows installer"
Write-Host "Install dir: $InstallDir"
Write-Host ""

if ((Test-Path (Join-Path $BinDir "bitcoind.exe")) -and (Test-Path (Join-Path $BinDir "bitcoin-cli.exe"))) {
    Write-Host "Binaries already present in $BinDir"
} else {
    try {
        $info = Get-ReleaseAssetUrl -Ver $Version
        Write-Host "Downloading $($info.Name) ($($info.Tag))..."
        $zip = Join-Path $env:TEMP $info.Name
        Invoke-WebRequest -Uri $info.Url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
        Remove-Item $zip -Force
        # Release zips use a top-level folder like blockzero-*-windows-x64/ or
        # blockzero-*-windows-x64-cli/ (the fast CLI-only build).
        Get-ChildItem $InstallDir -Directory -Filter "blockzero-*-windows-x64*" | ForEach-Object {
            $srcBin = Join-Path $_.FullName "bin"
            if (Test-Path $srcBin) {
                Get-ChildItem $srcBin -Filter "*.exe" | ForEach-Object {
                    Copy-Item $_.FullName $BinDir -Force
                }
            }
        }
        Write-Host "Installed to $BinDir"
    } catch {
        Write-Host ""
        Write-Host "No prebuilt release available yet."
        Write-Host "Build natively on Windows (recommended for mining speed):"
        Write-Host "  1. Install Visual Studio 2022+ with C++ desktop workload"
        Write-Host "  2. git clone --recurse-submodules https://github.com/$Repo"
        Write-Host "  3. See blockzero-core/doc/build-windows-msvc.md"
        Write-Host '  4. Copy build\bin\bitcoind.exe and bitcoin-cli.exe to' $BinDir
        Write-Host ""
        Write-Host "Do NOT mine in WSL2 - RandomX is much slower there."
        throw
    }
}

$conf = Join-Path $InstallDir "bitcoin.conf"
if (-not (Test-Path $conf)) {
    Copy-Item (Join-Path $PSScriptRoot "bitcoin.conf.example") $conf
}

Write-Host ""
Write-Host "Done. Add to PATH for this session:"
Write-Host ('  $env:Path += {0}{1}{0}' -f '"', $BinDir)
Write-Host ""
Write-Host "Start mining:"
Write-Host ('  .\mine-testnet.ps1 -BinDir {0}{1}{0}' -f '"', $BinDir)
