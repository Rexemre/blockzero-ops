# Runbook: BLOZ Mining Pool (pool.bloz.org)

## Architecture (2026-06-11)

| Host | Role | IP |
|------|------|-----|
| **Pool VPS** | Pool node, API, web, future stratum (8 cores, 15 GB) | `217.154.169.211` |
| **Miner VPS** | First pool worker (no local node) | `217.160.64.206` |
| **Seed** | P2P sync source | `217.160.46.61:8210` |

DNS `pool.bloz.org` → **`217.154.169.211`** (pool VPS). HTTPS via Caddy/Let's Encrypt.

**Stratum:** `wss://pool.bloz.org/stratum` (port 443 WebSocket — raw TCP 3333 is blocked by hoster firewall).

## Pool VPS paths (`217.154.169.211`)

| Path | Purpose |
|------|---------|
| `/opt/blockzero/bin/` | `bitcoind` / `bitcoin-cli` (rc9) |
| `/opt/bzero-pool/` | Pool node datadir (`bitcoin.conf`, RPC **8215**) |
| `/opt/blockzero-pool/web/` | Dashboard |
| `/opt/blockzero-pool/engine/` | Stratum + WebSocket bridge + API |
| `/opt/blockzero-pool/engine/status-server.py` | API on `:3020` |

## Miner VPS (`217.160.64.206`) — worker #1 only

| Path | Purpose |
|------|---------|
| `/opt/blockzero-pool-worker/wait-stratum.sh` | Waits for stratum on pool VPS |
| `/root/.blockzero-mainnet/mining-address.txt` | Payout `bz1…` |

Local `bitcoind` **stopped/disabled** — worker only, ~3 GB RAM freed.

## systemd

| Host | Unit | Status |
|------|------|--------|
| Pool | `blockzero-pool-node` | active |
| Pool | `blockzero-pool-api` | active |
| Pool | `blockzero-pool-stratum` | active (`127.0.0.1:3333`) |
| Pool | `blockzero-pool-ws` | active (`127.0.0.1:3420` → Caddy `/stratum`) |
| Pool | `caddy` | active (HTTPS `pool.bloz.org`) |
| Miner | `blockzero-pool-worker` | active (`blockzero-miner.py`) |
| Miner | `blockzero-mainnet` / `blockzero-miner` | **disabled** |

## Wallets on pool node

- `mining` — legacy solo wallet (kept)
- `pool` — payout wallet for future pool (`pool-payout` label)

## Ops commands (miner VPS)

```bash
# SSH (password auth — see deploy-miner-vps-rc9.py / MINER_VPS_PASSWORD)
ssh root@217.160.64.206

# Node status
/opt/blockzero/bin/bitcoin-cli -datadir=/root/.blockzero-mainnet getblockcount
systemctl status blockzero-mainnet

# Re-enable solo mining (rollback)
systemctl enable --now blockzero-miner
```

## Local setup scripts

```powershell
python blockzero-ops/scripts/mainnet/stop-miner-vps.py
python blockzero-ops/scripts/mainnet/setup-pool-vps-step2.py
python blockzero-ops/scripts/mainnet/setup-pool-caddy.py
python blockzero-ops/scripts/mainnet/verify-pool-vps.py
```

## Hardware

**Pool VPS:** 8 cores, 15 GB RAM, 464 GB disk — ideal for pool node + stratum.

**Miner VPS:** 4 cores, 4 GB RAM — enough as **one worker** (no local node).

## Miner VPS notes

- `/etc/hosts` entry `217.154.169.211 pool.bloz.org` (miner VPS DNS may lag).
- Connect: `wss://pool.bloz.org/stratum`, worker `bz1….worker1` (no password — payout address is in the worker name).

## Repos

| Repo | Visibility | Contents |
|------|------------|----------|
| `blockzero-pool` | **Private** | VPS engine + web dashboard |
| `blockzero-ops` | Public | User scripts + pool miner build (`pool/native/`) |

Deploy: `python blockzero-ops/scripts/mainnet/deploy-pool-stratum.py` (requires `POOL_VPS_PASSWORD`).

## PPLNS + payouts

| Setting | Default |
|---------|---------|
| Scheme | PPLNS, window `4000000` |
| Fee | `2%` (`POOL_FEE_BPS=200`) |
| Min payout | 0.5 BLOZ (`MIN_PAYOUT_SATS=50000000`) |
| DB | `/opt/blockzero-pool/data/pool.db` |

Services: `blockzero-pool-payout` (auto `sendtoaddress` every 120s).

## Next build steps

1. Native `blockzero-miner` binary (Go/Rust) for Windows/Linux
2. PostgreSQL migration (optional; SQLite today)
3. Open TCP `:3333` at hoster firewall (optional; WSS works today)
