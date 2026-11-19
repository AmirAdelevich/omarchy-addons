#!/usr/bin/env bash
# Adds +10 dB digital gain with a brickwall limiter in front of the laptop
# speakers. The physical sink already runs at the hardware maximum, so the only
# way up is gain, and the limiter is what keeps loud material from clipping.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
pipewire_dir="$config_home/pipewire"
unit_dir="$config_home/systemd/user"
sink_name="loudness_boost"
service="loudness-boost.service"
fragment="$pipewire_dir/loudness-boost.conf.d/90-boost.conf"
host_config="$pipewire_dir/loudness-boost.conf"
unit="$unit_dir/$service"

gain_db=10
action=install

usage() {
  cat <<'EOF'
Использование:
  bash install-sound-boost.sh              включить усиление +10 дБ
  bash install-sound-boost.sh --gain 14    включить усиление +14 дБ (1..24)
  bash install-sound-boost.sh --remove     убрать усиление и вернуть обычный выход
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --remove|--uninstall) action=remove ;;
    --gain)
      [[ ${2:-} =~ ^[0-9]{1,2}$ ]] && (( 10#$2 >= 1 && 10#$2 <= 24 )) ||
        die 'Усиление задаётся целым числом от 1 до 24 дБ.'
      gain_db=$((10#$2))
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

command -v pactl >/dev/null 2>&1 || die 'Не найден pactl (PipeWire/PulseAudio).'

sink_present() {
  LC_ALL=C pactl list short sinks 2>/dev/null |
    awk -v s="$1" '$2 == s { found = 1 } END { exit !found }'
}

physical_sink() {
  local sink
  sink="$(LC_ALL=C pactl list short sinks 2>/dev/null |
    awk '$2 ~ /HiFi__Speaker__sink$/ { print $2; exit }')"
  if [[ -z $sink ]]; then
    sink="$(pactl get-default-sink 2>/dev/null || true)"
  fi
  # Resolve through an existing virtual sink (this one, a tuning, EasyEffects).
  if [[ -n $sink && $sink != alsa_output.* && $sink != bluez_output.* ]]; then
    local resolved
    resolved="$(omarchy audio output sink "$sink" 2>/dev/null || true)"
    [[ -n $resolved ]] && sink=$resolved
  fi
  printf '%s\n' "$sink"
}

move_app_streams() {
  local target="$1" id
  # Only real application streams: the filter chain's own output is a sink input
  # without application.name, and moving it back would create a loop.
  local ids=()
  mapfile -t ids < <(LC_ALL=C pactl list sink-inputs 2>/dev/null | awk '
    /^Sink Input #/ { id = substr($3, 2) }
    /application\.name = / { if (id != "") print id }')
  for id in "${ids[@]}"; do
    pactl move-sink-input "$id" "$target" >/dev/null 2>&1 || true
  done
}

if [[ $action == remove ]]; then
  [[ -r $fragment || -r $unit ]] || {
    printf 'Усиление не установлено.\n'
    exit 0
  }

  speakers="$(physical_sink)"

  systemctl --user disable --now "$service" >/dev/null 2>&1 || true
  rm -f "$fragment" "$host_config" "$unit"
  rmdir "$pipewire_dir/loudness-boost.conf.d" 2>/dev/null || true
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  if [[ -n $speakers ]] && sink_present "$speakers"; then
    pactl set-default-sink "$speakers" >/dev/null 2>&1 || true
    move_app_streams "$speakers"
  fi
  printf 'Усиление убрано. Выход: %s\n' "${speakers:-обычный}"
  exit 0
fi

if sink_present omarchy_speaker_tuning; then
  die 'Уже включено штатное усиление Omarchy (speaker tuning). Убери его: omarchy audio tuning off'
fi
if LC_ALL=C pactl list short sinks 2>/dev/null | awk '$2 == "easyeffects_sink" { f = 1 } END { exit !f }'; then
  die 'Запущен EasyEffects. Останови его: systemctl --user disable --now easyeffects.service'
fi

speaker="$(physical_sink)"
[[ -n $speaker ]] || die 'Не найдено выходное аудиоустройство. Проверь pactl list short sinks.'
sink_present "$speaker" || die "Выход не найден: $speaker"

# The limiter and its lookahead. Without it +N dB would hard-clip loud tracks.
if [[ ! -r /usr/lib/lv2/lsp-plugins.lv2/limiter_stereo.ttl ]]; then
  printf 'Устанавливаю lsp-plugins-lv2...\n'
  sudo pacman -S --needed lsp-plugins-lv2
fi

gain_linear="$(awk -v g="$gain_db" 'BEGIN { printf "%.4f", 10 ^ (g / 20) }')"
threshold="$(awk 'BEGIN { printf "%.4f", 10 ^ (-1 / 20) }')"

install -d "$pipewire_dir/loudness-boost.conf.d" "$unit_dir"

cat > "$host_config" <<'HOST'
# Host config for the Loudness Boost filter chain.
#
# The chain runs as its own PipeWire client (pipewire -c loudness-boost.conf)
# rather than as a drop-in in the daemon's config, so it can be started and
# stopped without restarting pipewire-pulse (which drops every client).
#
# Installed by omarchy-addons/install-sound-boost.sh.

context.properties = {
    log.level = 0
}

context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}

context.modules = [
    { name = libpipewire-module-rt
        args = { rtportal.enabled = false }
        flags = [ ifexists nofail ]
    }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
]
HOST

cat > "$fragment" <<EOF
# Loudness boost in front of the internal speakers.
#
# The physical sink already sits at the hardware maximum (ALSA Master/Speaker at
# 0 dB, PipeWire at 100%), so the only way up is digital gain. This virtual sink
# applies +${gain_db} dB and then a brickwall limiter holding peaks at -1 dBFS,
# so quiet material gets louder and loud material does not clip.
#
# The physical sink stays underneath and keeps carrying the volume: the Omarchy
# volume keys resolve through this sink to the one it feeds, so they still move
# real loudness and this chain always sees full-scale input.

context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      node.description = "Loudness Boost"
      media.name       = "Loudness Boost"

      filter.graph = {
        nodes = [
          { type   = lv2
            name   = limiter
            plugin = "http://lsp-plug.in/plugins/lv2/limiter_stereo"
            control = {
              # "alr"/"boost" default to on and make the tone drift with
              # programme level; this is a fixed boost, so switch them off.
              "enabled" = 1
              "alr"     = 0
              "boost"   = 0
              # ${gain_linear} = +${gain_db} dB, ${threshold} = -1 dBFS.
              "g_in"    = ${gain_linear}
              "th"      = ${threshold}
            }
          }
        ]
        inputs  = [ "limiter:in_l" "limiter:in_r" ]
        outputs = [ "limiter:out_l" "limiter:out_r" ]
      }

      audio.channels = 2
      audio.position = [ FL FR ]

      capture.props = {
        node.name   = "${sink_name}"
        media.class = Audio/Sink
      }
      playback.props = {
        node.name     = "${sink_name}_output"
        node.passive  = true
        target.object = "${speaker}"
        # Stay on this output: moving "all streams" to another device must not
        # drag the processing along, and wait for it rather than fall back to
        # whatever default exists when this host starts first.
        node.dont-move     = true
        node.dont-fallback = true
        node.linger        = true
      }
    }
  }
]
EOF

