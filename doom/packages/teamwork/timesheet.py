#!/usr/bin/env python3
"""Teamwork timesheet sidecar.

Pulls the project/tasklist/task tree plus *your* time logs for a date range and
renders them as an editable org buffer; on submit, diffs the edited buffer
against the pulled snapshot and applies the minimal set of create/update/delete
calls to Teamwork, in dependency order, streaming per-action progress.

The pure functions (render_org, parse_org, compute_plan, serialize_parsed) have
no network or keyring dependency so they can be unit-tested offline. Only
load_creds() and Client touch secretstorage / requests, imported lazily.

Multiple Teamwork accounts may be configured (each a keyring item told apart by
an `account` name). Read/write subcommands take an optional --account NAME; the
pulled buffer records its account in a #+TEAMWORK_ACCOUNT header so submit uses
the same one. Per-account state (hidden-project prefs, snapshot cache) is keyed
by account, so accounts never clobber each other.

Subcommands:
    ping [--account N]                health check: who am I (read-only)
    accounts                          list configured accounts as JSON (read-only)
    account-delete --account N        remove one account from the keyring
    explore [--days N] [--account N]  dump real API JSON shapes (read-only)
    pull  --from D --to D [...]        emit org buffer to stdout, cache a snapshot
    submit --file F [--json]          print the diff plan (JSON with --json)
    submit --file F --apply --out G   apply the plan, stream progress, write the
                                      updated buffer to G
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import sys
import time

SERVICE = "teamwork-timesheet"
CACHE_DIR = pathlib.Path(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
) / "teamwork-timesheet"
CONFIG_DIR = pathlib.Path(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
) / "teamwork-timesheet"
PREFS_PATH = CONFIG_DIR / "prefs.json"
MAX_ATTEMPTS = 3
BACKOFF_BASE = 2  # seconds * attempt between retries; tests set this to 0


def _slug(s) -> str:
    """Filesystem-safe token for an account name (used in cache/prefs filenames)."""
    return re.sub(r"[^A-Za-z0-9._-]+", "_", str(s)).strip("_") or "default"


# --------------------------------------------------------------------------- #
# Local preferences (hidden projects) — persisted, never touches Teamwork
# --------------------------------------------------------------------------- #
def prefs_path(account=None) -> pathlib.Path:
    """Hidden-project prefs file, kept per account so accounts don't clobber each
    other. The no-account path stays prefs.json for backward compatibility."""
    return CONFIG_DIR / (f"prefs_{_slug(account)}.json" if account else "prefs.json")


def load_prefs(account=None) -> dict:
    try:
        p = json.loads(prefs_path(account).read_text(encoding="utf-8"))
        return {"hidden": p.get("hidden") or {}, "shown": p.get("shown") or []}
    except (OSError, ValueError):
        return {"hidden": {}, "shown": []}


def save_prefs(prefs: dict, account=None):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    prefs_path(account).write_text(
        json.dumps(prefs, indent=2, ensure_ascii=False), encoding="utf-8")


def reconcile_hidden(prefs: dict, prev_present, hidden_prop) -> set:
    """Compute the new hidden-project id set (strings).

    prev_present: set of project-id strings still present as headings in the
                  buffer being replaced, or None if there is no prior buffer.
    hidden_prop:  set of ids from the buffer's #+TEAMWORK_HIDDEN header (the
                  user-editable source of truth), or None if absent.

    New hidden = (edited header, or saved prefs if no header)
                 ∪ (projects shown last pull whose heading is now gone).
    """
    hidden0 = {str(k) for k in (prefs.get("hidden") or {})}
    shown_last = {str(x) for x in (prefs.get("shown") or [])}
    base = set(hidden_prop) if hidden_prop is not None else hidden0
    deleted = (shown_last - prev_present) if prev_present is not None else set()
    return base | deleted


# --------------------------------------------------------------------------- #
# Credentials + HTTP client (the only network/keyring code)
# --------------------------------------------------------------------------- #
def _open_collection():
    import secretstorage

    conn = secretstorage.dbus_init()
    coll = secretstorage.get_default_collection(conn)
    if coll.is_locked():
        coll.unlock()
    return coll


def _item_account(item, secret: dict) -> str:
    """Best-effort account name: the keyring `account` attribute, else a value
    baked into the secret, else the site (so a legacy single account still has a
    stable name)."""
    attrs = item.get_attributes() or {}
    return (attrs.get("account") or secret.get("account")
            or secret.get("site") or secret.get("base_url") or "?")


def _stored_creds() -> list[dict]:
    """Every stored account's secret dict, each with its resolved 'account' name."""
    out = []
    for item in _open_collection().search_items({"service": SERVICE}):
        try:
            d = json.loads(item.get_secret().decode())
        except (ValueError, UnicodeDecodeError):
            continue
        d["account"] = _item_account(item, d)
        out.append(d)
    return out


def load_creds(account=None) -> dict:
    creds = _stored_creds()
    if not creds:
        raise SystemExit("No Teamwork credentials found. Run teamwork-setup.sh first.")
    if account is not None:
        for d in creds:
            if d.get("account") == account:
                return d
        names = ", ".join(sorted(d["account"] for d in creds))
        raise SystemExit(f"No Teamwork account named {account!r}. Configured: {names}")
    if len(creds) == 1:
        return creds[0]
    names = ", ".join(sorted(d["account"] for d in creds))
    raise SystemExit(f"Multiple Teamwork accounts configured; pass --account NAME. "
                     f"Configured: {names}")


