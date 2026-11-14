#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
missing=()
while IFS= read -r package; do
  [[ -n $package ]] || continue
  if pacman -Si -- "$package" >/dev/null 2>&1; then
    missing+=("$package")
  else
    printf 'Пакет отсутствует в подключённых репозиториях: %s\n' "$package" >&2
  fi
done < "$repo/desktop/packages/native.txt"
if (( ${#missing[@]} )); then
  sudo pacman -S --needed -- "${missing[@]}"
fi
while IFS= read -r package; do
  [[ -n $package ]] || continue
  if pacman -Q -- "$package" >/dev/null 2>&1; then
    continue
  elif [[ $package == hiddify ]]; then
    python3 "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/msi.hiddify/update_hiddify.py" --language ru
  elif yay -Si -- "$package" >/dev/null 2>&1; then
    omarchy pkg aur add "$package"
  else
    printf 'Требуется отдельный источник пакета: %s\n' "$package" >&2
  fi
done < "$repo/desktop/packages/foreign.txt"
