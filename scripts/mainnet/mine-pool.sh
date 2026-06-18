#!/usr/bin/env bash
# BLOZ pool miner (Linux / macOS) — mines on pool.bloz.org
#
# Usage:
#   ./mine-pool.sh                      # auto: address from BlockZero wallet
#   ./mine-pool.sh bz1YOURADDRESS      # payout address only — rig name added automatically
#   THREADS=8 ./mine-pool.sh            # custom thread count
#   WORKER=rig2 ./mine-pool.sh bz1...   # optional custom rig name (default: hostname)
#   LIGHT=1 ./mine-pool.sh bz1...       # force light mode (use on low-RAM machines / 0 H/s)
#   USE_PYTHON=1 ./mine-pool.sh bz1...  # force Python miner (works if native stays at 0 H/s)
#
# First time? Create a wallet address with a local node:
#   bitcoind -datadir=~/.blockzero-mainnet -daemon
#   bitcoin-cli -datadir=~/.blockzero-mainnet createwallet mining
#   bitcoin-cli -datadir=~/.blockzero-mainnet -rpcwallet=mining getnewaddress > ~/.blockzero-mainnet/mining-address.txt
set -euo pipefail

POOL_URL="${POOL_URL:-wss://pool.bloz.org/stratum}"
REPO="${REPO:-Rexemre/blockzero-ops}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.blockzero/pool}"
DATA_DIR="${DATA_DIR:-$HOME/.blockzero-mainnet}"
WORKER="${WORKER:-$(hostname -s 2>/dev/null || echo rig1)}"
THREADS="${THREADS:-0}"

ADDRESS="${1:-}"
BIN="$INSTALL_DIR/bin/bz-pool-miner"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_PYTHON_MINER="$SCRIPT_DIR/../../pool/python-miner"

install_python_miner_source() {
    local py_dir="$INSTALL_DIR/python-miner"
    if [ -f "$py_dir/miner/blockzero-miner.py" ] && [ -f "$py_dir/requirements.txt" ]; then
        return 0
    fi
    say "Setting up Python pool miner..."
    mkdir -p "$py_dir"
    if [ -f "$BUNDLED_PYTHON_MINER/miner/blockzero-miner.py" ]; then
        cp -a "$BUNDLED_PYTHON_MINER/." "$py_dir/"
        say "Installed Python miner from blockzero-ops bundle."
        return 0
    fi
    say "Downloading Python miner from blockzero-ops (public repo)..."
    local tmp; tmp="$(mktemp -d)"
    if curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" \
        | tar -xz -C "$tmp" --strip-components=1 \
        && [ -d "$tmp/pool/python-miner" ]; then
        cp -a "$tmp/pool/python-miner/." "$py_dir/"
        rm -rf "$tmp"
        say "Installed Python miner from GitHub."
        return 0
    fi
    rm -rf "$tmp"
    die "Python miner files missing. Run: git pull  (in blockzero-ops)  then retry."
}

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
    local venv="$INSTALL_DIR/python-venv"
    install_python_miner_source
    if [ ! -f "$py_dir/requirements.txt" ]; then
        die "Python miner requirements.txt missing after install."
    fi
    if [ -x "$venv/bin/python3" ] && "$venv/bin/python3" -c "import randomx, websocket" 2>/dev/null; then
        return 0
    fi
    if python3 -c "import randomx, websocket" 2>/dev/null; then
        return 0
    fi

    say "Installing Python deps (randomx, websocket-client)..."
    if ! python3 -c "import venv" 2>/dev/null; then
        if command -v apt-get >/dev/null 2>&1; then
            say "Installing python3-venv (Debian/Ubuntu, one-time)..."
            apt-get install -y -qq python3-venv python3-full 2>/dev/null \
                || apt-get install -y python3-venv python3-full
        fi
    fi
    if python3 -m venv "$venv" 2>/dev/null; then
        "$venv/bin/python3" -m pip install -q --upgrade pip
        if "$venv/bin/python3" -m pip install -q -r "$py_dir/requirements.txt"; then
            say "Python miner ready ($venv)."
            return 0
        fi
    fi
    # Last resort: PEP 668 "externally managed" systems (Debian 12+, Ubuntu 23.04+).
    if python3 -m pip install -q --break-system-packages -r "$py_dir/requirements.txt" 2>/dev/null \
        || python3 -m pip install -q -r "$py_dir/requirements.txt" 2>/dev/null; then
        return 0
    fi
    die "Python deps failed. Run: apt install python3-venv python3-full build-essential && FORCE=1 ./mine-pool.sh $ADDRESS"
}