def list_accounts() -> list[dict]:
    """Public account list (no raw API keys) for the Emacs account picker/viewer."""
    out = []
    for d in _stored_creds():
        key = d.get("api_key", "") or ""
        out.append({
            "account": d.get("account"),
            "site": d.get("site") or d.get("subdomain"),
            "base_url": d.get("base_url"),
            "user_name": d.get("user_name"),
            "user_id": d.get("user_id"),
            "api_key_masked": (key[:4] + "…" + key[-4:]) if len(key) > 8 else "****",
        })
    out.sort(key=lambda a: (a.get("account") or "").lower())
    return out


def delete_account(account: str) -> int:
    """Remove every keyring item matching ACCOUNT. Returns how many were deleted."""
    coll = _open_collection()
    deleted = 0
    for item in coll.search_items({"service": SERVICE}):
        try:
            d = json.loads(item.get_secret().decode())
        except (ValueError, UnicodeDecodeError):
            d = {}
        if _item_account(item, d) == account:
            item.delete()
            deleted += 1
    return deleted


class Client:
    """Thin v1 REST client with Basic auth, pagination, and 429 backoff."""

    def __init__(self, creds: dict):
        import requests

        self.s = requests.Session()
        self.s.auth = (creds["api_key"], "")
        self.base = creds["base_url"].rstrip("/")
        self.user_id = int(creds["user_id"])
        self._last_headers = {}

    def _req(self, method: str, path: str, params=None, body=None):
        url = self.base + path
        for _ in range(6):
            r = self.s.request(method, url, params=params, json=body, timeout=30)
            if r.status_code == 429:
                time.sleep(int(r.headers.get("Retry-After", "5")))
                continue
            r.raise_for_status()
            self._last_headers = r.headers
            if not r.text.strip():
                return {}
            try:
                return r.json()
            except ValueError:
                return {"_raw": r.text}
        raise SystemExit(f"rate limited repeatedly on {path}")

    def get(self, path, **params):
        return self._req("GET", path, params={k: v for k, v in params.items() if v is not None} or None)

    def paged(self, path: str, key: str, page_size: int = 250, **params) -> list:
        """Fetch every page. Uses the X-Pages header (authoritative) to know when
        to stop; falls back to a short page only if that header is absent.

        The naive "stop when a page has < page_size items" rule is WRONG: some
        endpoints (e.g. /time_entries.json) cap the effective page size, so the
        first page comes back short and we'd miss everything after it."""
        out, page = [], 1
        while page <= 1000:  # hard safety cap
            data = self.get(path, page=page, pageSize=page_size, **params)
            items = data.get(key, []) if isinstance(data, dict) else []
            out.extend(items)
            try:
                total_pages = int(self._last_headers.get("X-Pages") or 0)
            except (TypeError, ValueError):
                total_pages = 0
            if total_pages:
                if page >= total_pages:
                    break
            elif len(items) < page_size:  # no header: best-effort fallback
                break
            if not items:
                break
            page += 1
        return out

    # -- reads (normalized to internal dicts) -------------------------------- #
    def projects(self) -> list[dict]:
        return [
            {"id": int(p["id"]), "name": p.get("name", "").strip()}
            for p in self.paged("/projects.json", "projects", status="active")
        ]

    def tasklists(self, project_id: int) -> list[dict]:
        return [
            {"id": int(t["id"]), "name": t.get("name", "").strip(), "project_id": project_id}
            for t in self.paged(f"/projects/{project_id}/tasklists.json", "tasklists")
        ]

    def tasks(self, tasklist_id: int, project_id: int) -> list[dict]:
        return [
            {
                "id": int(t["id"]),
                "title": (t.get("content") or "").strip(),
                "tasklist_id": tasklist_id,
                "project_id": project_id,
            }
            for t in self.paged(f"/tasklists/{tasklist_id}/tasks.json", "todo-items")
        ]

    def my_timelogs(self, date_from: str, date_to: str) -> list[dict]:
        raw = self.paged(
            "/time_entries.json",
            "time-entries",
            fromdate=date_from.replace("-", ""),
            todate=date_to.replace("-", ""),
            userId=self.user_id,
        )
        return [normalize_timelog(t) for t in raw]

    # -- writes -------------------------------------------------------------- #
    def create_tasklist(self, project_id: int, name: str) -> int:
        d = self._req("POST", f"/projects/{project_id}/tasklists.json",
                      body={"todo-list": {"name": name}})
        return int(d.get("TASKLISTID") or d.get("id"))

    def update_tasklist(self, tasklist_id: int, name: str):
        return self._req("PUT", f"/tasklists/{tasklist_id}.json",
                         body={"todo-list": {"name": name}})

    def create_task(self, tasklist_id: int, title: str) -> int:
        d = self._req("POST", f"/tasklists/{tasklist_id}/tasks.json",
                      body={"todo-item": {"content": title}})
        return int(d.get("id") or d.get("taskId"))

    def update_task(self, task_id: int, title: str):
        return self._req("PUT", f"/tasks/{task_id}.json",
                         body={"todo-item": {"content": title}})

    def complete_task(self, task_id: int):
        return self._req("PUT", f"/tasks/{task_id}/complete.json")

    def create_timelog(self, task_id: int, body: dict) -> int:
        d = self._req("POST", f"/tasks/{task_id}/time_entries.json",
                      body={"time-entry": body})
        return int(d.get("timeLogId") or d.get("id") or 0)

    def update_timelog(self, log_id: int, body: dict):
        return self._req("PUT", f"/time_entries/{log_id}.json", body={"time-entry": body})

    def delete_timelog(self, log_id: int):
        return self._req("DELETE", f"/time_entries/{log_id}.json")


