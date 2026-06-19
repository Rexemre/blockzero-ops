#!/usr/bin/env bash
# Block Zero one-line miner installer (Linux / macOS) using patched XMRig.
#
# Basic:
#   curl -fsSL https://pool.bloz.org/install.sh | ADDRESS=bz1qYOURADDRESS bash
#
# Linux (sudo = huge pages = full speed):
#   curl -fsSL https://pool.bloz.org/install.sh | sudo ADDRESS=bz1qYOURADDRESS bash
#
# With options (threads, rig name):
#   curl -fsSL https://pool.bloz.org/install.sh | sudo ADDRESS=bz1qYOURADDRESS THREADS=8 WORKER=rig2 bash
#
# Env:
#   ADDRESS=bz1...   your payout address (required; or pass as $1)
#   WORKER=name      rig name on the dashboard (default: hostname)
#   POOL=host:port   pool stratum (default: pool.bloz.org:3334)
#   THREADS=N        CPU threads — omit for auto (recommended)
#   REPO=owner/repo  GitHub repo for releases (default: Rexemre/blockzero-ops)
set -eu

REPO="${REPO:-Rexemre/blockzero-ops}"
POOL="${POOL:-pool.bloz.org:3334}"
ADDRESS="${ADDRESS:-${1:-}}"
WORKER="${WORKER:-$(hostname -s 2>/dev/null || echo rig)}"
DIR="${DIR:-$HOME/.blockzero/xmrig}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "$ADDRESS" ] || die "Set your address: ADDRESS=bz1... (get one at the wallet)"
case "$ADDRESS" in
    bz1*) ;;
    *) die "Address must start with bz1 (got: $ADDRESS)" ;;
esac

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
    Linux)  [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ] || die "Only x86_64 Linux prebuilt (got $ARCH)"; ASSET="bz-xmrig-linux-x64.tar.gz" ;;
    Darwin) [ "$ARCH" = "arm64" ] || die "Only Apple Silicon prebuilt (got $ARCH)"; ASSET="bz-xmrig-macos-arm64.tar.gz" ;;
    *) die "Unsupported OS: $OS" ;;
esac

# Resolve the latest xmrig-v* release tag.
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases" \
    | grep -o "\"tag_name\": *\"xmrig-v[^\"]*\"" | head -n1 | sed 's/.*"\(xmrig-v[^"]*\)"/\1/')"
[ -n "$TAG" ] || die "No xmrig-v* release found in $REPO"

URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
mkdir -p "$DIR"
printf 'Downloading %s (%s)...\n' "$ASSET" "$TAG"
curl -fsSL -o "$DIR/xmrig.tgz" "$URL"
tar -xzf "$DIR/xmrig.tgz" -C "$DIR"
chmod +x "$DIR/xmrig"
[ "$OS" = "Darwin" ] && xattr -dr com.apple.quarantine "$DIR/xmrig" 2>/dev/null || true

# --donate-level 0: no donation to XMRig devs (Block Zero's on-chain dev fund is separate).
ARGS="-a rx/blockzero -o $POOL -u $ADDRESS.$WORKER -p x --donate-level 0"
[ -n "${THREADS:-}" ] && ARGS="$ARGS -t $THREADS"

printf '\nStarting XMRig: %s.%s on %s\n' "$ADDRESS" "$WORKER" "$POOL"
if [ "$OS" = "Linux" ] && [ "$(id -u)" != "0" ]; then
    printf 'Tip: run as root (sudo) for huge pages = much higher hashrate.\n'
fi
# shellcheck disable=SC2086
exec "$DIR/xmrig" $ARGS
