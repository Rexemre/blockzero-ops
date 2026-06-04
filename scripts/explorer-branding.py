#!/usr/bin/env python3
"""Rebrand btc-rpc-explorer for Block Zero (testnet or mainnet).

btc-rpc-explorer ships only Bitcoin coin configs and hardcodes "Bitcoin
Explorer" in a few view templates. This patches the in-place coin config and
views for the chosen network. Re-run after every `git pull` of the explorer,
then restart the matching systemd unit.

Usage:
  python3 explorer-branding.py testnet   # TBLOZ, tbz HRP, port 3002 service
  python3 explorer-branding.py mainnet   # BLOZ, bz HRP, port 3003 service
"""
from __future__ import annotations

import argparse
import sys

BASE_BY_NETWORK = {
    "testnet": "/opt/btc-rpc-explorer",
    "mainnet": "/opt/btc-rpc-explorer-mainnet",
}

NETWORKS = {
    "testnet": {
        "service": "blockzero-explorer",
        "coin_name": "Block Zero",
        "ticker": "TBLOZ",
        "ticker_lower": "tbloz",
        "site_title": "Block Zero Testnet Explorer",
        "explorer_label": "Block Zero Testnet Explorer",
        "tagline": "A second chance at Genesis. CPU-mineable. Fair launch.",
        "subtitle": "Open-source explorer for the Block Zero testnet, powered by your own node.",
        "testnet_label": "Block Zero Testnet Explorer",
    },
    "mainnet": {
        "service": "blockzero-mainnet-explorer",
        "coin_name": "Block Zero",
        "ticker": "BLOZ",
        "ticker_lower": "bloz",
        "site_title": "Block Zero Explorer",
        "explorer_label": "Block Zero Explorer",
        "tagline": "A second chance at Genesis. CPU-mineable. Fair launch.",
        "subtitle": "Open-source explorer for Block Zero mainnet, powered by your own node.",
        "testnet_label": "Block Zero Explorer",
    },
}


def build_patches(base: str, cfg: dict) -> dict[str, list[tuple[str, str, int]]]:
    ticker = cfg["ticker"]
    ticker_lower = cfg["ticker_lower"]
    title = cfg["site_title"]
    label = cfg["explorer_label"]
    tagline = cfg["tagline"]
    subtitle = cfg["subtitle"]
    test_label = cfg["testnet_label"]

    return {
        f"{base}/app/coins/btc.js": [
            ('name:"Bitcoin",', f'name:"{cfg["coin_name"]}",', 1),
            ('ticker:"BTC",', f'ticker:"{ticker}",', 1),
            ('name:"BTC",', f'name:"{ticker}",', 1),
            ('values:["", "btc", "BTC"]', f'values:["", "{ticker_lower}", "{ticker}"]', 1),
            ('"BTC":currencyUnits[0]', f'"{ticker}":currencyUnits[0]', 1),
            ('"test":"Testnet Explorer",', f'"test":"{test_label}",', 1),
        ],
        f"{base}/views/index.pug": [
            ("title Bitcoin Explorer", f"title {title}", 1),
            ("h5 Bitcoin Explorer", f"h5 {title}", 1),
            ("Made for Bitcoiners by Bitcoiners. Enjoy!", tagline, 1),
        ],
        f"{base}/views/layout.pug": [
            ("span.fw-light Bitcoin Explorer", f"span.fw-light {label}", 1),
            ("BitcoinExplorer.org - Open-Source Bitcoin Explorer", label, 1),
            ('content="BTC Explorer"', f'content="{label}"', 0),
            (
                ".btn-primary.btn-sm #{item}",
                f'.btn-primary.btn-sm #{{item == "BTC" ? "{ticker}" : item}}',
                0,
            ),
            (
                "value=${item.toLowerCase()}`) #{item}",
                f'value=${{item.toLowerCase()}}`) #{{item == "BTC" ? "{ticker}" : item}}',
                0,
            ),
            ("title Explorer", f"title {title}", 1),
            (
                "Open-source, easy-to-use, educational Bitcoin explorer whose only dependency is your Bitcoin Core node.",
                subtitle,
                0,
            ),
            ('"BitcoinExplorer.org"', f'"{label}"', 0),
        ],
        f"{base}/views/layout-iframe.pug": [
            ("BitcoinExplorer.org - Open-Source Bitcoin Explorer", label, 1),
            ('content="BTC Explorer"', f'content="{label}"', 0),
        ],
        f"{base}/views/includes/shared-mixins.pug": [
            (".simpleVal} BTC`", ".simpleVal} " + ticker + "`", 0),
        ],
        f"{base}/views/snippets/utxo-set.pug": [
            (
                "The sum of all spendable BTC units across the entire blockchain",
                f"The sum of all spendable {ticker} units across the entire blockchain",
                1,
            ),
        ],
    }


def currency_patches(base: str, cfg: dict) -> dict[str, list[tuple[str, str, int]]]:
    ticker = cfg["ticker"]
    ticker_lower = cfg["ticker_lower"]
    return {
        f"{base}/app/currencies.js": [
            ('name:"BTC",', f'name:"{ticker}",', 1),
            (
                "global.currencySymbols = {",
                f'global.currencyTypes["{ticker_lower}"] = global.currencyTypes["btc"];\n\nglobal.currencySymbols = {{',
                1,
            ),
            ('"btc": "\u20bf",', f'"btc": "\u20bf",\n\t"{ticker_lower}": "\u20bf",', 1),
        ],
    }


def patch_file(path: str, reps: list[tuple[str, str, int]]) -> None:
    try:
        with open(path, encoding="utf-8") as f:
            s = f.read()
    except FileNotFoundError:
        print(f"  SKIP (missing): {path}")
        return
    changed = False
    for old, new, n in reps:
        if old not in s:
            if new in s:
                print(f"  already applied in {path}: {new!r}")
            else:
                print(f"  WARN not found in {path}: {old!r}")
            continue
        count = s.count(old)
        if n <= 0:
            s = s.replace(old, new)
            print(f"  patched {path} ({count}x): {old!r} -> {new!r}")
        else:
            s = s.replace(old, new, n)
            print(f"  patched {path}: {old!r} -> {new!r}")
        changed = True
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write(s)


def main() -> int:
    parser = argparse.ArgumentParser(description="Rebrand btc-rpc-explorer for Block Zero")
    parser.add_argument(
        "network",
        choices=sorted(NETWORKS),
        help="testnet (TBLOZ / texplorer.bloz.org) or mainnet (BLOZ / explorer.bloz.org)",
    )
    args = parser.parse_args()
    cfg = NETWORKS[args.network]
    base = BASE_BY_NETWORK[args.network]

    patches = build_patches(base, cfg)
    patches.update(currency_patches(base, cfg))

    print(f"Branding for {args.network} ({cfg['ticker']}) in {base}...")
    for path, reps in patches.items():
        patch_file(path, reps)
    print(f"done; restart with: systemctl restart {cfg['service']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
