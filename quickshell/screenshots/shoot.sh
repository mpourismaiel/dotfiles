#!/usr/bin/env bash
# shoot.sh — regenerate off-screen, mock-data screenshots of the pill + emaqs.
#
# Safe by construction: copies the repo sources (quickshell/{pill,emaqs}/) to a
# BUILD dir (default /tmp/shot — NEVER the live ~/.config/quickshell), neuters the
# python bridges, copies the mock state objects + harnesses from this repo dir into
# the build tree, and renders via FloatingWindow harnesses that never instantiate a
# NotificationServer / winbridge / DBus name. Output PNGs + contact sheets land in
# $SHOT_DIR/out.
#
# Usage:  quickshell/screenshots/shoot.sh              # full pass: every pill + emaqs state
#         quickshell/screenshots/shoot.sh menu-tetris  # fast: only pill states whose name
#                                                       #   contains this substring (pill-only,
#                                                       #   skips emaqs + contact sheets)
#         SHOT_DIR=/path/to/build shoot.sh             # override the build dir
#
# The target arg is for the quick per-edit loop while iterating on one pane; run the
# no-arg full pass when you're done to confirm nothing else regressed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SHOT="${SHOT_DIR:-/tmp/shot}"
PW="$SHOT/pill" EW="$SHOT/emaqs" OUT="$SHOT/out"
# a name-substring passed as $1 (or SHOT_ONLY) renders just the matching pill states
TARGET="${1:-${SHOT_ONLY:-}}"
export SHOT_ONLY="$TARGET"
mkdir -p "$PW" "$EW" "$OUT"

echo "==> copying repo sources to $SHOT (temp build dir, not live)"
for f in "$REPO"/quickshell/pill/*;  do case "$(basename "$f")" in deploy.sh|check.sh|README.md|CLAUDE.md) ;; *) cp -p "$f" "$PW"/ ;; esac; done
for f in "$REPO"/quickshell/emaqs/*; do case "$(basename "$f")" in deploy.sh|check.sh|README.md|CLAUDE.md) ;; *) cp -p "$f" "$EW"/ ;; esac; done

echo "==> installing mock state objects + harnesses from the repo"
cp "$HERE"/pill/*.qml  "$PW"/
cp "$HERE"/emaqs/*.qml "$EW"/
# fill the @OUT@ placeholder (kept out of the repo sources so they're path-agnostic)
sed -i "s#@OUT@#$OUT#g" "$PW"/harness.qml "$PW"/MockClip.qml

echo "==> neutering python bridges (DBus safety)"
for f in "$PW/winbridge.py" "$PW/clipbridge.py" "$PW/orgbridge.py" "$PW/hledgerbridge.py" \
         "$PW/gitbridge.py" "$PW/gcalbridge.py" \
         "$EW/fswatch.py" "$EW/emaqsbridge.py" "$EW/agentbridge.py"; do
  [ -e "$f" ] && printf '#!/usr/bin/env python\nimport time\nwhile True: time.sleep(3600)\n' > "$f" || true
done

RUN() { env WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=kde qs -p "$1"; }
export -f RUN

# emaqs + contact sheets only in a full pass — a targeted run is pill-only and
# leaves every other PNG untouched (the harness overwrites just the matches).
if [ -z "$TARGET" ]; then
  echo "==> generating the emaqs harness"
  python "$HERE/mk-emaqs.py" "$EW" "$OUT" >/dev/null

  echo "==> rendering emaqs states"
  rm -f "$OUT"/emaqs-*.png
  ( cd "$EW" && timeout 25 bash -c 'RUN harness.qml' ) 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'error|warning' | grep -viE 'qt\.qpa' || true
fi

if [ -z "$TARGET" ]; then
  echo "==> rendering pill states (full)"
  rm -f "$OUT"/pill-*.png
else
  echo "==> rendering pill states matching '$TARGET' (targeted)"
fi
( cd "$PW" && timeout 35 bash -c 'RUN harness.qml' ) 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'error|warning' | grep -viE 'qt\.qpa' || true

if [ -z "$TARGET" ]; then
  echo "==> building contact sheets"
  cd "$OUT"
  if ls pill-*.png >/dev/null 2>&1; then
    magick montage $(ls -1v pill-*.png) -tile 3x -geometry '+12+12' -background '#0d0b0e' \
      -bordercolor '#0d0b0e' -border 6 "$OUT/_pill-contact.png"
  fi
  if ls emaqs-*.png >/dev/null 2>&1; then
    magick montage $(ls -1v emaqs-*.png) -tile 2x -geometry '+12+12' -background '#0d0b0e' \
      -bordercolor '#0d0b0e' -border 6 "$OUT/_emaqs-contact.png"
  fi
fi

echo "==> done. PNGs in $OUT"
if [ -z "$TARGET" ]; then
  ls -1v "$OUT"/pill-*.png "$OUT"/emaqs-*.png 2>/dev/null | sed 's#.*/##'
else
  ls -1v "$OUT"/pill-*"$TARGET"*.png 2>/dev/null | sed 's#.*/##'
fi
