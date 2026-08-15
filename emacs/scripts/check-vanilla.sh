#!/usr/bin/env bash
# Smoke-test the vanilla config from the repo WITHOUT touching any live config.
#
# Copies emacs/ into a sandbox init dir under __ignore__/.vanilla-check/ and
# runs a batch startup there. First run downloads all packages via elpaca into
# the sandbox (slow, needs network); later runs reuse the sandbox's elpaca/.
#
# Usage: check-vanilla.sh [--fresh] [--compile]
#   --fresh    wipe the sandbox (incl. downloaded packages) first
#   --compile  additionally byte-compile lisp/ + packages/ and show warnings

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO/emacs"
SANDBOX="$REPO/__ignore__/.vanilla-check"
LOG="$SANDBOX/check.log"

FRESH=0 COMPILE=0
for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    --compile) COMPILE=1 ;;
  esac
done

[[ $FRESH -eq 1 ]] && rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# Sync config into sandbox, preserving its elpaca/ + var/ between runs.
rsync -a --delete \
  --exclude 'var/' --exclude 'elpaca/' \
  "$SRC/" "$SANDBOX/config/"

INIT_DIR="$SANDBOX/config"

echo "==> Batch startup check (sandbox: $INIT_DIR)"
set +e
emacs -Q --batch \
  --eval "(setq user-emacs-directory \"$INIT_DIR/\")" \
  -l "$INIT_DIR/early-init.el" \
  -l "$INIT_DIR/init.el" \
  --eval '(progn
            (elpaca-wait)
            ;; Elpaca build failures are async and non-fatal; surface them.
            (require (quote cl-lib))
            (if-let* ((failed (cl-loop for (id . e) in (elpaca--queued)
                                       when (eq (elpaca<-status e) (quote failed))
                                       collect id)))
                (message "MP-ELPACA-FAILED: %S" failed)
              (message "MP-STARTUP-OK")))' \
  >"$LOG" 2>&1
status=$?
set -e

if grep -q "MP-ELPACA-FAILED" "$LOG"; then
  echo "ELPACA PACKAGE BUILD FAILURES:"
  grep "MP-ELPACA-FAILED" "$LOG"
  grep -iE "elpaca.*(failed|error)" "$LOG" | head -10
  exit 1
fi
if [[ $status -ne 0 ]] || ! grep -q "MP-STARTUP-OK" "$LOG"; then
  echo "STARTUP FAILED (exit $status). Last 40 log lines:"
  tail -40 "$LOG"
  exit 1
fi
echo "  startup OK"

if grep -iE "error|warning" "$LOG" | grep -vE "Compiler-macro|docstring|native-comp" >"$SANDBOX/warnings.txt"; then
  echo "  notable log lines (see $SANDBOX/warnings.txt):"
  head -15 "$SANDBOX/warnings.txt"
fi

if [[ $COMPILE -eq 1 ]]; then
  echo "==> Byte-compile check"
  emacs -Q --batch \
    --eval "(setq user-emacs-directory \"$INIT_DIR/\")" \
    -l "$INIT_DIR/early-init.el" \
    -l "$INIT_DIR/init.el" \
    --eval "(progn
              (elpaca-wait)
              (setq byte-compile-error-on-warn nil)
              (dolist (dir (list (expand-file-name \"lisp\" user-emacs-directory)
                                 (expand-file-name \"packages\" user-emacs-directory)))
                (byte-recompile-directory dir 0 'force))
              (message \"MP-COMPILE-DONE\"))" \
    >"$SANDBOX/compile.log" 2>&1 || true
  grep -q "MP-COMPILE-DONE" "$SANDBOX/compile.log" \
    && echo "  compile pass done (warnings in $SANDBOX/compile.log)" \
    || { echo "  compile pass FAILED:"; tail -30 "$SANDBOX/compile.log"; exit 1; }
fi

echo "==> PASS"
