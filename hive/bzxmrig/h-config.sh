#!/usr/bin/env bash
# Generates XMRig config.json from Hive flight sheet (CUSTOM_* variables).

[[ -z $CUSTOM_URL ]] && echo -e "${YELLOW}CUSTOM_URL is empty${NOCOLOR}" && return 1

# Wallet.worker: flight sheet "Wallet and worker template" or %WAL%.%WORKER_NAME%
if [[ -n $CUSTOM_TEMPLATE ]]; then
  user="$CUSTOM_TEMPLATE"
elif [[ -n $WAL ]]; then
  user="${WAL}.${WORKER_NAME:-$HOSTNAME}"
else
  echo -e "${YELLOW}Wallet address missing (set CUSTOM_TEMPLATE or WAL)${NOCOLOR}" && return 1
fi

pool_url="$CUSTOM_URL"
pool_url="${pool_url#stratum+tcp://}"
pool_url="${pool_url#stratum+ssl://}"
pool_url="${pool_url#tcp://}"
pool_url="${pool_url#ssl://}"

algo="${CUSTOM_ALGO:-rx/blockzero}"
pass="${CUSTOM_PASS:-x}"
api_port="${MINER_API_PORT:-40600}"

conf=$(jq -n \
  --arg url "$pool_url" \
  --arg user "$user" \
  --arg pass "$pass" \
  --arg algo "$algo" \
  --argjson port "$api_port" \
  '{
    autosave: false,
    "donate-level": 0,
    cpu: { enabled: true, "huge-pages": true },
    randomx: { "1gb-pages": false, wrmsr: true },
    api: { "port": $port, "id": null, "worker-id": null },
    http: { enabled: true, host: "127.0.0.1", "port": $port },
    pools: [{
      algo: $algo,
      coin: null,
      url: $url,
      user: $user,
      pass: $pass,
      tls: false,
      "keepalive": true,
      nicehash: false
    }]
  }')

if [[ -n $CUSTOM_USER_CONFIG ]]; then
  while read -r line; do
    [[ -z $line ]] && continue
    conf=$(jq -s '.[0] * .[1]' <<< "$conf {$line}")
  done <<< "$CUSTOM_USER_CONFIG"
fi

echo "$conf" | jq . > "$CUSTOM_CONFIG_FILENAME"
