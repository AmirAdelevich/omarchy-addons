#!/usr/bin/env bash
set -uo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1

cat <<'MENU'
Omarchy Add-ons

1. Установить программы и восстановить рабочий стол
2. Установить программы
3. Восстановить рабочий стол
4. Установить Hiddify
5. Применить NoGaps
6. Восстановить рабочий стол с профилем вентиляторов MSI Katana

Восстановление заменяет настройки и сохраняет резервную копию.
Для установки пакетов и системных настроек может понадобиться sudo.
Enter — выход.
MENU
read -r -p 'Выбор: ' choice || exit 0

restore=(bash "$repo/restore-desktop.sh" --packages --keep-addons-widget)
status=0
case "$choice" in
  1) bash "$repo/install-all.sh" && "${restore[@]}" || status=$? ;;
  2) bash "$repo/install-all.sh" || status=$? ;;
  3) "${restore[@]}" || status=$? ;;
  4) bash "$repo/install-all.sh" --hiddify-only || status=$? ;;
  5) bash "$repo/install-no-gaps.sh" || status=$? ;;
  6) "${restore[@]}" --fan-control || status=$? ;;
  '') exit 0 ;;
  *) printf 'Выбери пункт от 1 до 6.\n' >&2; status=2 ;;
esac

if (( status == 0 )); then
  printf '\nГотово.\n'
else
  printf '\nОперация завершилась с ошибкой (код %s).\n' "$status" >&2
fi
read -r -p 'Нажми Enter, чтобы закрыть окно. ' _
exit "$status"
