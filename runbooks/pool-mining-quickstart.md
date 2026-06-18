# Pool mining quickstart

Mine BLOZ on **pool.bloz.org** — Windows, Linux and macOS.

Dashboard: https://pool.bloz.org (live stats, copy-paste setup, your earnings)

## Windows

```powershell
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops\scripts\mainnet
.\install-windows.ps1
.\mine-mainnet.ps1 -Pool
```

First run: installs binaries, creates wallet + `bz1` address, downloads pool miner, starts mining.
Later runs: uses your existing BlockZero wallet automatically.

## Linux / macOS

```bash
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops/scripts/mainnet
chmod +x mine-pool.sh
./mine-pool.sh bz1YOURADDRESS        # or just ./mine-pool.sh if you have a local wallet
```

**Important:** pass **only your `bz1` payout address** — not `bz1…rig1`. The script builds the Stratum
worker as `bz1YOURADDRESS.rigname` automatically (rig name = your hostname, or set `WORKER=rig2`).

The script downloads the prebuilt miner (Linux x64, Linux arm64, macOS arm64) from
[blockzero-ops releases](https://github.com/Rexemre/blockzero-ops/releases) and auto-restarts on crashes.

Options (env vars): `THREADS=8 ./mine-pool.sh` · `WORKER=rig2 ./mine-pool.sh bz1…` · `FORCE=1` re-downloads the miner.

No local wallet yet? The address is read from `~/.blockzero-mainnet/mining-address.txt` if present;
otherwise pass your `bz1` address as the first argument (address only, no `.rig` suffix).

### GUI wallet on macOS (Apple Silicon)

Want the graphical **Block Zero** wallet (the same `bitcoin-qt` GUI as on Windows)?

```bash
./install-macos.sh        # installs "Block Zero.app" + bitcoind/bitcoin-cli, sets up ~/.blockzero-mainnet
open "$HOME/Applications/Block Zero.app"
```

Copy your `bz1…` address from the **Receive** tab, then mine with `./mine-pool.sh bz1YOURADDRESS`.

## Commands (Windows)

| Command | What it does |
|---------|----------------|
| `.\mine-mainnet.ps1 -Pool` | Pool mine (recommended) |
| `.\mine-mainnet.ps1 -Pool -Threads 4` | Pool mine, 4 CPU threads |
| `.\mine-pool.bat` | Same as `-Pool` (double-click) |
| `.\mine-mainnet.ps1 -Status` | Solo node status + wallet balance |
| `.\mine-pool-mainnet.ps1 -Status` | Pool height, fee, stratum, pool hashrate |

## Files

| Path | Purpose |
|------|---------|
| `%LOCALAPPDATA%\BlockZeroMainnet\mining-address.txt` | Your `bz1` payout address (Windows) |
| `~/.blockzero-mainnet/mining-address.txt` | Same (Linux/macOS) |
| `%LOCALAPPDATA%\BlockZero\pool\miner.conf` | Pool miner settings (threads, worker name) |
| `~/.blockzero/pool/bin/bz-pool-miner` | Pool miner binary (Linux/macOS, auto-downloaded) |

## Solo vs pool

| | Solo | Pool (`-Pool` / `mine-pool.sh`) |
|--|--|--|
| Node sync | Required | Not for mining (wallet setup once) |
| Wallet | BlockZero | Same wallet |
| Payout | Direct | PPLNS (2% fee, min 0.5 BLOZ) |

## Pool settings

| Setting | Value |
|---------|-------|
| Dashboard | https://pool.bloz.org |
| Stratum | `wss://pool.bloz.org/stratum` |
| Worker (Stratum) | `bz1YOURADDRESS.rigname` — built by the script; rig = hostname or `WORKER=` |
| `mine-pool.sh` arg | **`bz1YOURADDRESS` only** — do not append `.rig1` yourself |
| Password | none (`x` by convention, ignored) |
| Threads | auto = all cores − 1; max 64 |

## Pool transparency

| Item | Value |
|------|-------|
| Pool payout address | `bz1qxp5dek9uq4hzemeg9cv0f8hfm3hl35kxunfkma` |
| Explorer | [View on explorer.bloz.org](https://explorer.bloz.org/address/bz1qxp5dek9uq4hzemeg9cv0f8hfm3hl35kxunfkma) |
| Pool engine source | [blockzero-pool (GitHub)](https://github.com/Rexemre/blockzero-pool) |
| Miner source | [blockzero-ops/pool/native](https://github.com/Rexemre/blockzero-ops/tree/main/pool/native) |

**How block rewards flow:**  
When the pool finds a block, the coinbase (block reward) is paid to the pool payout address above.
The pool engine immediately calculates each miner's PPLNS share and adds it to their pending balance.
Payouts happen automatically once a miner's pending balance reaches 0.5 BLOZ — no claiming needed.

The pool fee is 2% of each block reward. It stays in the pool address to cover server costs.
The remaining 98% is distributed to miners proportionally based on their share of the PPLNS window.

## Miner behavior (v0.6+)

- **Fast mode (default)** — builds a ~2 GB RandomX dataset in the background (~1 min). Mining continues in light mode during build. Hashrate jumps ~10× once the dataset is ready.
- **Light mode** (`--light`) — 256 MB cache only, starts immediately at lower hashrate.
- **JIT enabled on Windows** — RandomX JIT with SECURE pages (W^X) for full native speed.
- Survives connection drops: reconnects and re-subscribes automatically
- RandomX cache reused across jobs within an epoch (no re-init stall per job)
- VMs reused across job changes — only rebuilt on epoch key change or dataset ready
- Reports total hashrate + accepted/rejected shares every 30 s
- Thread count is clamped 1–64 (never a hard error)

## Troubleshooting

- **No wallet (Windows)** — run `.\mine-mainnet.ps1 -Pool` (creates wallet on first run)
- **Not on the dashboard yet** — connected ≠ listed; you appear after the first **accepted share** (check terminal for `Share accepted`)
- **No hashrate on dashboard** — wait 2–5 min after the first `Share accepted`; estimation needs a few shares
- **Worker shows `.rig.rig` (doubled name)** — you passed `bz1…rig1` to `mine-pool.sh`; use address only: `./mine-pool.sh bz1…`
- **Hashrate shows 0 then jumps** — normal: fast mode builds the 2 GB dataset for ~1 min first
- **Change threads** — Windows: `-Threads 8` · Linux/macOS: `THREADS=8 ./mine-pool.sh`
- **Pool connection error** — check firewall; the pool uses WSS on port 443
- **macOS blocks the binary** — System Settings → Privacy & Security → Allow
- **Share rejected: stale job** — update to pool miner v0.6.1+ (auto-updated by `mine-mainnet.ps1`)
