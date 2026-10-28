#!/usr/bin/env python3
"""Overwrite explorer bundled icons + clean layout favicon links."""
import json
import paramiko
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("pip install Pillow")

SEED = "217.160.46.61"
KEY = Path.home() / ".ssh/id_ed25519"
ASSETS = Path(r"C:\Users\USER\ServerRepo\sites\blockzero\assets")
EXPLORER_ICONS = "/opt/btc-rpc-explorer-mainnet/public/img/network-mainnet"
LAYOUT = "/opt/btc-rpc-explorer-mainnet/views/layout.pug"

FAVICON_Q = "?v=10"
FAVICON_LINKS = (
    f'\t\tlink(rel="icon", href="https://bloz.org/favicon.ico{FAVICON_Q}", sizes="any")\n'
    f'\t\tlink(rel="icon", type="image/png", sizes="32x32", href="https://bloz.org/assets/favicon-32.png{FAVICON_Q}")\n'
    f'\t\tlink(rel="icon", type="image/png", href="https://bloz.org/assets/favicon.png{FAVICON_Q}")\n'
    f'\t\tlink(rel="apple-touch-icon", href="https://bloz.org/assets/apple-touch-icon.png{FAVICON_Q}")\n'
)

# local prep: 16x16 + 192/512 for manifest
img32 = Image.open(ASSETS / "favicon-32.png")
img32.resize((16, 16), Image.LANCZOS).save(ASSETS / "favicon-16.png")
img180 = Image.open(ASSETS / "apple-touch-icon.png")
img180.resize((192, 192), Image.LANCZOS).save(ASSETS / "android-chrome-192.png")
img180.resize((512, 512), Image.LANCZOS).save(ASSETS / "android-chrome-512.png")

manifest = {
    "name": "Block Zero Explorer",
    "short_name": "BLOZ Explorer",
    "icons": [
        {"src": f"android-chrome-192.png{FAVICON_Q}", "sizes": "192x192", "type": "image/png"},
        {"src": f"android-chrome-512.png{FAVICON_Q}", "sizes": "512x512", "type": "image/png"},
    ],
    "theme_color": "#05070A",
    "background_color": "#05070A",
    "display": "standalone",
}
(ASSETS / "site.webmanifest").write_text(json.dumps(manifest, indent=4), encoding="utf-8")

uploads = [
    (ASSETS / "favicon-32.png", f"{EXPLORER_ICONS}/favicon-32x32.png"),
    (ASSETS / "favicon-16.png", f"{EXPLORER_ICONS}/favicon-16x16.png"),
    (ASSETS / "favicon.png", f"{EXPLORER_ICONS}/favicon.ico"),  # png as ico fallback
    (ASSETS / "apple-touch-icon.png", f"{EXPLORER_ICONS}/apple-touch-icon.png"),
    (ASSETS / "android-chrome-192.png", f"{EXPLORER_ICONS}/android-chrome-192x192.png"),
    (ASSETS / "android-chrome-512.png", f"{EXPLORER_ICONS}/android-chrome-512x512.png"),
    (ASSETS / "site.webmanifest", f"{EXPLORER_ICONS}/site.webmanifest"),
    (ASSETS / "favicon-32.png", "/opt/sites/blockzero/assets/favicon-32.png"),
    (ASSETS / "favicon.png", "/opt/sites/blockzero/assets/favicon.png"),
    (ASSETS / "apple-touch-icon.png", "/opt/sites/blockzero/assets/apple-touch-icon.png"),
]

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(SEED, username="root", key_filename=str(KEY), timeout=20)
sftp = c.open_sftp()
for local, remote in uploads:
    sftp.put(str(local), remote)
    print("uploaded", local.name, "->", remote)
sftp.close()

sftp = c.open_sftp()
sftp.put(
    str(Path(r"C:\Users\USER\blockzero\blockzero-ops\scripts\mainnet\fix-explorer-layout.py")),
    "/root/fix-explorer-layout.py",
)
sftp.close()
_, out, err = c.exec_command(
    "python3 /root/fix-explorer-layout.py && systemctl restart blockzero-mainnet-explorer && "
    "grep favicon /opt/btc-rpc-explorer-mainnet/views/layout.pug",
    timeout=45,
)
print(out.read().decode())
if err.read():
    print("stderr:", err.read().decode()[:300])
c.close()
print("done")
