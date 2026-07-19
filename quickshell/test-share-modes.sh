#!/usr/bin/env bash
# test-share-modes.sh — exercise the pill + emaqs screen-share / camera / mic
# behaviours without needing a real screen-sharing session.
#
# What each trigger maps to in the QML:
#   screencast  -> a PipeWire "Stream/Output/Video" node (root.screenRecording).
#                  Faked here with `gst-launch videotestsrc ! pipewiresink mode=provide`,
#                  which registers exactly that media.class. Drives: the pulsing red
#                  dot, pill auto-DND (+ "you missed N" summary on stop), emaqs DND
#                  bell, and the on-air equalizer.
#   camera      -> any process holding /dev/video* open (root.cameraInUse, polled by
#                  fuser every ~2s). Faked by holding an fd open. Drives: the camera
#                  glyph and the on-air equalizer ("your video is on").
#   mic         -> the default audio source's mute state (root.micUnmuted). Wavy line
#                  when open (amplitude follows your live voice — SPEAK to see it),
#                  flat fainter line when muted.
#
# Usage:
#   ./test-share-modes.sh demo            # guided walkthrough of every mode
#   ./test-share-modes.sh share-on|share-off
#   ./test-share-modes.sh cam-on|cam-off
#   ./test-share-modes.sh mic-on|mic-off
#   ./test-share-modes.sh notify [N]      # send N test notifications (default 3)
#   ./test-share-modes.sh status
#   ./test-share-modes.sh stop            # release camera + screencast, unmute
set -u

CAST_PID=/tmp/pill-test-screencast.pid
CAM_PID=/tmp/pill-test-camera.pid
VIDEO=/dev/video0
SRC='@DEFAULT_AUDIO_SOURCE@'

note() { printf '\033[1;33m»\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

share_on() {
    if [ -f "$CAST_PID" ] && kill -0 "$(cat "$CAST_PID")" 2>/dev/null; then
        note "screencast already running"; return
    fi
    # mode=provide registers a standalone Stream/Output/Video node (a "screencast").
    gst-launch-1.0 -q videotestsrc is-live=true \
        ! video/x-raw,width=640,height=360,framerate=15/1 \
        ! pipewiresink mode=provide >/tmp/pill-test-screencast.log 2>&1 &
    echo $! > "$CAST_PID"
    ok "screencast STARTED — red dot on the pill; DND on (pill + emaqs bell); equalizer visible"
}

share_off() {
    if [ -f "$CAST_PID" ]; then
        kill "$(cat "$CAST_PID")" 2>/dev/null
        rm -f "$CAST_PID"
        ok "screencast STOPPED — DND off; a 'you missed N notifications' popup appears if any arrived"
    else
        note "no screencast running"
    fi
}

cam_on() {
    if [ -f "$CAM_PID" ] && kill -0 "$(cat "$CAM_PID")" 2>/dev/null; then
        note "camera already held"; return
    fi
    if [ ! -e "$VIDEO" ]; then note "no $VIDEO on this machine"; return; fi
    # hold the video node open so `fuser /dev/video*` reports it busy.
    sleep 100000 3<"$VIDEO" &
    echo $! > "$CAM_PID"
    ok "camera HELD ($VIDEO busy) — camera glyph + equalizer (video on). fuser polls every ~2s."
}

cam_off() {
    if [ -f "$CAM_PID" ]; then
        kill "$(cat "$CAM_PID")" 2>/dev/null
        rm -f "$CAM_PID"
        ok "camera RELEASED"
    else
        note "camera not held"
    fi
}

mic_on()  { wpctl set-mute "$SRC" 0 >/dev/null 2>&1; ok "mic UNMUTED — wavy line; SPEAK to see it follow your voice"; }
mic_off() { wpctl set-mute "$SRC" 1 >/dev/null 2>&1; ok "mic MUTED — flat straight line in the clock's colour"; }

notify() {
    n="${1:-3}"
    for i in $(seq 1 "$n"); do
        notify-send -a "Test $i" "Test notification $i" "This would pop — unless you're sharing your screen."
        sleep 0.3
    done
    ok "sent $n notifications (silenced + counted while sharing; pop normally otherwise)"
}

status() {
    printf 'screencast: '; { [ -f "$CAST_PID" ] && kill -0 "$(cat "$CAST_PID")" 2>/dev/null && echo RUNNING; } || echo off
    printf 'camera:     '; { [ -f "$CAM_PID" ]  && kill -0 "$(cat "$CAM_PID")"  2>/dev/null && echo HELD;    } || echo off
    printf 'mic:        '; wpctl get-volume "$SRC" 2>/dev/null
    printf 'video node: '; pw-dump 2>/dev/null | grep -q '"media.class": "Stream/Output/Video"' && echo present || echo none
}

stop() { share_off; cam_off; mic_on; ok "cleaned up"; }

demo() {
    note "DEMO — watch the pill (top-centre). Steps auto-advance; Ctrl-C to bail (then run: $0 stop)"
    echo
    note "1/6  video on + mic open → wavy equalizer. SPEAK now — the line should follow your voice."
    mic_on; cam_on; sleep 8
    echo
    note "2/6  mute the mic → the wave falls to a flat, fainter horizontal line."
    mic_off; sleep 5
    echo
    note "3/6  video off → equalizer disappears."
    cam_off; sleep 3
    echo
    note "4/6  start 'screen sharing' → pulsing red dot, DND on (pill + emaqs bell), equalizer back (mic still muted = flat)."
    mic_on; share_on; sleep 5
    echo
    note "5/6  three notifications arrive WHILE sharing → all silenced (straight to history, no popup)."
    notify 3; sleep 3
    echo
    note "6/6  stop sharing → DND lifts and a single 'You missed 3 notifications' popup appears."
    share_off; sleep 3
    echo
    stop
    ok "demo done"
}

cmd="${1:-}"; shift || true
case "$cmd" in
    share-on)  share_on ;;
    share-off) share_off ;;
    cam-on)    cam_on ;;
    cam-off)   cam_off ;;
    mic-on)    mic_on ;;
    mic-off)   mic_off ;;
    notify)    notify "${1:-3}" ;;
    status)    status ;;
    stop)      stop ;;
    demo)      demo ;;
    *) sed -n '2,30p' "$0"; exit 1 ;;
esac
