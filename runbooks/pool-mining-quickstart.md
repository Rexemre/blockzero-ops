# Pool mining quickstart (Windows)

Mine BLOZ on **pool.bloz.org** — no blockchain sync, no local node.

## Option A — one PowerShell command

```powershell
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops\scripts\mainnet
.\mine-pool-mainnet.ps1
```

First run downloads `bz-pool-miner.exe` and asks for your **bz1 payout address**.  
Later runs start mining immediately.

| Command | What it does |
|---------|----------------|
| `.\mine-pool-mainnet.ps1` | Install (if needed) + mine |
| `.\mine-pool-mainnet.ps1 -Status` | Pool height, fee, stratum |
| `.\mine-pool.bat` | Same as above (double-click) |

Config is stored in `%LOCALAPPDATA%\BlockZero\pool\miner.conf`.

## Option B — zip (no git)

1. Download [blockzero-pool-miner-windows.zip](https://github.com/Rexemre/blockzero-pool/releases) (or build from `blockzero-pool`)
2. Extract anywhere
3. Double-click **SETUP.bat** (once)
4. Double-click **START-MINING.bat**

## Your bz1 address

Pool payouts use the address in your worker name: `bz1YOURADDRESS.rig1`

Get an address from solo mining once:

```powershell
.\mine-mainnet.ps1 -Status
```

Or create a wallet with `bitcoin-cli getnewaddress` if you already run a node.

## Pool settings

| Setting | Value |
|---------|-------|
| Dashboard | https://pool.bloz.org |
| Stratum | `wss://pool.bloz.org/stratum` |
| Password | `x` |
| Fee | 2% |
| Scheme | PPLNS (min payout 0.5 BLOZ) |

## Troubleshooting

- **"failed to connect"** — check firewall; pool uses HTTPS/WSS on port 443
- **No shares** — normal at pool difficulty; wait for `share nonce=…` in miner output
- **Slow hashrate** — use native `bz-pool-miner.exe`, not Python/WSL
