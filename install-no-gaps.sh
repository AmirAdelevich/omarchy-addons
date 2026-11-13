#!/usr/bin/env bash
set -euo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/looknfeel.lua"
if [[ ! -f "$config" ]]; then
  printf 'Файл Omarchy не найден: %s\n' "$config" >&2
  exit 1
fi

settings=$(cat <<'LUA'
hl.config({
  general = {
    gaps_in = 0,
    gaps_out = 0,
  },
})
LUA
)

if [[ $(cat "$config") != *"$settings"* ]]; then
  backup=$(mktemp "$config.bak.XXXXXXXX")
  cp -p -- "$config" "$backup"
  printf '\n%s\n' "$settings" >> "$config"
  printf 'Резервная копия: %s\n' "$backup"
fi

if hyprctl reload; then
  errors=$(hyprctl configerrors)
  if [[ -n "$errors" ]]; then
    printf '%s\n' "$errors" >&2
    exit 1
  fi
  printf 'Настройка отступов применена.\n'
else
  printf 'Настройка записана. Проверь её после запуска Hyprland.\n'
fi
