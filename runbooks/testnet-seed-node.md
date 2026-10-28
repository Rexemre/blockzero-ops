# Runbook: Block Zero Testnet Seed Node

How to run a persistent, reachable Block Zero **testnet** node. Two host options:

- **VPS (recommended for a public seed):** static public IP, always on, no NAT.
- **Home PC via WSL2:** works, but needs NAT/port-forwarding and survives reboots
  only with the autostart steps below.

P2P port: `18210` (testnet). RPC port: `18211` (local only).

**Production seed:** `217.160.46.61:18210` on the IONOS VPS (`mail.example.org`).

---

## A. VPS seed (217.160.46.61) — always on

Paths on the VPS:

| Path | Purpose |
|---|---|
| `/opt/blockzero-core/build/bin/bitcoind` | binary |
| `/opt/bzero-testnet/` | datadir + `bitcoin.conf` |
| `/etc/systemd/system/blockzero-testnet.service` | systemd unit |

Install or refresh the service (from your PC, as root):

```bash
ssh -i ~/.ssh/id_ed25519 root@217.160.46.61
ufw allow 18210/tcp comment 'Block Zero testnet P2P'
cp blockzero-ops/systemd/blockzero-testnet.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now blockzero-testnet
```

Health checks on the VPS:

```bash
systemctl status blockzero-testnet --no-pager
ss -tlnp | grep 18210
/opt/blockzero-core/build/bin/bitcoin-cli -testnet -datadir=/opt/bzero-testnet getblockchaininfo
```

### IONOS cloud firewall (required)

The VPS uses an **IONOS cloud firewall policy** that filters traffic *before* ufw.
Both must allow TCP **18210**:

1. `my.ionos.de` → Server & Cloud → Netzwerk → Firewall-Richtlinien
2. Open the policy assigned to server **server**
3. Add inbound rule: TCP **18210**, source `0.0.0.0/0`

Verify from your PC:

```powershell
.\scripts\testnet\check-seed.ps1
# or: Test-NetConnection 217.160.46.61 -Port 18210
```

---

## B. The node (Linux / WSL2 — home dev)

### Config

`~/.bzero/bitcoin.conf`:

```
server=1
listen=1
txindex=1
[test]
bind=0.0.0.0:18210
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
```

### systemd service

`/etc/systemd/system/blockzero-testnet.service`:

```
[Unit]
Description=Block Zero testnet node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=marlon
ExecStart=/home/USER/blockzero-core/build/bin/bitcoind -testnet -datadir=/home/USER/.bzero
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Install and enable:

```bash
pkill -x bitcoind 2>/dev/null            # stop any manual instance first
sudo cp ~/blockzero-testnet.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now blockzero-testnet
sudo loginctl enable-linger marlon       # run without an open login session
systemctl status blockzero-testnet --no-pager
```

Health checks:

```bash
cd ~/blockzero-core
./build/bin/bitcoin-cli -testnet -datadir=/home/USER/.bzero getblockchaininfo
./build/bin/bitcoin-cli -testnet -datadir=/home/USER/.bzero getconnectioncount
```

---

## B. Reachability on a home PC (Windows + WSL2)

WSL2 is NAT'd behind Windows, so inbound traffic must be forwarded to the WSL IP,
which **changes on reboot**. Use the helper script below.

### One-time firewall rule (Admin PowerShell)

```powershell
New-NetFirewallRule -DisplayName "BlockZero P2P 18210" -Direction Inbound -LocalPort 18210 -Protocol TCP -Action Allow
```

### Port-proxy refresh (Admin PowerShell, also at every boot)

See `scripts/wsl-portproxy.ps1`. It reads the current WSL IP and (re)creates the
portproxy from Windows:18210 to the WSL node.

### Router

Forward TCP `18210` to this PC's LAN IP.

### Public address

`getexternalip`/`https://api.ipify.org` shows the WAN IP. If the ISP IP is dynamic,
use a dynamic-DNS hostname for the seed entry instead of a raw IP.

---

## C. Boot autostart (home PC)

WSL does not auto-start on Windows boot by itself. Create a scheduled task (run at
logon; for a headless always-on box, run at startup as SYSTEM via an elevated task)
that launches WSL (systemd then starts the node) and refreshes the port-proxy:

```powershell
# starts WSL (-> systemd -> blockzero-testnet) and fixes the portproxy
schtasks /Create /TN "BlockZeroTestnet" /TR "powershell -ExecutionPolicy Bypass -File C:\Users\USER\blockzero\blockzero-ops\scripts\wsl-portproxy.ps1" /SC ONLOGON /RL HIGHEST /F
```

---

## E. Becoming a seed in chainparams

Once the node is reachable at a stable address (IP or dyndns hostname), add it to
`src/kernel/chainparams.cpp` (testnet section) as a fixed/DNS seed and ship a release.
Until then peers connect manually:

```bash
bitcoin-cli -testnet addnode "<host>:18210" add
```

---

## Notes

- Verifying blocks is one RandomX hash per block (cheap); a seed node is light.
- Keep the node updated when security backports land (see `blockzero-core/UPSTREAM.md`).