def normalize_timelog(t: dict) -> dict:
    """Map a raw v1 time-entry into our internal shape.

    Teamwork has no separate start-time field: the start is the time component of
    `dateUserPerspective` (the log's date/time in the account's timezone), and is
    only meaningful when `has-start-time` is set. Duration is `hours`+`minutes`.
    """
    def pick(*keys, default=None):
        for k in keys:
            if k in t and t[k] not in (None, ""):
                return t[k]
        return default

    # user-perspective timestamp, e.g. "2026-07-16T11:42:00Z" -> date + start
    stamp = str(pick("dateUserPerspective", "date", default=""))
    date = stamp[:10]
    has_start = str(pick("has-start-time", default="0")) in ("1", "true", "True", "yes")
    start = stamp[11:16] if (has_start and "T" in stamp and len(stamp) >= 16) else None

    hours = int(pick("hours", default=0) or 0)
    minutes = int(pick("minutes", default=0) or 0)
    billable = str(pick("isbillable", "billable", default="1")) in ("1", "true", "True", "yes")
    return {
        "id": int(pick("id")),
        "task_id": int(pick("todo-item-id", "taskId", "task-id", default=0) or 0),
        "task_name": (pick("todo-item-name", default="") or "").strip(),
        "tasklist_id": int(pick("todo-list-id", "tasklistId", default=0) or 0),
        "tasklist_name": (pick("todo-list-name", default="") or "").strip(),
        "project_id": int(pick("project-id", "projectId", default=0) or 0),
        "project_name": (pick("project-name", default="") or "").strip(),
        "date": date,
        "start": start,
        "minutes": hours * 60 + minutes,
        "description": (pick("description", default="") or "").strip(),
        "billable": billable,
    }


def synthesize_missing(projects, tasklists, tasks, logs):
    """Ensure every logged task/list/project exists as a node.

    Completed (or archived) task lists and tasks are omitted by the list
    endpoints, so a time log on one would otherwise have no heading to sit under
    and be dropped. Rebuild those nodes from the log's own metadata
    (todo-item-name / todo-list-name / project-name), which every entry carries.
    Mutates and returns the three lists.
    """
    proj_ids = {p["id"] for p in projects}
    tl_ids = {t["id"] for t in tasklists}
    tk_ids = {t["id"] for t in tasks}
    for lg in logs:
        pid, tlid, tkid = lg.get("project_id"), lg.get("tasklist_id"), lg.get("task_id")
        if pid and pid not in proj_ids:
            projects.append({"id": pid, "name": lg.get("project_name") or f"project {pid}"})
            proj_ids.add(pid)
        if tlid and tlid not in tl_ids and pid:
            tasklists.append({"id": tlid, "name": lg.get("tasklist_name") or f"list {tlid}",
                              "project_id": pid})
            tl_ids.add(tlid)
        if tkid and tkid not in tk_ids and tlid:
            tasks.append({"id": tkid, "title": lg.get("task_name") or f"task {tkid}",
                          "tasklist_id": tlid, "project_id": pid})
            tk_ids.add(tkid)
    return projects, tasklists, tasks


# --------------------------------------------------------------------------- #
# Pure rendering: internal dicts -> org text
# --------------------------------------------------------------------------- #
def _fmt_hm(total_min: int) -> str:
    return f"{total_min // 60}:{total_min % 60:02d}"


def _add_minutes(start: str, minutes: int) -> str:
    h, m = map(int, start.split(":"))
    total = (h * 60 + m + minutes) % (24 * 60)
    return f"{total // 60:02d}:{total % 60:02d}"


def render_log_line(log: dict) -> list[str]:
    """One time log -> the '- ...' line plus indented continuation lines."""
    idpart = f"{log['id']} " if log.get("id") else ""
    if log.get("start"):
        end = _add_minutes(log["start"], log["minutes"])
        head = f"{log['date']} {log['start']} {end}"
    else:
        head = f"{log['date']} ={_fmt_hm(log['minutes'])}"
    desc_lines = (log.get("description") or "").split("\n")
    first = desc_lines[0] if desc_lines else ""
    lines = [f"- {idpart}{head} {first}".rstrip()]
    for cont in desc_lines[1:]:
        lines.append(f"  {cont}")
    return lines


def _drawer(key: str, value) -> str:
    return f":PROPERTIES:\n:{key}: {value}\n:END:"


def _header(frm, to, user, hidden=None, hidden_names=None, account=None) -> list[str]:
    hidden = [str(h) for h in (hidden or [])]
    lines = [
        f"#+TITLE: Teamwork timesheet {frm} .. {to}",
        f"#+TEAMWORK: from={frm} to={to} user={user}",
    ]
    if account:
        lines.append(f"#+TEAMWORK_ACCOUNT: {account}")
    lines += [
        "#+TEAMWORK_BILLABLE: 1",
        "# Log lines:  - [ID] DATE START END description   (edit if ID present, create if not)",
        "#             - [ID] DATE =H:MM description        (duration form, no start time)",
        "# Times take HH:MM or HHMM (09:00 or 0900). Add [d] after the times to mark the",
        "# task complete on submit, e.g.  - 2026-06-01 0900 1300 [d] wrapped it up.",
        "# Remove a log line to delete it. Add a heading with no ID to create a task/list.",
        "# Rename a task/list by editing its heading text (keep its :TW_*_ID:).",
        "# Delete a whole project heading to stop fetching it (moves to TEAMWORK_HIDDEN,",
        "# its logs are left untouched). Remove an id from TEAMWORK_HIDDEN to fetch it again.",
    ]
    for h in hidden:
        nm = (hidden_names or {}).get(h)
        lines.append(f"#   hidden {h}  {nm}" if nm else f"#   hidden {h}")
    lines.append("#+TEAMWORK_HIDDEN: " + " ".join(hidden))
    lines.append("")
    return lines


