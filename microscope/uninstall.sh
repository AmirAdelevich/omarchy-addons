#!/usr/bin/env bash
# Удаление дополнения «Микроскоп H1600».
set -euo pipefail

bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/microscope"
hypr_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"

if [[ $EUID == 0 ]]; then
  echo 'Запусти от обычного пользователя (без sudo).' >&2
  exit 1
fi

rm -f "$bin_dir/microscope" "$bin_dir/microscope-settings" "$bin_dir/microscope-plain"
rm -f "$apps_dir/microscope.desktop" "$apps_dir/microscope-settings.desktop"
rm -rf "$cfg_dir"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps_dir" >/dev/null 2>&1 || true

if [[ -f $hypr_cfg ]] && grep -q 'ru\.omarchy\.Microscope' "$hypr_cfg"; then
  cp "$hypr_cfg" "$hypr_cfg.bak.$(date +%s)"
  /usr/bin/python3 - "$hypr_cfg" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).read().splitlines()
out, skip_next = [], False
for line in lines:
    if skip_next and line.strip().startswith("o.window("):
        skip_next = False
        continue
    if line.strip() == "-- Микроскоп H1600: плавающее окно в формате 16:9 (картинка без растяжения)":
        skip_next = True
        continue
    out.append(line)
open(path, "w").write("\n".join(out) + "\n")
PY
  if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
fi

echo 'Микроскоп H1600 удалён.'
