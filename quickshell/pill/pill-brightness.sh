#!/bin/sh
# pill-brightness.sh — change display brightness and flash a brightness burst on
# the pill. Uses brightnessctl (backlight). Bind up/down to the brightness media
# keys in KDE's Shortcuts settings (see qs-pill-docs.org).
#
# Usage:  pill-brightness.sh up|down [step]   (step is a percentage, default 5)

set -eu

action=${1:-up}
step=${2:-5}
init="$HOME/.config/quickshell/pill/init.qml"

# brightnessctl -m -> "device,class,cur,pct%,max"; take field 4 (pct) as 0..1.
read_bri() {
    pct=$(brightnessctl -m | cut -d, -f4 | tr -d '%')
    bri=$(awk "BEGIN { printf \"%.4f\", $pct / 100 }")
}

read_bri
prev=$bri

case "$action" in
    up)   brightnessctl set "${step}%+" >/dev/null ;;
    down) brightnessctl set "${step}%-" >/dev/null ;;
    *)    echo "usage: $0 up|down [step]" >&2; exit 1 ;;
esac

read_bri

qs ipc -p "$init" call media brightness "$bri" "$prev" 2>/dev/null || true
