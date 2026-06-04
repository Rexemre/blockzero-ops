# Runbook: Block Zero Testnet Block Explorer

A web block explorer for the Block Zero testnet, using the off-the-shelf
open-source [btc-rpc-explorer](https://github.com/janoside/btc-rpc-explorer)
pointed at the VPS seed node's RPC. No custom code.

- Host: IONOS VPS `217.160.46.61` (same box as the seed node).
- Public URL: `https://texplorer.bloz.org` (after DNS, see below).
- App: Node.js, listens on `127.0.0.1:3002`, behind Caddy.

## Components on the VPS

| Path | Purpose |
|---|---|
| `/opt/btc-rpc-explorer/` | the explorer (git clone + `npm install --omit=dev`) |
| `/opt/btc-rpc-explorer/.env` | config (see `systemd/blockzero-explorer.env.example`) |
| `/etc/systemd/system/blockzero-explorer.service` | systemd unit |
| `/opt/sites/blockzero-explorer/Caddyfile.snippet` | Caddy vhost (in MarlonMoralesServer repo) |

The explorer authenticates to bitcoind via the RPC cookie
`/opt/bzero-testnet/testnet3/.cookie`, so no password is stored.

## Install / refresh

```bash
ssh -i ~/.ssh/id_ed25519 root@217.160.46.61
cd /opt && git clone --depth 1 https://github.com/janoside/btc-rpc-explorer.git
cd btc-rpc-explorer && npm install --omit=dev
# copy .env from blockzero-ops/systemd/blockzero-explorer.env.example
cp blockzero-ops/systemd/blockzero-explorer.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now blockzero-explorer
```

## Publish (Caddy + DNS)

1. Add the Caddy snippet (symlinked into `/etc/caddy/sites/`):

   ```bash
   ln -sf /opt/sites/blockzero-explorer/Caddyfile.snippet \
          /etc/caddy/sites/blockzero-testnet-explorer.caddy
   ```

2. Pre-create the log file (Caddy runs as the `caddy` user):

   ```bash
   install -o caddy -g caddy -m 644 /dev/null /var/log/caddy/blockzero-testnet-explorer.log
   ```

3. The Caddyfile has `admin off`, so **restart** (not reload):

   ```bash
   systemctl restart caddy
   ```

4. **DNS (one-time, IONOS):** in the `bloz.org` zone add an A record
   `texplorer -> 217.160.46.61` (i.e. `texplorer.bloz.org`).
   Mainnet explorer uses `explorer.bloz.org` (see `mainnet-explorer.md`).
   Ports 80/443 are already open in the IONOS cloud firewall, so Caddy issues
   the TLS cert automatically on the first request.

## Health checks

```bash
systemctl status blockzero-explorer --no-pager
curl -s http://127.0.0.1:3002/api/blocks/tip/height      # current height
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090/   # via Caddy
```

## Branding (Block Zero / TBLOZ)

btc-rpc-explorer ships only Bitcoin labels. `scripts/explorer-branding.py`
rewrites the coin config (`app/coins/btc.js`), the global currency table
(`app/currencies.js` — this is where the amount unit "BTC" actually comes from)
and several Pug views so the UI reads **Block Zero** / **TBLOZ** instead of
**Bitcoin** / **BTC** (title, navbar, amounts, unit toggle, meta tags).

Re-run it after every `git pull` of the explorer, then restart:

```bash
python3 /opt/blockzero-ops/scripts/explorer-branding.py testnet
systemctl restart blockzero-explorer
```

Remaining upstream references are the project's own `@BitcoinExplorer` footer
links and the "Bitcoin Quote of the Day" widget (attribution, not currency).

The address prefix `tbz` (bech32 HRP) is intentional — it is Block Zero's
testnet HRP (mainnet `bz`), analogous to Bitcoin's `tb`/`bc`. It is **not** the
ticker; the ticker/unit is TBLOZ.

## Notes

- Address-history pages need an address index (electrs/electrumx). Block, tx
  and mempool browsing work without it.
