#!/usr/bin/env bash
# Launch the vanilla Emacs config.
#
# Default: run the DEPLOYED config (~/.config/emacs-vanilla), i.e. what
# deploy.sh last shipped. With --staging, run the check-sandbox copy instead
# (useful to try the repo state without deploying).
#
# Usage: run-vanilla.sh [--staging] [extra emacs args...]

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${EMACS_VANILLA_DIR:-$HOME/.config/emacs-vanilla}"

if [[ "${1:-}" == "--staging" ]]; then
  shift
  TARGET="$REPO/__ignore__/.vanilla-check/config"
  [[ -d "$TARGET" ]] || { echo "No staging sandbox; run check-vanilla.sh first."; exit 1; }
fi

[[ -f "$TARGET/init.el" ]] || { echo "No config at $TARGET (deploy first)."; exit 1; }
exec emacs --init-directory="$TARGET" "$@"
