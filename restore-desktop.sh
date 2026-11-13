#!/usr/bin/env bash
set -euo pipefail

snapshot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/desktop" && pwd)
config="$HOME/.config"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
omarchy_path=${OMARCHY_PATH:-/usr/share/omarchy}
background="$omarchy_path/themes/retro-82/backgrounds/1-in-the-groove.webp"

if [[ $EUID == 0 || ! -f "$config/hypr/hyprland.lua" || ! -f "$background" ]]; then
  echo 'Запусти восстановление от своего пользователя в Omarchy с темой Retro 82.' >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
while IFS=$'\t' read -r kind name url revision; do
  checkout="$tmp/$kind/$name"
  mkdir -p "$checkout"
  git -C "$checkout" init -q
  git -C "$checkout" remote add origin "$url"
  git -C "$checkout" fetch -q --depth=1 origin "$revision"
  git -C "$checkout" checkout -q --detach FETCH_HEAD
done < "$snapshot/sources.tsv"

omarchy pkg add ttf-ia-writer chromium
omarchy pkg aur add superwhisper-bin
superwhisper=/opt/superwhisper/assets/omarchy-plugin/superwhisper-panel
test -f "$superwhisper/manifest.json"

backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-addons"
mkdir -p "$backup_root"
backup=$(mktemp -d "$backup_root/desktop.XXXXXXXX")
printf 'Резервная копия рабочего стола: %s\n' "$backup"

replace() {
  local source=$1 destination=$2 saved=$3
  mkdir -p "$(dirname -- "$destination")"
  if [[ -e "$destination" || -L "$destination" ]]; then
    mkdir -p "$(dirname -- "$backup/$saved")"
    mv -- "$destination" "$backup/$saved"
  fi
  cp -a -- "$source" "$destination"
}

while IFS=$'\t' read -r kind name _ _; do
  replace "$tmp/$kind/$name" "$config/omarchy/$kind/$name" "config/omarchy/$kind/$name"
done < "$snapshot/sources.tsv"

ln -s "$superwhisper" "$tmp/superwhisper-panel"
replace "$tmp/superwhisper-panel" "$config/omarchy/plugins/superwhisper-panel" config/omarchy/plugins/superwhisper-panel

sudo install -D -o root -g root -m 0755 \
  "$config/omarchy/plugins/io.github.amiradelevich.fan/fan" /usr/local/libexec/omarchy-fan

while IFS= read -r -d '' file; do
  replace "$snapshot/config/$file" "$config/$file" "config/$file"
done < <(cd "$snapshot/config" && find . -type f -print0)

for launcher in "$snapshot/applications/"*.desktop; do
  name=${launcher##*/}
  replace "$launcher" "$apps/$name" "applications/$name"
done
for entry in bobbynicholas.omaland/omaland io.github.twiking.omasettings/omasettings; do
  plugin="$config/omarchy/plugins/${entry%/*}"
  name=${entry##*/}
  python3 - "$plugin" "$name" "$tmp/$name.desktop" <<'PY'
import sys
from pathlib import Path

plugin, name, output = sys.argv[1:]
directory = Path(plugin)
launcher = (directory / f"{name}.desktop").read_text()
Path(output).write_text(launcher.replace("@ICON@", str(directory / "icon.png")))
PY
  replace "$tmp/$name.desktop" "$apps/$name.desktop" "applications/$name.desktop"
done

omarchy theme set retro-82
staged_background="$HOME/.local/state/omarchy/current/theme/backgrounds/${background##*/}"
omarchy theme bg set "$staged_background"
hyprctl reload
errors=$(hyprctl configerrors)
if [[ -n "$errors" ]]; then
  printf '%s\n' "$errors" >&2
  exit 1
fi
omarchy restart shell
xdg-settings set default-web-browser google-chrome.desktop
echo 'Рабочий стол восстановлен.'
