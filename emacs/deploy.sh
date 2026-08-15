#!/usr/bin/env bash
# Deploy the vanilla Emacs config from this repo to ~/.config/emacs-vanilla/.
#
# Health-checks first (parens balance / readability of every .el), then rsyncs.
# Never touches ~/.config/emacs (Doom) or ~/.config/doom, except a ONE-TIME
# read-only seed of private data (private.el, connections.json) into the target
# when the target doesn't have them yet.
#
# Usage: deploy.sh [--dry-run]

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${EMACS_VANILLA_DIR:-$HOME/.config/emacs-vanilla}"
DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="--dry-run"

echo "==> Health check: reading every .el under $SRC"
fail=0
while IFS= read -r -d '' file; do
  if ! emacs -Q --batch --eval "(with-temp-buffer
      (insert-file-contents \"$file\")
      (goto-char (point-min))
      (condition-case err
          (while t (read (current-buffer)))
        (end-of-file nil)
        (error (kill-emacs 1))))" 2>/dev/null; then
    echo "  UNREADABLE (unbalanced parens?): $file"
    fail=1
  fi
done < <(find "$SRC" -name '*.el' -not -path '*/var/*' -not -path '*/elpaca/*' -print0)
[[ $fail -eq 0 ]] || { echo "Health check FAILED — not deploying."; exit 1; }
echo "  OK"

for required in init.el early-init.el lisp/mp-core.el; do
  [[ -f "$SRC/$required" ]] || { echo "Missing $required — not deploying."; exit 1; }
done

echo "==> Syncing to $TARGET ${DRY_RUN:+(dry run)}"
mkdir -p "$TARGET"
# Config files are replaced wholesale; runtime state (var/, elpaca/, the
# eca/ server binary downloaded by eca-emacs, tree-sitter/, emojis/) and
# machine-private data in the target are preserved. scripts/ is repo-only
# tooling (see emacs/scripts/) that must not ship to the live config.
# NOTE: eca/ MUST stay excluded — without it, --delete wipes the downloaded
# eca server on every deploy and AI inline completion silently dies.
rsync -a --delete $DRY_RUN \
  --exclude 'var/' \
  --exclude 'elpaca/' \
  --exclude 'eca/' \
  --exclude 'tree-sitter/' \
  --exclude 'emojis/' \
  --exclude 'scripts/' \
  --exclude 'private.el' \
  --exclude 'connections.json' \
  --exclude '__pycache__/' \
  "$SRC/" "$TARGET/"

if [[ -z "$DRY_RUN" ]]; then
  # One-time seed of private data (read-only w.r.t. the Doom config).
  for pair in "private.el" "connections.json"; do
    if [[ ! -f "$TARGET/$pair" && -f "$HOME/.config/doom/$pair" ]]; then
      cp "$HOME/.config/doom/$pair" "$TARGET/$pair"
      echo "  seeded $pair from ~/.config/doom (one-time copy)"
    fi
  done
fi

echo "==> Done. Launch with: emacs --init-directory=$TARGET"