cat > "$unit" <<'UNIT'
[Unit]
Description=Loudness Boost filter chain for the internal speakers
After=pipewire.service wireplumber.service
Requires=pipewire.service
Wants=wireplumber.service
# Restart with the audio daemon, since the chain loses its connection when
# PipeWire goes away.
PartOf=pipewire.service

[Service]
Type=simple
# Hosts the boost as a PipeWire client, so a failure breaks only this service
# and switching it off does not require an audio restart.
ExecStart=/usr/bin/pipewire -c loudness-boost.conf
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
UNIT

chmod 0644 "$host_config" "$fragment" "$unit"

systemctl --user daemon-reload
systemctl --user enable "$service" >/dev/null 2>&1 || true
systemctl --user restart "$service"

for _ in {1..40}; do
  sink_present "$sink_name" && break
  sleep 0.25
done
if ! sink_present "$sink_name"; then
  printf 'Фильтр не запустился. Журнал:\n' >&2
  journalctl --user -u "$service" -n 20 --no-pager >&2 || true
  exit 1
fi

pactl set-default-sink "$sink_name" >/dev/null 2>&1 || true
move_app_streams "$sink_name"

printf 'Усиление включено: +%s дБ с ограничителем на -1 dBFS.\n' "$gain_db"
printf 'Физический выход: %s\n' "$speaker"
printf 'Громкость и клавиши работают как раньше (0-100%% на физическом выходе).\n'
printf 'Убрать: bash install-sound-boost.sh --remove\n'
