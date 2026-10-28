#!/usr/bin/env python3
"""Prepare Block Zero brand assets from Downloads and copy into site repo."""
from __future__ import annotations

from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("pip install Pillow")

DOWNLOADS = Path(r"C:\Users\USER\Downloads")
SITE_ASSETS = Path(r"C:\Users\USER\ServerRepo\sites\blockzero\assets")
SITE_ROOT = SITE_ASSETS.parent
OPS_ASSETS = Path(r"C:\Users\USER\blockzero\blockzero-ops\assets")

FAVICON_VER = "10"
FAVICON_Q = f"?v={FAVICON_VER}"

NAVBAR_SRC = DOWNLOADS / "ChatGPT Image Jun 13, 2026, 02_17_27 PM.png"
ICON_SRC = DOWNLOADS / "favicon-15-06V2.png"
BSCSCAN_SRC = DOWNLOADS / "block_zero_0_only_bscscan_logo.svg"


def white_to_alpha(img: Image.Image, threshold: int = 245) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                px[x, y] = (r, g, b, 0)
    return img


def trim_transparent(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def flood_remove_edge_dark(img: Image.Image, tol: int = 42) -> Image.Image:
    """Remove dark background pixels reachable from image edges."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size

    def is_bg(x: int, y: int) -> bool:
        r, g, b, a = px[x, y]
        return a > 0 and r <= tol and g <= tol and b <= tol

    seen: set[tuple[int, int]] = set()
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))

    while q:
        x, y = q.popleft()
        if (x, y) in seen or x < 0 or y < 0 or x >= w or y >= h:
            continue
        if not is_bg(x, y):
            continue
        seen.add((x, y))
        px[x, y] = (0, 0, 0, 0)
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return img


def strip_dark_fringe(img: Image.Image, alpha_max: int = 72, rgb_max: int = 55) -> Image.Image:
    """Drop semi-transparent dark halo pixels left after background removal."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if 0 < a <= alpha_max and max(r, g, b) <= rgb_max:
                px[x, y] = (0, 0, 0, 0)
    return img


def content_bbox(img: Image.Image, min_alpha: int = 24) -> tuple[int, int, int, int]:
    px = img.load()
    w, h = img.size
    bbox = None
    for y in range(h):
        for x in range(w):
            if px[x, y][3] >= min_alpha:
                if bbox is None:
                    bbox = [x, y, x, y]
                else:
                    bbox[0] = min(bbox[0], x)
                    bbox[1] = min(bbox[1], y)
                    bbox[2] = max(bbox[2], x)
                    bbox[3] = max(bbox[3], y)
    if bbox is None:
        return (0, 0, w, h)
    return tuple(bbox)


def make_navbar_logo() -> None:
    img = Image.open(NAVBAR_SRC)
    img = white_to_alpha(img)
    img = trim_transparent(img)
    target_h = 104
    scale = target_h / img.height
    target_w = max(1, int(img.width * scale))
    img = img.resize((target_w, target_h), Image.LANCZOS)
    out = SITE_ASSETS / "bloz-logo-nav.png"
    img.save(out, optimize=True)
    print(f"navbar logo: {out} ({target_w}x{target_h})")


def make_favicon() -> None:
    src = Image.open(ICON_SRC).convert("RGBA")
    sizes = (
        (16, "favicon-16.png"),
        (32, "favicon-32.png"),
        (64, "favicon.png"),
        (180, "apple-touch-icon.png"),
        (192, "android-chrome-192.png"),
        (512, "android-chrome-512.png"),
    )
    images = []
    for size, name in sizes:
        img = src.resize((size, size), Image.LANCZOS)
        out = SITE_ASSETS / name
        img.save(out, optimize=True)
        images.append((size, img))
        print(f"favicon: {out} ({size}x{size})")

    ico_sizes = [16, 32, 48, 64, 128, 256]
    ico_images = [src.resize((s, s), Image.LANCZOS) for s in ico_sizes]
    root_ico = SITE_ROOT / "favicon.ico"
    ico_images[0].save(
        root_ico,
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=ico_images[1:],
    )
    print(f"root favicon.ico: {root_ico}")


def make_webmanifest() -> None:
    import json

    manifest = {
        "name": "Block Zero",
        "short_name": "BLOZ",
        "icons": [
            {"src": f"android-chrome-192.png{FAVICON_Q}", "sizes": "192x192", "type": "image/png"},
            {"src": f"android-chrome-512.png{FAVICON_Q}", "sizes": "512x512", "type": "image/png"},
        ],
        "theme_color": "#05070A",
        "background_color": "#05070A",
        "display": "standalone",
    }
    out = SITE_ASSETS / "site.webmanifest"
    out.write_text(json.dumps(manifest, indent=4) + "\n", encoding="utf-8")
    print(f"webmanifest: {out}")


def make_bscscan_svg() -> None:
    text = BSCSCAN_SRC.read_text(encoding="utf-8")
    text = text.replace('width="512" height="512"', 'width="32" height="32"', 1)
    for out in (SITE_ASSETS / "bloz-token-icon.svg", OPS_ASSETS / "bloz-token-icon.svg"):
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print(f"bscscan svg: {out} ({out.stat().st_size} bytes)")


def main() -> None:
    for p in (NAVBAR_SRC, ICON_SRC, BSCSCAN_SRC):
        if not p.exists():
            raise SystemExit(f"missing source file: {p}")
    SITE_ASSETS.mkdir(parents=True, exist_ok=True)
    make_navbar_logo()
    make_favicon()
    make_webmanifest()
    make_bscscan_svg()
    favicon_svg = SITE_ASSETS / "favicon.svg"
    if favicon_svg.exists():
        favicon_svg.unlink()
        print("removed stale favicon.svg (PNG favicon from Downloads is canonical)")
    print("done")


if __name__ == "__main__":
    main()
