#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ -f miner.pid ]] || { echo "Нет запущенного майнера."; exit 0; }
pid=$(cat miner.pid)
if [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]]; then
  cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline")
  if [[ $cmd == './krig-miner '* || $cmd == ./SRBMiner-Multi-*/SRBMiner-MULTI\ * ]]; then
    if ! kill -INT "$pid" 2>/dev/null; then sudo kill -INT "$pid"; fi
    echo "Остановка майнинга запрошена."
    exit 0
  fi
fi
echo "Майнер уже остановлен."
