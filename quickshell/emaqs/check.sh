#!/bin/sh
# check.sh — validate the emaqs sources in this directory. Touches NOTHING live:
# no copy, no deploy, safe to run any time (agents included). deploy.sh runs
# this first, then copies to the live config — deploying is the user's job.
set -eu
cd "$(dirname "$0")"

fail() { printf '\n\033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }

# --- 1. Python: parse every bridge script (no .pyc artifacts left behind) ----
for f in *.py; do
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" \
        || fail "python syntax error in $f"
done
echo "ok: python ($(ls *.py | wc -l) files)"

# --- 2. Shell scripts ---------------------------------------------------------
for f in *.sh; do
    bash -n "$f" || fail "shell syntax error in $f"
done
echo "ok: shell ($(ls *.sh | wc -l) files)"

# --- 3. QML: load the whole config headless with qs ---------------------------
# Offscreen there is no Wayland, so a *correct* config stops at exactly two
# ERROR lines: "Failed to load configuration" caused by "No PanelWindow backend
# loaded". Any other ERROR/WARN line is a real problem. This compiles and
# type-checks every referenced component (but not children inside the
# PanelWindow delegate — see ../qs-emaqs-docs.org "Validating").
LOG=$(mktemp)
timeout 60 env QT_QPA_PLATFORM=offscreen qs -p "$PWD/init.qml" >"$LOG" 2>&1 || true
sed -i 's/\x1b\[[0-9;]*m//g' "$LOG"
BAD=$(grep -E 'ERROR|WARN' "$LOG" | grep -v 'Failed to load configuration' \
        | grep -v 'No PanelWindow backend loaded' || true)
if [ -n "$BAD" ]; then
    echo "$BAD" >&2
    fail "qs reported errors (full log: $LOG)"
fi
grep -q 'No PanelWindow backend loaded' "$LOG" \
    || { cat "$LOG" >&2; fail "qs check did not reach the expected end state (log above)"; }
rm -f "$LOG"
echo "ok: qml (qs offscreen load)"
echo "checks passed (nothing deployed — run ./deploy.sh yourself to go live)"
