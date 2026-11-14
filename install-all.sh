#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $(uname -m) != x86_64 || $EUID == 0 ]]; then
  echo 'Запусти скрипт от обычного пользователя на Omarchy x86-64.' >&2
  exit 1
fi

hiddify_only=false
apps_only=false
case "${1:-}" in
  --apps-only) apps_only=true; shift ;;
  --hiddify-only) hiddify_only=true; shift ;;
esac
if (( $# )); then
  echo 'Использование: bash install-all.sh [--apps-only | --hiddify-only]' >&2
  exit 2
fi

requirements=(curl unzip sha256sum sudo pacman)
if $hiddify_only; then
  if pacman -Q hiddify >/dev/null 2>&1 || pacman -Q hiddify-app-bin >/dev/null 2>&1; then
    echo 'Hiddify уже установлен.'
    exit 0
  fi
else
  requirements+=(systemctl python3 omarchy yay xdg-settings)
fi
for cmd in "${requirements[@]}"; do
  command -v "$cmd" >/dev/null || { echo "Требуется $cmd" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
curl --fail --location --retry 3 --output "$tmp/arch-crypto-setup.zip" \
  https://github.com/AmirAdelevich/omarchy-addons/releases/download/crypto-bundle-v1/arch-crypto-setup.zip
cd "$tmp"
echo '753ade4004c9ae9067567140d584f756acddb36ced9a19ed7aa539248f814efd  arch-crypto-setup.zip' | sha256sum -c -
unzip -q arch-crypto-setup.zip
cd arch-crypto-setup
sha256sum -c SHA256SUMS

install_hiddify() {
  if ! pacman -Q hiddify >/dev/null 2>&1 && ! pacman -Q hiddify-app-bin >/dev/null 2>&1; then
    sudo pacman -U --needed packages/hiddify-5.5.5-1-x86_64.pkg.tar.zst
  fi
}

if $hiddify_only; then
  install_hiddify
  exit 0
fi

aur_packages=(google-chrome visual-studio-code-bin)
if ! pacman -Q telegram-desktop >/dev/null 2>&1; then
  aur_packages+=(telegram-desktop-bin)
fi
omarchy pkg aur add "${aur_packages[@]}"
packages=(tailscale papers)
if ! pacman -Q libreoffice-fresh >/dev/null 2>&1 && ! pacman -Q libreoffice-still >/dev/null 2>&1; then
  packages+=(libreoffice-fresh)
fi
sudo pacman -S --needed "${packages[@]}"
sudo systemctl enable --now tailscaled.service
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$apps"
for name in 'Google Photos' 'Google Drive' 'Google Messages'; do
  if [[ ! -e "$apps/$name.desktop" && ! -L "$apps/$name.desktop" ]]; then
    install -m 644 "$repo_dir/desktop/applications/$name.desktop" "$apps/$name.desktop"
  fi
done

sudo pacman -U --needed \
  packages/jacartauc-3.3.6.3921-1-x86_64.pkg.tar.zst \
  packages/cryptopro-csp-k1-5.0.13600-2-x86_64.pkg.tar.zst
sudo systemctl enable --now pcscd.socket
sudo install -D -m 644 cryptopro-cades-chrome.json /etc/opt/chrome/policies/managed/cryptopro-cades.json
if $apps_only; then
  exit 0
fi
python3 enable-chrome-autoscroll.py
bash "$repo_dir/install-no-gaps.sh"
install_hiddify
if ! env -u BROWSER xdg-settings set default-web-browser google-chrome.desktop ||
  [[ $(env -u BROWSER xdg-settings get default-web-browser) != google-chrome.desktop ]]; then
  echo 'Не удалось назначить Google Chrome браузером по умолчанию. Сделай это в настройках системы.' >&2
fi
echo 'Перезапусти Google Chrome, чтобы применить настройки.'
