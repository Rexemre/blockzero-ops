# BLOCK ZERO · Ops

**Modern BTC code. A second chance at Genesis.**

Infrastructure, release tooling, and runbooks for the Block Zero network.

Fair launch. Proof-of-work. No presale. No insiders.

---

## Mine mainnet in one command

| Platform | Script |
|----------|--------|
| **Windows (pool)** | [`mine-mainnet.ps1 -Pool`](scripts/mainnet/mine-mainnet.ps1) or double-click [`mine-pool.bat`](scripts/mainnet/mine-pool.bat) |
| **Windows (solo)** | [`install-windows.ps1`](scripts/testnet/install-windows.ps1) → [`mine-mainnet.ps1`](scripts/mainnet/mine-mainnet.ps1) |
| **Linux / macOS** | Build from [blockzero-core Releases](https://github.com/Rexemre/blockzero-core/releases), then use [`scripts/mainnet/`](scripts/mainnet/) |

**Public seed:** `217.160.46.61:8210` · **Explorer:** https://explorer.bloz.org

```powershell
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops\scripts\testnet
.\install-windows.ps1
cd ..\mainnet
.\mine-mainnet.ps1 -Status   # sync first — never mine with 0 peers
.\mine-mainnet.ps1
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
- Monitoring, incident response, postmortems

---

## Repositories

| Repo | Purpose |
|------|---------|
| [blockzero-core](https://github.com/Rexemre/blockzero-core) | Node & chain |
| [blockzero-docs](https://github.com/Rexemre/blockzero-docs) | Documentation |
| **blockzero-ops** (here) | Scripts & infrastructure |
| [blockzero-wallet](https://github.com/Rexemre/blockzero-wallet) | Wallet (in development) |
