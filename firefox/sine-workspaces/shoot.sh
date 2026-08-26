#!/usr/bin/env bash
# Dev helper: screenshot the "testing 2" Firefox window (KWin/Wayland-safe).
# Activates that window by its PID (read from the profile lock) via a KWin script,
# then captures the active window. Never touches any other profile/window.
#
#   ./shoot.sh [output.png]
set -euo pipefail

OUT="${1:-/tmp/sw.png}"
PROFILE="/home/mahdi/.mozilla/firefox/x3iaw2cf.testing 2"

lock=$(readlink "$PROFILE/lock" 2>/dev/null || true)
tpid="${lock##*+}"
if [[ -z "$tpid" ]]; then echo "testing 2 is not running" >&2; exit 1; fi

js=$(mktemp --suffix=.js)
cat >"$js" <<EOF
const target = $tpid;
const wins = (typeof workspace.windowList === "function") ? workspace.windowList() : workspace.clientList();
for (const w of wins) {
  try {
    if (w.pid === target) {
      w.minimized = false;
      if ("activeWindow" in workspace) { workspace.activeWindow = w; } else { workspace.activeClient = w; }
    }
  } catch (e) {}
}
EOF

sid=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js")
qdbus6 org.kde.KWin "/Scripting/Script$sid" org.kde.kwin.Script.run >/dev/null 2>&1 || true
rm -f "$js"
sleep 0.6
spectacle -b -n -a -o "$OUT" >/dev/null 2>&1
echo "captured testing-2 (pid $tpid) → $OUT"
