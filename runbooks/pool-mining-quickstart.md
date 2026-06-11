# Pool mining quickstart (Windows)

Mine BLOZ on **pool.bloz.org** — everything through BlockZero.

## One command

```powershell
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops\scripts\testnet
.\install-windows.ps1
cd ..\mainnet
.\mine-mainnet.ps1 -Pool
```

First run: BlockZero installs binaries, creates wallet + `bz1` address, downloads pool miner, starts mining.  
Later runs: uses your existing BlockZero wallet automatically.

## Commands

| Command | What it does |
|---------|----------------|
| `.\mine-mainnet.ps1 -Pool` | Pool mine (recommended) |
| `.\mine-mainnet.ps1 -Pool -Threads 4` | Pool mine, 4 CPU threads |
| `.\mine-pool.bat` | Same as `-Pool` (double-click) |
| `.\mine-mainnet.ps1 -Status` | Solo node status + wallet balance |
| `.\mine-pool-mainnet.ps1 -Status` | Pool height, fee, stratum |

## Files

| Path | Purpose |
|------|---------|
| `%LOCALAPPDATA%\BlockZeroMainnet\mining-address.txt` | Your `bz1` payout address |
| `%LOCALAPPDATA%\BlockZero\pool\miner.conf` | Pool miner settings (threads, worker name) |
| `%LOCALAPPDATA%\BlockZero\pool\bin\` | Pool miner binary (auto-downloaded) |

## Solo vs pool

| | Solo | Pool (`-Pool`) |
|--|--|--|
| Command | `.\mine-mainnet.ps1` | `.\mine-mainnet.ps1 -Pool` |
| Node sync | Required | Not for mining (wallet setup once) |
| Wallet | BlockZero | Same wallet |
| Payout | Direct | PPLNS (2% fee, min 0.5 BLOZ) |

## Pool settings

| Setting | Value |
|---------|-------|
| Dashboard | https://pool.bloz.org |
| Stratum | `wss://pool.bloz.org/stratum` |
| Worker | `bz1YOURADDRESS.pc` |
| Password | `x` |

## Troubleshooting

- **No wallet** — run `.\mine-mainnet.ps1 -Pool` (creates wallet on first run)
- **Change threads** — `.\mine-mainnet.ps1 -Pool -Threads 8`
- **Pool connection error** — check firewall; pool uses WSS on port 443
