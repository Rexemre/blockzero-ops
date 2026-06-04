# Runbook: Block Zero Mainnet Block Explorer

A web block explorer for Block Zero **mainnet**, using a dedicated
[btc-rpc-explorer](https://github.com/janoside/btc-rpc-explorer) install
(separate from the testnet instance so TBLOZ/BLOZ branding does not clash).

- Host: IONOS VPS `217.160.46.61` (same box as the seed node).
- Public URL: `https://explorer.bloz.org`
- App: Node.js, listens on `127.0.0.1:3003`, behind Caddy.
- Depends on `blockzero-mainnet.service` (enable the node on launch day first).

## Components on the VPS

| Path | Purpose |
|---|---|
| `/opt/btc-rpc-explorer-mainnet/` | mainnet explorer (git clone + `npm install --omit=dev`) |
| `/opt/btc-rpc-explorer-mainnet/.env` | mainnet config (see `systemd/blockzero-mainnet-explorer.env.example`) |
| `/etc/systemd/system/blockzero-mainnet-explorer.service` | systemd unit |
| `/opt/sites/blockzero-mainnet-explorer/Caddyfile.snippet` | Caddy vhost (MarlonMoralesServer repo) |

The explorer authenticates to bitcoind via the RPC cookie
`/opt/bzero-mainnet/.cookie`, so no password is stored.

## Install / refresh

```bash
ssh -i ~/.ssh/id_ed25519 root@217.160.46.61

# Ensure the mainnet explorer is installed
cd /opt && git clone --depth 1 https://github.com/janoside/btc-rpc-explorer.git btc-rpc-explorer-mainnet
cd btc-rpc-explorer-mainnet && npm install --omit=dev

cp /opt/blockzero-ops/systemd/blockzero-mainnet-explorer.env.example \
   /opt/btc-rpc-explorer-mainnet/.env
cp /opt/blockzero-ops/systemd/blockzero-mainnet-explorer.service /etc/systemd/system/

python3 /opt/blockzero-ops/scripts/explorer-branding.py mainnet
systemctl daemon-reload
systemctl enable --now blockzero-mainnet-explorer
```

> **Before launch:** `blockzero-mainnet.service` is disabled until 2026-06-06.
> The mainnet explorer will restart until the node is running — that is expected.
> Enable the node first (`systemctl enable --now blockzero-mainnet`), then the explorer.

## Publish (Caddy + DNS)

1. Add the Caddy snippet:

   ```bash
   ln -sf /opt/sites/blockzero-mainnet-explorer/Caddyfile.snippet \
          /etc/caddy/sites/blockzero-mainnet-explorer.caddy
   install -o caddy -g caddy -m 644 /dev/null /var/log/caddy/blockzero-mainnet-explorer.log
   ```

2. Update the testnet snippet symlink (domain moved to texplorer):

   ```bash
   ln -sf /opt/sites/blockzero-explorer/Caddyfile.snippet \
          /etc/caddy/sites/blockzero-testnet-explorer.caddy
   rm -f /etc/caddy/sites/blockzero-explorer.caddy   # old explorer.bloz.org -> :3002
   ```

3. Restart Caddy (`admin off` on this host):

   ```bash
   systemctl restart caddy
   ```

4. **DNS (IONOS):**
   - `explorer.bloz.org` → `217.160.46.61` (mainnet; record likely already exists)
   - `texplorer.bloz.org` → `217.160.46.61` (new A record for testnet)

## Health checks

```bash
systemctl status blockzero-mainnet-explorer --no-pager
curl -s http://127.0.0.1:3003/api/blocks/tip/height
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: explorer.bloz.org' http://127.0.0.1:8093/
curl -sI https://explorer.bloz.org/ | head -5
```

## Branding (Block Zero / BLOZ)

```bash
python3 /opt/blockzero-ops/scripts/explorer-branding.py mainnet
systemctl restart blockzero-mainnet-explorer
```

Address prefix `bz` (bech32 HRP) is Block Zero mainnet; ticker/unit is **BLOZ**.

## Notes

- Testnet explorer: **https://texplorer.bloz.org** (`/opt/btc-rpc-explorer/`, port 3002).
- Mainnet explorer: **https://explorer.bloz.org** (`/opt/btc-rpc-explorer-mainnet/`, port 3003).
- Each install has its own branding patch; re-run the matching `explorer-branding.py`
  after `git pull` in that directory.
