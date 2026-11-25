#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
unit_dir="$config_home/systemd/user"
local_bin="${HOME}/.local/bin"
chrome_unit=chrome-parser-guard.service
hermes_unit=hermes-dashboard.service
chrome_script=chrome-parser-keepalive
hermes_bin="$HOME/.hermes/hermes-agent/venv/bin/hermes"

usage() {
  cat <<'EOF'
Использование:
  bash install-runtime-settings.sh status
  bash install-runtime-settings.sh trim [on|off|status]
  bash install-runtime-settings.sh autostart [on|off|status]

Без on/off/status скрипт сначала показывает состояние и предлагает действие.
Переключение TRIM меняет discard для Btrfs и требует sudo.
EOF
}

trim_status() {
  local root_options timer_enabled timer_active
  root_options=$(findmnt -n -o OPTIONS / 2>/dev/null || true)
  timer_enabled=$(systemctl is-enabled fstrim.timer 2>/dev/null || true)
  timer_active=$(systemctl is-active fstrim.timer 2>/dev/null || true)
  [[ -n $timer_enabled ]] || timer_enabled=disabled
  [[ -n $timer_active ]] || timer_active=inactive
  printf 'Файловая система /: %s\n' "$(findmnt -n -o FSTYPE / 2>/dev/null || printf 'не определена')"
  case ",$root_options," in
    *,discard=async,*) printf 'TRIM: включён через discard=async на /\n' ;;
    *,discard=sync,*) printf 'TRIM: включён через синхронный discard на /\n' ;;
    *,discard=none,*) printf 'TRIM: отключён через discard=none на /\n' ;;
    *) printf 'TRIM: для / discard не указан\n' ;;
  esac
  printf 'Btrfs-разделы и режим discard:\n'
  findmnt -rn -t btrfs -o TARGET,OPTIONS 2>/dev/null |
    awk 'BEGIN { FS=" " } { mode="выключен"; if ($2 ~ /(^|,)discard=async(,|$)/) mode="async"; else if ($2 ~ /(^|,)discard=sync(,|$)/) mode="sync"; printf "  %s: %s\n", $1, mode }'
  printf 'Таймер fstrim.timer: %s, %s\n' "$timer_enabled" "$timer_active"
  if grep -Eq 'allow-discards|rd\.luks\.options=[^ ]*discard' /proc/cmdline 2>/dev/null; then
    printf 'LUKS: параметр передачи discard разрешён ядром\n'
  else
    printf 'LUKS: разрешение передачи discard в параметрах ядра не найдено\n'
  fi
}

autostart_status() {
  local unit state
  for unit in "$chrome_unit" "$hermes_unit"; do
    state=$(systemctl --user is-enabled "$unit" 2>/dev/null || true)
    [[ -n $state ]] || state=disabled
    local active
    active=$(systemctl --user is-active "$unit" 2>/dev/null || true)
    [[ -n $active ]] || active=inactive
    printf '%s: %s, %s\n' "$unit" "$state" "$active"
  done
}

status() {
  trim_status
  printf '\n'
  autostart_status
}

backup_if_changed() {
  local source=$1 destination=$2 mode=$3 backup
  mkdir -p "$(dirname -- "$destination")"
  if [[ -e $destination ]] && cmp -s -- "$source" "$destination"; then
    printf 'Уже актуально: %s\n' "$destination"
    return 0
  fi
  if [[ -e $destination ]]; then
    backup="$destination.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$destination" "$backup"
    printf 'Резервная копия: %s\n' "$backup"
  fi
  install -m "$mode" -- "$source" "$destination"
  printf 'Установлено: %s\n' "$destination"
}

remove_legacy_hypr_start() {
  local autostart_file="$config_home/hypr/autostart.lua"
  local old_line='o.exec_on_start("systemctl --user start chrome-parser-guard.service")'
  local backup
  [[ -f $autostart_file ]] || return 0
  grep -Fq -- "$old_line" "$autostart_file" || return 0
  backup="$autostart_file.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a -- "$autostart_file" "$backup"
  sed -i '\|o.exec_on_start("systemctl --user start chrome-parser-guard.service")|d' "$autostart_file"
  printf 'Убран старый запуск Chrome из Hyprland; резервная копия: %s\n' "$backup"
}

