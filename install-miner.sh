#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
miner_dir="${XDG_DATA_HOME:-$HOME/.local/share}/kryptex-miner"
apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

if [[ $EUID == 0 || $(uname -m) != x86_64 ]]; then
  echo 'Запусти установку от обычного пользователя на Linux x86-64.' >&2
  exit 1
fi
command -v nvidia-smi >/dev/null || { echo 'Установи драйвер NVIDIA и nvidia-smi.' >&2; exit 1; }
sudo pacman -S --needed wget foot python
mkdir -p "$miner_dir/SRBMiner-Multi-3-8-3" "$apps_dir"
install -m 755 "$repo_dir/miner/SRBMiner-Multi-3-8-3/SRBMiner-MULTI" "$miner_dir/SRBMiner-Multi-3-8-3/SRBMiner-MULTI"
install -m 755 "$repo_dir/miner/"*.sh "$miner_dir/"
install -m 644 "$repo_dir/miner/launch-background.py" "$miner_dir/"
cat > "$apps_dir/kryptex-miner.desktop" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Запустить майнер
Comment=SRBMiner для Kryptex, Pearl, лимит 160 Вт
Exec=/usr/bin/bash "$miner_dir/open-miner-console.sh" --restart
Path=$miner_dir
Icon=utilities-terminal
Terminal=false
StartupNotify=false
DESKTOP
echo 'Майнер установлен. Запусти «Запустить майнер» из меню приложений.'
