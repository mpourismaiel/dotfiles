#!/bin/sh
# run-pill.sh — launch the pill with a Wayland environment resolved at runtime.
#
# After a reboot the login shell often has no WAYLAND_DISPLAY / QT_QPA_PLATFORM
# exported, so Qt falls back to the xcb plugin, fails to connect, and crashes.
# Qt selects its platform plugin before any QML is parsed, so this has to be
# fixed in the launcher rather than in pill.qml. We discover the compositor's
# socket from XDG_RUNTIME_DIR and point Qt at it.
#
# Usage:  ./run-pill.sh            (runs quickshell/pill.qml next to this script)
#         ./run-pill.sh <args>     (extra args are forwarded to qs)

set -eu

dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

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

exec qs -p "$dir/pill.qml" "$@"