def render_org(projects, tasklists, tasks, logs, meta: dict, hidden_names: dict = None) -> str:
    """Render the full tree pulled from the API. Logs grouped under their task."""
    task_ids = {tk["id"] for tk in tasks}
    logs_by_task: dict[int, list] = {}
    orphan_logs = []
    for lg in logs:
        if lg["task_id"] and lg["task_id"] in task_ids:
            logs_by_task.setdefault(lg["task_id"], []).append(lg)
        else:
            orphan_logs.append(lg)  # never silently drop a log

    tls_by_project: dict[int, list] = {}
    for tl in tasklists:
        tls_by_project.setdefault(tl["project_id"], []).append(tl)
    tasks_by_tl: dict[int, list] = {}
    for tk in tasks:
        tasks_by_tl.setdefault(tk["tasklist_id"], []).append(tk)

    hidden_names = hidden_names or {}
    out = _header(meta["from"], meta["to"], meta["user_id"],
                  hidden=sorted(hidden_names, key=int), hidden_names=hidden_names,
                  account=meta.get("account"))
    for pr in sorted(projects, key=lambda p: p["name"].lower()):
        out.append(f"* {pr['name']}")
        out.append(_drawer("TW_PROJECT_ID", pr["id"]))
        for tl in sorted(tls_by_project.get(pr["id"], []), key=lambda t: t["name"].lower()):
            out.append(f"** {tl['name']}")
            out.append(_drawer("TW_TASKLIST_ID", tl["id"]))
            for tk in sorted(tasks_by_tl.get(tl["id"], []), key=lambda t: t["title"].lower()):
                out.append(f"*** {tk['title']}")
                out.append(_drawer("TW_TASK_ID", tk["id"]))
                for lg in sorted(logs_by_task.get(tk["id"], []), key=lambda l: (l["date"], l.get("start") or "")):
                    out.extend(render_log_line(lg))
    if orphan_logs:
        out.append("* (time logs with no task in the pulled tree)")
        for lg in orphan_logs:
            out.extend(render_log_line(lg))
    return "\n".join(out) + "\n"


def serialize_parsed(parsed: dict) -> str:
    """Reproduce an org buffer from a parsed (and possibly mutated) tree.

    Used after apply: created items now carry IDs (so re-parse treats them as
    existing), while unapplied creates keep id=None and stay 'new' for retry.
    """
    m = parsed["meta"]
    out = _header(m.get("from"), m.get("to"), m.get("user"), hidden=m.get("hidden"),
                  account=m.get("account"))
    for p in parsed["projects"]:
        out.append(f"* {p['name']}")
        if p["id"] is not None:
            out.append(_drawer("TW_PROJECT_ID", p["id"]))
        for tl in p["tasklists"]:
            out.append(f"** {tl['name']}")
            if tl["id"] is not None:
                out.append(_drawer("TW_TASKLIST_ID", tl["id"]))
            for tk in tl["tasks"]:
                out.append(f"*** {tk['title']}")
                if tk["id"] is not None:
                    out.append(_drawer("TW_TASK_ID", tk["id"]))
                for lg in tk["logs"]:
                    out.extend(render_log_line(lg))
    return "\n".join(out) + "\n"


def build_snapshot(projects, tasklists, tasks, logs, meta: dict) -> dict:
    return {
        "from": meta["from"],
        "to": meta["to"],
        "logs": {str(lg["id"]): _log_snap(lg) for lg in logs if lg.get("id")},
        "tasklists": {str(t["id"]): t["name"] for t in tasklists},
        "tasks": {str(t["id"]): t["title"] for t in tasks},
    }


def build_snapshot_from_parsed(parsed: dict) -> dict:
    m = parsed["meta"]
    logs, tls, tks = {}, {}, {}
    for p in parsed["projects"]:
        for tl in p["tasklists"]:
            if tl["id"] is not None:
                tls[str(tl["id"])] = tl["name"]
            for tk in tl["tasks"]:
                if tk["id"] is not None:
                    tks[str(tk["id"])] = tk["title"]
                for lg in tk["logs"]:
                    if lg.get("id"):
                        logs[str(lg["id"])] = _log_snap(lg)
    return {"from": m.get("from"), "to": m.get("to"), "logs": logs, "tasklists": tls, "tasks": tks}


def _log_snap(lg: dict) -> dict:
    return {
        "task_id": lg.get("task_id"),
        "project_id": lg.get("project_id"),
        "date": lg["date"],
        "start": lg.get("start"),
        "minutes": lg["minutes"],
        "description": lg.get("description", ""),
        "billable": lg.get("billable", True),
    }


# --------------------------------------------------------------------------- #
# Pure parsing: org text -> structured buffer
# --------------------------------------------------------------------------- #
_HEAD_RE = re.compile(r"^(\*{1,3})\s+(.*)$")
_PROP_RE = re.compile(r"^\s*:(TW_PROJECT_ID|TW_TASKLIST_ID|TW_TASK_ID):\s*(\d+)\s*$")
_LOG_RE = re.compile(
    r"^\s*-\s+"
    r"(?:(?P<id>\d+)\s+)?"
    r"(?P<date>\d{4}-\d{2}-\d{2})\s+"
    r"(?:"
    r"=(?P<dur>\d{1,2}:\d{2})"
    r"|(?P<start>\d{1,2}:\d{2}|\d{3,4})\s+(?P<end>\d{1,2}:\d{2}|\d{3,4})"
    r")"
    r"\s*(?:\[(?P<done>[dD])\]\s*)?(?P<desc>.*)$"
)


