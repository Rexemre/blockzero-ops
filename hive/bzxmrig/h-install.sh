#!/usr/bin/env bash
# Fallback: download patched XMRig if the binary was not bundled in the package.

set -e
cd "$(dirname "$0")"

REPO="${BZXMRIG_REPO:-Rexemre/blockzero-ops}"
TAG="${BZXMRIG_XMRIG_TAG:-xmrig-v6.26.0}"
URL="https://github.com/${REPO}/releases/download/${TAG}/bz-xmrig-linux-x64.tar.gz"

echo -e "${CYAN}Downloading Block Zero XMRig (${TAG})...${NOCOLOR}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

wget -q -O "$tmp/xmrig.tgz" "$URL"
tar -xzf "$tmp/xmrig.tgz" -C "$tmp"
cp "$tmp/xmrig" ./xmrig
chmod +x ./xmrig
./xmrig --version
