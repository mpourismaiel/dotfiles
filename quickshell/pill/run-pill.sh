#!/bin/sh
# run-pill.sh — launch the pill with a Wayland environment resolved at runtime.
#
# After a reboot the login shell often has no WAYLAND_DISPLAY / QT_QPA_PLATFORM
# exported, so Qt falls back to the xcb plugin, fails to connect, and crashes.
# Qt selects its platform plugin before any QML is parsed, so this has to be
# fixed in the launcher rather than in init.qml. We discover the compositor's
# socket from XDG_RUNTIME_DIR and point Qt at it.
#
# Usage:  ./run-pill.sh            (runs quickshell/init.qml next to this script)
#         ./run-pill.sh <args>     (extra args are forwarded to qs)
#         ./run-pill.sh -r [args]  (kill any running instance of this config,
#                                   relaunch detached in the background)

set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "${1:-}" = "-r" ]; then
    shift
    qs kill -p "$dir/init.qml" >/dev/null 2>&1 || true
    setsid -f "$0" "$@" >/dev/null 2>&1
    exit 0
fi

# XDG_RUNTIME_DIR is where the wayland socket lives; derive it if absent.
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR

# If we weren't handed a display, find the compositor's socket.
# Prefer wayland-0, else the first wayland-N socket present.
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
    echo "run-pill.sh: no wayland socket found in $XDG_RUNTIME_DIR" >&2
    exit 1
fi
export WAYLAND_DISPLAY
export QT_QPA_PLATFORM=wayland

# Icon theme. Icons (launcher app list, status/tray glyphs) resolve through Qt's
# icon theme. By default we load the KDE Qt platform theme so they follow KDE's
# configured icon theme (System Settings -> Icons). If Theme.qml sets
# `iconTheme: "Name"`, force that instead via the gtk3 platform theme, which reads
# an icon-theme name from a settings.ini we own (Qt has no env var for it). This
# keeps the override self-contained (XDG_CONFIG_HOME is prefixed, not replaced).
icon_theme=$(sed -n 's/.*property[[:space:]][[:space:]]*string[[:space:]][[:space:]]*iconTheme:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/Theme.qml" 2>/dev/null | head -n1)
if [ -n "${icon_theme:-}" ]; then
    cfg="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-pill"
    mkdir -p "$cfg/gtk-3.0"
    printf '[Settings]\ngtk-icon-theme-name=%s\n' "$icon_theme" >"$cfg/gtk-3.0/settings.ini"
    export XDG_CONFIG_HOME="$cfg:${XDG_CONFIG_HOME:-$HOME/.config}"
    export QT_QPA_PLATFORMTHEME=gtk3
else
    export QT_QPA_PLATFORMTHEME=kde
fi

exec qs -p "$dir/init.qml" "$@"
