#!/usr/bin/env bash
#
# deploy.sh — health-check every package under doom/packages/ and, only if all
# checks pass, sync them into the running Doom config at
# ~/.config/doom/packages/<name>/.
#
# config.org loads each package from there via `mp/require-package'. Tangling
# config.org runs this automatically (see the `org-babel-tangle' advice in
# config.org's Overview section); you can also run it by hand at any time.
#
# A "package" is any immediate subdirectory of this script's directory. Its
# files are copied verbatim (README.md is left behind — it is documentation,
# not runtime code). Health checks are reader/parser-only, so they need neither
# Doom nor the packages' own dependencies to be installed:
#   *.el  -> Emacs `check-parens' (balanced parens / strings / comments)
#   *.py  -> python3 -m py_compile (syntax)
#   *.sh  -> bash -n (syntax)
#
# Exit non-zero (and deploy nothing) if any check fails, so a broken edit can
# never reach the live config.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${DOOMDIR:-$HOME/.config/doom}/packages"

EMACS="${EMACS:-emacs}"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n'  "$*"; }

check_el() {
  # Read the file in emacs-lisp-mode (correct syntax table) and assert that
  # parens, strings and comments all balance. Returns non-zero with a location
  # on failure.
  "$EMACS" -Q --batch --eval "(condition-case e
      (with-temp-buffer
        (insert-file-contents \"$1\")
        (emacs-lisp-mode)
        (check-parens))
    (error (message \"%s\" (error-message-string e)) (kill-emacs 1)))" 2>&1
}

check_py() { python3 -m py_compile "$1" 2>&1; }
check_sh() { bash -n "$1" 2>&1; }

# ---- 1. Health check every file in every package -------------------------
fail=0
pkgs=()
for dir in "$SRC"/*/; do
  [ -d "$dir" ] || continue
  pkg="$(basename "$dir")"
  pkgs+=("$pkg")
  while IFS= read -r -d '' f; do
    rel="${f#"$SRC"/}"
    case "$f" in
      *.el) out="$(check_el "$f")" || { red "  ✗ $rel"; echo "$out" | sed 's/^/      /'; fail=1; continue; } ;;
      *.py) out="$(check_py "$f")" || { red "  ✗ $rel"; echo "$out" | sed 's/^/      /'; fail=1; continue; } ;;
      *.sh) out="$(check_sh "$f")" || { red "  ✗ $rel"; echo "$out" | sed 's/^/      /'; fail=1; continue; } ;;
      *) continue ;;
    esac
    dim "  ✓ $rel"
  done < <(find "$dir" -type f \( -name '*.el' -o -name '*.py' -o -name '*.sh' \) -print0)
done

if [ "$fail" -ne 0 ]; then
  red "health check failed — nothing deployed"
  exit 1
fi
green "health check passed (${#pkgs[@]} packages)"

# ---- 2. Sync each package into the live config ---------------------------
mkdir -p "$DEST"
for pkg in "${pkgs[@]}"; do
  rsync -a --delete --exclude 'README.md' --exclude '__pycache__' \
    "$SRC/$pkg/" "$DEST/$pkg/"
done
green "deployed to $DEST"
