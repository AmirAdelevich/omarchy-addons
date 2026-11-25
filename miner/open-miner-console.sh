#!/usr/bin/env bash
set -eu
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ ${1:-} != --inside ]]; then
    exec /usr/bin/foot --title='SRBMiner — Kryptex' /usr/bin/bash "$PWD/open-miner-console.sh" --inside "$@"
fi
shift

show_log() {
    if [[ -r mining.log ]]; then
        LC_ALL=C awk '
            /] Total: [0-9.]+ TH\/s/ && $4 + 0 > peak {
                peak = $4 + 0
                date = $1
                time = $2
            }
            END {
                if (peak > 0)
                    printf "Пик в журнале: %.2f TH/s %s %s\n\n", peak, date, time
            }
        ' mining.log
    fi
    exec tail -n 0 -F -- mining.log
}

if [[ ${1:-} != --restart && -f miner.lock ]] && ! flock -n miner.lock true; then
    printf 'Майнер уже запущен. Показываю журнал.\n'
    show_log
fi

printf 'Запуск SRBMiner с настройками Kryptex. Введите пароль sudo, если появится запрос.\n'
exec 8>"${XDG_RUNTIME_DIR:?}/kryptex-miner-launch.lock"
if ! flock -n 8; then
    read -r -p 'Запуск уже выполняется. Нажмите Enter, чтобы закрыть окно.'
    exit 1
fi

if sudo --preserve-env=http_proxy,https_proxy,all_proxy,HTTP_PROXY,HTTPS_PROXY,ALL_PROXY /usr/bin/bash -c '
    set -e
    if [[ ${1:-} == --restart && -f miner.lock ]] && ! flock -n miner.lock true; then
        bash ./stop-mining.sh
        if ! flock -w 30 miner.lock true; then
            echo "Майнер не завершился за 30 секунд."
            exit 1
        fi
    fi
    exec /usr/bin/python3 ./launch-background.py
' bash "${1:-}"; then
    sleep 2
    if [[ -f miner.lock ]] && ! flock -n miner.lock true; then
        exec 8>&-
        show_log
    fi
    tail -n 25 -- console.log
fi
read -r -p 'Майнер не запустился. Нажмите Enter, чтобы закрыть окно.'
