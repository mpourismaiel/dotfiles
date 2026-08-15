#!/usr/bin/env bash
# Daemon-path smoke test: start the sandbox config as a REAL forking daemon
# (the way systemd runs it) and assert every module loaded and representative
# deferred commands from the LATE modules are bound.
#
# This catches failures that the batch check (check-vanilla.sh) masks: elpaca
# processes queues synchronously under --batch, so a queue conflict that aborts
# init mid-load only shows up in the async daemon path.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SANDBOX="$REPO/__ignore__/.vanilla-check/config"
SERVER=vanilladaemoncheck

[[ -d "$SANDBOX/elpaca" ]] || { echo "Run check-vanilla.sh first (need built packages)."; exit 1; }

cleanup() {
  emacsclient -s "$SERVER" --eval '(progn (setq kill-emacs-hook nil) (kill-emacs))' \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Fresh config copy into the sandbox (keeps its elpaca/ + var/).
rsync -a --delete --exclude 'var/' --exclude 'elpaca/' "$REPO/emacs/" "$SANDBOX/"

echo "==> Starting daemon ($SERVER) with the sandbox config..."
emacs --daemon="$SERVER" --init-directory="$SANDBOX/" >/dev/null 2>&1 &
for _ in $(seq 1 90); do
  emacsclient -s "$SERVER" --eval 't' >/dev/null 2>&1 && break
  sleep 1
done
emacsclient -s "$SERVER" --eval 't' >/dev/null 2>&1 || { echo "Daemon never came up"; exit 1; }

echo "==> Asserting modules loaded + deferred commands bound..."
result=$(emacsclient -s "$SERVER" --eval '
  (let ((missing-mods
         (seq-remove #'"'"'featurep
                     (list (quote mp-core) (quote mp-evil) (quote mp-keys)
                           (quote mp-completion) (quote mp-ui) (quote mp-treesit)
                           (quote mp-lsp) (quote mp-workspaces) (quote mp-org)
                           (quote mp-langs) (quote mp-tools) (quote mp-ai))))
        (missing-cmds
         (seq-remove #'"'"'commandp
                     (list (quote magit-status) (quote dirvish) (quote agent-shell)
                           (quote eca) (quote color-rg-search-input-in-project)
                           (quote clutch-query-console) (quote docker)))))
    (if (or missing-mods missing-cmds)
        (format "FAIL modules=%S commands=%S" missing-mods missing-cmds)
      "MP-DAEMON-OK"))' 2>&1)

echo "  $result"
[[ "$result" == *MP-DAEMON-OK* ]] || { echo "==> DAEMON CHECK FAILED"; exit 1; }
echo "==> PASS"
