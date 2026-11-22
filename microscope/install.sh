#!/usr/bin/env bash
# Установка дополнения «Микроскоп H1600» для Omarchy.
# Ставит просмотрщик, окно настроек, ярлыки, конфиг и правило Hyprland.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/microscope"
hypr_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"

if [[ $EUID == 0 ]]; then
  echo 'Запусти установку от обычного пользователя (без sudo).' >&2
  exit 1
fi

# --- зависимости ---
missing=()
command -v ffmpeg >/dev/null 2>&1 || missing+=(ffmpeg)
command -v v4l2-ctl >/dev/null 2>&1 || missing+=(v4l-utils)
if ! /usr/bin/python3 - <<'PY' >/dev/null 2>&1
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw
PY
then
  missing+=(python-gobject gtk4 libadwaita)
fi

if ((${#missing[@]})); then
  echo "Устанавливаю зависимости: ${missing[*]}"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "${missing[@]}"
  else
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
fi

# --- файлы приложения ---
install -d "$bin_dir" "$apps_dir" "$cfg_dir"
for app in microscope microscope-settings microscope-plain; do
  install -m 755 "$repo_dir/bin/$app" "$bin_dir/$app"
done

# --- ярлыки (путь к бинарникам подставляется текущий) ---
for name in microscope microscope-settings; do
  sed "s|@BIN@|$bin_dir|g" "$repo_dir/desktop/$name.desktop.in" > "$apps_dir/$name.desktop"
  chmod 644 "$apps_dir/$name.desktop"
done
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps_dir" >/dev/null 2>&1 || true

# --- настройки по умолчанию ---
if [[ ! -f $cfg_dir/config ]]; then
  cat > "$cfg_dir/config" <<'EOF'
# Настройки просмотрщика микроскопа H1600
# VIEW_SIZE — разрешение камеры, VIEW_FPS — частота кадров,
# VIEW_CROP — сколько строк снизу отрезать (0 — показывать кадр целиком).
VIEW_SIZE=1920x1080
VIEW_FPS=30
VIEW_CROP=0
EOF
fi

# --- плавающее окно в Hyprland ---
if [[ -f $hypr_cfg ]]; then
  if grep -q 'ru\.omarchy\.Microscope' "$hypr_cfg"; then
    echo 'Правило плавающего окна уже есть в hyprland.lua.'
  else
    cp "$hypr_cfg" "$hypr_cfg.bak.$(date +%s)"
    cat >> "$hypr_cfg" <<'EOF'

-- Микроскоп H1600: плавающее окно в формате 16:9 (картинка без растяжения)
o.window("ru.omarchy.Microscope", { float = true, center = true, size = { 1280, 800 } })
EOF
    if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
      hyprctl reload >/dev/null 2>&1 || true
    fi
  fi
else
  echo "Не найден $hypr_cfg — правило плавающего окна пропущено." >&2
fi

echo
echo 'Готово. Запускай из меню приложений:'
echo '  «Микроскоп (H1600)» — просмотр, запись, фото;'
echo '  «Микроскоп — настройки» — качество, экспозиция, разрешение.'
echo "Настройки хранятся в $cfg_dir/config"
