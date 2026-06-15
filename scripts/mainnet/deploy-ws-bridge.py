#!/usr/bin/env python3
"""Deploy ws_bridge.py to pool VPS and restart ws service."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import paramiko

HOST = "217.154.169.211"
USER = "root"
REMOTE = "/opt/blockzero-pool/engine/ws_bridge.py"
LOCAL = Path(r"C:\Users\Marlon\blockzero\blockzero-pool\engine\ws_bridge.py")


def main() -> int:
    password = os.environ.get("BLOZ_POOL_SSH_PASSWORD", "")
    if not password:
        print("BLOZ_POOL_SSH_PASSWORD not set", file=sys.stderr)
        return 1
    if not LOCAL.exists():
        print(f"Missing {LOCAL}", file=sys.stderr)
        return 1

    data = LOCAL.read_bytes()
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=password, timeout=20, allow_agent=False, look_for_keys=False)
    sftp = c.open_sftp()
    with sftp.file(REMOTE, "wb") as f:
        f.write(data)
    sftp.close()
    _, out, err = c.exec_command("systemctl restart blockzero-pool-ws && systemctl is-active blockzero-pool-ws", timeout=30)
    print(out.read().decode(), end="")
    e = err.read().decode()
    if e:
        print(e, file=sys.stderr)
    c.close()
    print(f"Deployed {LOCAL.name} -> {REMOTE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
