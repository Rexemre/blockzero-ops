# Block Zero MAINNET miner (Windows, native binaries - NOT WSL)
# Usage:
#   .\mine-mainnet.ps1 -Threads 8   # mine with 8 RandomX threads (default: auto, max 16)
#   .\mine-mainnet.ps1 -Status      # show height, peers, balance
#   .\mine-mainnet.ps1 -Stop        # stop bitcoind
#   .\resync-mainnet.ps1            # reset fork and re-sync (run first if solo-mined)
#
# Mainnet uses real BLOZ. Block 1 cannot be mined before the launch moment
# (2026-06-06 06:06:06 UTC) because a block's time must be >= the genesis time.

param(
    [string]$BinDir = "",
    [string]$DataDir = "$env:LOCALAPPDATA\BlockZeroMainnet",
    [string]$WalletName = "mining",
    [long]$MaxTries = 500000000,
    [int]$Threads = 0,
    [switch]$Status,
    [switch]$Stop
)

. "$PSScriptRoot\chain-identity.ps1"

$ErrorActionPreference = "Stop"

function Get-GenerateToAddressArgs([string]$Name, [string]$Addr) {
    $args = @("-rpcwallet=$Name", "generatetoaddress", "1", $Addr, "$MaxTries")
    if ($Threads -gt 0) { $args += "$Threads" }
    return $args
}

function Get-MiningThreadsLabel() {
    if ($Threads -gt 0) { return "$Threads (explicit)" }
    $cores = [Environment]::ProcessorCount
    $auto = [Math]::Min(16, $cores)
    return "$auto auto (min(cores, 16))"
}

function Find-Exe([string]$Name) {
    if ($BinDir) {
        $p = Join-Path $BinDir $Name
        if (Test-Path $p) { return $p }
    }
    $defaultBin = Join-Path $env:LOCALAPPDATA "BlockZero\bin\$Name"
    if (Test-Path $defaultBin) { return $defaultBin }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "Cannot find $Name. Run install-windows.ps1 or pass -BinDir."
}

function Try-Invoke-Cli([string[]]$CliArgs) {
    $cli = Find-Exe "bitcoin-cli.exe"
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $prevNative = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    $out = & $cli -datadir="$DataDir" -rpcport=$RpcPort @CliArgs 2>&1
    $exit = $LASTEXITCODE
    $PSNativeCommandUseErrorActionPreference = $prevNative
    $ErrorActionPreference = $prevEap
    $text = ($out | Out-String).Trim()
    return @{ Ok = ($exit -eq 0); Text = $text; Exit = $exit }
}

$script:TransientRpcPattern = 'Loading|warming up|Rewinding|Verifying|Activating|Rescanning|Could not connect|couldn''t connect|connection refused|code: -28|in warmup|loading wallet|Wallet loading'

