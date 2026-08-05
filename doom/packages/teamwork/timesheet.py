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

Besides the timesheet, the same tree/diff/apply machinery drives a management
buffer (structure + labels, no time filter) and a per-task comments buffer. A
per-account project `filter` (persisted in prefs) selects which projects appear;
every pull also caches its rendered org so a reopen can show stale data instantly
while a fresh pull runs in the background (`cached` reads that cache).

Subcommands:
    ping [--account N]                health check: who am I (read-only)
    accounts                          list configured accounts as JSON (read-only)
    account-delete --account N        remove one account from the keyring
    explore [--days N] [--account N]  dump real API JSON shapes (read-only)
    projects [--account N]            list active projects + in_filter flags (JSON)
    filter-get / filter-set [...]     read / write the per-account project filter
    pull  --from D --to D [...]        emit timesheet org, cache snapshot + buffer
    manage [--projects ids] [...]     emit the project structure (no time filter)
    comments-pull --task ID [...]     emit a task's comments as an editable buffer
    cached --kind K --key K [...]     print the last cached buffer (exit 3 if none)
    submit --file F [--json]          print the diff plan (JSON with --json)
    submit --file F --apply --out G   apply the plan, stream progress, write the
                                      updated buffer to G
    comments-submit --file F [...]    same, for an edited comments buffer
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
        return {"hidden": p.get("hidden") or {}, "shown": p.get("shown") or [],
                "filter": p.get("filter") or []}
    except (OSError, ValueError):
        return {"hidden": {}, "shown": [], "filter": []}


def save_prefs(prefs: dict, account=None):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    prefs_path(account).write_text(
        json.dumps(prefs, indent=2, ensure_ascii=False), encoding="utf-8")


def update_prefs(account=None, **changes) -> dict:
    """Merge CHANGES into the account's prefs and persist. Merging (not
    replacing) is what keeps the per-account project `filter` alive when a pull
    rewrites `hidden`/`shown` — otherwise switching accounts and back would drop
    the filter, which read as "the filter reset"."""
    prefs = load_prefs(account)
    prefs.update(changes)
    save_prefs(prefs, account)
    return prefs


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
        """All tasks in a list, INCLUDING subtasks nested to any depth.

        `getSubTasks=yes` asks Teamwork to include subtasks in the response.
        Depending on the endpoint/account they come back either flat (each
        carrying a `parentTaskId`) or nested under a parent's `subTasks` array;
        we flatten either shape into one list, tagging every task with its
        `parent_id` (None for a top-level task) so the tree can be rebuilt.
        Dedup by id guards against an endpoint returning a subtask both ways."""
        raw = self.paged(f"/tasklists/{tasklist_id}/tasks.json", "todo-items",
                         getSubTasks="yes", getTags="yes")
        out, seen = [], set()

        def add(t, parent_id):
            tid = int(t["id"])
            if tid in seen:
                return
            seen.add(tid)
            out.append({
                "id": tid,
                "title": (t.get("content") or "").strip(),
                "tasklist_id": tasklist_id,
                "project_id": project_id,
                "parent_id": int(t.get("parentTaskId") or 0) or parent_id or None,
                "tags": _tag_names(t.get("tags")),
                "description": (t.get("description") or "").strip(),
                "due": _norm_due(t.get("dueDate") or t.get("due-date")),
                "priority": _norm_priority(t.get("priority")),
                "assignees": _assignee_ids(t),
            })
            for sub in (t.get("subTasks") or t.get("subtasks") or []):
                add(sub, tid)

        for t in raw:
            add(t, None)
        return out

    def task_title(self, task_id: int) -> str:
        """Title (content) of a single task — for the comments buffer header."""
        d = self.get(f"/tasks/{task_id}.json")
        item = (d.get("todo-item") if isinstance(d, dict) else None) or {}
        return (item.get("content") or "").strip() or f"task {task_id}"

    def comments(self, task_id: int) -> list[dict]:
        return [normalize_comment(c)
                for c in self.paged(f"/tasks/{task_id}/comments.json", "comments")]

    def project_people(self, project_id: int) -> list[dict]:
        """People assignable on a project: [{'id', 'name'}]."""
        return [{"id": str(p["id"]), "name": _person_name(p)}
                for p in self.paged(f"/projects/{project_id}/people.json", "people")]

    def all_tags(self) -> list[str]:
        """Every tag name configured in the account (for the tag picker)."""
        seen, out = set(), []
        for tg in self.paged("/tags.json", "tags"):
            nm = (tg.get("name") or "").strip()
            if nm and nm.lower() not in seen:
                seen.add(nm.lower())
                out.append(nm)
        return sorted(out, key=str.lower)

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

    def delete_tasklist(self, tasklist_id: int):
        return self._req("DELETE", f"/tasklists/{tasklist_id}.json")

    def create_task(self, tasklist_id: int, item: dict) -> int:
        d = self._req("POST", f"/tasklists/{tasklist_id}/tasks.json",
                      body={"todo-item": item})
        return int(d.get("id") or d.get("taskId"))

    def create_subtask(self, parent_task_id: int, item: dict) -> int:
        d = self._req("POST", f"/tasks/{parent_task_id}/subtasks.json",
                      body={"todo-item": item})
        return int(d.get("id") or d.get("taskId"))

    def update_task(self, task_id: int, item: dict):
        """Update a task from a prebuilt `todo-item` body (only changed fields)."""
        return self._req("PUT", f"/tasks/{task_id}.json", body={"todo-item": item})

    def delete_task(self, task_id: int):
        return self._req("DELETE", f"/tasks/{task_id}.json")

    def complete_task(self, task_id: int):
        return self._req("PUT", f"/tasks/{task_id}/complete.json")

    def set_task_tags(self, task_id: int, tags: list):
        """Replace a task's tags with TAGS (a list of names). The v1 tags API
        takes a comma-separated string; `replaceExistingTags` swaps the whole
        set rather than appending."""
        return self._req("PUT", f"/tasks/{task_id}/tags.json",
                         params={"replaceExistingTags": "true"},
                         body={"tags": {"content": ", ".join(tags)}})

    def create_comment(self, task_id: int, body: str) -> int:
        d = self._req("POST", f"/tasks/{task_id}/comments.json",
                      body={"comment": {"body": body, "content-type": "TEXT", "notify": ""}})
        return int(d.get("commentId") or d.get("id") or 0)

    def update_comment(self, comment_id: int, body: str):
        return self._req("PUT", f"/comments/{comment_id}.json",
                         body={"comment": {"body": body, "content-type": "TEXT"}})

    def delete_comment(self, comment_id: int):
        return self._req("DELETE", f"/comments/{comment_id}.json")

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


def _tag_names(raw) -> list:
    """Extract tag names from a task's `tags` array (objects with a `name`, or
    bare strings). Empty/blank names are dropped; order is preserved."""
    out = []
    for tg in (raw or []):
        nm = (tg.get("name") if isinstance(tg, dict) else str(tg)) or ""
        nm = nm.strip()
        if nm:
            out.append(nm)
    return out


# -- task property formats (due date / priority / assignees) ----------------- #
PRIORITIES = ("low", "medium", "high")   # plus "" for none


def _norm_due(s) -> str:
    """Display form 'YYYY-MM-DD' for a due date given as YYYYMMDD or YYYY-MM-DD;
    empty string for no/unknown date."""
    d = re.sub(r"\D", "", str(s or ""))
    return f"{d[0:4]}-{d[4:6]}-{d[6:8]}" if len(d) == 8 else ""


def _due_compact(s) -> str:
    """API write form 'YYYYMMDD' for a due date, or '' to clear it."""
    d = re.sub(r"\D", "", str(s or ""))
    return d if len(d) == 8 else ""


