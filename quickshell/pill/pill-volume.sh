#!/bin/sh
# pill-volume.sh — ask the pill to raise/lower/mute the *default sink* and flash
# the volume burst. The pill performs the change on Pipewire.defaultAudioSink (the
# device its UI shows as selected), so the keys always hit that device — no wpctl
# `@DEFAULT_AUDIO_SINK@` lag. Bind up/down/mute to the audio media keys in KDE's
# Shortcuts settings (see qs-pill-docs.org).
#
# Usage:  pill-volume.sh up|down|mute

set -eu

action=${1:-up}
init="$HOME/.config/quickshell/pill/init.qml"

case "$action" in
    up|down|mute) ;;
    *) echo "usage: $0 up|down|mute" >&2; exit 1 ;;
esac

# Needs the pill's config path (-p) + the session's WAYLAND_DISPLAY, both present
# in a Plasma session. Quiet no-op if the pill isn't running.
qs ipc -p "$init" call media volume "$action" 2>/dev/null || true
