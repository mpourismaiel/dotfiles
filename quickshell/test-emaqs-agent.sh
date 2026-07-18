#!/bin/sh
# test-emaqs-agent.sh — one-off manual test for emaqs's agent-shell surface.
# Simulates exactly what Emacs pushes: a permission-request card, then (a few
# seconds later) an "agent finished" line. Run with emaqs already up.
#
#   ./test-emaqs-agent.sh
set -eu

DEST=org.kde.emaqs.agent
OBJ=/Agent
IFACE=org.kde.emaqs.agent
ID="perm:test-$$"           # unique so re-runs don't collide
BUF="*claude:awesome*"
WS="awesome"

notify() {  # id kind buffer workspace title body actions_json
    gdbus call --session --dest "$DEST" --object-path "$OBJ" \
        --method "$IFACE".Notify "$1" "$2" "$3" "$4" "$5" "$6" "$7" >/dev/null
}
close() {   # id
    gdbus call --session --dest "$DEST" --object-path "$OBJ" \
        --method "$IFACE".Close "$1" >/dev/null
}

echo "→ permission card (Allow / Deny)…"
notify "$ID" permission "$BUF" "$WS" "$BUF" \
    "Edit doom/config.org — replace the agent-shell notification block" \
    '[["allow","Allow"],["reject","Deny"]]'

sleep 4

echo "→ dismissing it and showing the finished line…"
close "$ID"                 # a permission and finished can't both show; drop it first
notify "fin:test-$$" finished "$BUF" "$WS" "$BUF" "Agent finished!" '[]'

echo "done — the finished line has an ✕ to dismiss (or click it to 'switch')."
