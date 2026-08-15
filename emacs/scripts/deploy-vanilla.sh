#!/usr/bin/env bash
# Deploy the repo's vanilla Emacs config, gated on the sandbox checks.
#
# Flow: check-vanilla.sh (batch startup) -> check-daemon-vanilla.sh (daemon
# smoke, catches init-abort bugs the batch check masks) -> ../deploy.sh.
#
# Usage: deploy-vanilla.sh [--dry-run] [--no-check] [--close]
#   --dry-run   forward to ../deploy.sh; never closes the terminal
#   --no-check  skip the sandbox checks (just health-check + copy)
#   --close     close the terminal after a successful REAL deploy. Off by
#               default so interactive runs keep their terminal; the
#               __ignore__/scripts/ `SPC p S` wrapper passes it.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPTS/../.." && pwd)"

DRY_RUN=0 NO_CHECK=0 CLOSE=0 FORWARD=()
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=1; FORWARD+=("--dry-run") ;;
    --no-check) NO_CHECK=1 ;;
    --close)    CLOSE=1 ;;
    *)          FORWARD+=("$arg") ;;
  esac
done

if [[ $NO_CHECK -eq 0 ]]; then
  echo "==> [1/3] Startup check..."
  bash "$SCRIPTS/check-vanilla.sh"
  echo "==> [2/3] Daemon check..."
  bash "$SCRIPTS/check-daemon-vanilla.sh"
else
  echo "==> Skipping sandbox checks (--no-check)."
fi

echo "==> [3/3] Deploying..."
bash "$REPO/emacs/deploy.sh" "${FORWARD[@]}"

echo "==> Deploy complete."

# Close the terminal only when asked (--close) after a successful REAL deploy.
# A dry run never closes. Killing the parent shell dismisses the terminal
# window for terminals that close on shell exit.
if [[ $CLOSE -eq 1 && $DRY_RUN -eq 0 ]]; then
  echo "==> Closing terminal..."
  sleep 1
  kill -HUP "$PPID" 2>/dev/null || true
fi
