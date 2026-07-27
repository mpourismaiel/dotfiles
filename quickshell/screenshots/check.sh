#!/usr/bin/env bash
# check.sh — regression smoke test for the pill + emaqs screenshot harnesses.
# Re-tangles + renders (via shoot.sh) and asserts: both harnesses loaded, every
# expected stage produced a non-trivial PNG, and qs emitted no ERROR/WARNING.
# Exit non-zero on any failure — a broken component fails to load its stage and the
# PNG goes missing / tiny. Usage: quickshell/screenshots/check.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SHOT_DIR:-/tmp/shot}/out"
fail=0

EMAQS_STATES=(collapsed working finished permission bar menu confirm)
PILL_STATES=(resting resting-rec dashboard menu-network menu-volume menu-bluetooth \
             menu-battery menu-clipboard menu-calendar menu-finance menu-finance-add \
             menu-finance-wishlist menu-finance-forecast menu-finance-plan menu-notifhistory notif-stack \
             power-hush power-blaze power-ledger power-split)

echo "==> running shoot.sh"
if ! bash "$HERE/shoot.sh" 2>&1 | grep -iE 'error|warning' | grep -viE 'qt\.qpa'; then :; else
  echo "!! qs reported errors/warnings"; fail=1
fi

need() {  # need <prefix> <state...>
  local pfx=$1; shift
  for s in "$@"; do
    local f
    f=$(ls -1v "$OUT/$pfx"-*-"$s".png 2>/dev/null | head -1)
    if [ -z "$f" ]; then echo "!! MISSING: $pfx $s"; fail=1
    elif [ "$(stat -c%s "$f")" -lt 900 ]; then echo "!! TINY (render failed?): $f"; fail=1
    else echo "ok  $(basename "$f")"; fi
  done
}
echo "==> checking emaqs states"; need emaqs "${EMAQS_STATES[@]}"
echo "==> checking pill states";  need pill  "${PILL_STATES[@]}"

if [ "$fail" -eq 0 ]; then echo "PASS — all $((${#EMAQS_STATES[@]}+${#PILL_STATES[@]})) stages rendered clean"; else echo "FAIL"; fi
exit $fail
