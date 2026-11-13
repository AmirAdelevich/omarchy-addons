#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $(uname -m) != x86_64 || $EUID == 0 ]]; then
  echo 'Запусти скрипт от обычного пользователя на Omarchy x86-64.' >&2
  exit 1
fi

for cmd in gh unzip sha256sum sudo pacman systemctl python3; do
  command -v "$cmd" >/dev/null || { echo "Требуется $cmd" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
gh release download crypto-bundle-v1 -R AmirAdelevich/omarchy-addons \
  --pattern arch-crypto-setup.zip --dir "$tmp"
cd "$tmp"
echo '753ade4004c9ae9067567140d584f756acddb36ced9a19ed7aa539248f814efd  arch-crypto-setup.zip' | sha256sum -c -
unzip -q arch-crypto-setup.zip
cd arch-crypto-setup
sha256sum -c SHA256SUMS

sudo pacman -U --needed \
  packages/jacartauc-3.3.6.3921-1-x86_64.pkg.tar.zst \
  packages/cryptopro-csp-k1-5.0.13600-2-x86_64.pkg.tar.zst \
  packages/hiddify-5.5.5-1-x86_64.pkg.tar.zst
sudo systemctl enable --now pcscd.socket
sudo install -D -m 644 cryptopro-cades-chrome.json /etc/opt/chrome/policies/managed/cryptopro-cades.json
python3 enable-chrome-autoscroll.py
bash "$repo_dir/install-no-gaps.sh"
echo 'Перезапусти Google Chrome, чтобы применить настройки.'
