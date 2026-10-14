#!/usr/bin/env bash
# shoot.sh — off-screen screenshots of the mpv UI (shelf library, Actions
# dropdown, uosc controls) under Xvfb with synthetic media. Never touches the
# live Wayland session or ~/Videos: the library is pointed at generated clips
# and thumbnails go to a scratch cache.
#
#   mpv/shoot.sh [outdir]        default outdir: /tmp/mpv-shots
#
# Needs: Xvfb, xdotool, socat, ImageMagick (import), ffmpeg.
# mpv runs with vo=gpu on llvmpipe and --display-fps-override=60: Xvfb reports
# no refresh rate, and uosc derives its render timer from display-fps (it
# never paints otherwise).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-/tmp/mpv-shots}
W=${W:-1600}; H=${H:-900}; DPY=${DPY:-:97}
LIB=$OUT/lib; CACHE=$OUT/cache; SOCK=$OUT/sock
mkdir -p "$OUT" "$CACHE"

# ---- synthetic library ---------------------------------------------------
if [ ! -d "$LIB" ]; then
  echo "generating synthetic media in $LIB"
  mkdir -p "$LIB/Recordings" "$LIB/Clips/Shorts" "$LIB/Music"
  gen() { ffmpeg -nostdin -loglevel error -y -f lavfi -i "$2" -t "$3" -pix_fmt yuv420p -c:v libx264 -preset ultrafast "$1"; }
  gen "$LIB/Welcome tour.mp4"                       "testsrc2=size=640x360:rate=30" 12
  gen "$LIB/Nebula timelapse.mkv"                   "mandelbrot=size=640x360:rate=25" 10
  gen "$LIB/Recordings/2026-10-12 11-02-33.mkv"     "life=size=640x360:rate=25:mold=10:ratio=0.1:death_color=#1b1712:life_color=#d9a441" 15
  gen "$LIB/Recordings/2026-10-11 18-40-05.mkv"     "smptehdbars=size=640x360:rate=25" 8
  gen "$LIB/Recordings/2026-10-09 09-15-51.mkv"     "rgbtestsrc=size=640x360:rate=25" 6
  gen "$LIB/Recordings/2026-10-08 22-01-17.mkv"     "cellauto=size=640x360:rate=25:rule=110" 30
  gen "$LIB/Clips/Best goal ever.mov"              "testsrc=size=640x360:rate=25" 5
  gen "$LIB/Clips/Shorts/Loop.mp4"                  "sierpinski=size=640x360:rate=25" 4
  gen "$LIB/Clips/Shorts/Very long file name that needs to be ellipsized nicely.mp4" "gradients=size=640x360:rate=25" 7
  ffmpeg -nostdin -loglevel error -y -f lavfi -i "sine=frequency=440" -t 5 "$LIB/Music/Tone A.wav"
  ffmpeg -nostdin -loglevel error -y -f lavfi -i "rgbtestsrc=size=640x360" -frames:v 1 "$LIB/Clips/Frame.png"
  # mix mtimes so the newest-first sort is visible
  touch -d '2026-10-12 11:02' "$LIB/Recordings/2026-10-12 11-02-33.mkv"
  touch -d '2026-10-11 18:40' "$LIB/Recordings/2026-10-11 18-40-05.mkv"
  touch -d '2026-10-09 09:15' "$LIB/Recordings/2026-10-09 09-15-51.mkv"
  touch -d '2026-10-08 22:01' "$LIB/Recordings/2026-10-08 22-01-17.mkv"
fi

# ---- X server + mpv ------------------------------------------------------
if ! xdpyinfo -display "$DPY" >/dev/null 2>&1; then
  Xvfb "$DPY" -screen 0 "${W}x${H}x24" >/dev/null 2>&1 &
  XVFB_PID=$!
  sleep 1
