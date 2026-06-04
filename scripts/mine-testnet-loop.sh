#!/bin/bash
CLI=~/blockzero-core/build/bin/bitcoin-cli
ADDR=tbz1qug7eyh8pcspr0j5tpvgq6448y459dcq358e6rv
DATADIR=/home/marlon/.bzero
MAXTRIES=500000000
while true; do
  HEIGHT=$($CLI -testnet -datadir=$DATADIR -rpcport=18211 getblockcount 2>/dev/null)
  if [ "${HEIGHT:-0}" -ge 1 ] 2>/dev/null; then
    echo "$(date): Block $HEIGHT mined!"
    $CLI -testnet -datadir=$DATADIR -rpcport=18211 getbestblockhash
    exit 0
  fi
  echo "$(date): height=$HEIGHT, starting generatetoaddress (maxtries=$MAXTRIES)..."
  RESULT=$($CLI -testnet -datadir=$DATADIR -rpcport=18211 -rpcwallet=mining generatetoaddress 1 "$ADDR" $MAXTRIES 2>&1)
  RC=$?
  echo "$(date): generatetoaddress rc=$RC result=$RESULT"
  if echo "$RESULT" | grep -qE 'blockhash|"[0-9a-f]{64}"'; then
    echo "$(date): SUCCESS!"
    exit 0
  fi
  sleep 2
done
