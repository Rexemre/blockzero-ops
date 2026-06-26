#!/usr/bin/env python3
"""Deploy Block Zero brand assets and HTML to VPS."""
from __future__ import annotations

import os
from pathlib import Path

import paramiko

SEED = "217.160.46.61"
POOL = "217.154.169.211"
KEY = Path.home() / ".ssh" / "id_ed25519"

ASSETS = Path(r"C:\Users\Marlon\MarlonMoralesServer\sites\blockzero\assets")
SITE = Path(r"C:\Users\Marlon\MarlonMoralesServer\sites\blockzero")
POOL_WEB = Path(r"C:\Users\Marlon\blockzero\blockzero-pool\web\index.html")
BRIDGE_WEB = Path(r"C:\Users\Marlon\blockzero\blockzero-bridge\web\index.html")
BRANDING = Path(r"C:\Users\Marlon\blockzero\blockzero-ops\scripts\explorer-branding.py")

UPLOAD_ASSETS = [
    "bloz-logo-nav.png",
    "favicon-16.png",
    "favicon.png",
    "favicon-32.png",
    "apple-touch-icon.png",
    "android-chrome-192.png",
    "android-chrome-512.png",
    "site.webmanifest",
    "bloz-token-icon.svg",
    "bloz-header.css",
    "styles.css",
]


def connect(host: str, password: str | None = None) -> paramiko.SSHClient:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    if password:
        c.connect(host, username="root", password=password, timeout=20, allow_agent=False, look_for_keys=False)
    else:
        c.connect(host, username="root", key_filename=str(KEY), timeout=20)
    return c


def put(sftp: paramiko.SFTPClient, local: Path, remote: str) -> None:
    sftp.put(str(local), remote)
    print(f"  uploaded {local.name} -> {remote}")


def deploy_seed() -> None:
    print("== seed VPS ==")
    c = connect(SEED)
    sftp = c.open_sftp()
    for name in UPLOAD_ASSETS:
        put(sftp, ASSETS / name, f"/opt/sites/blockzero/assets/{name}")
    put(sftp, SITE / "index.html", "/opt/sites/blockzero/index.html")
    put(sftp, SITE / "favicon.ico", "/opt/sites/blockzero/favicon.ico")
    put(sftp, BRIDGE_WEB, "/opt/blockzero-bridge/web/index.html")
    put(sftp, BRANDING, "/opt/blockzero-ops/scripts/explorer-branding.py")
    sftp.close()
    _, out, err = c.exec_command(
        "rm -f /opt/sites/blockzero/assets/favicon.svg && "
        "python3 /opt/blockzero-ops/scripts/explorer-branding.py mainnet && "
        "systemctl restart blockzero-mainnet-explorer && "
        "curl -skI 'https://bloz.org/favicon.ico?v=11' | head -3 && "
        "curl -skI 'https://bloz.org/assets/favicon-32.png?v=11' | head -3",
        timeout=90,
    )
    text = out.read().decode(errors="replace")
    if text.strip():
        print(text.encode("ascii", errors="replace").decode("ascii"))
    e = err.read().decode(errors="replace")
    if e:
        print("stderr:", e[:500])
    c.close()


def deploy_pool() -> None:
    print("== pool VPS ==")
    pool_password = os.environ.get("BLOZ_POOL_SSH_PASSWORD")
    try:
        c = connect(POOL, password=pool_password) if pool_password else connect(POOL)
    except Exception as ex:
        print(f"  skip pool (no SSH): {ex}")
        return
    sftp = c.open_sftp()
    # pool may serve from different path
    for remote in ("/opt/blockzero-pool/web/index.html", "/var/www/pool/index.html"):
        try:
            put(sftp, POOL_WEB, remote)
            break
        except OSError:
            continue
    sftp.close()
    c.close()


if __name__ == "__main__":
    deploy_seed()
    deploy_pool()
    print("done")