autostart_on() {
  local chrome_available=false
  if [[ -x /opt/google/chrome/google-chrome ]] || command -v google-chrome-stable >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1; then
    chrome_available=true
    backup_if_changed "$repo_dir/desktop/systemd/user/$chrome_unit" "$unit_dir/$chrome_unit" 644
    backup_if_changed "$repo_dir/desktop/systemd/user/$chrome_script" "$local_bin/$chrome_script" 755
    systemctl --user daemon-reload
    systemctl --user enable "$chrome_unit" >/dev/null
    if systemctl --user is-active --quiet graphical-session.target; then
      systemctl --user start "$chrome_unit"
    fi
  else
    printf 'Google Chrome не найден; автозапуск Chrome пропущен.\n' >&2
  fi

  if [[ -x $hermes_bin ]]; then
    backup_if_changed "$repo_dir/desktop/systemd/user/$hermes_unit" "$unit_dir/$hermes_unit" 644
    systemctl --user daemon-reload
    systemctl --user enable --now "$hermes_unit"
  elif systemctl --user cat "$hermes_unit" >/dev/null 2>&1; then
    systemctl --user enable --now "$hermes_unit"
  else
    printf 'Hermes Agent не найден; автозапуск Hermes пропущен.\n' >&2
  fi

  remove_legacy_hypr_start
  systemctl --user daemon-reload
  if [[ $chrome_available == true ]] && systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user start "$chrome_unit"
  fi
  printf '\n'
  autostart_status
}

autostart_off() {
  systemctl --user disable --now "$chrome_unit" >/dev/null 2>&1 || true
  systemctl --user disable --now "$hermes_unit" >/dev/null 2>&1 || true
  remove_legacy_hypr_start
  printf 'Автозапуск Chrome и Hermes выключен. Файлы служб оставлены для повторного включения.\n\n'
  autostart_status
}

