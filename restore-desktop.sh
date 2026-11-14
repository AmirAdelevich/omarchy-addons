#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
snapshot="$repo/desktop"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
packages=false
fan_control=false
fan_only=false
keep_input_and_gaps=false
keep_addons_widget=false
for argument in "$@"; do
  case $argument in
    --packages) packages=true ;;
    --fan-only) fan_only=true ;;
    --keep-input-and-gaps) keep_input_and_gaps=true ;;
    --fan-control) fan_control=true ;;
    --keep-addons-widget) keep_addons_widget=true ;;
    --dry-run)
      python3 - "$snapshot" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
appearance=json.loads((root/'appearance.json').read_text())
assert (root/'themes'/appearance['theme']/'backgrounds'/appearance['background']).is_file()
plugins=json.loads((root/'plugins.json').read_text())
sources=[row.split('\t') for row in (root/'sources.tsv').read_text().splitlines()]
assert all(len(row)==4 and len(row[3])==40 and row[2].startswith('https://github.com/') for row in sources)
ids={row[1] for row in sources if row[0]=='plugins'}
ids.update(json.loads(p.read_text())['id'] for p in (root/'plugins').glob('*/manifest.json'))
assert all(p['firstParty'] or p['id'] in ids for p in plugins)
print('Снимок корректен. Тема',appearance['theme'],'плагинов',len(plugins),'источников',len(sources))
PY
      exit ;;
    *) printf 'Неизвестный параметр: %s\n' "$argument" >&2; exit 1 ;;
  esac
done
if [[ $EUID == 0 || ! -f "$config/hypr/hyprland.lua" ]]; then
  echo 'Запусти восстановление от своего пользователя в сессии Omarchy.' >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
apply_fan_profile() {
  python3 - "$snapshot/hardware/katana-profile.json" <<'PYMODEL'
import hashlib,json,pathlib,platform,sys
source=pathlib.Path(sys.argv[1]);p=json.loads(source.read_text())
if pathlib.Path('/sys/class/dmi/id/product_name').read_text().strip()!=p['model']:
 raise SystemExit('Профиль вентиляторов рассчитан на другую модель компьютера.')
if platform.release()!=p['kernel']:
 raise SystemExit('Для этого ядра нужно пересобрать модуль msi-ec. Снимок рассчитан на '+p['kernel'])
if hashlib.sha256((source.parent/p['module']).read_bytes()).hexdigest()!=p['moduleSha256']:
 raise SystemExit('Контрольная сумма модуля msi-ec не совпала.')
PYMODEL
  sudo install -D -o root -g root -m 0755 "$snapshot/hardware/katana-fans" /usr/local/libexec/katana-fans
  sudo install -o root -g root -m 0644 "$snapshot/hardware/katana-msi-ec-7.2.15-1-omarchy.ko" /usr/local/libexec/katana-msi-ec-7.2.15-1-omarchy.ko
  sudo install -D -o root -g root -m 0644 "$snapshot/hardware/katana-fans-driver.service" /etc/systemd/system/katana-fans-driver.service
  sudo install -D -o root -g root -m 0644 "$snapshot/hardware/katana-restore.conf" /etc/systemd/system/katana-fans-driver.service.d/restore.conf
  sudo systemctl daemon-reload
  sudo systemctl enable --now katana-fans-driver.service
  python3 - "$snapshot/hardware/katana-profile.json" <<'PY'
import json,pathlib,sys
p=json.load(open(sys.argv[1]))
if pathlib.Path('/sys/class/dmi/id/product_name').read_text().strip()!=p['model']:
 raise SystemExit('Профиль вентиляторов рассчитан на другую модель компьютера.')
firmware=pathlib.Path('/sys/devices/platform/msi-ec/fw_version')
if not firmware.is_file() or firmware.read_text().strip()!=p['firmware']:
 raise SystemExit('Нужен драйвер msi-ec и соответствующая прошивка контроллера.')
PY
  printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/katana-fans\n' "$(id -un)" > "$tmp/fan-policy"
  sudo visudo -cf "$tmp/fan-policy"
  sudo install -m 0440 -o root -g root "$tmp/fan-policy" /etc/sudoers.d/omarchy-addons-katana-fans
  readarray -t fan < <(python3 - "$snapshot/hardware/katana-profile.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
print(' '.join(str(v) for _,speeds in p['curves'] for v in speeds));print(p['mode']);print(p['boost'])
PY
)
  read -ra speeds <<< "${fan[0]}"
  sudo /usr/local/libexec/katana-fans apply "${speeds[@]}"
  sudo /usr/local/libexec/katana-fans mode "${fan[1]}"
  sudo /usr/local/libexec/katana-fans boost "${fan[2]}"
}

if $fan_only; then
  apply_fan_profile
  exit 0
fi

keep_config_file() {
  $keep_input_and_gaps && [[ $1 == ./hypr/input.lua || $1 == ./hypr/looknfeel.lua ]]
}