def _norm_priority(s) -> str:
    """Canonical priority: '' (none) / low / medium / high."""
    s = (str(s or "")).strip().lower()
    return "" if s in ("", "none") else s


def _assignee_ids(t: dict) -> list:
    """Person ids a task is assigned to, from whichever v1 field carries them."""
    raw = (t.get("responsible-party-ids") or t.get("responsible-party-id")
           or t.get("responsibleParties") or "")
    return [x for x in re.split(r"[,\s]+", str(raw)) if x.isdigit()]


def _person_name(p: dict) -> str:
    first = (p.get("first-name") or p.get("firstName") or "").strip()
    last = (p.get("last-name") or p.get("lastName") or "").strip()
    return (f"{first} {last}".strip() or (p.get("full-name") or p.get("email-address") or "?")).strip()


def normalize_comment(c: dict) -> dict:
    """Map a raw v1 comment into our internal shape (id, author, datetime, body)."""
    def pick(*keys, default=""):
        for k in keys:
            if c.get(k) not in (None, ""):
                return c[k]
        return default

    first = pick("author-firstname", "authorFirstName")
    last = pick("author-lastname", "authorLastName")
    author = (f"{first} {last}".strip() or str(pick("author-name", default="?")))
    stamp = str(pick("datetime", "post-date", "createdAt", default=""))
    when = stamp[:16].replace("T", " ")
    return {
        "id": int(pick("id", default=0) or 0),
        "author": author,
        "datetime": when,
        "body": (pick("body", default="") or "").strip(),
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


def _drawer_multi(pairs) -> str:
    """A :PROPERTIES: drawer from (key, value) pairs, skipping None/"" values.
    With a single non-empty pair this is byte-identical to `_drawer`, so tasks
    without tags render exactly as before."""
    lines = [":PROPERTIES:"]
    for k, v in pairs:
        if v is not None and v != "":
            lines.append(f":{k}: {v}")
    lines.append(":END:")
    return "\n".join(lines)


def _task_drawer(tk: dict, with_props=False):
    """Property drawer for task TK: id + TW_TAGS, and (management only, WITH_PROPS)
    TW_DUE / TW_PRIORITY / TW_ASSIGNEE lines. Returns None when there is nothing to
    show (a brand-new task with no properties), so callers can skip it."""
    tags = tk.get("tags")
    pairs = [("TW_TASK_ID", tk.get("id")),
             ("TW_TAGS", ", ".join(tags) if tags else None)]
    if with_props:
        names = tk.get("assignee_names")
        pairs += [("TW_DUE", tk.get("due") or None),
                  ("TW_PRIORITY", tk.get("priority") or None),
                  ("TW_ASSIGNEE", ", ".join(names) if names else None)]
    return _drawer_multi(pairs) if any(v not in (None, "") for _, v in pairs) else None


def _emit_project_tree(out, projects, tasklists, tasks, logs_by_task=None,
                       with_desc=False, with_props=False):
    """Append the `* project / ** list / *** task (+subtasks/tags[/logs])` tree to
    OUT. Shared by the timesheet (`render_org`) and management (`render_manage`)
    renderers; LOGS_BY_TASK is a {task_id: [log,…]} map, empty for management.
    WITH_DESC emits each task's description as body text under its drawer (used in
    management, where tasks have no logs to conflict with the free text). WITH_PROPS
    adds the TW_DUE / TW_PRIORITY / TW_ASSIGNEE property lines (management)."""
    logs_by_task = logs_by_task or {}
    tls_by_project: dict[int, list] = {}
    for tl in tasklists:
        tls_by_project.setdefault(tl["project_id"], []).append(tl)
    tops_by_tl: dict[int, list] = {}
    subs_by_parent: dict[int, list] = {}
    for tk in tasks:
        pid = tk.get("parent_id")
        if pid:
            subs_by_parent.setdefault(pid, []).append(tk)
        else:
            tops_by_tl.setdefault(tk["tasklist_id"], []).append(tk)

    def emit_task(tk, level):
        out.append(f"{'*' * level} {tk['title']}")
        drawer = _task_drawer(tk, with_props=with_props)
        if drawer:
            out.append(drawer)
        if with_desc and (tk.get("description") or "").strip():
            out.extend(tk["description"].split("\n"))
        for lg in sorted(logs_by_task.get(tk["id"], []), key=lambda l: (l["date"], l.get("start") or "")):
            out.extend(render_log_line(lg))
        for sub in sorted(subs_by_parent.get(tk["id"], []), key=lambda t: t["title"].lower()):
            emit_task(sub, level + 1)

    for pr in sorted(projects, key=lambda p: p["name"].lower()):
        out.append(f"* {pr['name']}")
        out.append(_drawer("TW_PROJECT_ID", pr["id"]))
        for tl in sorted(tls_by_project.get(pr["id"], []), key=lambda t: t["name"].lower()):
            out.append(f"** {tl['name']}")
            out.append(_drawer("TW_TASKLIST_ID", tl["id"]))
            for tk in sorted(tops_by_tl.get(tl["id"], []), key=lambda t: t["title"].lower()):
                emit_task(tk, 3)


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
        "# Demote a heading below a task (**** or deeper) to make it a subtask; subtasks",
        "# nest to any depth and take logs/renames/[d] like any task.",
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

    hidden_names = hidden_names or {}
    out = _header(meta["from"], meta["to"], meta["user_id"],
                  hidden=sorted(hidden_names, key=int), hidden_names=hidden_names,
                  account=meta.get("account"))
    _emit_project_tree(out, projects, tasklists, tasks, logs_by_task)
    if orphan_logs:
        out.append("* (time logs with no task in the pulled tree)")
        for lg in orphan_logs:
            out.extend(render_log_line(lg))
    return "\n".join(out) + "\n"


def _manage_header(user, account=None, hidden=None, hidden_names=None,
                   filt=None, filt_names=None) -> list:
    """Header for a management buffer — like `_header` but with no date range and
    a `#+TEAMWORK_MANAGE` marker so parse/submit route to management mode."""
    hidden = [str(h) for h in (hidden or [])]
    lines = [
        "#+TITLE: Teamwork management",
        f"#+TEAMWORK_MANAGE: user={user}",
    ]
    if account:
        lines.append(f"#+TEAMWORK_ACCOUNT: {account}")
    lines += [
        "# No time filter here — this is the whole project structure you can manage.",
        "# Add a heading with no ID to create a task/list; demote below a task (**** or",
        "# deeper) to create a subtask. Rename by editing heading text (keep :TW_*_ID:).",
        "# Task properties (in the drawer; empty value clears, missing line leaves as-is):",
        "#   :TW_TAGS: bug, backend      :TW_DUE: 2026-08-20      :TW_PRIORITY: high",
        "#   :TW_ASSIGNEE: Jane Doe, John Roe   (names as shown; C-c C-p picks values)",
        "# Write a task DESCRIPTION as plain text below its property drawer (before any",
        "# subtask heading); edit it freely — it is submitted with everything else.",
        "#   (don't start a description line with '*' — org would read it as a heading.)",
        "# Delete a task or task-list by removing its heading — it is DELETED in Teamwork",
        "# on submit (subtasks/tasks under it go too). The preview lists every deletion.",
        "# Which projects appear is the per-account filter — change it with teamwork-filter.",
        "# Delete a whole project heading to stop managing it (moves to TEAMWORK_HIDDEN).",
    ]
    for h in hidden:
        nm = (hidden_names or {}).get(h)
        lines.append(f"#   hidden {h}  {nm}" if nm else f"#   hidden {h}")
    lines.append("#+TEAMWORK_HIDDEN: " + " ".join(hidden))
    for pid in (filt or []):
        nm = (filt_names or {}).get(str(pid))
        lines.append(f"#   filter {pid}  {nm}" if nm else f"#   filter {pid}")
    lines.append("")
    return lines


def render_manage(projects, tasklists, tasks, meta: dict, hidden_names: dict = None,
                  filt=None, filt_names=None) -> str:
    """Render the management tree (structure + labels, no time logs)."""
    hidden_names = hidden_names or {}
    out = _manage_header(meta["user_id"], account=meta.get("account"),
                         hidden=sorted(hidden_names, key=int), hidden_names=hidden_names,
                         filt=filt, filt_names=filt_names)
    _emit_project_tree(out, projects, tasklists, tasks, None, with_desc=True, with_props=True)
    return "\n".join(out) + "\n"


def _comments_help() -> list:
    return [
        "# One * heading per comment. Edit the text below a heading to change it;",
        "# add a new * heading with body text to post a comment; delete a heading to",
        "# remove its comment. Keep each comment's :TW_COMMENT_ID:. The author/date",
        "# line is informational — only the body text and id matter on submit.",
    ]


def render_comments(task_id, task_title, comments, meta: dict) -> str:
    """Render a task's comments as an editable org buffer (chronological)."""
    out = [
        f"#+TITLE: Comments — {task_title}",
        f"#+TEAMWORK_COMMENTS: task={task_id} user={meta.get('user_id')}",
    ]
    if meta.get("account"):
        out.append(f"#+TEAMWORK_ACCOUNT: {meta['account']}")
    out += _comments_help()
    out.append("")
    for c in comments:
        head = c.get("author") or "?"
        if c.get("datetime"):
            head = f"{head} — {c['datetime']}"
        out.append(f"* {head}")
        out.append(_drawer("TW_COMMENT_ID", c["id"]))
        out.extend((c.get("body") or "").split("\n"))
        out.append("")
    return "\n".join(out) + "\n"


def serialize_comments(parsed: dict) -> str:
    """Rebuild a comments buffer from a parsed (and possibly mutated) tree — used
    after apply so freshly-created comments carry their new ids."""
    m = parsed["meta"]
    out = [
        "#+TITLE: Comments",
        f"#+TEAMWORK_COMMENTS: task={m.get('task')} user={m.get('user')}",
    ]
    if m.get("account"):
        out.append(f"#+TEAMWORK_ACCOUNT: {m['account']}")
    out += _comments_help()
    out.append("")
    for c in parsed["comments"]:
        out.append(f"* {c.get('author') or 'me'}")
        if c.get("id") is not None:
            out.append(_drawer("TW_COMMENT_ID", c["id"]))
        out.extend((c.get("body") or "").split("\n"))
        out.append("")
    return "\n".join(out) + "\n"


def serialize_parsed(parsed: dict) -> str:
    """Reproduce an org buffer from a parsed (and possibly mutated) tree.

    Used after apply: created items now carry IDs (so re-parse treats them as
    existing), while unapplied creates keep id=None and stay 'new' for retry.
    """
    m = parsed["meta"]
    manage = m.get("mode") == "manage"
    if manage:
        out = _manage_header(m.get("user"), account=m.get("account"), hidden=m.get("hidden"))
    else:
        out = _header(m.get("from"), m.get("to"), m.get("user"), hidden=m.get("hidden"),
                      account=m.get("account"))

    def emit_task(tk, level):
        out.append(f"{'*' * level} {tk['title']}")
        drawer = _task_drawer(tk, with_props=manage)   # keeps id/tags/props on retry
        if drawer:
            out.append(drawer)
        if manage and (tk.get("description") or "").strip():
            out.extend(tk["description"].split("\n"))
        for lg in tk["logs"]:
            out.extend(render_log_line(lg))
        for sub in tk.get("subtasks", []):
            emit_task(sub, level + 1)

    for p in parsed["projects"]:
        out.append(f"* {p['name']}")
        if p["id"] is not None:
            out.append(_drawer("TW_PROJECT_ID", p["id"]))
        for tl in p["tasklists"]:
            out.append(f"** {tl['name']}")
            if tl["id"] is not None:
                out.append(_drawer("TW_TASKLIST_ID", tl["id"]))
            for tk in tl["tasks"]:
                emit_task(tk, 3)
    return "\n".join(out) + "\n"


def build_snapshot(projects, tasklists, tasks, logs, meta: dict) -> dict:
    # The relationship maps (task_project / task_tasklist / task_parent /
    # tasklist_project) let compute_plan detect deletions safely: a heading gone
    # from the buffer is deleted only when its project is still present, and only
    # the topmost deleted node is hit (Teamwork cascades children).
    return {
        "from": meta.get("from"),
        "to": meta.get("to"),
        "logs": {str(lg["id"]): _log_snap(lg) for lg in logs if lg.get("id")},
        "tasklists": {str(t["id"]): t["name"] for t in tasklists},
        "tasks": {str(t["id"]): t["title"] for t in tasks},
        "task_tags": {str(t["id"]): (t.get("tags") or []) for t in tasks},
        "task_desc": {str(t["id"]): (t.get("description") or "") for t in tasks},
        "task_due": {str(t["id"]): (t.get("due") or "") for t in tasks},
        "task_priority": {str(t["id"]): (t.get("priority") or "") for t in tasks},
        "task_assignees": {str(t["id"]): (t.get("assignee_names") or []) for t in tasks},
        "task_project": {str(t["id"]): t["project_id"] for t in tasks},
        "task_tasklist": {str(t["id"]): str(t["tasklist_id"]) for t in tasks},
        "task_parent": {str(t["id"]): (str(t["parent_id"]) if t.get("parent_id") else None)
                        for t in tasks},
        "tasklist_project": {str(t["id"]): t["project_id"] for t in tasklists},
    }


def build_snapshot_from_parsed(parsed: dict, people=None) -> dict:
    m = parsed["meta"]
    logs, tls, tks, tags = {}, {}, {}, {}
    desc, due, pri, asg = {}, {}, {}, {}
    t_proj, t_tl, t_parent, tl_proj = {}, {}, {}, {}

    def walk(tk, proj_id, tl_id, parent_id):
        if tk["id"] is not None:
            sid = str(tk["id"])
            tks[sid] = tk["title"]
            if "tags" in tk:                 # only record when the buffer stated it
                tags[sid] = tk.get("tags") or []
            if "description" in tk:
                desc[sid] = tk.get("description") or ""
            if "due" in tk:
                due[sid] = tk.get("due") or ""
            if "priority" in tk:
                pri[sid] = tk.get("priority") or ""
            if "assignee_names" in tk:
                asg[sid] = tk.get("assignee_names") or []
            t_proj[sid] = proj_id
            t_tl[sid] = str(tl_id) if tl_id is not None else None
            t_parent[sid] = str(parent_id) if parent_id is not None else None
        for lg in tk["logs"]:
            if lg.get("id"):
                logs[str(lg["id"])] = _log_snap(lg)
        for sub in tk.get("subtasks", []):
            walk(sub, proj_id, tl_id, tk["id"])

    for p in parsed["projects"]:
        for tl in p["tasklists"]:
            if tl["id"] is not None:
                tls[str(tl["id"])] = tl["name"]
                tl_proj[str(tl["id"])] = p["id"]
            for tk in tl["tasks"]:
                walk(tk, p["id"], tl["id"], None)
    return {"from": m.get("from"), "to": m.get("to"), "logs": logs,
            "tasklists": tls, "tasks": tks, "task_tags": tags, "task_desc": desc,
            "task_due": due, "task_priority": pri, "task_assignees": asg,
            "task_project": t_proj, "task_tasklist": t_tl, "task_parent": t_parent,
            "tasklist_project": tl_proj, "people": people or {}}


def build_comment_snapshot(task_id, comments) -> dict:
    return {"task": str(task_id),
            "comments": {str(c["id"]): c["body"] for c in comments if c.get("id")}}


def build_comment_snapshot_from_parsed(parsed: dict) -> dict:
    m = parsed["meta"]
    return {"task": m.get("task"),
            "comments": {str(c["id"]): c.get("body", "")
                         for c in parsed["comments"] if c.get("id") is not None}}


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
_HEAD_RE = re.compile(r"^(\*+)\s+(.*)$")
_PROP_RE = re.compile(r"^\s*:(TW_PROJECT_ID|TW_TASKLIST_ID|TW_TASK_ID):\s*(\d+)\s*$")
_TAGS_RE = re.compile(r"^\s*:TW_TAGS:\s*(.*)$")
_TASKPROP_RE = re.compile(r"^\s*:(TW_DUE|TW_PRIORITY|TW_ASSIGNEE):\s*(.*)$")
_DRAWER_LINE_RE = re.compile(r"^\s*:(?:PROPERTIES|END):\s*$")
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
            "hidden": None, "account": None, "mode": "timesheet"}
    problems: list[str] = []
    projects: list[dict] = []
    cur_p = cur_tl = cur_tk = None
    cur_log = None
    # Open task nodes keyed by heading level, so a heading at level N nests under
    # the nearest open task at a shallower level (level 3 = top-level task under a
    # list; level 4+ = subtask). Reset whenever a project or list heading opens.
    task_by_level: dict[int, dict] = {}

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
        if raw.startswith("#+TEAMWORK_MANAGE:"):
            meta["mode"] = "manage"
            for tok in raw.split(":", 1)[1].split():
                if tok.startswith("user="):
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
                task_by_level = {}
            elif level == 2:
                if cur_p is None:
                    problems.append(f"line {lineno}: task list '{title}' has no parent project")
                    continue
                cur_tl = {"id": None, "name": title, "tasks": [], "project": cur_p}
                cur_p["tasklists"].append(cur_tl)
                cur_tk = None
                task_by_level = {}
            else:  # level >= 3: a task (3) or a subtask nested under one (4+)
                if cur_tl is None:
                    problems.append(f"line {lineno}: task '{title}' has no parent task list")
                    continue
                parent = next((task_by_level[lv] for lv in range(level - 1, 2, -1)
                               if lv in task_by_level), None)
                if level > 3 and parent is None:
                    problems.append(f"line {lineno}: subtask '{title}' has no parent task")
                    continue
                cur_tk = {"id": None, "title": title, "logs": [], "subtasks": [],
                          "tasklist": cur_tl, "parent": parent}
                if parent is None:
                    cur_tl["tasks"].append(cur_tk)
                else:
                    parent["subtasks"].append(cur_tk)
                # This level is now the open task; drop any deeper (now-closed) ones.
                task_by_level = {lv: n for lv, n in task_by_level.items() if lv < level}
                task_by_level[level] = cur_tk
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

        tagm = _TAGS_RE.match(raw)
        if tagm and cur_tk is not None:
            # Presence of the line is authoritative: empty value clears tags,
            # a missing line (handled by never getting here) leaves them untouched.
            cur_tk["tags"] = [t.strip() for t in tagm.group(1).split(",") if t.strip()]
            continue

        propm = _TASKPROP_RE.match(raw)
        if propm and cur_tk is not None:
            key, val = propm.group(1), propm.group(2).strip()
            if key == "TW_DUE":
                cur_tk["due"] = _norm_due(val)
            elif key == "TW_PRIORITY":
                cur_tk["priority"] = _norm_priority(val)
            elif key == "TW_ASSIGNEE":
                cur_tk["assignee_names"] = [n.strip() for n in val.split(",") if n.strip()]
            continue

        # In management mode there are no time logs: free text under a task (after
        # its property drawer, before the next heading) is the task DESCRIPTION.
        # Collected verbatim here and finalised once the buffer is fully parsed.
        if meta["mode"] == "manage" and cur_tk is not None:
            if not _DRAWER_LINE_RE.match(raw):        # skip :PROPERTIES: / :END:
                cur_tk.setdefault("_desc_lines", []).append(raw)
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

    # Finalise management descriptions: every task carries an (authoritative)
    # description string — empty when the task has no body text, so clearing the
    # text clears it in Teamwork.
    if meta["mode"] == "manage":
        def _finalize_desc(tk):
            lines = tk.pop("_desc_lines", None)
            tk["description"] = "\n".join(lines).strip() if lines else ""
            for sub in tk.get("subtasks", []):
                _finalize_desc(sub)
        for p in projects:
            for tl in p["tasklists"]:
                for tk in tl["tasks"]:
                    _finalize_desc(tk)

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


