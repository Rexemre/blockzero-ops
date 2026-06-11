function Copy-OpenSslRuntime {
    param([string]$DestDir)

    $names = @("libssl-3-x64.dll", "libcrypto-3-x64.dll")
    $roots = @(
        "C:\Program Files\OpenSSL\bin",
        "C:\Program Files\OpenSSL-Win64\bin",
        "C:\tools\openssl\bin"
    )
    if ($env:VCPKG_INSTALLATION_ROOT) {
        $roots += Join-Path $env:VCPKG_INSTALLATION_ROOT "installed\x64-windows\bin"
    }

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $missing = $false
        foreach ($name in $names) {
            if (-not (Test-Path (Join-Path $root $name))) { $missing = $true; break }
        }
        if ($missing) { continue }

        foreach ($name in $names) {
            Copy-Item (Join-Path $root $name) (Join-Path $DestDir $name) -Force
        }
        Write-Host "Copied OpenSSL runtime from $root"
        return
    }

    throw "OpenSSL runtime DLLs not found. Install OpenSSL 3 x64 (e.g. choco install openssl.light)."
}