trim_apply_as_root() {
  local action=$1 backup= targets target new_mode tmp_fstab current_mode
  [[ $EUID -eq 0 ]] || { printf 'Внутренняя команда доступна только через sudo.\n' >&2; exit 2; }
  [[ $action == on || $action == off ]] || { printf 'Режим должен быть on или off.\n' >&2; exit 2; }
  [[ $(findmnt -n -o FSTYPE / 2>/dev/null || true) == btrfs ]] || {
    printf 'Переключение discard этим скриптом поддерживает корневую файловую систему Btrfs.\n' >&2
    exit 1
  }
  mapfile -t targets < <(findmnt --fstab -rn -t btrfs -o TARGET)
  ((${#targets[@]} > 0)) || { printf 'В /etc/fstab не найдены точки монтирования Btrfs.\n' >&2; exit 1; }
  if [[ $action == on ]]; then new_mode=async; else new_mode=none; fi
  declare -A previous=()
  for target in "${targets[@]}"; do
    if mountpoint -q -- "$target"; then
      current_mode=$(findmnt -n -o OPTIONS --target "$target" | tr ',' '\n' | sed -n 's/^discard=//p' | head -n 1)
      case "$current_mode" in
        async) previous["$target"]=async ;;
        sync) previous["$target"]=sync ;;
        *) previous["$target"]=none ;;
      esac
    fi
  done

  tmp_fstab=$(mktemp /etc/fstab.omarchy-addons.XXXXXX)
  python3 - "$action" >"$tmp_fstab" <<'PY'
import pathlib, re, sys

action = sys.argv[1]
lines = pathlib.Path('/etc/fstab').read_text().splitlines(keepends=True)
output = []
for line in lines:
    match = re.match(r'^(\s*\S+\s+\S+\s+\S+\s+)(\S+)(.*)$', line)
    if not match or line.lstrip().startswith('#'):
        output.append(line)
        continue
    fields = line.split()
    if len(fields) < 4 or fields[2] != 'btrfs':
        output.append(line)
        continue
    desired = 'discard=async' if action == 'on' else 'discard=none'
    options = []
    replaced = False
    for option in fields[3].split(','):
        if option.startswith('discard='):
            if not replaced:
                options.append(desired)
                replaced = True
        else:
            options.append(option)
    if not replaced:
        options.append(desired)
    replacement = ','.join(options)
    output.append(match.group(1) + replacement + match.group(3))
if not any(re.match(r'^\s*\S+\s+\S+\s+btrfs\s+', line) for line in lines if not line.lstrip().startswith('#')):
    raise SystemExit('В /etc/fstab не найдены записи Btrfs.')
sys.stdout.write(''.join(output))
PY
  if ! cmp -s /etc/fstab "$tmp_fstab"; then
    backup="/etc/fstab.bak.omarchy-addons.$(date +%Y%m%d-%H%M%S.%N)"
    cp -a /etc/fstab "$backup"
    cat "$tmp_fstab" >/etc/fstab
    printf 'Резервная копия /etc/fstab: %s\n' "$backup"
  fi
  rm -f -- "$tmp_fstab"

  for target in "${targets[@]}"; do
    mountpoint -q -- "$target" || continue
    [[ ${previous[$target]} == "$new_mode" ]] && continue
    if ! mount -o "remount,discard=$new_mode" -- "$target"; then
      printf 'Не удалось перемонтировать %s; возвращаю прежние настройки.\n' "$target" >&2
      [[ -z $backup ]] || cp -a "$backup" /etc/fstab
      for rollback_target in "${targets[@]}"; do
        [[ -n ${previous[$rollback_target]:-} ]] || continue
        mount -o "remount,discard=${previous[$rollback_target]}" -- "$rollback_target" || true
      done
      exit 1
    fi
  done

  if ! systemctl disable --now fstrim.timer || ! systemctl stop fstrim.service; then
    printf 'Не удалось выключить fstrim.timer; возвращаю прежние настройки.\n' >&2
    [[ -z $backup ]] || cp -a "$backup" /etc/fstab
    for target in "${targets[@]}"; do
      [[ -n ${previous[$target]:-} ]] || continue
      mount -o "remount,discard=${previous[$target]}" -- "$target" || true
    done
    exit 1
  fi
  printf 'TRIM %s: Btrfs использует discard=%s; fstrim.timer выключен.\n' "$action" "$new_mode"
}

choose_action() {
  local area=$1 answer
  if [[ $area == trim ]]; then trim_status; else autostart_status; fi
  printf '\nВыбери: on — включить, off — выключить, status — только проверить: '
  if [[ ! -t 0 ]] && { exec 3</dev/tty; } 2>/dev/null; then
    read -r -u 3 answer || return 0
  else
    read -r answer || return 0
  fi
  case "$area:$answer" in
    trim:on|trim:off) trim_apply "$answer" ;;
    trim:status) trim_status ;;
    autostart:on) autostart_on ;;
    autostart:off) autostart_off ;;
    autostart:status) autostart_status ;;
    *) printf 'Выбери on, off или status.\n' >&2; return 2 ;;
  esac
}

trim_apply() {
  local action=$1
  [[ $action == on || $action == off ]] || { usage >&2; return 2; }
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { printf 'Для переключения TRIM требуется sudo.\n' >&2; return 1; }
    sudo -- bash "$repo_dir/install-runtime-settings.sh" --root-trim "$action"
    return
  fi
  trim_apply_as_root "$action"
}

case "${1:-status}" in
  status) status ;;
  trim)
    case "${2:-}" in
      on|off) trim_apply "$2" ;;
      status) trim_status ;;
      '') choose_action trim ;;
      -h|--help) usage ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  autostart)
    case "${2:-}" in
      on) autostart_on ;;
      off) autostart_off ;;
      status) autostart_status ;;
      '') choose_action autostart ;;
      -h|--help) usage ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  --root-trim) trim_apply_as_root "${2:-}" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
