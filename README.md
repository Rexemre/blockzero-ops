# BLOCK ZERO · Ops

### **Mine with your CPU** — not a warehouse. **Start at Block Zero.**

Official mainnet scripts — pool mining in one command. **RandomX** = your processor counts; ASIC & GPU farms don't.

Fair launch. Proof-of-work. No presale. No insiders.

**👉 New here? [Join Discord →](https://discord.gg/FbJzrwAU2W)** · **⛏ [pool.bloz.org](https://pool.bloz.org)** · **🌐 [bloz.org](https://bloz.org)**

---

## Start in 3 steps

1. **Get a `bz1…` address** — download the [Block Zero wallet](https://github.com/Rexemre/blockzero-core/releases/latest) (`Block Zero.exe` / `Block Zero.app`), open it, copy your address from the **Receive** tab.
2. **Pool mine with XMRig (recommended)** — one line, replace `bz1qYOURADDRESS`:
   ```bash
   # Linux (sudo = huge pages = full speed) / macOS
   curl -fsSL https://pool.bloz.org/install.sh | sudo ADDRESS=bz1qYOURADDRESS bash
   ```
   ```powershell
   # Windows — PowerShell as Administrator (antivirus flags all CPU miners)
   $env:ADDRESS='bz1qYOURADDRESS'; irm https://pool.bloz.org/install.ps1 | iex
   ```
3. **Help** — **[Discord](https://discord.gg/FbJzrwAU2W)** · live stats at [pool.bloz.org](https://pool.bloz.org)

Uses patched [XMRig](https://github.com/xmrig/xmrig) (`rx/blockzero`, built in [`xmrig-bz/`](xmrig-bz/)). Prefer the native miner/scripts? See below.

---

## Mine mainnet in one command

| Platform | Script |
|----------|--------|
| **Windows (wallet + pool)** | [`install-windows.ps1`](scripts/mainnet/install-windows.ps1) → [`mine-mainnet.ps1 -Pool`](scripts/mainnet/mine-mainnet.ps1) or [`mine-pool.bat`](scripts/mainnet/mine-pool.bat) |
| **macOS (wallet)** | [`install-macos.sh`](scripts/mainnet/install-macos.sh) — installs **`Block Zero.app`** + tools (Apple Silicon) |
| **Linux / macOS (pool)** | [`mine-pool.sh`](scripts/mainnet/mine-pool.sh) — `./mine-pool.sh bz1YOURADDRESS` |
| **Windows (solo)** | [`install-windows.ps1`](scripts/mainnet/install-windows.ps1) → [`mine-mainnet.ps1`](scripts/mainnet/mine-mainnet.ps1) |
| **Linux / macOS (solo)** | Build from [blockzero-core Releases](https://github.com/Rexemre/blockzero-core/releases), then use [`scripts/mainnet/`](scripts/mainnet/) |

**Public seed:** `217.160.46.61:8210` · **Explorer:** https://explorer.bloz.org

```powershell
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops\scripts\mainnet
.\install-windows.ps1
.\mine-mainnet.ps1 -Pool              # pool mine (recommended)
.\mine-mainnet.ps1 -Status            # solo: sync first — never mine with 0 peers
.\mine-mainnet.ps1                    # solo mine
```

Downloads prebuilt binaries from [blockzero-core Releases](https://github.com/Rexemre/blockzero-core/releases).  
**Use native Windows binaries for mining** — WSL2 RandomX is ~10× slower.

Full walkthrough: [blockzero-docs/quickstart-mining.md](https://github.com/Rexemre/blockzero-docs/blob/main/quickstart-mining.md)

### Pool mining (recommended — wallet + pool in one)

```powershell
cd blockzero-ops\scripts\mainnet
.\mine-mainnet.ps1 -Pool              # wallet + pool mine
.\mine-mainnet.ps1 -Pool -Threads 4  # custom thread count
.\mine-pool-mainnet.ps1 -Status      # check pool.bloz.org
```

Pool dashboard: https://pool.bloz.org

---

## Runbooks

- [Pool mining quickstart](runbooks/pool-mining-quickstart.md) — mine on pool.bloz.org (Windows)
- [Mainnet mining pool (ops)](runbooks/mainnet-mining-pool.md) — pool VPS infrastructure
- [Mainnet Seed Node](runbooks/mainnet-seed-node.md) — run a persistent, reachable mainnet peer
- [Mainnet Explorer](runbooks/mainnet-explorer.md) — btc-rpc-explorer for BLOZ
- [Testnet Seed Node](runbooks/testnet-seed-node.md) — testnet peer (TBLOZ, dev/testing)
- [`scripts/wsl-portproxy.ps1`](scripts/wsl-portproxy.ps1) — Windows→WSL port proxy (dev only)

---

## Scope

- Public seed nodes and network bootstrap (mainnet + testnet)
- Release checklists and CI
- Pool miner builds ([pool-miner-v* releases](https://github.com/Rexemre/blockzero-ops/releases))
- Monitoring, incident response, postmortems

---

## Official links

| | |
|---|---|
| **Website** | https://bloz.org |
| **Pool** | https://pool.bloz.org |
| **Explorer** | https://explorer.bloz.org |
| **Bridge** | https://bridge.bloz.org |
| **Discord** | https://discord.gg/FbJzrwAU2W |
| **X (Twitter)** | https://x.com/Block_Zero_2009 |
| **Full list** | [official-links.md](https://github.com/Rexemre/blockzero-docs/blob/main/official-links.md) |

**Mainnet seed:** `217.160.46.61:8210`

---

## Repositories

| Repo | Purpose |
|------|---------|
| [blockzero-core](https://github.com/Rexemre/blockzero-core) | Node & chain |
| [blockzero-docs](https://github.com/Rexemre/blockzero-docs) | Documentation |
| **blockzero-ops** (here) | Scripts & infrastructure |
| [blockzero-wallet](https://github.com/Rexemre/blockzero-wallet) | Wallet guides |
| [blockzero-bridge](https://github.com/Rexemre/blockzero-bridge) | wBLOZ bridge |

> **Warning:** Copycat sites (e.g. `.cc` domains) and third-party pools are **not affiliated** with Block Zero — we have no insight into their code and accept **no liability** for malware, wrong-chain mining, fraud, or unfair pool payouts. [Read the full warning →](https://github.com/Rexemre/blockzero-docs/blob/main/official-links.md#warning-copycat-sites--unofficial-services)
