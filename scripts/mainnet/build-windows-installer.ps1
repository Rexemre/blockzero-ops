# Build a single double-click Block Zero installer (Block-Zero-Setup.exe).
#
# Prereq: a Release GUI build exists (run build-windows-local.ps1 first).
# This script deploys the Qt runtime + VC++ CRT next to the exe, then runs
# Inno Setup (ISCC) to produce one installer .exe.
#
# Usage:
#   .\build-windows-installer.ps1 -AppVersion 1.0.0-rc22
param(
    [string]$CoreDir = "C:\Users\Marlon\blockzero\blockzero-core",
    [string]$AppVersion = "1.0.0",
    [string]$OutDir = "C:\Users\Marlon\blockzero\blockzero-core\build\installer"
)

$ErrorActionPreference = "Stop"
$rel = Join-Path $CoreDir "build\bin\Release"
$qtVer = "6.8.3"
$qtBin = Join-Path $CoreDir "qt\$qtVer\msvc2022_64\bin"

if (-not (Test-Path (Join-Path $rel "bitcoin-qt.exe"))) {
    throw "bitcoin-qt.exe not found in $rel. Build it first (build-windows-local.ps1)."
}

# 1) Bundle the Qt runtime (DLLs + plugin folders) next to the exe.
$windeployqt = Join-Path $qtBin "windeployqt.exe"
if (Test-Path $windeployqt) {
    $env:PATH = "$qtBin;$env:PATH"
    Write-Host "Running windeployqt..."
    & $windeployqt --release --no-translations --no-opengl-sw --compiler-runtime (Join-Path $rel "bitcoin-qt.exe") | Out-Null
} else {
    Write-Warning "windeployqt not found at $windeployqt - assuming Qt runtime is already present."
}

# 2) Bundle the VC++ runtime DLLs app-locally so no VC redist install is needed.
$vsBase = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Redist\MSVC"
if (Test-Path $vsBase) {
    $crt = Get-ChildItem $vsBase -Recurse -Filter "msvcp140.dll" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\Microsoft\.VC\d+\.CRT" -and $_.FullName -notmatch "onecore" } |
        Select-Object -First 1
    if (-not $crt) {
        $crt = Get-ChildItem $vsBase -Recurse -Filter "msvcp140.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($crt) {
        Write-Host "Bundling VC++ runtime from $($crt.DirectoryName)"
        Copy-Item (Join-Path $crt.DirectoryName "*.dll") $rel -Force
    } else {
        Write-Warning "VC++ runtime DLLs not found - users may need the VC++ Redistributable."
    }
}

# 3) Ship the GUI under the friendly Block Zero name (parity with the release).
Copy-Item (Join-Path $rel "bitcoin-qt.exe") (Join-Path $rel "Block Zero.exe") -Force

# 4) Run Inno Setup using the canonical script that ships with blockzero-core.
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = "$env:ProgramFiles\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $iscc)) { throw "Inno Setup (ISCC.exe) not found. Install Inno Setup 6 first." }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$iss = Join-Path $CoreDir "contrib\windows\block-zero.iss"
if (-not (Test-Path $iss)) { throw "Installer script not found: $iss" }

& $iscc "/DSourceDir=$rel" "/DAppVersion=$AppVersion" "/O$OutDir" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

Write-Host ""
Write-Host "Installer: $OutDir\Block-Zero-Setup.exe"
