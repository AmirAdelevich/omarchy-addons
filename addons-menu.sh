#!/usr/bin/env bash
# Add-ons menu: every feature has its own number and the answer may list
# several numbers separated by spaces (for example "1 5 12").
set -uo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
version=$(sed -n 's/^[[:space:]]*"version": "\([^"]*\)",$/\1/p' "$repo/manifest.json" | head -n 1)

sections=()
labels=()
actions=()

add() {
  sections+=("$1")
  labels+=("$2")
  actions+=("$3")
}

# Программы
add "ПРОГРАММЫ" "Google Chrome" "program:chrome"
add "ПРОГРАММЫ" "Visual Studio Code" "program:code"
add "ПРОГРАММЫ" "Telegram Desktop" "program:telegram"
add "ПРОГРАММЫ" "Tailscale" "program:tailscale"
add "ПРОГРАММЫ" "LibreOffice" "program:libreoffice"
add "ПРОГРАММЫ" "Papers (PDF)" "program:papers"
add "ПРОГРАММЫ" "Веб-приложения Google: Фото, Диск, Сообщения" "program:webapps"
add "ПРОГРАММЫ" "КриптоПро CSP, CAdES и JaCarta" "program:cryptopro"
add "ПРОГРАММЫ" "Hiddify" "program:hiddify"
add "ПРОГРАММЫ" "Прокрутка колёсиком в Chrome" "program:autoscroll"
add "ПРОГРАММЫ" "Chrome браузером по умолчанию" "program:default-browser"

# Плагины
add "ПЛАГИНЫ" "Fans: обороты вентиляторов MSI Katana" "plugin:fans"
add "ПЛАГИНЫ" "Pulse: CPU, GPU, температуры" "plugin:pulse"

# Настройки
add "НАСТРОЙКИ" "Мышь: чувствительность 0, без ускорения" "setting:mouse"
add "НАСТРОЙКИ" "NoGaps: убрать отступы окон" "setting:nogaps"
add "НАСТРОЙКИ" "Усиление звука динамиков: +10 дБ с ограничителем" "setting:sound"

# Оборудование
add "ОБОРУДОВАНИЕ" "Профиль вентиляторов MSI Katana" "hardware:fans"

# Рабочий стол
add "РАБОЧИЙ СТОЛ" "Снимок рабочего стола: тема, панель, конфиги" "desktop:snapshot"

run() {
  case $1 in
    program:*) bash "$repo/install-all.sh" "${1#program:}" ;;
    plugin:*) bash "$repo/install-plugin.sh" "${1#plugin:}" ;;
    setting:mouse) bash "$repo/install-mouse.sh" ;;
    setting:nogaps) bash "$repo/install-no-gaps.sh" ;;
    setting:sound) bash "$repo/install-sound-boost.sh" ;;
    hardware:fans) bash "$repo/restore-desktop.sh" --fan-only ;;
    desktop:snapshot) bash "$repo/restore-desktop.sh" --packages --keep-addons-widget --keep-input-and-gaps ;;
    *)
      printf 'Неизвестное действие: %s\n' "$1" >&2
      return 2
      ;;
  esac
}

print_menu() {
  local i section=
  printf 'Omarchy Add-ons'
  [[ -n $version ]] && printf ' %s' "$version"
  printf '\n\nВведи номера через пробел, например: 1 5 12. Enter — выход.\n'
  for i in "${!labels[@]}"; do
    if [[ ${sections[i]} != "$section" ]]; then
      section=${sections[i]}
      printf '\n%s\n' "$section"
    fi
    printf ' %2d. %s\n' "$((i + 1))" "${labels[i]}"
  done
  printf '\nПункты 1-11 ставят только выбранное. Снимок рабочего стола заменяет настройки и сохраняет резервную копию.\n'
  printf 'Для пакетов и системных настроек может понадобиться sudo.\n'
}

picks=()

collect_picks() {
  local token n ok=1
  picks=()
  for token in "$@"; do
    if [[ ! $token =~ ^[0-9]+$ ]]; then
      printf 'Не число: %s\n' "$token" >&2
      ok=0
      continue
    fi
    n=$((10#$token))
    if (( n < 1 || n > ${#labels[@]} )); then
      printf 'Нет пункта %s (всего %d).\n' "$token" "${#labels[@]}" >&2
      ok=0
      continue
    fi
    picks+=("$n")
  done
  (( ok ))
}

run_picks() {
  local n status=0 failed=()
  local -A seen=()
  for n in "${picks[@]}"; do
    [[ -n ${seen[$n]:-} ]] && continue
    seen[$n]=1
    printf '\n=== %s ===\n' "${labels[n - 1]}"
    if ! run "${actions[n - 1]}"; then
      failed+=("$n")
      status=1
    fi
  done
  if (( ${#failed[@]} )); then
    printf '\nС ошибкой: %s\n' "${failed[*]}" >&2
  else
    printf '\nГотово.\n'
  fi
  if [[ -t 0 ]]; then
    read -r -p 'Enter — закрыть окно. ' _ || true
  fi
  return $status
}

interactive() {
  local answer
  print_menu
  while :; do
    read -r -p 'Номера: ' answer || return 0
    answer=${answer//,/ }
    if [[ -z ${answer//[[:space:]]/} ]]; then
      return 0
    fi
    # shellcheck disable=SC2086
    collect_picks $answer && break
  done
  run_picks
}

case "${1:-}" in
  --list) print_menu ;;
  --run)
    shift
    if (( $# == 0 )); then
      print_menu
      exit 0
    fi
    collect_picks "$@" || exit 2
    run_picks
    ;;
  ''|--menu) interactive ;;
  -h|--help) print_menu ;;
  *)
    printf 'Неизвестный параметр: %s\n' "$1" >&2
    exit 2
    ;;
esac
