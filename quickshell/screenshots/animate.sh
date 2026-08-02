#!/usr/bin/env bash
# animate.sh — capture pill ANIMATIONS as mp4 + gif (+ a frame contact strip) so
# they can be eyeballed and debugged off-screen. Sibling of shoot.sh: same
# safe-by-construction build (copies repo sources to a temp dir, neuters the python
# bridges, renders via a FloatingWindow harness that never touches DBus / the live
# pill) — but it plays each animation scene and grabs a burst of frames, then
# encodes them with ffmpeg.
#
# Scenes live in pill/anim.qml (`_scenes`): currently `deadlines` (org-deadlines
# menu drop-in) and `droplet` (notification water-droplet drop-out).
#
# Usage:  quickshell/screenshots/animate.sh            # build dir = /tmp/shot
#         SHOT_DIR=/path/to/build animate.sh
#         FPS=25 animate.sh                             # must match anim.qml frameMs
# Output: $SHOT_DIR/out/<scene>.mp4, <scene>.gif, <scene>-strip.png; raw frames in
#         $SHOT_DIR/out/frames/<scene>/.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SHOT="${SHOT_DIR:-/tmp/shot}"
FPS="${FPS:-25}"                         # keep in sync with anim.qml `frameMs` (40ms → 25)
PW="$SHOT/pill" OUT="$SHOT/out"
mkdir -p "$PW" "$OUT/frames"

echo "==> copying repo sources to $SHOT (temp build dir, not live)"
for f in "$REPO"/quickshell/pill/*; do case "$(basename "$f")" in deploy.sh|check.sh|README.md|CLAUDE.md) ;; *) cp -p "$f" "$PW"/ ;; esac; done

echo "==> installing mock state objects + the anim harness from the repo"
cp "$HERE"/pill/*.qml "$PW"/
sed -i "s#@OUT@#$OUT#g" "$PW"/anim.qml

echo "==> neutering python bridges (DBus safety)"
for f in "$PW/winbridge.py" "$PW/clipbridge.py" "$PW/orgbridge.py" "$PW/hledgerbridge.py"; do
  [ -e "$f" ] && printf '#!/usr/bin/env python\nimport time\nwhile True: time.sleep(3600)\n' > "$f" || true
done

echo "==> rendering animation frames"
rm -rf "$OUT"/frames/* 2>/dev/null || true
RUN() { env WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
            QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=kde qs -p "$1"; }
export -f RUN
( cd "$PW" && timeout 40 bash -c 'RUN anim.qml' ) 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'error|warning' | grep -viE 'qt\.qpa' || true

echo "==> encoding mp4 + gif + contact strip per scene"
shopt -s nullglob
# scenes = distinct prefixes of frames/<scene>-fNNNN.png
scenes=$(for f in "$OUT"/frames/*-f????.png; do basename "$f" | sed -E 's/-f[0-9]{4}\.png$//'; done | sort -u)
for scene in $scenes; do
  frames=("$OUT"/frames/"$scene"-f????.png)
  [ "${#frames[@]}" -gt 0 ] || { echo "!! no frames for $scene"; continue; }

  # mp4 (h264, yuv420p, even dims)
  ffmpeg -y -loglevel error -framerate "$FPS" -i "$OUT/frames/$scene-f%04d.png" \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p \
    "$OUT/$scene.mp4"

  # gif (two-pass palette for clean colour)
  ffmpeg -y -loglevel error -framerate "$FPS" -i "$OUT/frames/$scene-f%04d.png" \
    -vf "fps=$FPS,scale=iw:ih:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
    "$OUT/$scene.gif"

  # contact strip: ~10 evenly-spaced frames montaged into one PNG for a quick look
  n="${#frames[@]}"; picks=()
  for i in $(seq 0 9); do
    idx=$(( i * (n - 1) / 9 ))
    picks+=("${frames[$idx]}")
  done
  magick montage "${picks[@]}" -tile 5x2 -geometry '+6+6' -background '#0d0b0e' \
    -bordercolor '#2a2622' -border 1 "$OUT/$scene-strip.png"

  echo "ok  $scene: ${#frames[@]} frames -> $scene.mp4 / .gif / -strip.png"
done

echo "==> done. Videos + strips in $OUT"
ls -1 "$OUT"/*.mp4 "$OUT"/*.gif "$OUT"/*-strip.png 2>/dev/null | sed 's#.*/##'
