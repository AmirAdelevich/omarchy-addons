#!/usr/bin/env bash
# Add-ons menu: features are grouped into numbered blocks, and each item has
# its own number inside its block. The answer may list several numbers
# separated by spaces, for example "1.3 2.1 3.2".
set -uo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
version=$(sed -n 's/^[[:space:]]*"version": "\([^"]*\)",$/\1/p' "$repo/manifest.json" | head -n 1)

sections=()
items_sec=()
items_label=()
items_action=()
current=-1

section() {
  sections+=("$1")
  current=$(( ${#sections[@]} - 1 ))
}

item() {
  items_sec+=("$current")
  items_label+=("$1")
  items_action+=("$2")
}

# 1. ПРОГРАММЫ
section "ПРОГРАММЫ"
item "Google Chrome" "program:chrome"
item "Visual Studio Code" "program:code"
item "Telegram Desktop" "program:telegram"
item "Tailscale" "program:tailscale"
item "LibreOffice" "program:libreoffice"
item "Papers (PDF)" "program:papers"
item "Веб-приложения Google: Фото, Диск, Сообщения" "program:webapps"
item "КриптоПро CSP, CAdES и JaCarta" "program:cryptopro"
item "Hiddify" "program:hiddify"
item "Прокрутка колёсиком в Chrome" "program:autoscroll"
item "Chrome браузером по умолчанию" "program:default-browser"

# 2. ПЛАГИНЫ
section "ПЛАГИНЫ"
item "Fans: обороты вентиляторов MSI Katana" "plugin:fans"
item "Pulse: CPU, GPU, температуры" "plugin:pulse"

# 3. НАСТРОЙКИ
section "НАСТРОЙКИ"
item "Мышь: чувствительность 0, без ускорения" "setting:mouse"
item "NoGaps: убрать отступы окон" "setting:nogaps"
item "Усиление звука динамиков: +10 дБ с ограничителем" "setting:sound"

# 4. ОБОРУДОВАНИЕ
section "ОБОРУДОВАНИЕ"
item "Профиль вентиляторов MSI Katana" "hardware:fans"

# 5. РАБОЧИЙ СТОЛ
section "РАБОЧИЙ СТОЛ"
item "Снимок рабочего стола: тема, панель, конфиги" "desktop:snapshot"

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

# Number of items in a 1-based section number.
section_size() {
  local s=$1 count=0 i
  for i in "${!items_label[@]}"; do
    (( items_sec[i] == s - 1 )) && count=$((count + 1))
  done
  printf '%s\n' "$count"
}

# Index of an item by 1-based section number and 1-based number inside it.
item_index() {
  local s=$1 n=$2 seen=0 i
  for i in "${!items_label[@]}"; do
    (( items_sec[i] == s - 1 )) || continue
    seen=$((seen + 1))
    if (( seen == n )); then
      printf '%s\n' "$i"
      return 0
    fi
  done
  return 1
}

print_menu() {
  local s=-1 n=0 i
  printf 'Omarchy Add-ons'
  [[ -n $version ]] && printf ' %s' "$version"
  printf '\n\nВведи номера через пробел, например: 1.3 2.1 3.2. Enter — выход.\n'
  for i in "${!items_label[@]}"; do
    if (( items_sec[i] != s )); then
      s=${items_sec[i]}
      n=0
      printf '\n%d. %s\n' "$((s + 1))" "${sections[s]}"
    fi
    n=$((n + 1))
    printf '   %d.%d. %s\n' "$((s + 1))" "$n" "${items_label[i]}"
  done
  printf '\nНомер блока и номер пункта пишутся через точку: 2.1 — плагин Fans, 3.3 — усиление звука.\n'
  printf 'Пункты 1.1-1.11 ставят только выбранное. Пункт 5.1 заменяет настройки и сохраняет резервную копию.\n'
  printf 'Для пакетов и системных настроек может понадобиться sudo.\n'
}

picks=()
pick_keys=()

collect_picks() {
  local token s n idx ok=1 total raw
  local -a tokens=()
  picks=()
  pick_keys=()
  # Commas are accepted as separators too ("1.3, 2.1").
  for raw in "$@"; do
    raw=${raw//,/ }
    # shellcheck disable=SC2206
    tokens+=($raw)
  done
  for token in "${tokens[@]}"; do
    if [[ $token =~ ^([0-9]+)\.([0-9]+)$ ]]; then
      s=$((10#${BASH_REMATCH[1]}))
      n=$((10#${BASH_REMATCH[2]}))
    elif [[ $token =~ ^[0-9]+$ ]]; then
      s=$((10#${token}))
      if (( s < 1 || s > ${#sections[@]} )); then
        printf 'Нет блока %d (всего %d).\n' "$s" "${#sections[@]}" >&2
      else
        printf 'Нужен номер пункта: %d.1, %d.2 и так далее.\n' "$s" "$s" >&2
      fi
      ok=0
      continue
    else
      printf 'Не понял «%s». Формат: блок.пункт, например 1.3\n' "$token" >&2
      ok=0
      continue
    fi

    if (( s < 1 || s > ${#sections[@]} )); then
      printf 'Нет блока %d (всего %d).\n' "$s" "${#sections[@]}" >&2
      ok=0
      continue
    fi

    total=$(section_size "$s")
    if (( n < 1 || n > total )); then
      printf 'В блоке %d нет пункта %d (всего %d).\n' "$s" "$n" "$total" >&2
      ok=0
      continue
    fi

    idx=$(item_index "$s" "$n") || {
      printf 'Нет пункта %d.%d.\n' "$s" "$n" >&2
      ok=0
      continue
    }
    picks+=("$idx")
    pick_keys+=("$s.$n")
  done
  (( ok )) && (( ${#picks[@]} > 0 ))
}

run_picks() {
  local k status=0 idx key
  local -a failed=()
  local -A seen=()
  for k in "${!picks[@]}"; do
    idx=${picks[k]}
    key=${pick_keys[k]}
    [[ -n ${seen[$idx]:-} ]] && continue
    seen[$idx]=1
    printf '\n=== %s. %s ===\n' "$key" "${items_label[idx]}"
    if ! run "${items_action[idx]}"; then
      failed+=("$key")
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
