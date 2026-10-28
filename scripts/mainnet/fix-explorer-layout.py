#!/usr/bin/env python3
"""Replace explorer layout favicon block."""
from pathlib import Path

new_block = (
    '\t\tlink(rel="icon", href="https://bloz.org/favicon.ico?v=11", sizes="any")\n'
    '\t\tlink(rel="icon", type="image/png", sizes="32x32", href="https://bloz.org/assets/favicon-32.png?v=11")\n'
    '\t\tlink(rel="icon", type="image/png", href="https://bloz.org/assets/favicon.png?v=11")\n'
    '\t\tlink(rel="apple-touch-icon", href="https://bloz.org/assets/apple-touch-icon.png?v=11")\n'
)

old_block_variants = (
    (
        '\t\tlink(rel="icon", type="image/png", sizes="32x32", href="https://bloz.org/assets/favicon-32.png?v=6")\n'
        '\t\tlink(rel="icon", type="image/png", href="https://bloz.org/assets/favicon.png?v=6")\n'
    ),
    new_block.replace("?v=11", "?v=10"),
    new_block.replace("?v=11", "?v=9"),
    new_block.replace("?v=11", "?v=8"),
    new_block.replace("?v=11", "?v=6"),
    new_block.replace("?v=11", "?v=7"),
    new_block.replace("?v=11", "?v=5").replace("favicon.ico?v=5", "favicon.svg?v=5"),
    (
        '\t\tlink(rel="icon", type="image/png", sizes="32x32", href="https://bloz.org/assets/favicon-32.png")\n'
        '\t\tlink(rel="icon", type="image/png", href="https://bloz.org/assets/favicon.png")\n'
        '\t\tlink(rel="apple-touch-icon", href="https://bloz.org/assets/apple-touch-icon.png")\n'
    ),
)

layout = Path("/opt/btc-rpc-explorer-mainnet/views/layout.pug")
text = layout.read_text(encoding="utf-8")
if new_block in text:
    print("layout.pug favicon block already v=11")
    raise SystemExit(0)

replaced = False
for old in old_block_variants:
    if old in text:
        new = new_block if old.startswith("\t\t") else new_block.replace("\t\t", "\t")
        text = text.replace(old, new, 1)
        replaced = True
        break
if not replaced:
    raise SystemExit("favicon block not found in layout.pug")

layout.write_text(text, encoding="utf-8")
print("layout.pug favicon block replaced")
