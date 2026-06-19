#!/usr/bin/env python3
"""Upload blockzero-pool/web to pool node VPS."""
import os
import paramiko

ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "blockzero-pool", "web")
)
REMOTE = "/opt/blockzero-pool/web"
HOST = os.environ.get("POOL_VPS_HOST", "217.154.169.211")
FALLBACK_HOST = os.environ.get("POOL_WEB_FALLBACK_HOST", "217.160.64.206")


def main() -> None:
    pw = os.environ.get("POOL_VPS_PASSWORD") or ""
    if not pw:
        raise SystemExit("Set POOL_VPS_PASSWORD")
    print(f"Deploying to {HOST}...")
    try:
        upload_with_pw(HOST, pw)
        print("Done.")
        return
    except Exception as exc:
        print(f"{HOST}: {exc}")
    fb_pw = os.environ.get("MINER_VPS_PASSWORD", "")
    if FALLBACK_HOST and FALLBACK_HOST != HOST and fb_pw:
        print(f"Fallback {FALLBACK_HOST} (not live DNS unless you switch)...")
        try:
            upload_with_pw(FALLBACK_HOST, fb_pw)
            print("Fallback upload ok — pool.bloz.org still serves from POOL VPS until you deploy there.")
            return
        except Exception as exc2:
            print(f"{FALLBACK_HOST}: {exc2}")
    raise SystemExit("Deploy failed")


def upload_with_pw(host: str, pw: str) -> None:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, username="root", password=pw, timeout=30)
    s = c.open_sftp()
    for name in ("index.html", "assets/app.css", "assets/app.js", "install.sh", "install.ps1"):
        local = os.path.join(ROOT, name.replace("/", os.sep))
        if not os.path.exists(local):
            continue
        remote = f"{REMOTE}/{name}"
        s.put(local, remote)
        print(f"  {local} -> {host}:{remote}")
    s.close()
    _, o, _ = c.exec_command(
        f"grep -c 'details open' {REMOTE}/index.html || true", timeout=15
    )
    print(f"  details open count: {o.read().decode().strip()}")
    c.close()


if __name__ == "__main__":
    main()
