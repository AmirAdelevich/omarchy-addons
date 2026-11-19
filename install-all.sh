#!/usr/bin/env bash
# Installs the application bundle. Running it with no arguments keeps the old
# behaviour; each component can also be installed on its own by name, which is
# what the add-ons menu does.
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

components=(chrome code telegram tailscale libreoffice papers webapps cryptopro hiddify autoscroll default-browser)

usage() {
  cat <<'EOF'
Использование:
  bash install-all.sh                 установить всё
  bash install-all.sh <компонент>...  установить выбранные компоненты

Компоненты:
  chrome           Google Chrome (AUR)
  code             Visual Studio Code (AUR)
  telegram         Telegram Desktop
  tailscale        Tailscale и служба tailscaled
  libreoffice      LibreOffice Fresh, если нет Still
  papers           Papers для PDF
  webapps          Веб-приложения Google Фото, Диск, Сообщения
  cryptopro        КриптоПро CSP, CAdES и JaCarta
  hiddify          Hiddify
  autoscroll       Прокрутка колёсиком в Chrome
  default-browser  Google Chrome браузером по умолчанию
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || die "Требуется $cmd"
  done
}

tmp=
cleanup() { if [[ -n $tmp ]]; then rm -rf -- "$tmp"; fi; }
trap cleanup EXIT

ensure_bundle() {
  [[ -n $tmp ]] && return 0
  require curl unzip sha256sum
  tmp=$(mktemp -d)
  curl --fail --location --retry 3 --output "$tmp/arch-crypto-setup.zip" \
    https://github.com/AmirAdelevich/omarchy-addons/releases/download/crypto-bundle-v1/arch-crypto-setup.zip
  (
    cd "$tmp"
    echo '753ade4004c9ae9067567140d584f756acddb36ced9a19ed7aa539248f814efd  arch-crypto-setup.zip' | sha256sum -c -
    unzip -q arch-crypto-setup.zip
    cd arch-crypto-setup
    sha256sum -c SHA256SUMS
  )
}

install_chrome() { require omarchy yay; omarchy pkg aur add google-chrome; }

install_code() { require omarchy yay; omarchy pkg aur add visual-studio-code-bin; }

install_telegram() {
  if pacman -Q telegram-desktop >/dev/null 2>&1; then
    echo 'Telegram Desktop уже установлен.'
    return 0
  fi
  require omarchy yay
  omarchy pkg aur add telegram-desktop-bin
}

install_tailscale() {
  require sudo pacman systemctl
  sudo pacman -S --needed tailscale
  sudo systemctl enable --now tailscaled.service
}

install_libreoffice() {
  require sudo pacman
  if pacman -Q libreoffice-fresh >/dev/null 2>&1 || pacman -Q libreoffice-still >/dev/null 2>&1; then
    echo 'LibreOffice уже установлен.'
    return 0
  fi
  sudo pacman -S --needed libreoffice-fresh
}

install_papers() { require sudo pacman; sudo pacman -S --needed papers; }

install_webapps() {
  local apps name
  apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$apps"
  for name in 'Google Photos' 'Google Drive' 'Google Messages'; do
    if [[ ! -e "$apps/$name.desktop" && ! -L "$apps/$name.desktop" ]]; then
      install -m 644 "$repo_dir/desktop/applications/$name.desktop" "$apps/$name.desktop"
      printf 'Добавлено: %s\n' "$name"
    fi
  done
  return 0
}

install_cryptopro() {
  require sudo pacman systemctl
  ensure_bundle
  sudo pacman -U --needed \
    "$tmp/arch-crypto-setup/packages/jacartauc-3.3.6.3921-1-x86_64.pkg.tar.zst" \
    "$tmp/arch-crypto-setup/packages/cryptopro-csp-k1-5.0.13600-2-x86_64.pkg.tar.zst"
  sudo systemctl enable --now pcscd.socket
  sudo install -D -m 644 "$tmp/arch-crypto-setup/cryptopro-cades-chrome.json" \
    /etc/opt/chrome/policies/managed/cryptopro-cades.json
}

install_hiddify() {
  require sudo pacman
  if pacman -Q hiddify >/dev/null 2>&1 || pacman -Q hiddify-app-bin >/dev/null 2>&1; then
    echo 'Hiddify уже установлен.'
    return 0
  fi
  ensure_bundle
  sudo pacman -U --needed "$tmp/arch-crypto-setup/packages/hiddify-5.5.5-1-x86_64.pkg.tar.zst"
}

install_autoscroll() {
  require python3
  python3 "$repo_dir/enable-chrome-autoscroll.py"
}

install_default_browser() {
  require xdg-settings
  if ! env -u BROWSER xdg-settings set default-web-browser google-chrome.desktop ||
    [[ $(env -u BROWSER xdg-settings get default-web-browser) != google-chrome.desktop ]]; then
    echo 'Не удалось назначить Google Chrome браузером по умолчанию. Сделай это в настройках системы.' >&2
  fi
}

[[ $(uname -m) == x86_64 ]] || die 'Скрипт рассчитан на Omarchy x86-64.'
[[ $EUID != 0 ]] || die 'Запусти скрипт от обычного пользователя.'

selected=("$@")
run_all=false
if (( ${#selected[@]} == 0 )); then
  selected=("${components[@]}")
  run_all=true
fi

for component in "${selected[@]}"; do
  case $component in
    -h|--help) usage; exit 0 ;;
    chrome|code|telegram|tailscale|libreoffice|papers|webapps|cryptopro|hiddify|autoscroll|default-browser) ;;
    *) usage >&2; die "Неизвестный компонент: $component" ;;
  esac
done

for component in "${selected[@]}"; do
  printf '\n== %s ==\n' "$component"
  "install_${component//-/_}"
done

if $run_all; then
  bash "$repo_dir/install-no-gaps.sh"
  echo 'Перезапусти Google Chrome, чтобы применить настройки.'
fi
