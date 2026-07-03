#!/usr/bin/env bash
# Tangle the literate org configs into plain files and bundle them for release.
#
# This is the single source of truth for "building" the config so that people
# who don't use Emacs can grab ready-to-use files. It's called both by the
# GitHub Actions release workflow and by hand:
#
#     bin/tangle-release.sh            # -> ./dist/*.tar.gz
#     bin/tangle-release.sh /some/dir  # -> /some/dir/*.tar.gz
#
# Nothing is written into the working tree; everything happens in a temp dir,
# so the generated files never need to be tracked in git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/dist}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Batch-tangle an org file with a clean Emacs (-Q: ignore the user's config).
# Tangling is pure text extraction, so no language runtimes are needed and no
# code in the blocks is evaluated.
tangle() {
  emacs -Q --batch \
    --eval "(require 'org)" \
    --eval "(setq org-confirm-babel-evaluate nil)" \
    --eval "(org-babel-tangle-file \"$1\")"
}

# Tangle an org file whose blocks use *relative* tangle paths, redirecting the
# output into a chosen dir. Org resolves relative targets against the buffer's
# file name, so we visit the real file and rebind that name into the temp dir —
# nothing is copied and the working tree is never written to.
tangle_into() {
  local org="$1" out="$2"
  mkdir -p "$out"
  emacs -Q --batch \
    --eval "(require 'org)" \
    --eval "(setq org-confirm-babel-evaluate nil)" \
    --eval "(with-current-buffer (find-file-noselect \"$org\")
              (setq buffer-file-name \"$out/$(basename "$org")\"
                    default-directory \"$out/\")
              (set-buffer-modified-p nil)
              (org-babel-tangle))"
}

echo ">> Tangling quickshell/qs-pill-docs.org"
# The pill blocks tangle to absolute ~/.config/quickshell/pill/... paths, so we
# point HOME at the staging dir and collect the result from there.
mkdir -p "$STAGE/qs-home"
HOME="$STAGE/qs-home" tangle "$ROOT/quickshell/qs-pill-docs.org"

echo ">> Tangling doom/config.org"
# The doom blocks tangle to relative paths (config.el/init.el/packages.el);
# redirect them straight into the staging dir.
tangle_into "$ROOT/doom/config.org" "$STAGE/doom"

echo ">> Packaging into $OUT"
mkdir -p "$OUT"

# Extract into ~/.config/quickshell/  ->  gives you ~/.config/quickshell/pill/
tar -czf "$OUT/quickshell-pill.tar.gz" \
  -C "$STAGE/qs-home/.config/quickshell" pill

# Extract into ~/.config/doom/ (or ~/.doom.d/)
tar -czf "$OUT/doom-config.tar.gz" \
  -C "$STAGE/doom" config.el init.el packages.el

echo ">> Done:"
ls -la "$OUT"/*.tar.gz
