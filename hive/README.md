# Block Zero on Hive OS

CPU mining only (`rx/blockzero` RandomX). Stock XMRig does **not** work — use the patched build from [blockzero-ops releases](https://github.com/Rexemre/blockzero-ops/releases).

## Option A — Custom miner (works today, no Hive approval)

### 1. Build or download the package

```bash
cd hive
./build-package.sh 6.26.0 xmrig-v6.26.0
```

After publishing to GitHub Releases (`bzxmrig-6.26.0.tar.gz`), rigs can install with:

```bash
custom-get https://github.com/Rexemre/blockzero-ops/releases/download/hive-bzxmrig-v6.26.0/bzxmrig-6.26.0.tar.gz -f
```

### 2. Flight sheet (Hive web UI)

| Field | Value |
|-------|--------|
| Coin | `CUSTOM` |
| Miner | `custom` |
| Miner name | `bzxmrig` |
| Installation URL | URL of `bzxmrig-6.26.0.tar.gz` |
| Hash algorithm | `rx/blockzero` (or any label — algo is fixed in config) |
| Wallet and worker template | `%WAL%.%WORKER_NAME%` |
| Pool URL | `pool.bloz.org:3334` |
| Pass | `x` |
| Extra config (optional) | e.g. `"max-threads-hint": 100` inside `cpu` — one JSON key per line |

Wallet must be a `bz1…` address. Worker name becomes the rig name on [pool.bloz.org](https://pool.bloz.org).

### 3. Huge pages

In Hive: **Settings → Access → run `hugepages -rx` once**, or enable huge pages in the rig shell before mining. Without this, RandomX hashrate is much lower.

---

## Option B — Official coin / miner in Hive preset list

There is **no public web form**. Contact Hive:

| Channel | Address |
|---------|---------|
| Business / integration | **business@hiveos.com** |
| Community | [Hive OS forum](https://hiveon.com/forum/) — category Miners |

Attach or link the custom miner tarball and point to:

- Pool: `pool.bloz.org:3334`
- Algorithm: `rx/blockzero` (patched XMRig)
- Docs: https://github.com/Rexemre/blockzero-docs/blob/main/how-to-mine.md
- Binary source: https://github.com/Rexemre/blockzero-ops/tree/main/xmrig-bz

See `listing-email-de.txt` for a ready-to-send German email draft.
