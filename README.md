# BLOCK ZERO · Ops

Official scripts and infrastructure for Block Zero mainnet.

**👉 [Discord](https://discord.gg/FbJzrwAU2W)** · **⛏ [pool.bloz.org](https://pool.bloz.org)** · **📖 [Docs](https://github.com/Rexemre/blockzero-docs)**

---

## Start mining (3 steps)

Full guides in **[blockzero-docs](https://github.com/Rexemre/blockzero-docs)**:

1. **[Wallet](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-use-wallet.md)** — get your `bz1` address
2. **[Mine](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-mine.md)** — XMRig one-liner (recommended)
3. **[FAQ](https://github.com/Rexemre/blockzero-docs/blob/main/faq.md)** — troubleshooting

```bash
# Linux (sudo = huge pages) / macOS
curl -fsSL https://pool.bloz.org/install.sh | sudo ADDRESS=bz1qYOURADDRESS bash
```

```powershell
# Windows — PowerShell as Administrator
$env:ADDRESS='bz1qYOURADDRESS'; irm https://pool.bloz.org/install.ps1 | iex
```

Options (`THREADS`, `WORKER`): [how-to-mine.md](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-mine.md)

---

## Scripts (`scripts/mainnet/`)

| Script | Purpose |
|--------|---------|
| [`install-xmrig.sh`](scripts/mainnet/install-xmrig.sh) / [`.ps1`](scripts/mainnet/install-xmrig.ps1) | XMRig one-liner (served as pool.bloz.org/install.*) |
| [`install-windows.ps1`](scripts/mainnet/install-windows.ps1) | Download node + wallet binaries (Windows) |
| [`install-macos.sh`](scripts/mainnet/install-macos.sh) | Download `Block Zero.app` + tools (Apple Silicon) |
| [`mine-mainnet.ps1`](scripts/mainnet/mine-mainnet.ps1) | Wallet + pool/solo (Windows, native miner) |
| [`mine-pool.sh`](scripts/mainnet/mine-pool.sh) | Native pool miner (Linux/macOS) |
| [`mine-solo.sh`](scripts/mainnet/mine-solo.sh) | Solo mining (Linux/macOS) |

Alternative methods & script details: [quickstart-mining.md](https://github.com/Rexemre/blockzero-docs/blob/main/quickstart-mining.md)

XMRig patch & build: [`xmrig-bz/`](xmrig-bz/)

> **Do not mine in WSL2** — RandomX is ~10× slower. Use native Windows/Linux/macOS.

---

## Runbooks

- [Pool mining quickstart](runbooks/pool-mining-quickstart.md)
- [Mainnet mining pool (ops)](runbooks/mainnet-mining-pool.md)
- [Mainnet Seed Node](runbooks/mainnet-seed-node.md)
- [Mainnet Explorer](runbooks/mainnet-explorer.md)
- [Testnet Seed Node](runbooks/testnet-seed-node.md)

---

## Scope

- Public seed nodes (mainnet + testnet)
- XMRig builds & pool miner releases
- CI, monitoring, incident response

**Seed:** `217.160.46.61:8210` · **Explorer:** https://explorer.bloz.org

---

## Repositories

| Repo | Purpose |
|------|---------|
| [blockzero-core](https://github.com/Rexemre/blockzero-core) | Node & wallet |
| [blockzero-docs](https://github.com/Rexemre/blockzero-docs) | Documentation |
| **blockzero-ops** (here) | Scripts & infrastructure |
| [blockzero-wallet](https://github.com/Rexemre/blockzero-wallet) | Wallet doc hub |
| [blockzero-bridge](https://github.com/Rexemre/blockzero-bridge) | wBLOZ bridge |

> Copycat sites and third-party pools are **not affiliated** with Block Zero. [Warning →](https://github.com/Rexemre/blockzero-docs/blob/main/official-links.md#warning-copycat-sites--unofficial-services)
