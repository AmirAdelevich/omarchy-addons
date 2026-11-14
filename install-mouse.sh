#!/usr/bin/env bash
set -euo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/input.lua"
settings='hl.config({ input = { sensitivity = 0, accel_profile = "flat" } })'
if [[ ! -f "$config" ]]; then
  printf 'Файл Omarchy не найден: %s\n' "$config" >&2
  exit 1
fi

backup=
if [[ $(tail -n 1 -- "$config") != "$settings" ]]; then
  backup=$(mktemp "$config.bak.XXXXXXXX")
  cp -p -- "$config" "$backup"
  printf '\n-- Mouse speed and acceleration.\n%s\n' "$settings" >> "$config"
fi

if hyprctl reload && errors=$(hyprctl configerrors) && [[ -z "$errors" ]]; then
  if [[ -n "$backup" ]]; then
    printf 'Резервная копия: %s\n' "$backup"
  fi
  printf 'Чувствительность мыши: 0. Ускорение отключено.\n'
else
  if [[ -n "$backup" ]]; then
    cp -p -- "$backup" "$config"
    hyprctl reload || true
  fi
  printf 'Ошибка конфигурации Hyprland.\n%s\n' "${errors:-}" >&2
  exit 1
fi
