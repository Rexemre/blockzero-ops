# Build native bz-pool-miner.exe (Windows, MSVC)
# Requires: Visual Studio 2022 Build Tools with C++ workload, CMake 3.20+, Git
param(
    [string]$BuildType = "Release",
    [string]$BuildDir = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $BuildDir) { $BuildDir = Join-Path $Root "build\native" }

Write-Host "Building bz-pool-miner ($BuildType)"
Write-Host "Source: $Root\native"

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) { throw "cmake not found. Install CMake and add to PATH." }

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Push-Location $BuildDir
try {
    cmake -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=$BuildType "$Root\native"
    cmake --build . --config $BuildType --target bz-pool-miner -j
    $exe = Join-Path $BuildDir "$BuildType\bz-pool-miner.exe"
    if (-not (Test-Path $exe)) { $exe = Join-Path $BuildDir "Release\bz-pool-miner.exe" }
    if (-not (Test-Path $exe)) { throw "Build failed: bz-pool-miner.exe not found" }
    $out = Join-Path $Root "bin\bz-pool-miner.exe"
    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
    Copy-Item -Force $exe $out
    . (Join-Path $Root "scripts\copy-openssl-runtime.ps1")
    Copy-OpenSslRuntime -DestDir (Split-Path $out)
    Write-Host "OK: $out"
} finally {
    Pop-Location
}
