#!/usr/bin/env bash
# setup-transcribe.sh — one-time setup for the pill's voice-to-text pipeline:
# whisper venv + model download, prompt files, KDE shortcuts, API key. Re-runnable.
set -euo pipefail

VENV="$HOME/.local/share/pill-transcribe/venv"
PILL="$HOME/.config/quickshell/pill"
APPS="$HOME/.local/share/applications"
WHISPER_MODEL="${WHISPER_MODEL:-small}"
LOCAL_MODEL="${LOCAL_MODEL:-qwen2.5:3b}"

# pull the local (ollama) polish model — the "local" option in the Transcribe
# tab's Polish setting. Additive: touches nothing else.
setup_local() {
    if ! command -v ollama >/dev/null 2>&1; then
        echo "!! ollama not installed — the local polish model needs it."
        echo "   Install: sudo pacman -S ollama  &&  systemctl enable --now ollama"
        return 1
    fi
    echo "==> pulling local polish model '$LOCAL_MODEL' via ollama"
    ollama pull "$LOCAL_MODEL"
}

# `setup-transcribe.sh local` ONLY adds the local model — it does NOT re-run the
# venv / shortcuts / API-key setup, so it safely adds local polish to an existing
# install without rewriting anything. Pick the model with
# LOCAL_MODEL=llama3.2:3b setup-transcribe.sh local
if [ "${1:-}" = "local" ]; then
    setup_local
    exit $?
fi

echo "==> venv at $VENV (python 3.12 — ctranslate2 wheels lag system python)"
uv venv --python 3.12 "$VENV"
uv pip install --python "$VENV/bin/python" \
    faster-whisper anthropic keyring nvidia-cublas-cu12 nvidia-cudnn-cu12

echo "==> pre-downloading whisper model '$WHISPER_MODEL'"
"$VENV/bin/python" - "$WHISPER_MODEL" <<'PY'
import sys
from faster_whisper import WhisperModel
WhisperModel(sys.argv[1], device="cpu", compute_type="int8")
print("model '%s' ready" % sys.argv[1])
PY

echo "==> default prompt files (~/.config/quickshell/transcribe/)"
"$VENV/bin/python" "$PILL/voicebridge.py" init >/dev/null && echo "    ok"

echo "==> KDE global shortcuts (Meta+X record, Meta+Shift+X record+polish)"
mkdir -p "$APPS"
write_desktop() {
    cat > "$APPS/$1.desktop" <<EOF
[Desktop Entry]
Exec=qs -p $HOME/.config/quickshell/pill/init.qml ipc call pill $2
Name=$3
NoDisplay=true
StartupNotify=false
Type=Application
X-KDE-GlobalAccel-CommandShortcut=true
EOF
}
write_desktop net.local.qs-voice        voiceToggle       "Quickshell - Voice Transcribe"
write_desktop net.local.qs-voice-polish voicePolishToggle "Quickshell - Voice Transcribe + Polish"
kwriteconfig6 --file kglobalshortcutsrc \
    --group services --group net.local.qs-voice.desktop --key _launch "Meta+X"
kwriteconfig6 --file kglobalshortcutsrc \
    --group services --group net.local.qs-voice-polish.desktop --key _launch "Meta+Shift+X"
systemctl --user restart plasma-kglobalaccel.service || \
    echo "    (couldn't restart kglobalaccel — log out/in to pick the combos up)"

if [ ! -e /usr/lib/ladspa/librnnoise_ladspa.so ]; then
    echo "!! RNNoise LADSPA plugin missing — noise suppression will silently degrade."
    echo "   Install it with: sudo pacman -S noise-suppression-for-voice"
fi

echo "==> done. Meta+X = quick raw note; Meta+Shift+X = memo menu (type/polish/org)."
echo "    Polish backend + API keys + local-model download are all in the pill now:"
echo "    Volume ▸ Transcribe tab (Claude / Gemini keys with an eye toggle, or a"
echo "    Download button for the local ollama model). No key prompt here anymore."
echo "    Memos are stored in ~/Documents/memos (see the Clipboard ▸ Memos tab)."
echo "    Org memos go to ~/org/inbox.org (TODO + parsed DEADLINE) / ~/org/notes.org."
echo "    (Local models still need 'ollama' installed: sudo pacman -S ollama.)"
