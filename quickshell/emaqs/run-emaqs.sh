#!/bin/sh
# run-emaqs.sh — launch emaqs with a Wayland environment resolved at runtime.
# (See run-pill.sh in qs-pill-docs.org for the full rationale.)
#
# Usage:  ./run-emaqs.sh            (runs init.qml next to this script)
#         ./run-emaqs.sh <args>     (extra args are forwarded to qs)

set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
        WAYLAND_DISPLAY=wayland-0
    else
        for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
            case "$sock" in
                *.lock) continue ;;
            esac
            [ -S "$sock" ] || continue
            WAYLAND_DISPLAY=$(basename "$sock")
            break
        done
    fi
fi

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "run-emaqs.sh: no wayland socket found in $XDG_RUNTIME_DIR" >&2
    exit 1
fi
export WAYLAND_DISPLAY
export QT_QPA_PLATFORM=wayland

icon_theme=$(sed -n 's/.*property[[:space:]][[:space:]]*string[[:space:]][[:space:]]*iconTheme:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/Theme.qml" 2>/dev/null | head -n1)
if [ -n "${icon_theme:-}" ]; then
    cfg="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-emaqs"
    mkdir -p "$cfg/gtk-3.0"
    printf '[Settings]\ngtk-icon-theme-name=%s\n' "$icon_theme" >"$cfg/gtk-3.0/settings.ini"
    export XDG_CONFIG_HOME="$cfg:${XDG_CONFIG_HOME:-$HOME/.config}"
    export QT_QPA_PLATFORMTHEME=gtk3
else
    export QT_QPA_PLATFORMTHEME=kde
fi

exec qs -p "$dir/init.qml" "$@"