def _norm_tags(tags) -> list:
    """Canonical form for comparing tag sets: trimmed, lower-cased, de-duped,
    sorted — so 'Bug, backend' and 'backend,bug' read as unchanged."""
    return sorted({t.strip().lower() for t in (tags or []) if t.strip()})


def _summary(lg: dict, tk: dict, kind: str) -> str:
    when = f"{lg['date']} {lg['start'] or '=' + _fmt_hm(lg['minutes'])}"
    return f"{kind} log {when} [{_fmt_hm(lg['minutes'])}] on {tk['title'][:40]!r}"


def compute_plan(parsed: dict, snapshot: dict, user_id: int) -> dict:
    """Ordered plan: create lists -> create tasks/subtasks -> renames -> log writes -> completes -> deletes.

    Tasks nest to any depth: a level-3 heading is a top-level task under its list,
    a deeper heading is a subtask under the task above it. Creating a subtask hits
    a different endpoint than a top-level task, so it gets its own action type; a
    depth-first walk that appends a parent's create before its children's keeps
    parents ahead of children in the plan, so ref resolution works during apply."""
    creates_tl, creates_tk, renames, tag_writes, log_writes, completes, deletes = \
        [], [], [], [], [], [], []
    problems = list(parsed["problems"])
    manage = parsed["meta"].get("mode") == "manage"
    billable = parsed["meta"].get("billable_default", True)
    snap_logs = dict(snapshot.get("logs", {}))
    snap_tasks = snapshot.get("tasks", {})
    snap_tls = snapshot.get("tasklists", {})
    snap_tags = snapshot.get("task_tags", {})
    snap_desc = snapshot.get("task_desc", {})
    snap_due = snapshot.get("task_due", {})
    snap_pri = snapshot.get("task_priority", {})
    snap_asg = snapshot.get("task_assignees", {})     # {task_id: [name, …]}
    people = snapshot.get("people", {})               # {id: name}
    name2id = {v.strip().lower(): k for k, v in people.items()}
    present_pids = {p["id"] for p in parsed["projects"] if p["id"] is not None}
    seen: set[str] = set()             # log ids present in the buffer
    seen_tls: set[str] = set()         # tasklist ids present (for deletion diff)
    seen_tks: set[str] = set()         # task ids present (for deletion diff)
    ref = {"n": 0}

    def new_ref(kind: str) -> str:
        ref["n"] += 1
        return f"{kind}:{ref['n']}"

    def resolve_assignees(names, title):
        """Names -> person id strings via the snapshot people map. A bare numeric
        token is taken as an id; an unknown name is reported as a problem."""
        ids = []
        for nm in names:
            nm = nm.strip()
            if nm.isdigit():
                ids.append(nm)
            elif nm.lower() in name2id:
                ids.append(name2id[nm.lower()])
            elif nm:
                problems.append(f"task {title!r}: unknown assignee {nm!r} "
                                f"(not on this project)")
        return ids

    def process_task(tk, parent_target, tl_target, tl_name):
        """Diff one task and its subtasks. PARENT_TARGET is the parent task's id
        or {ref} for a subtask, or None for a top-level task (created under the
        list). TL_TARGET / TL_NAME describe the enclosing list for summaries."""
        desc = tk.get("description")   # None in timesheet; str (maybe "") in manage
        sid = str(tk["id"]) if tk["id"] is not None else None
        # Property values stated in the buffer (manage only). "in tk" == the line
        # was present, so it is authoritative (empty value clears the field).
        has_due, has_pri, has_asg = ("due" in tk), ("priority" in tk), ("assignee_names" in tk)
        if tk["id"] is None:
            tk_ref = new_ref("task")
            base = {"ref": tk_ref, "title": tk["title"], "description": desc or None, "_obj": tk}
            if has_due:
                base["due"] = tk["due"]
            if has_pri:
                base["priority"] = tk["priority"]
            if has_asg:
                base["assignees"] = resolve_assignees(tk["assignee_names"], tk["title"])
            if parent_target is None:
                base.update({"type": "create_task", "tasklist": tl_target,
                             "summary": f"new task {tk['title']!r} in {tl_name!r}"})
            else:
                pname = (tk.get("parent") or {}).get("title", "")
                base.update({"type": "create_subtask", "parent": parent_target,
                             "summary": f"new subtask {tk['title']!r} under {pname!r}"})
            creates_tk.append(base)
            tk_target = {"ref": tk_ref}
        else:
            tk_target = tk["id"]
            seen_tks.add(sid)
            prev_title = snap_tasks.get(sid)
            title_changed = prev_title is not None and prev_title != tk["title"]
            desc_changed = desc is not None and (desc or "") != (snap_desc.get(sid) or "")
            due_changed = has_due and (tk["due"] or "") != (snap_due.get(sid) or "")
            pri_changed = has_pri and _norm_priority(tk["priority"]) != _norm_priority(snap_pri.get(sid))
            asg_ids = resolve_assignees(tk["assignee_names"], tk["title"]) if has_asg else None
            asg_changed = has_asg and set(asg_ids) != set(resolve_assignees(snap_asg.get(sid) or [], tk["title"]))
            if title_changed or desc_changed or due_changed or pri_changed or asg_changed:
                kind = "subtask" if parent_target is not None else "task"
                act = {"type": "update_task", "id": tk["id"], "_obj": tk}
                bits = []
                if title_changed:
                    act["title"] = tk["title"]; bits.append(f"rename -> {tk['title']!r}")
                if desc_changed:
                    act["description"] = desc
                    bits.append("clear description" if not desc else "edit description")
                if due_changed:
                    act["due"] = tk["due"]; bits.append(f"due {tk['due'] or '(none)'}")
                if pri_changed:
                    act["priority"] = tk["priority"]; bits.append(f"priority {tk['priority'] or '(none)'}")
                if asg_changed:
                    act["assignees"] = asg_ids
                    shown = ", ".join(tk["assignee_names"]) if tk["assignee_names"] else "(none)"
                    bits.append(f"assignees {shown}")
                act["summary"] = f"update {kind} {(prev_title or tk['title'])[:40]!r}: " + ", ".join(bits)
                renames.append(act)
        # Labels: only when the buffer stated them (the :TW_TAGS: line is present).
        # A new task always gets its tags set after creation; an existing one only
        # when they differ from the snapshot (so unchanged tags cost no call).
        if "tags" in tk:
            new_tags = tk["tags"]
            old_tags = snap_tags.get(str(tk["id"])) if tk["id"] is not None else None
            if (tk["id"] is None and new_tags) or \
               (tk["id"] is not None and _norm_tags(new_tags) != _norm_tags(old_tags)):
                shown = ", ".join(new_tags) if new_tags else "(none)"
                tag_writes.append({"type": "set_task_tags", "task": tk_target, "tags": new_tags,
                                   "summary": f"set labels on {tk['title'][:40]!r}: {shown}",
                                   "_obj": tk})
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
        # A [d] marker on any of the task's logs completes that task (any depth).
        if any(lg.get("done") for lg in tk["logs"]):
            completes.append({"type": "complete_task", "task": tk_target,
                              "summary": f"mark task {tk['title'][:40]!r} complete", "_obj": tk})
        for sub in tk["subtasks"]:
            process_task(sub, tk_target, tl_target, tl_name)

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
                seen_tls.add(str(tl["id"]))
                prev = snap_tls.get(str(tl["id"]))
                if prev is not None and prev != tl["name"]:
                    renames.append({"type": "update_tasklist", "id": tl["id"], "name": tl["name"],
                                    "summary": f"rename list {prev!r} -> {tl['name']!r}", "_obj": tl})
            for tk in tl["tasks"]:
                process_task(tk, None, tl_target, tl["name"])
    for sid, prev in snap_logs.items():
        if sid in seen:
            continue
        pid = prev.get("project_id")
        if pid is not None and int(pid) not in present_pids:
            continue  # whole project absent from buffer (hidden/removed) -> keep its logs
        deletes.append({"type": "delete_timelog", "id": int(sid),
                        "summary": f"delete log {sid} ({prev['date']} {_fmt_hm(prev['minutes'])})"})

    # Management mode only: a task/tasklist heading removed from the buffer is a
    # DELETE in Teamwork. Guard with present_pids (removing a whole project just
    # hides it, never deletes) and only hit the topmost removed node — Teamwork
    # cascades to children, so deleting a parent/list would 404 on its kids.
    if manage:
        tl_proj = snapshot.get("tasklist_project", {})
        tk_proj = snapshot.get("task_project", {})
        tk_tl = snapshot.get("task_tasklist", {})
        tk_parent = snapshot.get("task_parent", {})
        del_tls = {tid for tid in snap_tls
                   if tid not in seen_tls and int(tl_proj.get(tid, 0) or 0) in present_pids}
        cand = {tid for tid in snap_tasks
                if tid not in seen_tks and int(tk_proj.get(tid, 0) or 0) in present_pids}

        def _ancestor_removed(tid):
            p = tk_parent.get(tid)
            while p:
                if p in cand:            # an ancestor task is itself being removed
                    return True
                p = tk_parent.get(p)
            return False

        del_tks = {tid for tid in cand
                   if tk_tl.get(tid) not in del_tls and not _ancestor_removed(tid)}
        for tid in sorted(del_tks, key=int):
            deletes.append({"type": "delete_task", "id": int(tid),
                            "summary": f"delete task {snap_tasks.get(tid, tid)!r}"})
        for tid in sorted(del_tls, key=int):
            deletes.append({"type": "delete_tasklist", "id": int(tid),
                            "summary": f"delete list {snap_tls.get(tid, tid)!r} (and its tasks)"})

    return {"actions": (creates_tl + creates_tk + renames + tag_writes
                        + log_writes + completes + deletes),
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


def _build_task_item(a: dict) -> dict:
    """Translate an action's task fields into a v1 `todo-item` body. Only keys the
    action carries are emitted, so an update touches exactly what changed."""
    item = {}
    if "title" in a:
        item["content"] = a["title"]
    if "description" in a:
        item["description"] = a["description"] or ""
    if "due" in a:
        item["due-date"] = _due_compact(a["due"])
    if "priority" in a:
        item["priority"] = a.get("priority") or ""
    if "assignees" in a:
        item["responsible-party-id"] = ",".join(a["assignees"])
    return item


def _execute(a: dict, client: "Client", created: dict):
    t = a["type"]
    if t == "create_tasklist":
        created[a["ref"]] = client.create_tasklist(a["project_id"], a["name"])
    elif t == "update_tasklist":
        client.update_tasklist(a["id"], a["name"])
    elif t == "create_task":
        created[a["ref"]] = client.create_task(int(_resolve(a["tasklist"], created)),
                                               _build_task_item(a))
    elif t == "create_subtask":
        created[a["ref"]] = client.create_subtask(int(_resolve(a["parent"], created)),
                                                  _build_task_item(a))
    elif t == "update_task":
        client.update_task(a["id"], _build_task_item(a))
    elif t == "delete_task":
        client.delete_task(a["id"])
    elif t == "set_task_tags":
        client.set_task_tags(int(_resolve(a["task"], created)), a["tags"])
    elif t == "complete_task":
        client.complete_task(int(_resolve(a["task"], created)))
    elif t == "create_timelog":
        a["_new_id"] = client.create_timelog(int(_resolve(a["task"], created)), a["body"])
    elif t == "update_timelog":
        client.update_timelog(a["id"], a["body"])
    elif t == "delete_timelog":
        client.delete_timelog(a["id"])
    elif t == "delete_tasklist":
        client.delete_tasklist(a["id"])


def _mutate_on_success(a: dict, created: dict):
    """Fold applied results back into the parsed tree so re-parse sees IDs."""
    if a["type"] in ("create_tasklist", "create_task", "create_subtask"):
        a["_obj"]["id"] = created[a["ref"]]
    elif a["type"] == "create_timelog":
        a["_obj"]["id"] = a.get("_new_id")


def _emit(obj: dict):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _apply_actions(actions, execute_one, on_success=None):
    """Shared streamed apply loop: emit begin/start/(retry…)/ok|fail per action,
    with retry + abort-on-first-failure. EXECUTE_ONE(a) does the work and may
    raise; ON_SUCCESS(a), if given, folds results back after a success. Returns
    (applied, aborted)."""
    _emit({"event": "begin", "count": len(actions)})
    aborted = False
    applied = 0
    for idx, a in enumerate(actions):
        _emit({"event": "start", "idx": idx, "type": a["type"], "summary": a.get("summary", a["type"])})
        err = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                execute_one(a)
                err = None
                break
            except Exception as e:  # noqa: BLE001 - report any failure to the UI
                err = f"{type(e).__name__}: {e}"
                if attempt < MAX_ATTEMPTS:
                    _emit({"event": "retry", "idx": idx, "attempt": attempt, "error": err})
                    time.sleep(min(BACKOFF_BASE * attempt, 5))
        if err is None:
            if on_success:
                on_success(a)
            applied += 1
            _emit({"event": "ok", "idx": idx})
        else:
            _emit({"event": "fail", "idx": idx, "attempts": MAX_ATTEMPTS, "error": err})
            aborted = True
            break
    return applied, aborted


def apply_stream(plan: dict, client: "Client", parsed: dict, out_path: str, snap_path: str):
    actions = plan["actions"]
    created: dict = {}
    applied, aborted = _apply_actions(
        actions,
        lambda a: _execute(a, client, created),
        lambda a: _mutate_on_success(a, created))
    # Always persist the (partially) applied state so unapplied edits survive.
    # Carry the people map (id->name) forward so the next assignee diff resolves.
    people = {}
    try:
        people = json.loads(pathlib.Path(snap_path).read_text(encoding="utf-8")).get("people", {})
    except (OSError, ValueError):
        pass
    pathlib.Path(out_path).write_text(serialize_parsed(parsed), encoding="utf-8")
    pathlib.Path(snap_path).write_text(
        json.dumps(build_snapshot_from_parsed(parsed, people)), encoding="utf-8")
    _emit({"event": "done", "aborted": aborted, "applied": applied,
           "total": len(actions), "buffer": out_path})


# --------------------------------------------------------------------------- #
# Comments: parse / diff / apply (a flat list of * headings under one task)
# --------------------------------------------------------------------------- #
_COMMENT_ID_RE = re.compile(r"^\s*:TW_COMMENT_ID:\s*(\d+)\s*$")  # _DRAWER_LINE_RE: see top


def parse_comments(text: str) -> dict:
    """Parse a comments buffer: one `*` heading per comment, body text below it,
    optional :TW_COMMENT_ID: (present = existing, absent = a new comment)."""
    meta = {"task": None, "user": None, "account": None}
    comments: list[dict] = []
    problems: list[str] = []
    cur = None

    def close():
        nonlocal cur
        if cur is not None:
            cur["body"] = "\n".join(cur.pop("_lines")).strip()
        cur = None

    for raw in text.splitlines():
        if raw.startswith("#+TEAMWORK_COMMENTS:"):
            for tok in raw.split(":", 1)[1].split():
                if tok.startswith("task="):
                    meta["task"] = tok[5:]
                elif tok.startswith("user="):
                    meta["user"] = tok[5:]
            continue
        if raw.startswith("#+TEAMWORK_ACCOUNT:"):
            meta["account"] = raw.split(":", 1)[1].strip() or None
            continue
        if raw.startswith("#+") or raw.startswith("#"):
            continue
        hm = _HEAD_RE.match(raw)
        if hm:
            close()
            cur = {"id": None, "author": hm.group(2).strip(), "_lines": []}
            comments.append(cur)
            continue
        cm = _COMMENT_ID_RE.match(raw)
        if cm and cur is not None:
            cur["id"] = int(cm.group(1))
            continue
        if _DRAWER_LINE_RE.match(raw):
            continue
        if cur is not None:
            cur["_lines"].append(raw)
    close()
    return {"meta": meta, "comments": comments, "problems": problems}


def compute_comment_plan(parsed: dict, snapshot: dict) -> dict:
    """Diff parsed comments against the snapshot -> create/update/delete actions."""
    actions = []
    problems = list(parsed["problems"])
    snap = dict(snapshot.get("comments", {}))
    seen: set[str] = set()
    for c in parsed["comments"]:
        body = (c.get("body") or "").strip()
        if c["id"] is None:
            if body:  # a new heading with no text is ignored, not posted
                actions.append({"type": "create_comment", "body": body,
                                "summary": f"new comment {body[:40]!r}", "_obj": c})
        else:
            sid = str(c["id"])
            seen.add(sid)
            prev = snap.get(sid)
            if prev is None or (prev or "").strip() != body:
                actions.append({"type": "update_comment", "id": c["id"], "body": body,
                                "summary": f"edit comment {c['id']}", "_obj": c})
    for sid in snap:
        if sid not in seen:
            actions.append({"type": "delete_comment", "id": int(sid),
                            "summary": f"delete comment {sid}"})
    return {"actions": actions, "problems": problems}


def apply_comments(plan: dict, client: "Client", task_id: int, parsed: dict,
                   out_path: str, snap_path: str):
    def execute_one(a):
        t = a["type"]
        if t == "create_comment":
            a["_new_id"] = client.create_comment(task_id, a["body"])
        elif t == "update_comment":
            client.update_comment(a["id"], a["body"])
        elif t == "delete_comment":
            client.delete_comment(a["id"])

    def on_success(a):
        if a["type"] == "create_comment":
            a["_obj"]["id"] = a.get("_new_id")

    applied, aborted = _apply_actions(plan["actions"], execute_one, on_success)
    pathlib.Path(out_path).write_text(serialize_comments(parsed), encoding="utf-8")
    pathlib.Path(snap_path).write_text(
        json.dumps(build_comment_snapshot_from_parsed(parsed)), encoding="utf-8")
    _emit({"event": "done", "aborted": aborted, "applied": applied,
           "total": len(plan["actions"]), "buffer": out_path})


# --------------------------------------------------------------------------- #
# Snapshot / buffer cache helpers
# --------------------------------------------------------------------------- #
def snapshot_path(date_from: str, date_to: str, account=None) -> pathlib.Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    # No-account path is unchanged (backward compatible); accounts get their own
    # snapshot so submitting account B never diffs against account A's pull.
    if account:
        return CACHE_DIR / f"snapshot_{_slug(account)}_{date_from}_{date_to}.json"
    return CACHE_DIR / f"snapshot_{date_from}_{date_to}.json"


def manage_snapshot_path(account=None) -> pathlib.Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return CACHE_DIR / (f"manage_{_slug(account)}.json" if account else "manage.json")


def comment_snapshot_path(task_id, account=None) -> pathlib.Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return CACHE_DIR / (f"comments_{_slug(account)}_{task_id}.json" if account
                        else f"comments_{task_id}.json")


def cache_org_path(kind: str, key: str, account=None) -> pathlib.Path:
    """Where the last rendered org buffer for (KIND, KEY, account) is cached, so a
    reopen can show stale data instantly while a fresh pull runs in the
    background. KIND is timesheet|manage|comments; KEY is the range / "manage" /
    task id."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    return CACHE_DIR / f"buf_{kind}_{_slug(account)}_{_slug(key)}.org"


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


def _select_projects(c, prefs, args_projects, args_prev):
    """Apply hidden prefs and the per-account project filter to the active-project
    list. Returns (projects, hidden_ids, hidden_names, filter_ids, filter_names,
    name_by_id). An explicit --projects overrides the stored filter for one run;
    otherwise a non-empty stored filter is an allowlist, and an empty one means
    "all active projects" (the original behaviour)."""
    prev_present = hidden_prop = None
    if args_prev and os.path.exists(args_prev):
        pv = parse_org(pathlib.Path(args_prev).read_text(encoding="utf-8"))
        prev_present = {str(p["id"]) for p in pv["projects"] if p["id"] is not None}
        hp = pv["meta"].get("hidden")
        hidden_prop = {str(x) for x in hp} if hp is not None else None
    hidden_ids = reconcile_hidden(prefs, prev_present, hidden_prop)

    projects_all = c.projects()
    name_by_id = {str(p["id"]): p["name"] for p in projects_all}
    old_names = prefs.get("hidden") or {}
    hidden_names = {h: name_by_id.get(h, old_names.get(h, "?")) for h in hidden_ids}

    projects = [p for p in projects_all if str(p["id"]) not in hidden_ids]
    filt = [int(x) for x in (prefs.get("filter") or [])]
    only = (set(int(x) for x in args_projects.split(",")) if args_projects
            else (set(filt) if filt else None))
    if only is not None:
        projects = [p for p in projects if p["id"] in only]
    filt_names = {str(pid): name_by_id.get(str(pid), "?") for pid in filt}
    return projects, hidden_ids, hidden_names, filt, filt_names, name_by_id


def _walk_tree(c, projects):
    """Fetch every tasklist and its tasks (incl. subtasks/tags) for PROJECTS."""
    tasklists, tasks = [], []
    for i, p in enumerate(projects, 1):
        tls = c.tasklists(p["id"])
        tasklists.extend(tls)
        for tl in tls:
            tasks.extend(c.tasks(tl["id"], p["id"]))
        sys.stderr.write(f"\r  walked {i}/{len(projects)} projects")
        sys.stderr.flush()
    sys.stderr.write("\n")
    return tasklists, tasks


def _gather_people(c, projects) -> dict:
    """Union of assignable people across PROJECTS as {id: name}."""
    people = {}
    for p in projects:
        try:
            for person in c.project_people(p["id"]):
                people[person["id"]] = person["name"]
        except Exception:  # noqa: BLE001 - a project without people access is not fatal
            pass
    return people


def cmd_pull(args):
    creds = load_creds(getattr(args, "account", None))
    account = creds.get("account")
    c = Client(creds)
    meta = {"from": args.date_from, "to": args.date_to, "user_id": creds["user_id"],
            "account": account, "mode": "timesheet"}

    prefs = load_prefs(account)
    projects, hidden_ids, hidden_names, _filt, _filt_names, _names = \
        _select_projects(c, prefs, args.projects, args.prev)
    sys.stderr.write(f"projects: {len(projects)} shown, {len(hidden_ids)} hidden\n")

    tasklists, tasks = _walk_tree(c, projects)

    logs = [lg for lg in c.my_timelogs(args.date_from, args.date_to)
            if str(lg["project_id"]) not in hidden_ids]
    sys.stderr.write(f"time logs in range: {len(logs)}\n")

    # Reattach logs on completed/archived (hence unfetched) lists/tasks by
    # rebuilding those nodes from each log's own metadata.
    before = len(tasks)
    synthesize_missing(projects, tasklists, tasks, logs)
    if len(tasks) > before:
        sys.stderr.write(f"reattached {len(tasks) - before} completed/archived task(s) from logs\n")

    # Merge (don't replace) prefs so the per-account project filter survives.
    update_prefs(account, hidden=hidden_names, shown=[p["id"] for p in projects])
    snapshot_path(args.date_from, args.date_to, account).write_text(
        json.dumps(build_snapshot(projects, tasklists, tasks, logs, meta)), encoding="utf-8"
    )
    org = render_org(projects, tasklists, tasks, logs, meta, hidden_names)
    cache_org_path("timesheet", f"{args.date_from}_{args.date_to}", account).write_text(
        org, encoding="utf-8")
    (open(args.out, "w", encoding="utf-8") if args.out else sys.stdout).write(org)


def cmd_manage(args):
    creds = load_creds(getattr(args, "account", None))
    account = creds.get("account")
    c = Client(creds)
    meta = {"user_id": creds["user_id"], "account": account, "mode": "manage"}

    prefs = load_prefs(account)
    projects, hidden_ids, hidden_names, filt, filt_names, _names = \
        _select_projects(c, prefs, args.projects, args.prev)
    sys.stderr.write(f"projects: {len(projects)} shown, {len(hidden_ids)} hidden, "
                     f"{len(filt)} in filter\n")

    tasklists, tasks = _walk_tree(c, projects)

    # Resolve each task's assignee ids to names for display; keep the id->name map
    # in the snapshot so submit can turn edited names back into ids.
    people = _gather_people(c, projects)
    for tk in tasks:
        tk["assignee_names"] = [people.get(i, i) for i in tk.get("assignees", [])]
    sys.stderr.write(f"people assignable: {len(people)}\n")

    update_prefs(account, hidden=hidden_names, shown=[p["id"] for p in projects])
    snap = build_snapshot(projects, tasklists, tasks, [], meta)
    snap["people"] = people
    manage_snapshot_path(account).write_text(json.dumps(snap), encoding="utf-8")
    org = render_manage(projects, tasklists, tasks, meta, hidden_names, filt, filt_names)
    cache_org_path("manage", "manage", account).write_text(org, encoding="utf-8")
    (open(args.out, "w", encoding="utf-8") if args.out else sys.stdout).write(org)


def cmd_comments_pull(args):
    creds = load_creds(getattr(args, "account", None))
    account = creds.get("account")
    c = Client(creds)
    tid = int(args.task)
    title = c.task_title(tid)
    comments = c.comments(tid)
    sys.stderr.write(f"comments on task {tid}: {len(comments)}\n")
    meta = {"user_id": creds["user_id"], "account": account}
    comment_snapshot_path(tid, account).write_text(
        json.dumps(build_comment_snapshot(tid, comments)), encoding="utf-8")
    org = render_comments(tid, title, comments, meta)
    cache_org_path("comments", str(tid), account).write_text(org, encoding="utf-8")
    (open(args.out, "w", encoding="utf-8") if args.out else sys.stdout).write(org)


def cmd_projects(args):
    """List active projects (id, name, in_filter) as JSON for the filter picker."""
    creds = load_creds(getattr(args, "account", None))
    account = creds.get("account")
    prefs = load_prefs(account)
    filt = {str(x) for x in (prefs.get("filter") or [])}
    projs = Client(creds).projects()
    print(json.dumps([{"id": p["id"], "name": p["name"],
                       "in_filter": str(p["id"]) in filt} for p in projs],
                     ensure_ascii=False))


def cmd_people(args):
    """List assignable people (id, name) as JSON for the assignee picker, across
    the account's filtered/shown projects."""
    creds = load_creds(getattr(args, "account", None))
    account = creds.get("account")
    c = Client(creds)
    prefs = load_prefs(account)
    projects, *_ = _select_projects(c, prefs, getattr(args, "projects", None), None)
    people = _gather_people(c, projects)
    out = [{"id": pid, "name": nm} for pid, nm in people.items()]
    out.sort(key=lambda x: x["name"].lower())
    print(json.dumps(out, ensure_ascii=False))


def cmd_tags(args):
    """List existing tag names as JSON for the tag picker."""
    print(json.dumps(Client(load_creds(getattr(args, "account", None))).all_tags(),
                     ensure_ascii=False))


def cmd_filter_get(args):
    prefs = load_prefs(getattr(args, "account", None))
    print(json.dumps({"filter": [int(x) for x in (prefs.get("filter") or [])]}))


def cmd_filter_set(args):
    account = getattr(args, "account", None)
    ids = [int(x) for x in (args.projects or "").split(",") if x.strip().isdigit()]
    update_prefs(account, filter=ids)
    print(json.dumps({"filter": ids}))


def cmd_cached(args):
    """Emit the last cached org buffer for (kind, key, account), if any. Exit 3
    when there is no cache yet (so Emacs falls back to a plain load)."""
    p = cache_org_path(args.kind, args.key, getattr(args, "account", None))
    if not p.exists():
        raise SystemExit(3)
    sys.stdout.write(p.read_text(encoding="utf-8"))


def cmd_submit(args):
    text = pathlib.Path(args.file).read_text(encoding="utf-8")
    parsed = parse_org(text)
    # The buffer's own #+TEAMWORK_ACCOUNT wins; --account is an override/fallback.
    account = parsed["meta"].get("account") or getattr(args, "account", None)
    if parsed["meta"].get("mode") == "manage":
        snap_file = manage_snapshot_path(account)
        if not snap_file.exists():
            raise SystemExit(f"no management snapshot (re-run manage first): {snap_file}")
    else:
        frm, to = parsed["meta"]["from"], parsed["meta"]["to"]
        if not frm or not to:
            raise SystemExit("buffer is missing its #+TEAMWORK: from=.. to=.. header")
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


def cmd_comments_submit(args):
    text = pathlib.Path(args.file).read_text(encoding="utf-8")
    parsed = parse_comments(text)
    tid = parsed["meta"].get("task")
    if not tid:
        raise SystemExit("buffer is missing its #+TEAMWORK_COMMENTS: task=.. header")
    account = parsed["meta"].get("account") or getattr(args, "account", None)
    snap_file = comment_snapshot_path(tid, account)
    if not snap_file.exists():
        raise SystemExit(f"no comment snapshot for task {tid} (re-run comments-pull first)")
    snapshot = json.loads(snap_file.read_text(encoding="utf-8"))
    plan = compute_comment_plan(parsed, snapshot)

    if args.json:
        print(json.dumps({"actions": [public_action(a) for a in plan["actions"]],
                          "problems": plan["problems"]}, ensure_ascii=False))
        return
    if args.apply:
        if plan["problems"]:
            _emit({"event": "error", "problems": plan["problems"]})
            raise SystemExit(2)
        creds = load_creds(account)
        out = args.out or (str(args.file) + ".applied")
        apply_comments(plan, Client(creds), int(tid), parsed, out, str(snap_file))
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

    mn = sub.add_parser("manage", help="emit the project structure (no time filter) to manage")
    mn.add_argument("--projects", default=None, help="comma-separated project ids (overrides the stored filter)")
    mn.add_argument("--prev", default=None, help="the buffer being replaced (for hidden-project reconciliation)")
    mn.add_argument("--account", default=None, help="which stored account to use")
    mn.add_argument("--out", default=None)
    mn.set_defaults(func=cmd_manage)

    cp = sub.add_parser("comments-pull", help="emit a task's comments as an editable org buffer")
    cp.add_argument("--task", required=True, help="task id to fetch comments for")
    cp.add_argument("--account", default=None, help="which stored account to use")
    cp.add_argument("--out", default=None)
    cp.set_defaults(func=cmd_comments_pull)

    pr = sub.add_parser("projects", help="list active projects as JSON (with in_filter flags)")
    pr.add_argument("--account", default=None, help="which stored account to use")
    pr.set_defaults(func=cmd_projects)

    fg = sub.add_parser("filter-get", help="print the account's project filter as JSON")
    fg.add_argument("--account", default=None, help="which stored account to use")
    fg.set_defaults(func=cmd_filter_get)

    pp = sub.add_parser("people", help="list assignable people as JSON (assignee picker)")
    pp.add_argument("--projects", default=None, help="comma-separated project ids (else the filter)")
    pp.add_argument("--account", default=None, help="which stored account to use")
    pp.set_defaults(func=cmd_people)

    tg = sub.add_parser("tags", help="list existing tag names as JSON (tag picker)")
    tg.add_argument("--account", default=None, help="which stored account to use")
    tg.set_defaults(func=cmd_tags)

    fs = sub.add_parser("filter-set", help="set the account's project filter (comma-separated ids)")
    fs.add_argument("--projects", default="", help="comma-separated project ids (empty clears the filter)")
    fs.add_argument("--account", default=None, help="which stored account to use")
    fs.set_defaults(func=cmd_filter_set)

    ch = sub.add_parser("cached", help="print the last cached org buffer (exit 3 if none)")
    ch.add_argument("--kind", required=True, choices=["timesheet", "manage", "comments"])
    ch.add_argument("--key", required=True, help="range 'FROM_TO' / 'manage' / task id")
    ch.add_argument("--account", default=None, help="which stored account to use")
    ch.set_defaults(func=cmd_cached)

    sb = sub.add_parser("submit")
    sb.add_argument("--file", required=True)
    sb.add_argument("--apply", action="store_true", help="execute the plan (streams progress)")
    sb.add_argument("--stream", action="store_true", help="(implied by --apply) stream JSON events")
    sb.add_argument("--json", action="store_true", help="emit the plan as JSON and exit")
    sb.add_argument("--account", default=None, help="account fallback if the buffer lacks a header")
    sb.add_argument("--out", default=None, help="where to write the updated buffer after --apply")
    sb.set_defaults(func=cmd_submit)

    cs = sub.add_parser("comments-submit", help="diff/apply an edited comments buffer")
    cs.add_argument("--file", required=True)
    cs.add_argument("--apply", action="store_true", help="execute the plan (streams progress)")
    cs.add_argument("--json", action="store_true", help="emit the plan as JSON and exit")
    cs.add_argument("--account", default=None, help="account fallback if the buffer lacks a header")
    cs.add_argument("--out", default=None, help="where to write the updated buffer after --apply")
    cs.set_defaults(func=cmd_comments_submit)

    args = ap.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
