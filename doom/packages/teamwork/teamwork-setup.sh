#!/usr/bin/env bash
#
# teamwork-setup.sh — securely store Teamwork.com API credentials.
#
# Credentials are written to the system keyring via the Secret Service API
# (gnome-keyring / KWallet), NOT to any file in this repo. The API key is
# encrypted at rest and auto-unlocked at login. Read it back from Python with
# `secretstorage` or from the shell with `secret-tool lookup service teamwork-timesheet`.
#
# Usage:
#   ./teamwork-setup.sh                 # interactive: add an account (name, site, key)
#   ./teamwork-setup.sh --print         # list configured account names
#   ./teamwork-setup.sh --remove NAME   # delete one account from the keyring
#
# Multiple accounts are supported: each is stored as its own keyring item, told
# apart by a user-chosen `account` name. The Emacs commands teamwork-account-add
# / teamwork-account-view / teamwork-account-delete drive this from inside Emacs.
#
set -euo pipefail

SERVICE="teamwork-timesheet"     # keyring lookup attribute; must match the sidecar
LABEL="Teamwork Timesheet (API key)"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }

# --- dependency checks -------------------------------------------------------
for dep in curl secret-tool python3; do
  command -v "$dep" >/dev/null 2>&1 || die "missing dependency: $dep"
done

# --- subcommands -------------------------------------------------------------
case "${1:-}" in
  --remove)
    name="${2:-}"
    [ -n "$name" ] || die "usage: $0 --remove ACCOUNT_NAME (see --print for names)"
    if secret-tool clear service "$SERVICE" account "$name"; then
      ok "Removed Teamwork account '$name' from the keyring."
    else
      die "no account named '$name' found (see --print)"
    fi
    exit 0
    ;;
  --print)
    info "Configured Teamwork accounts:"
    names="$(secret-tool search --all service "$SERVICE" 2>/dev/null \
             | sed -n 's/^attribute\.account = //p')"
    if [ -n "$names" ]; then
      printf '%s\n' "$names" | sed 's/^/  - /'
    else
      echo "  (none — run without arguments to add one)"
    fi
    echo "Use the Emacs command teamwork-account-view for site/user details."
    exit 0
    ;;
  ""|--setup|--add) : ;;   # fall through to interactive setup
  *) die "unknown option: $1 (use --print or --remove NAME)" ;;
esac

# --- interactive setup -------------------------------------------------------
info "Teamwork.com credential setup"
echo "This stores your API key in the system keyring (encrypted, not in the repo)."
echo

# Account name: a short label you pick to tell accounts apart (e.g. 'work',
# 'client-x'). Stored as the keyring `account` attribute; re-using a name
# updates that account in place.
read -rp "Account name (a label for this account, e.g. work or client-x): " account_name
account_name="$(printf '%s' "$account_name" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
[ -n "$account_name" ] || die "account name cannot be empty"

# Site URL: used AS-IS (custom domains welcome). We only add https:// when no
# scheme is given and trim whitespace / a trailing slash — no .teamwork.com munging.
read -rp "Teamwork site URL (e.g. https://acme.teamwork.com or your custom domain): " raw_site
base_url="$(printf '%s' "$raw_site" | sed -E 's#[[:space:]]##g; s#/+$##')"
[ -n "$base_url" ] || die "site URL cannot be empty"
case "$base_url" in
  http://*|https://*) : ;;
  *) base_url="https://$base_url" ;;
esac
# host label, for display only
site="$(printf '%s' "$base_url" | sed -E 's#^https?://##; s#/.*$##')"

# API key: read silently, never echoed.
read -rsp "API key (from Teamwork > your profile > API & Mobile): " api_key
echo
[ -n "$api_key" ] || die "API key cannot be empty"

# --- validate against the live API ------------------------------------------
info "Validating against ${base_url} ..."
resp="$(curl -sS -m 20 -w $'\n%{http_code}' -u "${api_key}:" "${base_url}/me.json")" \
  || die "could not reach ${base_url} (network error)"
code="$(printf '%s' "$resp" | tail -n1)"
body="$(printf '%s' "$resp" | sed '$d')"

[ "$code" = "200" ] || die "API rejected the request (HTTP $code) at ${base_url}. Check the site URL and key."

# Extract user id + name from the v1 /me.json payload (defensive about shape).
readarray -t parsed < <(python3 - "$body" <<'PY'
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    print(""); print(""); raise SystemExit
p = d.get("person") or d.get("account") or {}
uid = p.get("id") or p.get("userId") or ""
name = " ".join(x for x in [p.get("first-name") or p.get("firstName"),
                            p.get("last-name")  or p.get("lastName")] if x) \
       or p.get("email-address") or p.get("email") or ""
print(uid)
print(name)
PY
)
user_id="${parsed[0]:-}"
user_name="${parsed[1]:-}"
[ -n "$user_id" ] || die "authenticated, but could not read your user id from /me.json"

ok "Authenticated as ${user_name:-'(unknown)'} — user id ${user_id}."

# --- store as a single JSON secret in the keyring ---------------------------
secret_json="$(python3 - "$account_name" "$site" "$base_url" "$api_key" "$user_id" "$user_name" <<'PY'
import json, sys
_, account, site, base, key, uid, name = sys.argv
print(json.dumps({
    "account":   account,
    "site":      site,
    "base_url":  base,
    "api_key":   key,
    "user_id":   int(uid) if str(uid).isdigit() else uid,
    "user_name": name,
}))
PY
)"

printf '%s' "$secret_json" | secret-tool store --label="$LABEL — $account_name" \
  service "$SERVICE" account "$account_name"
ok "Stored account '$account_name' in the keyring under service='$SERVICE'."
echo
echo "Accounts are told apart by name; add more by re-running this script."
echo "To list accounts:          $0 --print"
echo "To remove this one:        $0 --remove $account_name"
