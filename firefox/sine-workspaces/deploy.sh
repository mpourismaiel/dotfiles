#!/usr/bin/env bash
# Deploy sine-workspaces into a Firefox profile's Sine mods directory.
#
#   ./deploy.sh                       # deploys to the default "testing 2" profile
#   ./deploy.sh "/path/to/profile"    # deploys to another profile (explicit opt-in)
#   ./deploy.sh --close               # close the terminal after a successful deploy
#                                     # (used by __ignore__/scripts/ SPC p S wrapper)
#
# This copies files only. It NEVER launches or kills Firefox, and it only ever
# writes inside the target profile's chrome/sine-mods/ tree. Your live
# workspaces.json is preserved (excluded from the sync).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$PWD"

CLOSE=0
PROFILE="/home/mahdi/.mozilla/firefox/x3iaw2cf.testing 2"
for arg in "$@"; do
  case "$arg" in
    --close) CLOSE=1 ;;
    *) PROFILE="$arg" ;;
  esac
done

MODS_DIR="$PROFILE/chrome/sine-mods"
DEST="$MODS_DIR/sine-workspaces"
MODS_JSON="$MODS_DIR/mods.json"

# --- safety checks --------------------------------------------------------
if [[ ! -d "$PROFILE" ]]; then
  echo "ERROR: profile not found: $PROFILE" >&2; exit 1
fi
if [[ ! -d "$MODS_DIR" ]]; then
  echo "ERROR: $MODS_DIR does not exist — is Sine installed in this profile?" >&2; exit 1
fi

# --- static validation (aborts the deploy on failure) ---------------------
./check.sh

echo "Deploying to: $PROFILE"

# --- 1. sync mod payload (preserve the user's live config) ----------------
mkdir -p "$DEST"
rsync -a --delete --exclude 'config/workspaces.json' "$REPO/mod/" "$DEST/"
echo "  synced mod payload → $DEST"

# --- 2. register the mod in mods.json (idempotent, preserves other mods) ---
tmp="$(mktemp)"
if [[ -f "$MODS_JSON" ]]; then
  jq --argjson entry "$(cat "$REPO/mod.entry.json")" \
     '. + {"sine-workspaces": $entry}' "$MODS_JSON" > "$tmp"
else
  jq -n --argjson entry "$(cat "$REPO/mod.entry.json")" \
     '{"sine-workspaces": $entry}' > "$tmp"
fi
mv "$tmp" "$MODS_JSON"
echo "  registered sine-workspaces in $(basename "$MODS_JSON")"

echo
echo "Done. Restart the \"testing 2\" Firefox instance (or Sine → Rebuild) to apply."

# --- close the terminal only when asked (SPC p S wrapper passes --close) ---
# A failed check/deploy exits non-zero above, so we never reach here on failure.
if [[ "$CLOSE" -eq 1 ]]; then
  echo "closing terminal…"
  sleep 1
  kill -HUP "$PPID" 2>/dev/null || true
fi
