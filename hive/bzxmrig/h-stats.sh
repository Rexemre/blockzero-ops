#!/usr/bin/env bash

get_cpu_temps () {
  local t_core
  t_core=$(cpu-temp)
  local i=0
  local l_num_cores=$1
  local l_temp=
  for (( i=0; i < ${l_num_cores}; i++ )); do
    l_temp+="$t_core "
  done
  echo "${l_temp[@]}" | tr " " "\n" | jq -cs '.'
}

get_cpu_fans () {
  local i=0
  local l_num_cores=$1
  local l_fan=
  for (( i=0; i < ${l_num_cores}; i++ )); do
    l_fan+="0 "
  done
  echo "${l_fan[@]}" | tr " " "\n" | jq -cs '.'
}

get_bus_numbers () {
  local i=0
  local l_num_cores=$1
  local l_numbers=
  for (( i=0; i < ${l_num_cores}; i++ )); do
    l_numbers+="null "
  done
  echo "${l_numbers[@]}" | tr " " "\n" | jq -cs '.'
}

stats_raw=$(curl --connect-timeout 2 --max-time "$API_TIMEOUT" --silent --noproxy '*' \
  "http://127.0.0.1:${MINER_API_PORT}/1/summary")

if [[ $? -ne 0 || -z $stats_raw ]]; then
  echo -e "${YELLOW}Failed to read xmrig from localhost:${MINER_API_PORT}${NOCOLOR}"
else
  khs=$(echo "$stats_raw" | jq -r '.hashrate.total[0]' | awk '{print $1/1000}')
  ac=$(jq '.results.shares_good' <<< "$stats_raw")
  rj=$(( $(jq '.results.shares_total' <<< "$stats_raw") - ac ))
  num_cores=$(echo "$stats_raw" | jq '.hashrate.threads[][0]' | wc -l)
  cpu_temp=$(get_cpu_temps "$num_cores")
  cpu_fan=$(get_cpu_fans "$num_cores")
  bus_numbers=$(get_bus_numbers "$num_cores")
  stats=$(echo "$stats_raw" | jq --arg ac "$ac" --arg rj "$rj" \
    --argjson temp "$cpu_temp" \
    --argjson fan "$cpu_fan" \
    --argjson bus_numbers "$bus_numbers" \
    '{hs: [.hashrate.threads[][0]], $temp, $fan, ar: [$ac, $rj],
      uptime: .connection.uptime, algo: .algo, $bus_numbers, ver: .version}')
fi

[[ -z $khs ]] && khs=0
[[ -z $stats ]] && stats="null"