def _to_minutes(hm: str) -> int:
    """Minutes for a time token in 'H:MM' or 'HHMM'/'HMM' form."""
    if ":" in hm:
        h, m = hm.split(":")
    else:
        hm = hm.zfill(4)  # '900' -> '0900'
        h, m = hm[:-2], hm[-2:]
    return int(h) * 60 + int(m)


def _norm_hm(hm: str) -> str:
    """Normalise a time token ('HHMM' or 'H:MM') to canonical 'HH:MM'."""
    total = _to_minutes(hm)
    return f"{total // 60:02d}:{total % 60:02d}"


def parse_org(text: str) -> dict:
    meta = {"from": None, "to": None, "user": None, "billable_default": True,
            "hidden": None, "account": None}
    problems: list[str] = []
    projects: list[dict] = []
    cur_p = cur_tl = cur_tk = None
    cur_log = None

    def close_log():
        nonlocal cur_log
        cur_log = None

    for lineno, raw in enumerate(text.splitlines(), 1):
        if raw.startswith("#+TEAMWORK:"):
            for tok in raw.split(":", 1)[1].split():
                if tok.startswith("from="):
                    meta["from"] = tok[5:]
                elif tok.startswith("to="):
                    meta["to"] = tok[3:]
                elif tok.startswith("user="):
                    meta["user"] = tok[5:]
            continue
        if raw.startswith("#+TEAMWORK_ACCOUNT:"):
            meta["account"] = raw.split(":", 1)[1].strip() or None
            continue
        if raw.startswith("#+TEAMWORK_BILLABLE:"):
            meta["billable_default"] = raw.split(":", 1)[1].strip() in ("1", "true", "yes")
            continue
        if raw.startswith("#+TEAMWORK_HIDDEN:"):
            meta["hidden"] = [int(x) for x in raw.split(":", 1)[1].split() if x.isdigit()]
            continue
        if raw.startswith("#"):
            continue

        m = _HEAD_RE.match(raw)
        if m:
            close_log()
            level, title = len(m.group(1)), m.group(2).strip()
            if level == 1:
                cur_p = {"id": None, "name": title, "tasklists": []}
                projects.append(cur_p)
                cur_tl = cur_tk = None
            elif level == 2:
                if cur_p is None:
                    problems.append(f"line {lineno}: task list '{title}' has no parent project")
                    continue
                cur_tl = {"id": None, "name": title, "tasks": [], "project": cur_p}
                cur_p["tasklists"].append(cur_tl)
                cur_tk = None
            elif level == 3:
                if cur_tl is None:
                    problems.append(f"line {lineno}: task '{title}' has no parent task list")
                    continue
                cur_tk = {"id": None, "title": title, "logs": [], "tasklist": cur_tl}
                cur_tl["tasks"].append(cur_tk)
            continue

        pm = _PROP_RE.match(raw)
        if pm:
            kind, val = pm.group(1), int(pm.group(2))
            if kind == "TW_PROJECT_ID" and cur_p is not None:
                cur_p["id"] = val
            elif kind == "TW_TASKLIST_ID" and cur_tl is not None:
                cur_tl["id"] = val
            elif kind == "TW_TASK_ID" and cur_tk is not None:
                cur_tk["id"] = val
            continue

        lm = _LOG_RE.match(raw)
        if lm:
            if cur_tk is None:
                problems.append(f"line {lineno}: time log has no parent task")
                close_log()
                continue
            if lm.group("dur"):
                minutes, start = _to_minutes(lm.group("dur")), None
            else:
                start, end = lm.group("start"), lm.group("end")
                minutes = _to_minutes(end) - _to_minutes(start)
                if minutes <= 0:
                    problems.append(f"line {lineno}: end time is not after start time")
                    close_log()
                    continue
                start = _norm_hm(start)
            cur_log = {
                "id": int(lm.group("id")) if lm.group("id") else None,
                "task_id": cur_tk["id"],
                "project_id": cur_p["id"],
                "date": lm.group("date"),
                "start": start,
                "minutes": minutes,
                "description": lm.group("desc").strip(),
                "done": bool(lm.group("done")),
                "line": lineno,
            }
            cur_tk["logs"].append(cur_log)
            continue

        if cur_log is not None and raw.strip() and (raw.startswith(" ") or raw.startswith("\t")):
            cur_log["description"] = (cur_log["description"] + "\n" + raw.strip()).strip()
            continue
        if not raw.strip():
            close_log()

    return {"meta": meta, "projects": projects, "problems": problems}


# --------------------------------------------------------------------------- #
# Pure diff: parsed buffer + snapshot -> ordered action plan
# --------------------------------------------------------------------------- #
def _log_body(log: dict, user_id: int, billable: bool) -> dict:
    minutes = log["minutes"]
    return {
        "description": log["description"],
        "person-id": user_id,
        "date": log["date"].replace("-", ""),
        "time": log["start"] or "09:00",
        "hours": minutes // 60,
        "minutes": minutes % 60,
        "isbillable": 1 if billable else 0,
    }


def _log_signature(d: dict) -> tuple:
    return (d.get("date"), d.get("start"), int(d.get("minutes", 0)), (d.get("description") or "").strip())


def _summary(lg: dict, tk: dict, kind: str) -> str:
    when = f"{lg['date']} {lg['start'] or '=' + _fmt_hm(lg['minutes'])}"
    return f"{kind} log {when} [{_fmt_hm(lg['minutes'])}] on {tk['title'][:40]!r}"


