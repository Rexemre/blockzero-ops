#!/usr/bin/env bash

cd "$(dirname "$0")"

if [[ ! -x ./xmrig ]]; then
  echo -e "${YELLOW}xmrig binary missing — running h-install.sh${NOCOLOR}"
  bash ./h-install.sh || exit 1
fi

[[ $(ps aux | egrep './[x]mrig' | grep -v grep | wc -l) != 0 ]] &&
  echo -e "${RED}Another xmrig instance is already running${NOCOLOR}" &&
  exit 1

# RandomX needs huge pages on Linux for decent hashrate.
if command -v hugepages >/dev/null 2>&1; then
  echo "HugePages tuning for RandomX ..."
  hugepages -rx
fi

./xmrig -c "$CUSTOM_CONFIG_FILENAME" 2>&1 | tee --append "${CUSTOM_LOG_BASENAME}.log"
