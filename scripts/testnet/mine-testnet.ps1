# Block Zero testnet miner (Windows, native binaries — NOT WSL)
# Usage:
#   .\mine-testnet.ps1              # sync check + mine on public testnet
#   .\mine-testnet.ps1 -Status      # show height, peers, balance
#   .\mine-testnet.ps1 -Stop        # stop bitcoind
#   .\resync-testnet.ps1            # reset fork and re-sync (run this first if solo-mined)

param(
    [string]$BinDir = "",
    [string]$DataDir = "$env:LOCALAPPDATA\BlockZero",
    [string]$WalletName = "mining",
    [int]$MaxTries = 500000000,
    [switch]$Status,
    [switch]$Stop
)

$ErrorActionPreference = "Stop"
$OfficialBlock1 = "7a28c3b91ddd8404a13a2557eb0e1f8bee664ffc7e7a0a90fb4473f762e6ec79"

function Find-Exe([string]$Name) {
    if ($BinDir) {
        $p = Join-Path $BinDir $Name
        if (Test-Path $p) { return $p }
    }
    $defaultBin = Join-Path $env:LOCALAPPDATA "BlockZero\bin\$Name"
    if (Test-Path $defaultBin) { return $defaultBin }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "Cannot find $Name. Run install-windows.ps1 or: .\mine-testnet.ps1 -BinDir `"$env:LOCALAPPDATA\BlockZero\bin`""
}

function Try-Invoke-Cli([string[]]$CliArgs) {
    $cli = Find-Exe "bitcoin-cli.exe"
    $prevEap = $ErrorActionPreference
    # Use Continue (not SilentlyContinue) so stderr text from bitcoin-cli is
    # preserved by the 2>&1 merge instead of being dropped. Disable native
    # exit-code-to-exception coupling (PS 7.3+) so a non-zero exit doesn't throw
    # before we can inspect it.
    $ErrorActionPreference = "Continue"
    $prevNative = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    $out = & $cli -testnet -datadir="$DataDir" -rpcport=18211 @CliArgs 2>&1
    $exit = $LASTEXITCODE
    $PSNativeCommandUseErrorActionPreference = $prevNative
    $ErrorActionPreference = $prevEap
    $text = ($out | Out-String).Trim()
    return @{ Ok = ($exit -eq 0); Text = $text; Exit = $exit }
}

# Transient errors seen while bitcoind is starting up / warming up its indexes
# and wallet subsystem. We retry these instead of failing the whole script.
$script:TransientRpcPattern = 'Loading|warming up|Rewinding|Verifying|Activating|Rescanning|Could not connect|couldn''t connect|connection refused|code: -28|in warmup|loading wallet|Wallet loading'

function Invoke-Cli([string[]]$CliArgs) {
    $deadline = (Get-Date).AddSeconds(45)
    while ($true) {
        # Pass the array as a single argument (NOT splatted): splatting an array
        # whose first element looks like "-rpcwallet=..." makes PowerShell treat
        # it as a parameter name and silently drops the actual RPC command.
        $result = Try-Invoke-Cli $CliArgs
        if ($result.Ok) { return $result.Text }
        $transient = (-not $result.Text) -or ($result.Text -match $script:TransientRpcPattern)
        if ($transient -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            continue
        }
        $msg = if ($result.Text) { $result.Text } else { "bitcoin-cli failed (exit $($result.Exit)) - node not ready" }
        throw $msg
    }
}

function Write-DefaultConf([string]$Path) {
    @"
server=1
txindex=1

[test]
listen=0
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=18211
addnode=217.160.46.61:18210
addnode=127.0.0.1:18210
"@ | Set-Content -Path $Path -Encoding UTF8
}

function Test-WalletOnDisk([string]$Name) {
    $paths = @(
        (Join-Path $DataDir "testnet3\wallets\$Name")
        (Join-Path $DataDir "testnet3\$Name")
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

function Ensure-Wallet([string]$Name) {
    $wallets = @(Invoke-Cli @("listwallets") | ConvertFrom-Json)
    if ($wallets -contains $Name) { return }

    $load = Try-Invoke-Cli @("loadwallet", $Name)
    if ($load.Ok) { return }
    if ($load.Text -match "already loaded|error code: -35") { return }

    if (Test-WalletOnDisk $Name) {
        throw @"
Wallet '$Name' exists on disk but could not be loaded.

Try:
  .\mine-testnet.ps1 -Stop
  .\mine-testnet.ps1

If it persists, restart bitcoind manually and run:
  bitcoin-cli -testnet -datadir=$DataDir loadwallet $Name

RPC error: $($load.Text)
"@
    }

    Invoke-Cli @("createwallet", $Name) | Out-Null
    Write-Host "Created wallet '$Name'."
}

function Get-MiningAddressFile() {
    return Join-Path $DataDir "mining-address.txt"
}

function Get-OrCreate-MiningAddress([string]$Name) {
    $addrFile = Get-MiningAddressFile
    if (Test-Path $addrFile) {
        $saved = (Get-Content $addrFile -Raw).Trim()
        if ($saved) {
            try {
                Invoke-Cli @("-rpcwallet=$Name", "getaddressinfo", $saved) | Out-Null
                return $saved
            } catch {}
        }
    }
    $coins = @(Invoke-Cli @("-rpcwallet=$Name", "listunspent", "0", "9999999") | ConvertFrom-Json)
    $recent = $coins | Where-Object { $_.confirmations -lt 100 -and $_.confirmations -ge 0 } |
        Sort-Object -Property confirmations -Descending |
        Select-Object -First 1
    if ($recent) {
        $addr = $recent.address
        Set-Content -Path $addrFile -Value $addr -NoNewline -Encoding ASCII
        return $addr
    }
    $addr = Invoke-Cli @("-rpcwallet=$Name", "getnewaddress")
    Set-Content -Path $addrFile -Value $addr.Trim() -NoNewline -Encoding ASCII
    return $addr.Trim()
}

function Get-RewardSummary([string]$Name) {
    $coins = @(Invoke-Cli @("-rpcwallet=$Name", "listunspent", "0", "9999999") | ConvertFrom-Json)
    $immature = @($coins | Where-Object { $_.confirmations -lt 100 -and $_.confirmations -ge 0 })
    $byAddr = $immature | Group-Object address
    return @{
        BlockCount = $immature.Count
        Addresses  = @($byAddr | ForEach-Object { $_.Name })
    }
}

function Wait-ForRpc {
    param([int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Try-Invoke-Cli @("getblockcount")
        if ($r.Ok) { return }
        if ($r.Text -match "Loading|verifying|rescanning|warming up|Rewinding|init message") {
            Write-Host "Node starting... ($($r.Text))"
        }
        Start-Sleep -Seconds 3
    }
    throw "bitcoind RPC did not become ready within ${TimeoutSec}s. Check the node (it may still be verifying blocks)."
}

function Wait-ForPublicChain {
    param([int]$TimeoutSec = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $pc = Try-Invoke-Cli @("getconnectioncount")
        $hc = Try-Invoke-Cli @("getblockcount")
        if (-not $pc.Ok -or -not $hc.Ok) {
            Start-Sleep -Seconds 3
            continue
        }
        $peers = [int]$pc.Text
        $height = [int]$hc.Text
        if ($peers -ge 1) {
            if ($height -ge 1) {
                $bh = Try-Invoke-Cli @("getblockhash", "1")
                if (-not $bh.Ok) {
                    # node still warming up its block index; retry
                    Start-Sleep -Seconds 3
                    continue
                }
                if ($bh.Text -ne $OfficialBlock1) {
                    throw "Local block 1 is not the public testnet. Run .\resync-testnet.ps1 first."
                }
            }
            return
        }
        Write-Host "Waiting for peer... (peers=$peers)"
        Start-Sleep -Seconds 5
    }
    throw @"
No connection to the public testnet (0 peers). Do NOT mine solo — that creates a fork.

1. Start WSL bridge (PowerShell):
   wsl -e bash -lc '/home/marlon/blockzero-core/build/bin/bitcoind -testnet -datadir=/home/marlon/.bzero -daemon'
2. Resync:
   .\resync-testnet.ps1
3. Mine:
   .\mine-testnet.ps1
"@
}

if ($Stop) {
    try { Invoke-Cli @("stop") | Out-Null; Write-Host "Stopping bitcoind..." }
    catch { Write-Host "bitcoind was not running (RPC)."; }
    $procs = Get-Process bitcoind -ErrorAction SilentlyContinue
    if ($procs) {
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Process bitcoind -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
        }
        $still = Get-Process bitcoind -ErrorAction SilentlyContinue
        if ($still) {
            Write-Host "Shutdown slow (RandomX) - forcing."
            $still | Stop-Process -Force
        }
    }
    Write-Host "bitcoind stopped."
    exit 0
}

if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
}

$conf = Join-Path $DataDir "bitcoin.conf"
if (-not (Test-Path $conf)) {
    Write-DefaultConf $conf
    Write-Host "Created $conf"
}

$daemon = Find-Exe "bitcoind.exe"
$running = Get-Process bitcoind -ErrorAction SilentlyContinue

if (-not $running) {
    Write-Host "Starting bitcoind (native Windows, testnet)..."
    Start-Process -FilePath $daemon -ArgumentList "-testnet", "-datadir=$DataDir" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

Wait-ForRpc
Wait-ForPublicChain

Ensure-Wallet $WalletName

$height = Invoke-Cli @("getblockcount")
$peers = Invoke-Cli @("getconnectioncount")

if ($Status) {
    $bal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
    $rewards = Get-RewardSummary $WalletName
    $addrFile = Get-MiningAddressFile
    $activeAddr = if (Test-Path $addrFile) { (Get-Content $addrFile -Raw).Trim() } else { "" }
    if (-not $activeAddr -and $rewards.BlockCount -gt 0) {
        $activeAddr = ($rewards.Addresses | Select-Object -Last 1)
    }
    Write-Host "Peers: $peers"
    Write-Host "Height: $height"
    if ($activeAddr) {
        Write-Host "Mining address: $activeAddr"
    } else {
        Write-Host "Mining address: (not set yet - run .\mine-testnet.ps1 once)"
    }
    if ($rewards.BlockCount -gt 0) {
        Write-Host "Blocks mined (immature): $($rewards.BlockCount)"
    }
    Write-Host "Immature TBLOZ: $($bal.mine.immature)"
    Write-Host "Trusted TBLOZ: $($bal.mine.trusted)"
    if ([int]$height -ge 1) {
        Write-Host "Block 1: $(Invoke-Cli @('getblockhash','1'))"
    }
    exit 0
}

$addr = Get-OrCreate-MiningAddress $WalletName

Write-Host "Peers: $peers | Chain height: $height"
Write-Host "Mining to: $addr"
Write-Host "Press Ctrl+C to stop mining (node keeps running). Use -Stop to shut down bitcoind."
Write-Host ""

while ($true) {
    $height = [int](Invoke-Cli @("getblockcount"))
    Write-Host "$(Get-Date -Format 'HH:mm:ss') height=$height mining..."
    $result = Invoke-Cli @("-rpcwallet=$WalletName", "generatetoaddress", "1", $addr, "$MaxTries")
    if ($result -match '[0-9a-f]{64}') {
        Write-Host "Block found: $result"
        $height = Invoke-Cli @("getblockcount")
        if ([int]$height -gt 0) {
            $bal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
            Write-Host "New height: $height | immature TBLOZ: $($bal.mine.immature)"
        }
    }
    Start-Sleep -Seconds 2
}
