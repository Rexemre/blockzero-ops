#!/usr/bin/env bash
# Block Zero testnet miner (Linux / macOS)
# Usage:
#   ./mine-testnet.sh              # start node + mine
#   ./mine-testnet.sh status
#   ./mine-testnet.sh stop
#
# Env: BZERO_BINDIR, BZERO_DATADIR, BZERO_WALLET, BZERO_MAXTRIES

set -euo pipefail

BINDIR="${BZERO_BINDIR:-}"
DATADIR="${BZERO_DATADIR:-${HOME}/.blockzero/testnet3}"
WALLET="${BZERO_WALLET:-mining}"
MAXTRIES="${BZERO_MAXTRIES:-500000000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_bin() {
  local name="$1"
  if [[ -n "$BINDIR" && -x "${BINDIR}/${name}" ]]; then
    echo "${BINDIR}/${name}"
    return
  fi
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi
  echo "Cannot find ${name}. Set BZERO_BINDIR or install Block Zero binaries." >&2
  echo "See https://github.com/Rexemre/blockzero-docs/blob/main/quickstart-mining.md" >&2
  exit 1
}

cli() {
  "$(find_bin bitcoin-cli)" -testnet -datadir="$DATADIR" -rpcport=18211 "$@"
}

stop_node() {
  cli stop >/dev/null 2>&1 || true
  echo "bitcoind stopped."
}

if [[ "${1:-}" == "stop" ]]; then
  stop_node
  exit 0
fi

mkdir -p "$DATADIR"
if [[ ! -f "${DATADIR}/bitcoin.conf" ]]; then
  cp "${SCRIPT_DIR}/bitcoin.conf.example" "${DATADIR}/bitcoin.conf"
  echo "Created ${DATADIR}/bitcoin.conf"
fi

DAEMON="$(find_bin bitcoind)"
if ! pgrep -x bitcoind >/dev/null 2>&1; then
  echo "Starting bitcoind (testnet)..."
  "$DAEMON" -testnet -datadir="$DATADIR" -daemon
  sleep 5
fi

cli loadwallet "$WALLET" >/dev/null 2>&1 || true
cli createwallet "$WALLET" >/dev/null 2>&1 || true
ADDR="$(cli -rpcwallet="$WALLET" getnewaddress)"
HEIGHT="$(cli getblockcount)"

if [[ "${1:-}" == "status" ]]; then
  echo "Height: $HEIGHT"
  echo "Mining address: $ADDR"
  cli -rpcwallet="$WALLET" getbalances
  exit 0
fi

echo "Chain height: $HEIGHT"
echo "Mining to: $ADDR"
echo "Ctrl+C stops mining; bitcoind keeps running. Use: $0 stop"
echo ""

while true; do
  HEIGHT="$(cli getblockcount)"
  echo "$(date +%H:%M:%S) height=${HEIGHT} mining..."
  RESULT="$(cli -rpcwallet="$WALLET" generatetoaddress 1 "$ADDR" "$MAXTRIES" 2>&1)" || true
  echo "$RESULT"
  if echo "$RESULT" | grep -qE '[0-9a-f]{64}'; then
    cli -rpcwallet="$WALLET" getbalances
  fi
  sleep 2
done
