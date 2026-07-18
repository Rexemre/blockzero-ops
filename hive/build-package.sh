#!/usr/bin/env bash
# Build Hive OS custom miner archive: bzxmrig-VERSION.tar.gz
# Bundles scripts + patched xmrig binary from the latest GitHub release.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$ROOT/bzxmrig"
VERSION="${1:-6.26.0}"
TAG="${2:-xmrig-v6.26.0}"
REPO="${BZXMRIG_REPO:-Rexemre/blockzero-ops}"
OUT="$ROOT/bzxmrig-${VERSION}.tar.gz"
STAGE=$(mktemp -d)

trap 'rm -rf "$STAGE"' EXIT

echo "Staging bzxmrig $VERSION ..."
cp -r "$PKG_DIR" "$STAGE/bzxmrig"
chmod +x "$STAGE/bzxmrig"/*.sh

echo "Downloading binary ($TAG) ..."
tmp=$(mktemp -d)
wget -q -O "$tmp/xmrig.tgz" \
  "https://github.com/${REPO}/releases/download/${TAG}/bz-xmrig-linux-x64.tar.gz"
tar -xzf "$tmp/xmrig.tgz" -C "$tmp"
cp "$tmp/xmrig" "$STAGE/bzxmrig/xmrig"
chmod +x "$STAGE/bzxmrig/xmrig"

sed -i "s/^CUSTOM_VERSION=.*/CUSTOM_VERSION=${VERSION}/" "$STAGE/bzxmrig/h-manifest.conf"

echo "Creating $OUT ..."
tar -czf "$OUT" -C "$STAGE" bzxmrig
ls -lh "$OUT"
echo "Install on Hive rig:"
echo "  custom-get file://$OUT -f"
echo "  # or after GitHub release:"
echo "  custom-get https://github.com/${REPO}/releases/download/hive-bzxmrig-v${VERSION}/bzxmrig-${VERSION}.tar.gz -f"