def compute_plan(parsed: dict, snapshot: dict, user_id: int) -> dict:
    """Ordered plan: create lists -> create tasks -> renames -> log writes -> completes -> deletes."""
    creates_tl, creates_tk, renames, log_writes, completes, deletes = [], [], [], [], [], []
    problems = list(parsed["problems"])
    billable = parsed["meta"].get("billable_default", True)
    snap_logs = dict(snapshot.get("logs", {}))
    snap_tasks = snapshot.get("tasks", {})
    snap_tls = snapshot.get("tasklists", {})
    present_pids = {p["id"] for p in parsed["projects"] if p["id"] is not None}
    seen: set[str] = set()
    ref = {"n": 0}

    def new_ref(kind: str) -> str:
        ref["n"] += 1
        return f"{kind}:{ref['n']}"

    for p in parsed["projects"]:
        if p["id"] is None:
            problems.append(f"project '{p['name']}' has no TW_PROJECT_ID (creating projects is not supported)")
            continue
        for tl in p["tasklists"]:
            if tl["id"] is None:
                tl_ref = new_ref("tasklist")
                creates_tl.append({"type": "create_tasklist", "ref": tl_ref, "project_id": p["id"],
                                   "name": tl["name"], "summary": f"new list {tl['name']!r} in {p['name']!r}",
                                   "_obj": tl})
                tl_target = {"ref": tl_ref}
            else:
                tl_target = tl["id"]
                prev = snap_tls.get(str(tl["id"]))
                if prev is not None and prev != tl["name"]:
                    renames.append({"type": "update_tasklist", "id": tl["id"], "name": tl["name"],
                                    "summary": f"rename list {prev!r} -> {tl['name']!r}", "_obj": tl})
            for tk in tl["tasks"]:
                if tk["id"] is None:
                    tk_ref = new_ref("task")
                    creates_tk.append({"type": "create_task", "ref": tk_ref, "tasklist": tl_target,
                                       "title": tk["title"], "summary": f"new task {tk['title']!r} in {tl['name']!r}",
                                       "_obj": tk})
                    tk_target = {"ref": tk_ref}
                else:
                    tk_target = tk["id"]
                    prev = snap_tasks.get(str(tk["id"]))
                    if prev is not None and prev != tk["title"]:
                        renames.append({"type": "update_task", "id": tk["id"], "title": tk["title"],
                                        "summary": f"rename task {prev!r} -> {tk['title']!r}", "_obj": tk})
                for lg in tk["logs"]:
                    body = _log_body(lg, user_id, billable)
                    if lg["id"] is None:
                        log_writes.append({"type": "create_timelog", "task": tk_target, "body": body,
                                           "summary": _summary(lg, tk, "new"), "_obj": lg})
                    else:
                        sid = str(lg["id"])
                        seen.add(sid)
                        prev = snap_logs.get(sid)
                        if prev is None or _log_signature(prev) != _log_signature(lg):
                            log_writes.append({"type": "update_timelog", "id": lg["id"], "body": body,
                                               "summary": _summary(lg, tk, "edit"), "_obj": lg})
                # A [d] marker on any of the task's logs completes the parent task.
                if any(lg.get("done") for lg in tk["logs"]):
                    completes.append({"type": "complete_task", "task": tk_target,
                                      "summary": f"mark task {tk['title'][:40]!r} complete", "_obj": tk})
    for sid, prev in snap_logs.items():
        if sid in seen:
            continue
        pid = prev.get("project_id")
        if pid is not None and int(pid) not in present_pids:
            continue  # whole project absent from buffer (hidden/removed) -> keep its logs
        deletes.append({"type": "delete_timelog", "id": int(sid),
                        "summary": f"delete log {sid} ({prev['date']} {_fmt_hm(prev['minutes'])})"})

    return {"actions": creates_tl + creates_tk + renames + log_writes + completes + deletes,
            "problems": problems}


def public_action(a: dict) -> dict:
    """Strip in-process-only keys (object refs) for JSON output."""
    return {k: v for k, v in a.items() if not k.startswith("_")}


# --------------------------------------------------------------------------- #
# Apply (streaming, ordered, with retry + abort)
# --------------------------------------------------------------------------- #
def _resolve(target, created: dict):
    if isinstance(target, dict) and "ref" in target:
        return created[target["ref"]]
    return target


def _execute(a: dict, client: "Client", created: dict):
    t = a["type"]
    if t == "create_tasklist":
        created[a["ref"]] = client.create_tasklist(a["project_id"], a["name"])
    elif t == "update_tasklist":
        client.update_tasklist(a["id"], a["name"])
    elif t == "create_task":
        created[a["ref"]] = client.create_task(int(_resolve(a["tasklist"], created)), a["title"])
    elif t == "update_task":
        client.update_task(a["id"], a["title"])
    elif t == "complete_task":
        client.complete_task(int(_resolve(a["task"], created)))
    elif t == "create_timelog":
        a["_new_id"] = client.create_timelog(int(_resolve(a["task"], created)), a["body"])
    elif t == "update_timelog":
        client.update_timelog(a["id"], a["body"])
    elif t == "delete_timelog":
        client.delete_timelog(a["id"])


def _mutate_on_success(a: dict, created: dict):
    """Fold applied results back into the parsed tree so re-parse sees IDs."""
    if a["type"] in ("create_tasklist", "create_task"):
        a["_obj"]["id"] = created[a["ref"]]
    elif a["type"] == "create_timelog":
        a["_obj"]["id"] = a.get("_new_id")


