# Fix bitcoin-qt using the wrong Windows datadir (legacy Bitcoin folder in QSettings).
# Run once if you see: "Incorrect or no genesis block found. Wrong datadir for network?"
#
# Usage: .\fix-wallet-datadir.ps1

$ErrorActionPreference = "Stop"
$mainnetDir = Join-Path $env:LOCALAPPDATA "BlockZeroMainnet"
$legacyDir = Join-Path $env:LOCALAPPDATA "Bitcoin"
$regKey = "HKCU:\Software\Bitcoin\Bitcoin-Qt"

if (-not (Test-Path $mainnetDir)) {
    New-Item -ItemType Directory -Force -Path $mainnetDir | Out-Null
}

if (Test-Path $regKey) {
    $current = (Get-ItemProperty -Path $regKey -Name strDataDir -ErrorAction SilentlyContinue).strDataDir
    if ($current -eq $legacyDir) {
        Set-ItemProperty -Path $regKey -Name strDataDir -Value $mainnetDir
        Write-Host "Updated QSettings strDataDir: $legacyDir -> $mainnetDir"
    } elseif ($current -eq $mainnetDir) {
        Write-Host "QSettings strDataDir already correct: $mainnetDir"
    } else {
        Write-Host "QSettings strDataDir is custom: $current (not changed)"
    }
} else {
    Write-Host "No Bitcoin-Qt QSettings key yet (first run will use BlockZeroMainnet)."
}

Write-Host ""
Write-Host "Start wallet: $env:LOCALAPPDATA\BlockZero\bin\Block Zero.exe"
