#!/usr/bin/env bash
# Static validation for sine-workspaces. No browser is launched; nothing live is
# touched. Run this before deploy.sh.
set -euo pipefail

cd "$(dirname "$0")"
fail=0

echo "== JS syntax (node --check) =="
while IFS= read -r -d '' f; do
  if node --check "$f" 2>/tmp/sw-check.err; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; sed 's/^/       /' /tmp/sw-check.err; fail=1
  fi
done < <(find mod -type f \( -name '*.mjs' -o -name '*.js' \) -print0)

echo "== JSON validity (jq) =="
while IFS= read -r -d '' f; do
  if jq empty "$f" >/dev/null 2>&1; then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; fail=1
  fi
done < <(find . -type f -name '*.json' -not -path './mod/config/workspaces.json' -print0)

echo "== entry script referenced in mod.entry.json exists =="
entry=$(jq -r '.scripts.src | keys[0]' mod.entry.json)
if [[ -f "mod/src/$entry" ]]; then
  echo "  ok   mod/src/$entry"
else
  echo "  FAIL mod/src/$entry missing"; fail=1
fi

echo "== chrome manifest present =="
[[ -f mod/sine-chrome.manifest ]] && echo "  ok   mod/sine-chrome.manifest" || { echo "  FAIL manifest"; fail=1; }

if [[ $fail -eq 0 ]]; then
  echo "ALL CHECKS PASSED"
else
  echo "CHECKS FAILED"; exit 1
fi