fi
export DISPLAY=$DPY
MPV_PID=
launch() { # launch WxH
  rm -f "$SOCK"
  LIBGL_ALWAYS_SOFTWARE=1 mpv --config-dir="$HERE" --vo=gpu --gpu-context=x11 --display-fps-override=60 --dither=no \
      --idle=yes --force-window=yes --geometry="$1" \
      --input-ipc-server="$SOCK" \
      --script-opts="shelf-dirs=$LIB,shelf-cache_dir=$CACHE,shelf-state_file=$OUT/state.json,SimpleHistory-auto_run_incognito_mode=yes" \
      --msg-level=all=warn,shelf=info >>"$OUT/mpv.log" 2>&1 &
  MPV_PID=$!
  for _ in $(seq 40); do [ -S "$SOCK" ] && break; sleep 0.25; done
}
stop() {
  [ -n "$MPV_PID" ] || return 0
  ipc '{"command":["quit"]}' 2>/dev/null || true
  sleep 0.5
  kill "$MPV_PID" 2>/dev/null || true
  MPV_PID=
}
cleanup() {
  stop
  [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT

ipc()  { printf '%s\n' "$1" | socat -t 1 - "$SOCK" >/dev/null 2>&1 || true; }
cmd()  { ipc "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1:]}))' "$@")"; }
shot() { sleep "${2:-0.6}"; import -display "$DPY" -window root "$OUT/$1.png"; echo "  $1.png"; }
move() { xdotool mousemove "$1" "$2"; sleep 0.25; }

: >"$OUT/mpv.log"
rm -f "$OUT/state.json"  # fresh collapse/accordion state every run
launch "${W}x${H}"
sleep 3  # let the library scan + thumbnails land
echo "shooting into $OUT"

# 1. idle library (root open, subfolders collapsed), hovering the first card
move 170 230
shot 01-library-idle 0.8

# 1b. expand the "Clips" folder by clicking its header, then hover a card in it
move 100 401; xdotool click 1; sleep 0.4
move 170 470
shot 01b-library-folder-open 0.6

# 1c. accordion on (collapses "Clips" again, only the root stays open); opening
#     "Shorts" then closes the root section too
cmd script-message-to shelf set-accordion yes
sleep 0.3
move 100 453; xdotool click 1; sleep 0.4
move 800 300
shot 01c-library-accordion 0.6
cmd script-message-to shelf set-accordion no
move 100 137; xdotool click 1; sleep 0.3

# 2. keyboard selection, then scrolled down to the deeper folders
cmd keypress DOWN; cmd keypress RIGHT
shot 02-library-keyboard 0.5
for _ in 1 2 3 4 5 6; do cmd keypress WHEEL_DOWN; done
shot 02b-library-scrolled 0.6
cmd keypress HOME

# 3. Actions dropdown via the ☰ button, hovering "Playback"
move 60 22; xdotool click 1; sleep 0.3
move 60 193
shot 03-actions-dropdown 0.6

# 4. playback: load a clip, pause, hover the bottom controls
cmd keypress ESC
cmd loadfile "$LIB/Welcome tour.mp4"
sleep 2
cmd set pause yes
move 800 870
shot 04-playback-controls 0.8

# 5. playback: top strip revealed
move 400 20
shot 05-playback-topbar 0.5

# 6. playback: dropdown open over the video, flyout for Subtitles
move 60 22; xdotool click 1; sleep 0.3
move 60 289
shot 06-playback-actions 0.6
cmd keypress ESC

# 7. library opened over the paused video
cmd script-binding shelf/toggle-library
sleep 0.8
move 426 230
shot 07-library-over-video 0.8
cmd script-binding shelf/toggle-library

# 8. uosc menu (bottom-left ≡ / `menu` key — reads the same #! annotations)
cmd script-binding uosc/menu
shot 08-uosc-menu 0.8
cmd keypress ESC

# 8b. playlist view over the paused video (current item marked)
cmd script-binding shelf/playlist
sleep 0.8
move 800 300
shot 08b-playlist 0.8
cmd script-binding shelf/playlist

# 9. small window: fresh 960x600 instance, idle library
stop
launch 960x600
sleep 2.5
move 170 230
shot 09-library-small 0.8

echo "log:"; grep -v "^$" "$OUT/mpv.log" | tail -20 || true
