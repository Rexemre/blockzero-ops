# Copy Block Zero binaries into %LOCALAPPDATA%\BlockZero\bin for local testing.
# Use this after a local MSVC build OR to deploy from an extracted release folder.
#
# Examples:
#   .\deploy-local-bin.ps1 -SourceDir C:\Users\Marlon\blockzero\blockzero-core\build\bin\Release
#   .\deploy-local-bin.ps1 -SourceDir "$env:LOCALAPPDATA\BlockZero\blockzero-v1.0.0-rc21-windows-x64\bin"
#
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [string]$InstallDir = "$env:LOCALAPPDATA\BlockZero"
)

$ErrorActionPreference = "Stop"
$BinDir = Join-Path $InstallDir "bin"
$SourceDir = (Resolve-Path $SourceDir).Path

if (-not (Test-Path (Join-Path $SourceDir "bitcoind.exe"))) {
    throw "SourceDir must contain bitcoind.exe: $SourceDir"
}

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Get-Process bitcoind, bitcoin-qt, "Block Zero" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Get-ChildItem $SourceDir -Filter "*.exe" | ForEach-Object {
    # Ship the GUI under the Block Zero name (parity with the release + macOS app).
    if ($_.Name -eq "bitcoin-qt.exe") {
        Copy-Item $_.FullName (Join-Path $BinDir "Block Zero.exe") -Force
        Write-Host "  Block Zero.exe (from $($_.Name))"
    } else {
        Copy-Item $_.FullName $BinDir -Force
        Write-Host "  $($_.Name)"
    }
}
Get-ChildItem $SourceDir -Filter "*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName $BinDir -Force
}
# Copy Qt plugin subfolders produced by windeployqt. "tls" and
# "networkinformation" are required for HTTPS (miner download + pool API);
# the rest keep the GUI rendering correct.
$qtPluginDirs = @("platforms", "tls", "networkinformation", "imageformats", "iconengines", "styles", "generic")
foreach ($sub in $qtPluginDirs) {
    $src = Join-Path $SourceDir $sub
    if (Test-Path $src) {
        $dest = Join-Path $BinDir $sub
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $src "*") $dest -Force -Recurse
    }
}

$qt = Get-Item (Join-Path $BinDir "Block Zero.exe")
Write-Host ""
Write-Host "Deployed to $BinDir"
Write-Host "Block Zero.exe: $($qt.Length) bytes, $($qt.LastWriteTime)"
Write-Host "Start: Start-Process `"$(Join-Path $BinDir 'Block Zero.exe')`""
