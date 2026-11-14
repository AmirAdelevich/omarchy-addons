#!/usr/bin/env bash
set -uo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1

cat <<'MENU'
Omarchy Add-ons

1. Установить программы
2. Применить снимок рабочего стола
3. Настроить мышь: чувствительность -0.10, ускорение выключено
4. Применить NoGaps: убрать отступы окон
5. Установить Hiddify
6. Применить профиль вентиляторов MSI Katana

Снимок заменяет настройки и сохраняет резервную копию. Настройки мыши,
клавиатуры и оформления окон (включая отступы) остаются текущими.
Для установки пакетов и системных настроек может понадобиться sudo.
Enter — выход.
MENU
read -r -p 'Выбор: ' choice || exit 0

status=0
case "$choice" in
  1) bash "$repo/install-all.sh" --apps-only || status=$? ;;
  2) bash "$repo/restore-desktop.sh" --packages --keep-addons-widget --keep-input-and-gaps || status=$? ;;
  3) bash "$repo/install-mouse.sh" || status=$? ;;
  4) bash "$repo/install-no-gaps.sh" || status=$? ;;
  5) bash "$repo/install-all.sh" --hiddify-only || status=$? ;;
  6) bash "$repo/restore-desktop.sh" --fan-only || status=$? ;;
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
