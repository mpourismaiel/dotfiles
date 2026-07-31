#!/bin/sh
# deploy.sh — validate the emaqs sources (via ./check.sh), then copy them to the
# live Quickshell config at ~/.config/quickshell/emaqs/.
#
# USER-ONLY: this script touches the live config. AI agents must never run it —
# they validate with ./check.sh and leave deploying to the user.
#
# Nothing is copied until every check passes, and only changed files are copied
# (so the running overlay reloads once, only when something actually changed).
set -eu
cd "$(dirname "$0")"
DEST="$HOME/.config/quickshell/emaqs"

./check.sh

# --- Copy changed files to the live config ------------------------------------
mkdir -p "$DEST"
copied=0
for f in *; do
    case "$f" in deploy.sh|check.sh|README.md|CLAUDE.md) continue ;; esac
    [ -f "$f" ] || continue
    if ! cmp -s "$f" "$DEST/$f"; then
        cp -p "$f" "$DEST/$f"
        echo "copied: $f"
        copied=$((copied + 1))
    fi
done
# Files that exist live but not here are left alone — just surfaced.
for f in "$DEST"/*; do
    b=$(basename "$f")
    [ -e "$b" ] || echo "note: $b exists in live config but not in the repo"
done
if [ "$copied" -eq 0 ]; then
    echo "done: live config already up to date"
else
    echo "done: $copied file(s) copied — the running emaqs reloads on its own"
fi
