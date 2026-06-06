# Runbook: Block Zero Mainnet Seed Node

Production mainnet seed on the IONOS VPS (`217.160.46.61`).

- P2P: `8210` (public)
- RPC: `8211` (localhost only)
- Explorer: https://explorer.bloz.org

## Paths on the VPS

| Path | Purpose |
|---|---|
| `/opt/bzero-mainnet/` | datadir + `bitcoin.conf` |
| `/opt/blockzero-core/build/bin/bitcoind` | node binary |
| `/etc/systemd/system/blockzero-mainnet.service` | systemd unit |
| `/opt/btc-rpc-explorer-mainnet/` | mainnet block explorer |

## bitcoin.conf

Use `systemd/bzero-mainnet-seed.bitcoin.conf.example`. The seed must bind
`0.0.0.0:8210` for inbound peers. Do **not** put `listen=1` outside `[main]` —
that caused RPC bind failures on startup.

## Launch day

```bash
ssh root@217.160.46.61
cp /opt/blockzero-ops/systemd/bzero-mainnet-seed.bitcoin.conf.example \
   /opt/bzero-mainnet/bitcoin.conf
systemctl enable --now blockzero-mainnet
sleep 20
/opt/blockzero-core/build/bin/bitcoin-cli -datadir=/opt/bzero-mainnet getblockhash 0
# 44c1a8c852b3eda21966e1ddb6b0807e22488dffe8a270bf24bf1fa2d66c13bd
systemctl restart blockzero-mainnet-explorer
```

## Firewall

```bash
ufw allow 8210/tcp comment 'Block Zero mainnet P2P'
```

Also open **TCP 8210** in the IONOS cloud firewall (server policy), same as
testnet port 18210.

## Health checks

```bash
systemctl is-active blockzero-mainnet
ss -tlnp | grep 8210
/opt/blockzero-core/build/bin/bitcoin-cli -datadir=/opt/bzero-mainnet getblockcount
curl -s https://explorer.bloz.org/api/blocks/tip/height
```

From outside: `Test-NetConnection 217.160.46.61 -Port 8210`
