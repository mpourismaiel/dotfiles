#!/usr/bin/env bash
# Deploy sine-workspaces into a Firefox profile's Sine mods directory.
#
#   ./deploy.sh <profile-dir>            # deploy to the given Firefox profile
#   ./deploy.sh --close <profile-dir>    # ...and close the terminal on success
#                                        # (used by the __ignore__/scripts SPC p S wrapper)
#
# The profile path is a required argument — this script is committed, so it must
# not hardcode a machine-specific profile. Personal paths live in the (ignored)
# __ignore__/scripts/ wrapper.
#
# This copies files only. It NEVER launches or kills Firefox, and it only ever
# writes inside the target profile's chrome/sine-mods/ tree. Your live
# workspaces.json is preserved (excluded from the sync).
set -euo pipefail

cd "$(dirname "$0")"
REPO="$PWD"

CLOSE=0
PROFILE=""
for arg in "$@"; do
  case "$arg" in
    --close) CLOSE=1 ;;
    *) PROFILE="$arg" ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "ERROR: no profile path given." >&2
  echo "Usage: deploy.sh [--close] <profile-dir>" >&2
  exit 1
fi

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
