#!/usr/bin/env bash
# Block Zero SOLO mining (Linux / macOS) — run your OWN node and keep the whole
# 50 BLOZ for every block you find. Downloads the node, syncs to the public
# mainnet, then mines with the node's RandomX generatetoaddress.
#
#   ./mine-solo.sh                 # auto threads
#   THREADS=8 ./mine-solo.sh       # 8 RandomX threads
#   FORCE=1 ./mine-solo.sh         # re-download the node
#
# Solo finds blocks rarely unless you have a lot of hashrate. For steady payouts
# use pool mining instead: ./install-xmrig.sh  (or  ./mine-pool.sh).
set -euo pipefail

REPO="${REPO:-Rexemre/blockzero-core}"
VERSION="${VERSION:-latest}"
BIN_DIR="${BIN_DIR:-$HOME/.blockzero/bin}"
DATA_DIR="${DATA_DIR:-$HOME/.blockzero-mainnet}"
RPC_PORT=8332
SEED="217.160.46.61:8210"
GENESIS="44c1a8c852b3eda21966e1ddb6b0807e22488dffe8a270bf24bf1fa2d66c13bd"
WALLET="mining"
THREADS="${THREADS:-0}"
MAXTRIES="${MAXTRIES:-500000000}"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
    Linux)  case "$ARCH" in x86_64|amd64) ASSET="linux-x64" ;; aarch64|arm64) ASSET="linux-arm64" ;; *) die "No prebuilt node for $ARCH — build from source." ;; esac ;;
    Darwin) [ "$ARCH" = "arm64" ] || die "macOS node is Apple Silicon only (got $ARCH)."; ASSET="macos-arm64" ;;
    *) die "Unsupported OS: $OS" ;;
esac

BD="$BIN_DIR/bitcoind"
BCLI="$BIN_DIR/bitcoin-cli"
cli() { "$BCLI" -datadir="$DATA_DIR" -rpcport="$RPC_PORT" "$@"; }

# ---------- download node ----------
if [ ! -x "$BD" ] || [ "${FORCE:-0}" = "1" ]; then
    if [ "$VERSION" = "latest" ]; then api="https://api.github.com/repos/$REPO/releases/latest"; else api="https://api.github.com/repos/$REPO/releases/tags/$VERSION"; fi
    url="$(curl -fsSL "$api" | grep -o "\"browser_download_url\": *\"[^\"]*${ASSET}\.tar\.gz\"" | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')"
    [ -n "$url" ] || die "No $ASSET release tarball found in $REPO."
    say "Downloading node: $(basename "$url")"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/node.tgz" "$url"
    tar -xzf "$tmp/node.tgz" -C "$tmp"
    src="$(find "$tmp" -maxdepth 2 -type d -name bin | head -n1)"
    [ -n "$src" ] || die "bin/ not found in release tarball."
    mkdir -p "$BIN_DIR"
    cp "$src/bitcoind" "$src/bitcoin-cli" "$BIN_DIR/"
    chmod +x "$BIN_DIR/"*
    [ "$OS" = "Darwin" ] && xattr -dr com.apple.quarantine "$BIN_DIR" 2>/dev/null || true
    rm -rf "$tmp"
    say "Installed node to $BIN_DIR"
fi

# ---------- config ----------
mkdir -p "$DATA_DIR"
conf="$DATA_DIR/bitcoin.conf"
if [ ! -f "$conf" ]; then
    cat > "$conf" <<EOF
# Block Zero mainnet (solo)
server=1
txindex=1

[main]
listen=1
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=$RPC_PORT
addnode=$SEED
EOF
    say "Created $conf"
fi

# ---------- start node ----------
if ! cli getblockcount >/dev/null 2>&1; then
    say "Starting node (bitcoind, mainnet)..."
    "$BD" -datadir="$DATA_DIR" -daemon
fi
for _ in $(seq 1 60); do cli getblockcount >/dev/null 2>&1 && break; sleep 3; done
cli getblockcount >/dev/null 2>&1 || die "Node RPC did not become ready."

# ---------- safety: peers + genesis + sync ----------
say "Waiting for a peer (never solo-mine with 0 peers — it creates a fork)..."
peers=0
for _ in $(seq 1 120); do
    peers="$(cli getconnectioncount 2>/dev/null || echo 0)"
    [ "${peers:-0}" -ge 1 ] && break
    sleep 5
done
[ "${peers:-0}" -ge 1 ] || die "No peers — is the seed reachable? Do NOT mine. Check $SEED."

g="$(cli getblockhash 0 2>/dev/null || echo '')"
[ "$g" = "$GENESIS" ] || die "Genesis mismatch (wrong chain). Delete $DATA_DIR and re-sync."

while true; do
    bi="$(cli getblockchaininfo)"
    blocks="$(printf '%s' "$bi" | grep -o '"blocks": *[0-9]*' | grep -o '[0-9]*' | head -1)"
    headers="$(printf '%s' "$bi" | grep -o '"headers": *[0-9]*' | grep -o '[0-9]*' | head -1)"
    [ "$(( ${headers:-0} - ${blocks:-0} ))" -le 1 ] && break
    say "Syncing: $blocks / $headers ..."
    sleep 5
done

# ---------- wallet + address ----------
cli listwallets 2>/dev/null | grep -q "\"$WALLET\"" \
    || cli loadwallet "$WALLET" >/dev/null 2>&1 \
    || cli createwallet "$WALLET" >/dev/null
addr_file="$DATA_DIR/mining-address.txt"
if [ -f "$addr_file" ] && grep -q '^bz1' "$addr_file"; then
    addr="$(tr -d '[:space:]' < "$addr_file")"
else
    addr="$(cli -rpcwallet="$WALLET" getnewaddress)"
    printf '%s' "$addr" > "$addr_file"
fi

say ""
say "SOLO mining to: $addr"
say "Threads: $([ "${THREADS:-0}" -gt 0 ] 2>/dev/null && echo "$THREADS" || echo 'auto') · Block reward: 50 BLOZ (matures after 100 blocks)"
say "Stop: Ctrl+C (node keeps running) · shut node down with: $BCLI -datadir=$DATA_DIR stop"
say ""

gen=(-rpcclienttimeout=0 -rpcwallet="$WALLET" generatetoaddress 1 "$addr" "$MAXTRIES")
[ "${THREADS:-0}" -gt 0 ] 2>/dev/null && gen+=("$THREADS")

trap 'exit 0' INT TERM
while true; do
    h="$(cli getblockcount 2>/dev/null || echo '?')"
    printf '%s  mining h=%s ...\n' "$(date +%H:%M:%S)" "$h"
    res="$(cli "${gen[@]}" 2>&1 || true)"
    if printf '%s' "$res" | grep -qiE '[0-9a-f]{64}'; then
        nh="$(cli getblockcount 2>/dev/null || echo '?')"
        printf '%s  *** BLOCK %s FOUND — 50 BLOZ to %s ***\n' "$(date +%H:%M:%S)" "$nh" "$addr"
    fi
    sleep 2
done
