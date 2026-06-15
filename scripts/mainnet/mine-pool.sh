#!/usr/bin/env bash
# BLOZ pool miner (Linux / macOS) — mines on pool.bloz.org
#
# Usage:
#   ./mine-pool.sh                      # auto: address from BlockZero wallet
#   ./mine-pool.sh bz1YOURADDRESS      # payout address only — rig name added automatically
#   THREADS=8 ./mine-pool.sh            # custom thread count
#   WORKER=rig2 ./mine-pool.sh bz1...   # optional custom rig name (default: hostname)
#   USE_PYTHON=1 ./mine-pool.sh bz1...  # force Python miner (works if native stays at 0 H/s)
#
# First time? Create a wallet address with a local node:
#   bitcoind -datadir=~/.blockzero-mainnet -daemon
#   bitcoin-cli -datadir=~/.blockzero-mainnet createwallet mining
#   bitcoin-cli -datadir=~/.blockzero-mainnet -rpcwallet=mining getnewaddress > ~/.blockzero-mainnet/mining-address.txt
set -euo pipefail

POOL_URL="${POOL_URL:-wss://pool.bloz.org/stratum}"
POOL_REPO="${POOL_REPO:-Rexemre/blockzero-pool}"
REPO="${REPO:-Rexemre/blockzero-ops}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.blockzero/pool}"
DATA_DIR="${DATA_DIR:-$HOME/.blockzero-mainnet}"
WORKER="${WORKER:-$(hostname -s 2>/dev/null || echo rig1)}"
THREADS="${THREADS:-0}"

ADDRESS="${1:-}"
BIN="$INSTALL_DIR/bin/bz-pool-miner"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- payout address ----------
if [ -z "$ADDRESS" ] && [ -f "$DATA_DIR/mining-address.txt" ]; then
    ADDRESS="$(tr -d '[:space:]' < "$DATA_DIR/mining-address.txt")"
    say "Using BlockZero wallet address from $DATA_DIR/mining-address.txt"
fi

if [ -z "$ADDRESS" ]; then
    say ""
    say "No payout address found."
    say "Either pass one:   ./mine-pool.sh bz1YOURADDRESS"
    say "Or create a wallet first (see header of this script),"
    say "then re-run ./mine-pool.sh"
    exit 1
fi

case "$ADDRESS" in
    bz1*) ;;
    *) die "Payout address must start with bz1 (got: $ADDRESS)" ;;
esac

# bz1ADDRESS.rigname → split (Stratum format is not the script argument)
if [[ "$ADDRESS" == bz1*.* ]]; then
    parsed_rig="${ADDRESS#*.}"
    ADDRESS="${ADDRESS%%.*}"
    say "Note: pass only your bz1 address — the script adds the rig name."
    say "      Using rig name \"$parsed_rig\" from your argument (override with WORKER=…)."
    WORKER="$parsed_rig"
fi

# ---------- platform ----------
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Linux)
        case "$ARCH" in
            x86_64|amd64) ASSET="bz-pool-miner-linux-x64.tar.gz" ;;
            aarch64|arm64) ASSET="bz-pool-miner-linux-arm64.tar.gz" ;;
            *) die "No prebuilt Linux binary for $ARCH. Build from source: pool/native in $REPO" ;;
        esac
        ;;
    Darwin)
        [ "$ARCH" = "arm64" ] || die "Prebuilt macOS binary is Apple Silicon only (got $ARCH). Build from source: pool/native in $REPO"
        ASSET="bz-pool-miner-macos-arm64.tar.gz"
        ;;
    *)
        die "Unsupported OS: $OS"
        ;;
esac

# ---------- install / update miner ----------
download_miner() {
    say "Looking up latest pool miner release..."
    local api="https://api.github.com/repos/$REPO/releases"
    local url
    url="$(curl -fsSL "$api" \
        | grep -o "\"browser_download_url\": *\"[^\"]*$ASSET\"" \
        | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')"
    [ -n "$url" ] || die "No $ASSET found in $REPO releases (pool-miner-v* tag). Try again later or build from source."

    say "Downloading $ASSET ..."
    mkdir -p "$INSTALL_DIR/bin"
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/$ASSET" "$url"
    tar -xzf "$tmp/$ASSET" -C "$INSTALL_DIR/bin"
    chmod +x "$BIN"
    rm -rf "$tmp"
    say "Installed: $BIN"
}

if [ ! -x "$BIN" ] || [ "${FORCE:-0}" = "1" ]; then
    download_miner
fi

needs_python_miner() {
    local err
    err="$("$BIN" 2>&1 || true)"
    echo "$err" | grep -qE 'GLIBC_|GLIBCXX_'
}

ensure_python_miner() {
    local py_dir="$INSTALL_DIR/python-miner"
    if [ ! -f "$py_dir/miner/blockzero-miner.py" ]; then
        say "Setting up Python pool miner (compatible with older Linux)..."
        mkdir -p "$py_dir"
        curl -fsSL "https://codeload.github.com/$POOL_REPO/tar.gz/refs/heads/main" \
            | tar -xz -C "$py_dir" --strip-components=1
    fi
    if ! python3 -c "import randomx, websocket" 2>/dev/null; then
        say "Installing Python deps (randomx, websocket-client)..."
        python3 -m pip install --user -q -r "$py_dir/requirements.txt" \
            || python3 -m pip install -q -r "$py_dir/requirements.txt"
    fi
}

run_python_miner() {
    ensure_python_miner
    python3 "$INSTALL_DIR/python-miner/miner/blockzero-miner.py" \
        -o "$POOL_URL" -u "$FULL_WORKER" -t "$THREADS"
}

USE_PYTHON=0
if [ "${USE_PYTHON:-0}" = "1" ]; then
    say "Using Python pool miner (USE_PYTHON=1)."
    USE_PYTHON=1
elif needs_python_miner; then
    say ""
    say "Prebuilt bz-pool-miner needs a newer system libc (built for recent Ubuntu)."
    say "Using Python miner instead — same pool, same payouts."
    USE_PYTHON=1
fi

# ---------- threads ----------
if [ "$THREADS" -le 0 ] 2>/dev/null; then
    if [ "$OS" = "Darwin" ]; then
        CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    else
        CORES="$(nproc 2>/dev/null || echo 4)"
    fi
    if [ "$CORES" -gt 4 ]; then THREADS=$((CORES - 1)); else THREADS="$CORES"; fi
fi

FULL_WORKER="$ADDRESS.$WORKER"

say ""
say "Pool:    $POOL_URL"
say "Worker:  $FULL_WORKER"
say "Threads: $THREADS"
say "Dashboard: https://pool.bloz.org  (enter your bz1 address under 'Your stats')"
say "Press Ctrl+C to stop."
say ""

# Auto-restart on crash; clean exit (Ctrl+C) stops the loop.
trap 'exit 0' INT TERM
while true; do
    if [ "$USE_PYTHON" = "1" ]; then
        run_python_miner && break
    else
        if ! "$BIN" -o "$POOL_URL" -u "$FULL_WORKER" -Threads "$THREADS"; then
            if needs_python_miner; then
                say "Switching to Python miner (GLIBC/GLIBCXX too old for prebuilt binary)..."
                USE_PYTHON=1
                continue
            fi
            say "Miner exited unexpectedly - restarting in 10s (Ctrl+C to stop)..."
            sleep 10
            continue
        fi
        break
    fi
    say "Miner exited unexpectedly - restarting in 10s (Ctrl+C to stop)..."
    sleep 10
done
