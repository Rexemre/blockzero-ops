# Pool mining quickstart

Ops runbook for **pool.bloz.org**. User-facing guides live in [blockzero-docs](https://github.com/Rexemre/blockzero-docs).

| Guide | Link |
|-------|------|
| Wallet | [how-to-use-wallet.md](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-use-wallet.md) |
| Mining (XMRig) | [how-to-mine.md](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-mine.md) |
| Scripts & alternatives | [quickstart-mining.md](https://github.com/Rexemre/blockzero-docs/blob/main/quickstart-mining.md) |

Dashboard: https://pool.bloz.org

---

## Recommended: XMRig one-liner

See [how-to-mine.md](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-mine.md) for full commands and options (`THREADS`, `WORKER`).

```powershell
$env:ADDRESS='bz1qYOURADDRESS'; irm https://pool.bloz.org/install.ps1 | iex
```

```bash
curl -fsSL https://pool.bloz.org/install.sh | sudo ADDRESS=bz1qYOURADDRESS bash
```

---

## Alternative: native miner scripts

### Windows (`mine-mainnet.ps1 -Pool`)

```powershell
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops\scripts\mainnet
.\install-windows.ps1
.\mine-mainnet.ps1 -Pool
.\mine-mainnet.ps1 -Pool -Threads 4
```

### Linux / macOS (`mine-pool.sh`)

```bash
git clone https://github.com/Rexemre/blockzero-ops.git
cd blockzero-ops/scripts/mainnet
chmod +x mine-pool.sh
sudo ./mine-pool.sh bz1YOURADDRESS
```

Pass **address only** — not `bz1…rig1`. Options: `THREADS=8` · `WORKER=rig2` · `FORCE=1`.

---

## Pool settings

| Setting | Value |
|---------|-------|
| Dashboard | https://pool.bloz.org |
| XMRig stratum | `pool.bloz.org:3334` (TCP) |
| Native stratum | `wss://pool.bloz.org/stratum` |
| Worker format | `bz1YOURADDRESS.rigname` |
| Password | `x` |
| Payout | PPLNS, 2% fee, min 0.5 BLOZ |

---

## Pool transparency

| Item | Value |
|------|-------|
| Pool payout address | `bz1qxp5dek9uq4hzemeg9cv0f8hfm3hl35kxunfkma` |
| Explorer | [explorer.bloz.org](https://explorer.bloz.org/address/bz1qxp5dek9uq4hzemeg9cv0f8hfm3hl35kxunfkma) |
| Pool engine | [blockzero-pool](https://github.com/Rexemre/blockzero-pool) |
| Miner source | [pool/native](https://github.com/Rexemre/blockzero-ops/tree/main/pool/native) · [xmrig-bz](https://github.com/Rexemre/blockzero-ops/tree/main/xmrig-bz) |

When the pool finds a block, rewards are split PPLNS and auto-paid once balance ≥ 0.5 BLOZ.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Not on dashboard yet | Wait for first **accepted share** (~1–2 min) |
| Worker shows `.rig.rig` | Pass address only to `mine-pool.sh`, not `bz1…rig1` |
| Hashrate 0 then jumps | Normal — RandomX dataset builds ~1 min first |
| Change threads | XMRig: [how-to-mine.md § Options](https://github.com/Rexemre/blockzero-docs/blob/main/how-to-mine.md#options--threads-rig-name--more) · native: `-Threads 8` / `THREADS=8` |
| macOS blocks binary | System Settings → Privacy & Security → Allow |
| Low hashrate on EPYC | Run with `sudo` for huge pages |

More: [FAQ](https://github.com/Rexemre/blockzero-docs/blob/main/faq.md)

---

## Files (Windows)

| Path | Purpose |
|------|---------|
| `%LOCALAPPDATA%\BlockZeroMainnet\mining-address.txt` | Payout address |
| `%LOCALAPPDATA%\BlockZero\xmrig\` | XMRig install location |
| `~/.blockzero/xmrig/` | XMRig (Linux/macOS) |
