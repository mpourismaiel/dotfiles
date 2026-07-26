#!/usr/bin/env bash
# shoot.sh — regenerate off-screen, mock-data screenshots of the pill + emaqs.
#
# Safe by construction: tangles the org sources to a BUILD dir (default /tmp/shot —
# NEVER the live ~/.config/quickshell), neuters the python bridges, copies the mock
# state objects + harnesses from this repo dir into the build tree, and renders via
# FloatingWindow harnesses that never instantiate a NotificationServer / winbridge /
# DBus name. Output PNGs + contact sheets land in $SHOT_DIR/out.
#
# Usage:  quickshell/screenshots/shoot.sh          # build dir = /tmp/shot
#         SHOT_DIR=/path/to/build shoot.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SHOT="${SHOT_DIR:-/tmp/shot}"
PW="$SHOT/pill" EW="$SHOT/emaqs" OUT="$SHOT/out"
mkdir -p "$PW" "$EW" "$OUT"

echo "==> tangling org sources to $SHOT (temp build dir, not live)"
sed 's#~/.config/quickshell/pill/#'"$PW"'/#g'  "$REPO/quickshell/qs-pill-docs.org"  > "$SHOT/pill-src.org"
sed 's#~/.config/quickshell/emaqs/#'"$EW"'/#g' "$REPO/quickshell/qs-emaqs-docs.org" > "$SHOT/emaqs-src.org"
emacs --batch -Q -l org "$SHOT/pill-src.org"  --eval '(org-babel-tangle)' 2>&1 | tail -1
emacs --batch -Q -l org "$SHOT/emaqs-src.org" --eval '(org-babel-tangle)' 2>&1 | tail -1

echo "==> installing mock state objects + harnesses from the repo"
cp "$HERE"/pill/*.qml  "$PW"/
cp "$HERE"/emaqs/*.qml "$EW"/
# fill the @OUT@ placeholder (kept out of the repo sources so they're path-agnostic)
sed -i "s#@OUT@#$OUT#g" "$PW"/harness.qml "$PW"/MockClip.qml

echo "==> neutering python bridges (DBus safety)"
for f in "$PW/winbridge.py" "$PW/clipbridge.py" "$PW/orgbridge.py" "$PW/hledgerbridge.py" \
         "$EW/fswatch.py" "$EW/emaqsbridge.py" "$EW/agentbridge.py"; do
  [ -e "$f" ] && printf '#!/usr/bin/env python\nimport time\nwhile True: time.sleep(3600)\n' > "$f" || true
done

echo "==> generating the emaqs harness"
python "$HERE/mk-emaqs.py" "$EW" "$OUT" >/dev/null

RUN() { env WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=kde qs -p "$1"; }
export -f RUN

echo "==> rendering emaqs states"
rm -f "$OUT"/emaqs-*.png
( cd "$EW" && timeout 25 bash -c 'RUN harness.qml' ) 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'error|warning' | grep -viE 'qt\.qpa' || true

echo "==> rendering pill states"
rm -f "$OUT"/pill-*.png
( cd "$PW" && timeout 35 bash -c 'RUN harness.qml' ) 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'error|warning' | grep -viE 'qt\.qpa' || true

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

echo "==> done. PNGs in $OUT"
ls -1v "$OUT"/pill-*.png "$OUT"/emaqs-*.png 2>/dev/null | sed 's#.*/##'