function Invoke-Cli([string[]]$CliArgs) {
    $deadline = (Get-Date).AddSeconds(45)
    while ($true) {
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

[main]
listen=1
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=$RpcPort
addnode=$SeedNode
"@ | Set-Content -Path $Path -Encoding ASCII
}

function Test-WalletOnDisk([string]$Name) {
    $paths = @(
        (Join-Path $DataDir "wallets\$Name")
        (Join-Path $DataDir "$Name")
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
        throw "Wallet '$Name' exists on disk but could not be loaded. RPC error: $($load.Text)"
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

function Get-RewardSummary([string]$Name, [object]$Bal) {
    $blockReward = 50
    return @{
        ImmatureBlockCount = [int]([decimal]$Bal.mine.immature / $blockReward)
        MatureBlockCount   = [int]([decimal]$Bal.mine.trusted / $blockReward)
    }
}

function Format-WalletBalance([object]$Bal) {
    $mature = [decimal]$Bal.mine.trusted
    $immature = [decimal]$Bal.mine.immature
    $total = $mature + $immature
    return "mature: $mature BLOZ, immature: $immature BLOZ, total: $total BLOZ"
}

function Wait-ForRpc {
    # 180s: a previous bitcoind can hold the datadir lock for ~90s during the
    # slow RandomX shutdown, so a fresh start may need to wait that out first.
    param([int]$TimeoutSec = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Try-Invoke-Cli @("getblockcount")
        if ($r.Ok) { return }
        if ($r.Text -match "Loading|verifying|rescanning|warming up|Rewinding|init message") {
            Write-Host "Node starting... ($($r.Text))"
        }
        Start-Sleep -Seconds 3
    }
    throw "bitcoind RPC did not become ready within ${TimeoutSec}s."
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
        if ($peers -ge 1) {
            $gh = Try-Invoke-Cli @("getblockhash", "0")
            if (-not $gh.Ok) {
                Start-Sleep -Seconds 3
                continue
            }
            if ($OfficialGenesis -notlike "PENDING*" -and $gh.Text -ne $OfficialGenesis) {
                throw "Local genesis does not match public mainnet. Run .\resync-mainnet.ps1 first."
            }
            return
        }
        Write-Host "Waiting for peer... (peers=$peers)"
        Start-Sleep -Seconds 5
    }
    throw "No connection to the public mainnet (0 peers). Do NOT mine solo - that creates a fork. Run .\resync-mainnet.ps1."
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

# Decide based on RPC responsiveness, not just process presence: a bitcoind
# stuck in the slow RandomX shutdown is still alive but serves no RPC, which
# would otherwise make us wait on a dead node instead of starting a fresh one.
# Probe for ~20s so we never kill a healthy node that is just briefly busy
# validating an incoming block (RandomX verification blocks RPC momentarily).
$rpcUp = $false
if (Get-Process bitcoind -ErrorAction SilentlyContinue) {
    # Probe up to ~60s: right after a fresh start the node validates the chain
    # with RandomX and blocks RPC for 30-40s. Only a node that stays silent the
    # whole window is treated as truly stuck and cleared.
    for ($i = 0; $i -lt 30; $i++) {
        if ((Try-Invoke-Cli @("getblockcount")).Ok) { $rpcUp = $true; break }
        Start-Sleep -Seconds 2
    }
}
if (-not $rpcUp) {
    $stale = Get-Process bitcoind -ErrorAction SilentlyContinue
    if ($stale) {
        Write-Host "A bitcoind is running but not responding (likely shutting down) - clearing it..."
        $stale | Stop-Process -Force
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Process bitcoind -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
        }
        Remove-Item (Join-Path $DataDir ".lock") -ErrorAction SilentlyContinue
    }
    Write-Host "Starting bitcoind (native Windows, mainnet)..."
    Start-Process -FilePath $daemon -ArgumentList "-datadir=`"$DataDir`"" -WindowStyle Hidden
    Start-Sleep -Seconds 5
}

Wait-ForRpc
Wait-ForPublicChain

Ensure-Wallet $WalletName

$height = Invoke-Cli @("getblockcount")
$peers = Invoke-Cli @("getconnectioncount")

if ($Status) {
    $bal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
    $rewards = Get-RewardSummary $WalletName $bal
    $addrFile = Get-MiningAddressFile
    $activeAddr = if (Test-Path $addrFile) { (Get-Content $addrFile -Raw).Trim() } else { "" }
    Write-Host "Peers: $peers"
    Write-Host "Height: $height"
    if ($activeAddr) {
        Write-Host "Mining address: $activeAddr"
    } else {
        Write-Host "Mining address: (not set yet - run .\mine-mainnet.ps1 once)"
    }
    if ($rewards.MatureBlockCount -gt 0 -or $rewards.ImmatureBlockCount -gt 0) {
        Write-Host "Blocks mined: $($rewards.MatureBlockCount) mature + $($rewards.ImmatureBlockCount) immature (100-block wait)"
    }
    Write-Host (Format-WalletBalance $bal)
    exit 0
}

function Ensure-NodeUp {
    if (-not (Get-Process bitcoind -ErrorAction SilentlyContinue)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') bitcoind not running - (re)starting..."
        $daemon = Find-Exe "bitcoind.exe"
        Start-Process -FilePath $daemon -ArgumentList "-datadir=$DataDir" -WindowStyle Hidden
        Start-Sleep -Seconds 5
    }
    Wait-ForRpc
}

$addr = Get-OrCreate-MiningAddress $WalletName

Write-Host "Peers: $peers | Chain height: $height"
Write-Host "Mining to: $addr | RandomX threads: $(Get-MiningThreadsLabel)"
$startBal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
Write-Host "Balance: $(Format-WalletBalance $startBal)"
Write-Host "Press Ctrl+C to stop mining (node keeps running). Use -Stop to shut down bitcoind."
Write-Host "Coinbase rewards mature after 100 blocks."
Write-Host ""

while ($true) {
    try {
        Ensure-NodeUp
        $height = [int](Invoke-Cli @("getblockcount"))
        Write-Host "$(Get-Date -Format 'HH:mm:ss') height=$height mining..."
        $result = Invoke-Cli (Get-GenerateToAddressArgs $WalletName $addr)
        if ($result -match '[0-9a-f]{64}') {
            Write-Host "Block found: $result"
            $bal = Invoke-Cli @("-rpcwallet=$WalletName", "getbalances") | ConvertFrom-Json
            $newHeight = Invoke-Cli @('getblockcount')
            $balLine = Format-WalletBalance $bal
            Write-Host "New height: $newHeight; $balLine"
        }
    } catch {
        $msg = ($_.Exception.Message -split "`n")[0].Trim()
        Write-Host "$(Get-Date -Format 'HH:mm:ss') mining hiccup ($msg) - recovering..."
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 2
}
