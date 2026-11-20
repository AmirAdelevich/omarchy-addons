#!/usr/bin/env bash
# Installs one third-party plugin from the snapshot, without touching the rest
# of the desktop preset: Fans comes from the bundled snapshot, Pulse is fetched
# at the revision pinned in desktop/sources.tsv.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config="${XDG_CONFIG_HOME:-$HOME/.config}"
plugins="$config/omarchy/plugins"
state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-addons"

usage() {
  cat <<'EOF'
Использование:
  bash install-plugin.sh fans    плагин MSI Katana Fan и helper
  bash install-plugin.sh pulse   плагин Pulse: CPU, GPU, температуры
  bash install-plugin.sh list    список плагинов
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

backup_existing() {
  local dest=$1
  [[ -e $dest || -L $dest ]] || return 0
  local backup
  mkdir -p "$state"
  backup=$(mktemp -d "$state/plugins.XXXXXXXX")
  chmod 700 "$backup"
  mv -- "$dest" "$backup/${dest##*/}"
  printf 'Резервная копия: %s\n' "$backup"
}

enable_plugin() {
  local id=$1 result
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  result=$(omarchy-shell shell setPluginEnabled "$id" true)
  [[ $result == ok ]] || printf 'Плагин пока недоступен: %s\n' "$id" >&2
}

install_fans() {
  require omarchy-shell sudo python3
  backup_existing "$plugins/msi.katana-fans"
  install -d "$plugins/msi.katana-fans"
  cp -a "$repo/desktop/plugins/msi.katana-fans/." "$plugins/msi.katana-fans/"
  # Install the helper before restoring the driver and fan profile.
  sudo install -D -o root -g root -m 0755 "$repo/desktop/hardware/katana-fans" /usr/local/libexec/katana-fans
  bash "$repo/restore-desktop.sh" --fan-only
  enable_plugin msi.katana-fans
  printf 'Плагин Fans установлен, драйвер и профиль вентиляторов настроены.\n'
}

install_pulse() {
  require omarchy-shell git
  local url revision
  read -r url revision < <(awk -F'\t' '$1 == "plugins" && $2 == "io.github.sanchokusika.pulse" { print $3, $4 }' \
    "$repo/desktop/sources.tsv")
  [[ -n ${url:-} && -n ${revision:-} ]] || die 'В desktop/sources.tsv нет источника Pulse.'

  tmp=$(mktemp -d)
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin "$url"
  git -C "$tmp" fetch -q --depth=1 origin "$revision"
  git -C "$tmp" checkout -q --detach FETCH_HEAD
  rm -rf "$tmp/.git"

  backup_existing "$plugins/io.github.sanchokusika.pulse"
  install -d "$plugins/io.github.sanchokusika.pulse"
  cp -a "$tmp/." "$plugins/io.github.sanchokusika.pulse/"
  enable_plugin io.github.sanchokusika.pulse
  printf 'Плагин Pulse установлен.\n'
}

case "${1:-}" in
  fans) install_fans ;;
  pulse) install_pulse ;;
  list)
    printf 'fans   MSI Katana Fan: обороты и управление вентиляторами\n'
    printf 'pulse  Pulse: процессор, память, GPU, температуры, потребление\n'
    ;;
  -h|--help|'') usage; [[ -n ${1:-} ]] || exit 2 ;;
  *) usage >&2; die "Неизвестный плагин: $1" ;;
esac
