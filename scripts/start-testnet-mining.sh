#!/bin/bash
set -e
cd ~/blockzero-core
CLI="./build/bin/bitcoin-cli"
BD="./build/bin/bitcoind"

# --- regtest sanity check ---
DD=/tmp/bz-mine-test
rm -rf "$DD"
mkdir -p "$DD"
$BD -regtest -datadir="$DD" -listen=0 -rpcport=29999 -daemon
sleep 4
$CLI -regtest -datadir="$DD" -rpcport=29999 createwallet t 2>/dev/null || true
ADDR=$($CLI -regtest -datadir="$DD" -rpcport=29999 -rpcwallet=t getnewaddress)
echo "regtest addr: $ADDR"
$CLI -regtest -datadir="$DD" -rpcport=29999 -rpcwallet=t -generate 1 50000000
echo "regtest blocks: $($CLI -regtest -datadir="$DD" -rpcport=29999 getblockcount)"
$CLI -regtest -datadir="$DD" -rpcport=29999 stop
sleep 2

# --- testnet background mining ---
pkill -f 'generatetoaddress.*tbz1' 2>/dev/null || true
sleep 1
MADDR="tbz1qug7eyh8pcspr0j5tpvgq6448y459dcq358e6rv"
nohup $CLI -testnet -datadir=/home/marlon/.bzero -rpcport=18211 -rpcwallet=mining \
  generatetoaddress 1 "$MADDR" 500000000 > /tmp/bz-mine.log 2>&1 &
echo "testnet mining pid: $!"
echo "log: /tmp/bz-mine.log"