while IFS=$'\t' read -r kind name url revision; do
  checkout="$tmp/$kind/$name"
  mkdir -p "$checkout"
  git -C "$checkout" init -q
  git -C "$checkout" remote add origin "$url"
  git -C "$checkout" fetch -q --depth=1 origin "$revision"
  git -C "$checkout" checkout -q --detach FETCH_HEAD
done < "$snapshot/sources.tsv"
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-addons"
mkdir -p "$backup_root"
backup=$(mktemp -d "$backup_root/desktop.XXXXXXXX")
chmod 700 "$backup"
printf 'Резервная копия рабочего стола: %s\n' "$backup"
replace() {
  local source=$1 destination=$2 saved=$3
  mkdir -p "$(dirname -- "$destination")"
  if [[ -e "$destination" || -L "$destination" ]]; then
    mkdir -p "$(dirname -- "$backup/$saved")"
    if [[ -e "$backup/$saved" || -L "$backup/$saved" ]]; then
      rm -rf -- "$destination"
    else
      mv -- "$destination" "$backup/$saved"
    fi
  fi
  cp -a -- "$source" "$destination"
}
while IFS=$'\t' read -r kind name _ _; do
  replace "$tmp/$kind/$name" "$config/omarchy/$kind/$name" "config/omarchy/$kind/$name"
done < "$snapshot/sources.tsv"
for plugin in "$snapshot/plugins/"*; do
  replace "$plugin" "$config/omarchy/plugins/${plugin##*/}" "config/omarchy/plugins/${plugin##*/}"
done
for theme in "$snapshot/themes/"*; do
  replace "$theme" "$config/omarchy/themes/${theme##*/}" "config/omarchy/themes/${theme##*/}"
done
if $packages; then
  bash "$repo/restore-packages.sh"
else
  omarchy pkg add ttf-ia-writer chromium
fi
sudo install -D -o root -g root -m 0755 "$snapshot/hardware/katana-fans" /usr/local/libexec/katana-fans
readarray -t appearance < <(python3 - "$snapshot/appearance.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]))
print(value['theme']);print(value['background'])
PY
)
# Theme application can regenerate app files, so preserve their previous contents first.
while IFS= read -r -d '' file; do
  if keep_config_file "$file"; then continue; fi
  if [[ -e "$config/$file" ]]; then
    mkdir -p "$(dirname -- "$backup/config/$file")"
    cp -a -- "$config/$file" "$backup/config/$file"
  fi
done < <(cd "$snapshot/config" && find . -type f -print0)
omarchy theme set "${appearance[0]}"
omarchy theme bg set "$state/current/theme/backgrounds/${appearance[1]}"
while IFS= read -r -d '' file; do
  if keep_config_file "$file"; then continue; fi
  source="$snapshot/config/$file"
  if $keep_addons_widget && [[ $file == ./omarchy/shell.json ]] &&
    [[ -f "$config/omarchy/plugins/io.github.amiradelevich.omarchy-addons/manifest.json" ]]; then
    source="$tmp/shell.json"
    jq '.bar.layout.right += [{"id": "io.github.amiradelevich.omarchy-addons"}]' \
      "$snapshot/config/$file" > "$source"
  fi
  replace "$source" "$config/$file" "config/$file"
done < <(cd "$snapshot/config" && find . -type f -print0)
while IFS= read -r -d '' file; do
  replace "$snapshot/state/$file" "$state/$file" "state/$file"
done < <(cd "$snapshot/state" && find . -type f -print0)
for launcher in "$snapshot/applications/"*.desktop; do
  name=${launcher##*/}
  python3 - "$launcher" "$config" "$tmp/$name" <<'PY'
import pathlib,sys
source,config,target=sys.argv[1:]
pathlib.Path(target).write_text(pathlib.Path(source).read_text().replace('@CONFIG_HOME@',config))
PY
  replace "$tmp/$name" "$apps/$name" "applications/$name"
done
omarchy-shell shell rescanPlugins
while IFS=$'\t' read -r id enabled; do
  result=$(omarchy-shell shell setPluginEnabled "$id" "$enabled")
  [[ $result == ok ]] || printf 'Плагин пока недоступен: %s\n' "$id" >&2
done < <(python3 - "$snapshot/plugins.json" <<'PY'
import json,sys
for plugin in json.load(open(sys.argv[1])):
 print(plugin['id']+'\t'+str(plugin['enabled']).lower())
PY
)
if $fan_control; then
  apply_fan_profile
fi
hyprctl reload
errors=$(hyprctl configerrors)
if [[ -n $errors ]]; then printf '%s\n' "$errors" >&2; exit 1; fi
python3 - "$snapshot/gtk-interface.json" <<'PYGTK'
import json,subprocess,sys
for key,value in json.load(open(sys.argv[1])).items():
 subprocess.run(['gsettings','set','org.gnome.desktop.interface',key,value],check=True)
PYGTK
zone=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["timezone"])' "$snapshot/appearance.json")
sudo timedatectl set-timezone "$zone"
omarchy restart shell
update-desktop-database "$apps" || true
printf 'Рабочий стол восстановлен.\n'