def _emit(obj: dict):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def apply_stream(plan: dict, client: "Client", parsed: dict, out_path: str, snap_path: str):
    actions = plan["actions"]
    created: dict = {}
    _emit({"event": "begin", "count": len(actions)})
    aborted = False
    applied = 0
    for idx, a in enumerate(actions):
        _emit({"event": "start", "idx": idx, "type": a["type"], "summary": a.get("summary", a["type"])})
        err = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                _execute(a, client, created)
                err = None
                break
            except Exception as e:  # noqa: BLE001 - report any failure to the UI
                err = f"{type(e).__name__}: {e}"
                if attempt < MAX_ATTEMPTS:
                    _emit({"event": "retry", "idx": idx, "attempt": attempt, "error": err})
                    time.sleep(min(BACKOFF_BASE * attempt, 5))
        if err is None:
            _mutate_on_success(a, created)
            applied += 1
            _emit({"event": "ok", "idx": idx})
        else:
            _emit({"event": "fail", "idx": idx, "attempts": MAX_ATTEMPTS, "error": err})
            aborted = True
            break

    # Always persist the (partially) applied state so unapplied edits survive.
    pathlib.Path(out_path).write_text(serialize_parsed(parsed), encoding="utf-8")
    pathlib.Path(snap_path).write_text(json.dumps(build_snapshot_from_parsed(parsed)), encoding="utf-8")
    _emit({"event": "done", "aborted": aborted, "applied": applied,
           "total": len(actions), "buffer": out_path})


# --------------------------------------------------------------------------- #
# Snapshot cache helpers
# --------------------------------------------------------------------------- #
def snapshot_path(date_from: str, date_to: str, account=None) -> pathlib.Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    # No-account path is unchanged (backward compatible); accounts get their own
    # snapshot so submitting account B never diffs against account A's pull.
    if account:
        return CACHE_DIR / f"snapshot_{_slug(account)}_{date_from}_{date_to}.json"
    return CACHE_DIR / f"snapshot_{date_from}_{date_to}.json"


# --------------------------------------------------------------------------- #
# Subcommands
# --------------------------------------------------------------------------- #
def cmd_ping(args):
    creds = load_creds(getattr(args, "account", None))
    print(f"OK: {creds.get('user_name')} (id {creds['user_id']}) @ {creds['base_url']}"
          f"  [account: {creds.get('account')}]")


def cmd_accounts(_args):
    print(json.dumps(list_accounts(), ensure_ascii=False))


def cmd_account_delete(args):
    n = delete_account(args.account)
    if not n:
        raise SystemExit(f"No Teamwork account named {args.account!r} to delete.")
    # Drop that account's local prefs too; the snapshot cache is harmless to keep.
    try:
        prefs_path(args.account).unlink()
    except OSError:
        pass
    print(json.dumps({"deleted": args.account, "count": n}))


def cmd_explore(args):
    creds = load_creds(getattr(args, "account", None))
    c = Client(creds)
    end = dt.date.today()
    start = end - dt.timedelta(days=args.days)
    te = c.get("/time_entries.json", fromdate=start.strftime("%Y%m%d"), todate=end.strftime("%Y%m%d"),
               userId=c.user_id, page=1, pageSize=3)
    entries = te.get("time-entries", []) if isinstance(te, dict) else []
    print(json.dumps({"time_entry_sample_keys": sorted(entries[0].keys()) if entries else [],
                      "time_entry_sample": entries[0] if entries else None}, indent=2, ensure_ascii=False))


def cmd_logs(args):
    """Read-only: dump every time log fetched for a range (for diagnostics)."""
    c = Client(load_creds(getattr(args, "account", None)))
    logs = c.my_timelogs(args.date_from, args.date_to)
    g = (args.grep or "").lower()
    shown = 0
    for lg in sorted(logs, key=lambda l: (l["date"], l.get("start") or "")):
        hay = f"{lg['task_name']} {lg['tasklist_name']} {lg['project_name']} {lg['description']}".lower()
        if g and g not in hay:
            continue
        shown += 1
        print(f"{lg['date']} {lg['start'] or '=':>5} {lg['minutes']:>4}m  "
              f"proj {lg['project_id']}:{lg['project_name']!r}  "
              f"list {lg['tasklist_id']}:{lg['tasklist_name']!r}  "
              f"task {lg['task_id']}:{lg['task_name']!r}  log {lg['id']}")
    sys.stderr.write(f"fetched {len(logs)} logs in {args.date_from}..{args.date_to}"
                     + (f", {shown} match {g!r}" if g else "") + "\n")


