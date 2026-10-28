# Local Windows GUI build (mirrors .github/workflows/release.yml windows-x64 job).
# Requires: Visual Studio 2022+ with "Desktop development with C++", Python 3, pip.
param(
    [string]$CoreDir = "C:\Users\USER\blockzero\blockzero-core"
)

$ErrorActionPreference = "Stop"
Set-Location $CoreDir

if (-not (Test-Path (Join-Path $CoreDir "src\randomx\CMakeLists.txt"))) {
    Write-Host "Initializing git submodules (randomx)..."
    git submodule update --init --recursive src/randomx
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "Visual Studio not found. Install VS Community with C++ desktop workload first."
}

$vsInfo = & $vswhere -all -format json | ConvertFrom-Json | Select-Object -First 1
if (-not $vsInfo -or -not $vsInfo.isComplete) {
    throw "Visual Studio is still installing (isComplete=$($vsInfo.isComplete)). Wait for the installer to finish, then rerun this script."
}

$vsPath = $vsInfo.installationPath
$vsDevCmd = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"
if (-not (Test-Path $vsDevCmd)) {
    throw "Launch-VsDevShell.ps1 not found under $vsPath"
}

& $vsDevCmd -Arch amd64 -HostArch amd64 | Out-Null

$env:PYTHONUTF8 = "1"
$env:QT_VERSION = "6.8.3"
$env:QT_ARCH = "win64_msvc2022_64"
$env:QT_PATH = "msvc2022_64"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "cmake not in PATH after VS dev shell import"
}

$qtRoot = Join-Path $CoreDir "qt\$($env:QT_VERSION)\$($env:QT_PATH)"
if (-not (Test-Path (Join-Path $qtRoot "bin\Qt6Core.dll"))) {
    Write-Host "Installing Qt $($env:QT_VERSION) via aqtinstall..."
    py -3 -m pip install --upgrade aqtinstall
    py -3 -m aqt install-qt windows desktop $env:QT_VERSION $env:QT_ARCH -O qt --archives qtbase qttools qtsvg
}

$env:CMAKE_PREFIX_PATH = $qtRoot
$env:Qt6_DIR = Join-Path $qtRoot "lib\cmake\Qt6"
$env:PATH = "$(Join-Path $qtRoot 'bin');$env:PATH"

if ($env:VCPKG_INSTALLATION_ROOT) {
    $triplet = Join-Path $env:VCPKG_INSTALLATION_ROOT "triplets\x64-windows.cmake"
    if (-not (Select-String -Path $triplet -Pattern "VCPKG_BUILD_TYPE release" -Quiet)) {
        Add-Content $triplet 'set(VCPKG_BUILD_TYPE release)'
    }
    $env:VCPKG_ROOT = $env:VCPKG_INSTALLATION_ROOT
}

Write-Host "Generating build system..."
cmake -B build --preset vs2026 `
    -DBUILD_GUI=ON `
    -DENABLE_IPC=OFF `
    -DBUILD_TESTS=OFF `
    -DENABLE_WALLET=ON `
    -DWITH_ZMQ=OFF `
    -DVCPKG_MANIFEST_NO_DEFAULT_FEATURES=ON `
    -DVCPKG_MANIFEST_FEATURES="wallet;qrencode" `
    -DCMAKE_PREFIX_PATH="$env:CMAKE_PREFIX_PATH"

Write-Host "Building bitcoin-qt..."
cmake --build build --config Release -j $env:NUMBER_OF_PROCESSORS --target bitcoind bitcoin-cli bitcoin-qt bz-genesis-miner

Write-Host ""
Write-Host "Build output: $CoreDir\build\bin\Release"
Write-Host "Deploy: .\deploy-local-bin.ps1 -SourceDir $CoreDir\build\bin\Release"
