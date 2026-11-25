#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ $EUID -ne 0 ]]; then exec sudo --preserve-env=http_proxy,https_proxy,all_proxy,HTTP_PROXY,HTTPS_PROXY,ALL_PROXY bash "$PWD/start-srb-160w.sh" "$@"; fi
exec 9>miner.lock
flock -n 9 || { echo "Майнер уже запущен."; exit 1; }
nvidia-smi -i 0 --power-limit=160
actual=$(nvidia-smi -i 0 --query-gpu=power.limit --format=csv,noheader,nounits)
awk -v value="$actual" 'BEGIN {exit !(value <= 160.5)}' || exit 1
echo $$ > miner.pid
exec ./SRBMiner-Multi-3-8-3/SRBMiner-MULTI --algorithm pearlhash --disable-cpu --disable-gpu-amd --disable-gpu-intel \
 --gpu-cclock0 2550 --gpu-coffset0 200 --gpu-mclock0 5001 --gpu-plimit0 160 \
 --pool prl-ru.kryptex.network:8048 --tls true --wallet krxXV29VP7.worker \
 --log-file "$PWD/mining.log" --log-file-mode 1 "$@"