def cmd_pull(args):
    creds = load_creds(getattr(args, "account", None))
    account = creds.get("account")
    c = Client(creds)
    meta = {"from": args.date_from, "to": args.date_to, "user_id": creds["user_id"],
            "account": account}
    only = set(int(x) for x in args.projects.split(",")) if args.projects else None

    # -- reconcile hidden-project preferences from the buffer being replaced --
    prefs = load_prefs(account)
    prev_present = hidden_prop = None
    if args.prev and os.path.exists(args.prev):
        pv = parse_org(pathlib.Path(args.prev).read_text(encoding="utf-8"))
        prev_present = {str(p["id"]) for p in pv["projects"] if p["id"] is not None}
        hp = pv["meta"].get("hidden")
        hidden_prop = {str(x) for x in hp} if hp is not None else None
    hidden_ids = reconcile_hidden(prefs, prev_present, hidden_prop)

    projects_all = c.projects()
    name_by_id = {str(p["id"]): p["name"] for p in projects_all}
    old_names = prefs.get("hidden") or {}
    hidden_names = {h: name_by_id.get(h, old_names.get(h, "?")) for h in hidden_ids}

    projects = [p for p in projects_all if str(p["id"]) not in hidden_ids]
    if only:
        projects = [p for p in projects if p["id"] in only]
    sys.stderr.write(f"projects: {len(projects)} shown, {len(hidden_ids)} hidden\n")

    tasklists, tasks = [], []
    for i, p in enumerate(projects, 1):
        tls = c.tasklists(p["id"])
        tasklists.extend(tls)
        for tl in tls:
            tasks.extend(c.tasks(tl["id"], p["id"]))
        sys.stderr.write(f"\r  walked {i}/{len(projects)} projects")
        sys.stderr.flush()
    sys.stderr.write("\n")

    logs = [lg for lg in c.my_timelogs(args.date_from, args.date_to)
            if str(lg["project_id"]) not in hidden_ids]
    sys.stderr.write(f"time logs in range: {len(logs)}\n")

    # Reattach logs on completed/archived (hence unfetched) lists/tasks by
    # rebuilding those nodes from each log's own metadata.
    before = len(tasks)
    synthesize_missing(projects, tasklists, tasks, logs)
    if len(tasks) > before:
        sys.stderr.write(f"reattached {len(tasks) - before} completed/archived task(s) from logs\n")

    save_prefs({"hidden": hidden_names, "shown": [p["id"] for p in projects]}, account)
    snapshot_path(args.date_from, args.date_to, account).write_text(
        json.dumps(build_snapshot(projects, tasklists, tasks, logs, meta)), encoding="utf-8"
    )
    org = render_org(projects, tasklists, tasks, logs, meta, hidden_names)
    (open(args.out, "w", encoding="utf-8") if args.out else sys.stdout).write(org)


def cmd_submit(args):
    text = pathlib.Path(args.file).read_text(encoding="utf-8")
    parsed = parse_org(text)
    frm, to = parsed["meta"]["from"], parsed["meta"]["to"]
    if not frm or not to:
        raise SystemExit("buffer is missing its #+TEAMWORK: from=.. to=.. header")
    # The buffer's own #+TEAMWORK_ACCOUNT wins; --account is an override/fallback.
    account = parsed["meta"].get("account") or getattr(args, "account", None)
    snap_file = snapshot_path(frm, to, account)
    if not snap_file.exists():
        raise SystemExit(f"no snapshot for {frm}..{to} (re-run pull first): {snap_file}")
    snapshot = json.loads(snap_file.read_text(encoding="utf-8"))
    creds = load_creds(account)
    plan = compute_plan(parsed, snapshot, int(creds["user_id"]))

    if args.json:
        print(json.dumps({"actions": [public_action(a) for a in plan["actions"]],
                          "problems": plan["problems"]}, ensure_ascii=False))
        return
    if args.apply:
        if plan["problems"]:
            _emit({"event": "error", "problems": plan["problems"]})
            raise SystemExit(2)
        out = args.out or (str(args.file) + ".applied")
        apply_stream(plan, Client(creds), parsed, out, str(snap_file))
        return
    _print_plan(plan)


def _print_plan(plan: dict):
    if plan["problems"]:
        print("PROBLEMS:")
        for p in plan["problems"]:
            print(f"  ! {p}")
        print()
    if not plan["actions"]:
        print("No changes to submit.")
        return
    print(f"PLAN ({len(plan['actions'])} action(s)):")
    for a in plan["actions"]:
        print(f"  {a.get('summary') or a['type']}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="timesheet")
    sub = ap.add_subparsers(dest="cmd", required=True)

    pg = sub.add_parser("ping")
    pg.add_argument("--account", default=None, help="which stored account to use")
    pg.set_defaults(func=cmd_ping)

    sub.add_parser("accounts", help="list configured accounts as JSON").set_defaults(func=cmd_accounts)

    ad = sub.add_parser("account-delete", help="remove one account from the keyring")
    ad.add_argument("--account", required=True, help="account name to delete")
    ad.set_defaults(func=cmd_account_delete)

    ex = sub.add_parser("explore")
    ex.add_argument("--days", type=int, default=30)
    ex.add_argument("--account", default=None, help="which stored account to use")
    ex.set_defaults(func=cmd_explore)

    lg = sub.add_parser("logs", help="read-only: list every fetched time log for a range")
    lg.add_argument("--from", dest="date_from", required=True)
    lg.add_argument("--to", dest="date_to", required=True)
    lg.add_argument("--grep", default=None, help="filter by task/list/project/description text")
    lg.add_argument("--account", default=None, help="which stored account to use")
    lg.set_defaults(func=cmd_logs)

    pl = sub.add_parser("pull")
    pl.add_argument("--from", dest="date_from", required=True)
    pl.add_argument("--to", dest="date_to", required=True)
    pl.add_argument("--projects", default=None, help="comma-separated project ids to limit the walk")
    pl.add_argument("--prev", default=None, help="the buffer being replaced (for hidden-project reconciliation)")
    pl.add_argument("--account", default=None, help="which stored account to use")
    pl.add_argument("--out", default=None)
    pl.set_defaults(func=cmd_pull)

    sb = sub.add_parser("submit")
    sb.add_argument("--file", required=True)
    sb.add_argument("--apply", action="store_true", help="execute the plan (streams progress)")
    sb.add_argument("--stream", action="store_true", help="(implied by --apply) stream JSON events")
    sb.add_argument("--json", action="store_true", help="emit the plan as JSON and exit")
    sb.add_argument("--account", default=None, help="account fallback if the buffer lacks a header")
    sb.add_argument("--out", default=None, help="where to write the updated buffer after --apply")
    sb.set_defaults(func=cmd_submit)

    args = ap.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