python_miner_bin() {
    local venv="$INSTALL_DIR/python-venv"
    if [ -x "$venv/bin/python3" ] && "$venv/bin/python3" -c "import randomx, websocket" 2>/dev/null; then
        echo "$venv/bin/python3"
    else
        echo python3
    fi
}

run_python_miner() {
    ensure_python_miner
    "$(python_miner_bin)" "$INSTALL_DIR/python-miner/miner/blockzero-miner.py" \
        -o "$POOL_URL" -u "$FULL_WORKER" -t "$THREADS"
}

# Run the native miner but watch its output. Switch to the Python miner when:
#   - no job arrives within ~90s ("Waiting for work" forever), or
#   - a job arrived but hashrate stays 0 for ~90s (broken RandomX path).
# Returns 99 to signal the caller to use the Python miner.
run_native_with_watchdog() {
    local logf; logf="$(mktemp)"
    "$BIN" -o "$POOL_URL" -u "$FULL_WORKER" -Threads "$THREADS" $LIGHT_FLAG > >(tee "$logf") 2>&1 &
    local pid=$!
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        if grep -qE 'New job:|Share found|Hashrate: [1-9][0-9]* H/s' "$logf"; then
            local rc=0; wait "$pid" || rc=$?; rm -f "$logf"; return "$rc"
        fi
        i=$((i + 1))
        if [ "$i" -ge 90 ]; then
            say ""
            if grep -qE 'Connected to pool|Subscribed and authorized' "$logf"; then
                say "Native miner connected but received no work within ~90s - switching to Python miner."
            else
                say "Native miner stuck at 0 H/s for ~90s - switching to Python miner."
            fi
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            rm -f "$logf"
            return 99
        fi
        sleep 1
    done
    local rc=0; wait "$pid" 2>/dev/null || rc=$?; rm -f "$logf"; return "$rc"
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

# ---------- fast vs light mode ----------
# Fast mode builds a ~2 GB RandomX dataset. On a small VPS that allocation/init
# thrashes swap and freezes mining at 0 H/s (the miner stays stuck on the
# "light" label and never hashes). Use real light mode when RAM is short.
LIGHT_FLAG=""
if [ "${LIGHT:-0}" = "1" ]; then
    LIGHT_FLAG="--light"
    say "Light mode forced (LIGHT=1)."
else
    if [ "$OS" = "Darwin" ]; then
        AVAIL_MIB="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 ))"
    else
        AVAIL_MIB="$(awk '/MemAvailable/ {print int($2/1024); exit}' /proc/meminfo 2>/dev/null || echo 0)"
    fi
    if [ "${AVAIL_MIB:-0}" -gt 0 ] && [ "$AVAIL_MIB" -lt 3072 ]; then
        LIGHT_FLAG="--light"
        say "Only ${AVAIL_MIB} MiB RAM available - using light mode (fast mode needs ~3 GB)."
    fi
fi

say ""
say "Pool:    $POOL_URL"
say "Worker:  $FULL_WORKER"
say "Threads: $THREADS"
say "Mode:    $([ -n "$LIGHT_FLAG" ] && echo light || echo 'fast (RandomX dataset)')"
say "Dashboard: https://pool.bloz.org  (enter your bz1 address under 'Your stats')"
say "Press Ctrl+C to stop."
say ""

# Auto-restart on crash; clean exit (Ctrl+C) stops the loop.
trap 'exit 0' INT TERM
while true; do
    if [ "$USE_PYTHON" = "1" ]; then
        run_python_miner && break
        say "Python miner exited - restarting in 10s (Ctrl+C to stop)..."
        sleep 10
        continue
    else
        rc=0
        run_native_with_watchdog && rc=0 || rc=$?
        if [ "$rc" -eq 99 ]; then
            USE_PYTHON=1
            continue
        fi
        if [ "$rc" -ne 0 ]; then
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
done
