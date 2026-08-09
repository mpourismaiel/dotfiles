#!/usr/bin/env python3
"""GitHub PR review-comment sidecar.

Fetches a pull request's review-comment threads (the inline "conversations")
plus the general PR discussion through the `gh` CLI, and renders them as an
editable org buffer where the newest-active conversation floats to the top.
Reply by adding a level-2 heading with an EMPTY author and no properties, type
your reply below it, then submit; each pending reply is posted back to GitHub.

Every bit of GitHub access is delegated to `gh`, which owns authentication and
account selection, so there is no keyring / credential code here — only the
Python stdlib and the `gh` binary are required.

The pure functions (md_to_org, org_to_md, render_org, parse_org, compute_plan)
have no subprocess dependency and are unit-tested offline. Only run_gh / graphql
/ gh_post shell out.

Subcommands:
    ping                                  gh auth sanity check (read-only)
    pull  --pr REF [--repo R] [--out F]   emit the org buffer to stdout / F
    submit --file F [--json]              print the reply plan (JSON with --json)
    submit --file F --apply               post pending replies, streaming events
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
import time

MAX_ATTEMPTS = 3
BACKOFF_BASE = 2  # seconds * attempt between retries; tests set this to 0


# --------------------------------------------------------------------------- #
# gh invocation (the only subprocess code)
# --------------------------------------------------------------------------- #
def run_gh(args: list, input_text: str = None) -> str:
    """Run `gh ARGS`, returning stdout. Raises RuntimeError on failure so the
    apply loop can retry it (SystemExit would not be caught by `except Exception`)."""
    import subprocess

    p = subprocess.run(["gh", *args], input=input_text,
                       capture_output=True, text=True)
    if p.returncode != 0:
        msg = (p.stderr or p.stdout or "").strip()
        raise RuntimeError(f"gh {' '.join(args)} failed:\n{msg}")
    return p.stdout


def graphql(query: str, **variables) -> dict:
    """Run a GraphQL query via `gh api graphql` and return its `data` object.
    Integer variables are passed with -F (typed), everything else with -f (raw);
    None-valued variables are omitted so they arrive as GraphQL null."""
    args = ["api", "graphql", "-f", f"query={query}"]
    for k, v in variables.items():
        if v is None:
            continue
        args += (["-F", f"{k}={v}"] if isinstance(v, int) else ["-f", f"{k}={v}"])
    data = json.loads(run_gh(args))
    if data.get("errors"):
        raise RuntimeError("GitHub GraphQL error: " + json.dumps(data["errors"]))
    return data.get("data") or {}


def gh_post(path: str, payload: dict):
    """POST PAYLOAD (as JSON) to a REST endpoint via `gh api --input -`."""
    run_gh(["api", "-X", "POST", path, "--input", "-"],
           input_text=json.dumps(payload))


_URL_RE = re.compile(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)")


def resolve_pr(ref: str, repo: str = None) -> dict:
    """Resolve a PR reference (URL, number, or branch) to canonical fields.

    `gh pr view` accepts a URL / number / branch and knows the repo from -R or
    the working directory; we read back the canonical `url` and parse the base
    owner/repo/number from it (the base repo is where the comments live)."""
    args = ["pr", "view", ref, "--json", "url,title"]
    if repo:
        args += ["-R", repo]
    d = json.loads(run_gh(args))
    m = _URL_RE.search(d.get("url", ""))
    if not m:
        raise RuntimeError(f"could not parse a PR url from `gh pr view {ref}`")
    return {"owner": m.group(1), "repo": m.group(2), "number": int(m.group(3)),
            "url": d["url"], "title": (d.get("title") or "").strip()}


# --------------------------------------------------------------------------- #
# Fetch (paginated)
# --------------------------------------------------------------------------- #
_Q_THREADS = """
query($owner:String!,$name:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      reviewThreads(first:50, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id isResolved isOutdated path line originalLine
          comments(first:100){
            totalCount
            nodes{ databaseId url author{login} createdAt body originalCommit{oid} }
          }
        }
      }
    }
  }
}
"""

_Q_ISSUE = """
query($owner:String!,$name:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      comments(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{ databaseId url author{login} createdAt body }
      }
    }
  }
}
"""


def _paginate(query: str, path: list, owner: str, name: str, number: int) -> list:
    """Walk a `nodes`/`pageInfo` connection to the end, following the cursor.
    PATH is the key sequence from `pullRequest` down to the connection."""
    nodes, cursor = [], None
    while True:
        conn = graphql(query, owner=owner, name=name, number=number, cursor=cursor)
        conn = conn["repository"]["pullRequest"]
        for key in path:
            conn = conn[key]
        nodes.extend(conn["nodes"])
        info = conn["pageInfo"]
        if info["hasNextPage"]:
            cursor = info["endCursor"]
        else:
            return nodes


# --------------------------------------------------------------------------- #
# Local checkout resolution — turn a review thread into openable links
# --------------------------------------------------------------------------- #
def _git(worktree: str, args: list):
    import subprocess

    return subprocess.run(["git", "-C", worktree, *args],
                          capture_output=True, text=True)


def _git_out(worktree: str, args: list) -> str:
    p = _git(worktree, args)
    return p.stdout if p.returncode == 0 else ""


def _git_ok(worktree: str, args: list) -> bool:
    return bool(worktree) and _git(worktree, args).returncode == 0


_REMOTE_RE = re.compile(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?(?:\s|$)")


def _remote_matches(remote_line: str, slug: str) -> bool:
    """True if a `git remote -v` line points at github.com/SLUG (case-insensitive)."""
    m = _REMOTE_RE.search(remote_line)
    return bool(m) and m.group(1).lower() == slug.lower()


def local_root(worktree: str, owner: str, repo: str):
    """Return WORKTREE's toplevel if any of its git remotes point at OWNER/REPO,
    else None. This is the "does the magit/git remote match the PR" check."""
    if not worktree:
        return None
    remotes = _git_out(worktree, ["remote", "-v"])
    slug = f"{owner}/{repo}"
    if not any(_remote_matches(ln, slug) for ln in remotes.splitlines()):
        return None
    root = _git_out(worktree, ["rev-parse", "--show-toplevel"]).strip()
    return root or None


def conversation_links(conv: dict, root, file_exists, blob_exists) -> list:
    """Build the org links shown under a review conversation (before its comments).

    Pure given the FILE_EXISTS(abspath) and BLOB_EXISTS(oid, relpath) probes, so
    it is unit-tested with fakes. Emits whichever of these actually resolve:
      - local file   : open the working-tree file at the current line
      - file @<rev>  : open the file at the commit the comment was written on
      - browse thread: the thread's GitHub permalink
    """
    if conv["kind"] != "review":
        return []
    links, path, line = [], conv.get("path"), conv.get("line")
    if root and path and file_exists(os.path.join(root, path)):
        tgt = os.path.join(root, path)
        links.append(f"[[file:{tgt}::{line}][local file]]" if line
                     else f"[[file:{tgt}][local file]]")
    oid, oline = conv.get("orig_oid"), conv.get("orig_line")
    if root and oid and path and blob_exists(oid, path):
        anchor = f"::{oline}" if oline else ""
        links.append(f"[[ghpr-rev:{oid}:{path}{anchor}][file @{oid[:7]}]]")
    if conv.get("url"):
        links.append(f"[[{conv['url']}][browse thread]]")
    return links


def annotate_local_links(convs: list, pr: dict, worktree: str):
    """Attach conv['links'] to every conversation; return the matched local root."""
    root = local_root(worktree, pr["owner"], pr["repo"])
    for c in convs:
        c["links"] = conversation_links(
            c, root, os.path.exists,
            lambda oid, path: _git_ok(root, ["cat-file", "-e", f"{oid}:{path}"]))
    return root


def _author(c: dict) -> str:
    a = c.get("author")
    return (a or {}).get("login") or "ghost"


def _fmt_dt(iso: str) -> str:
    """Render a GitHub UTC timestamp as local 'YYYY-MM-DD HH:MM' (raw ISO on error)."""
    import datetime as dt

    try:
        t = dt.datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
        return t.astimezone().strftime("%Y-%m-%d %H:%M")
    except (ValueError, TypeError):
        return iso or ""


def _message(c: dict) -> dict:
    return {"author": _author(c), "id": c["databaseId"], "url": c.get("url"),
            "created": c["createdAt"], "body": c.get("body") or ""}


def build_conversations(threads: list, issue_comments: list) -> list:
    """Turn raw threads + issue comments into conversations sorted newest-first.

    A conversation's heading date is its FIRST comment; its sort key is its
    LAST (newest) comment, so a fresh reply floats the whole thread to the top.
    """
    convs = []
    for t in threads:
        cs = sorted(t["comments"]["nodes"], key=lambda c: c["createdAt"])
        if not cs:
            continue
        convs.append({
            "kind": "review",
            "thread_id": t["id"],
            "reply_to": cs[0]["databaseId"],
            "url": cs[0].get("url"),
            "path": t.get("path"),
            "line": t.get("line") or t.get("originalLine"),
            "orig_oid": (cs[0].get("originalCommit") or {}).get("oid"),
            "orig_line": t.get("originalLine"),
            "state": ("resolved" if t["isResolved"]
                      else "outdated" if t["isOutdated"] else "open"),
            "first": cs[0]["createdAt"], "last": cs[-1]["createdAt"],
            "truncated": t["comments"]["totalCount"] > len(cs),
            "messages": [_message(c) for c in cs],
        })
    if issue_comments:
        cs = sorted(issue_comments, key=lambda c: c["createdAt"])
        convs.append({
            "kind": "issue", "state": "discussion",
            "first": cs[0]["createdAt"], "last": cs[-1]["createdAt"],
            "truncated": False,
            "messages": [_message(c) for c in cs],
        })
    convs.sort(key=lambda c: c["last"], reverse=True)
    return convs


# --------------------------------------------------------------------------- #
# Markdown <-> org (lightweight, dependency-free)
# --------------------------------------------------------------------------- #
_FENCE_RE = re.compile(r"```([^\n`]*)\n(.*?)```", re.S)
_SRC_RE = re.compile(r"#\+begin_src[^\n]*\n(.*?)\n[ \t]*#\+end_src", re.S | re.I)


def md_to_org(text: str) -> str:
    """Convert GitHub-flavoured markdown to readable org (lossy but faithful).

    Fenced code blocks become src blocks; `#` headings become bold lines (never
    org headings, so they can't collide with the buffer structure); `*`/`+`
    bullets become `-`; links, bold and inline code get org syntax."""
    text = (text or "").replace("\r\n", "\n").replace("\r", "\n")

    blocks: list[str] = []

    def stash(m):
        lang = m.group(1).strip()
        code = m.group(2)
        if code.endswith("\n"):
            code = code[:-1]
        blocks.append(f"#+begin_src {lang}\n{code}\n#+end_src".replace("  ", "  "))
        return f"\x00{len(blocks) - 1}\x00"

    text = _FENCE_RE.sub(stash, text)

    out = []
    for ln in text.split("\n"):
        h = re.match(r"^\s{0,3}(#{1,6})\s+(.*)$", ln)
        if h:
            out.append(f"*{h.group(2).strip()}*")
            continue
        b = re.match(r"^(\s*)[\*\+]\s+(.*)$", ln)
        if b:
            ln = f"{b.group(1)}- {b.group(2)}"
        ln = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r"[[\2][\1]]", ln)
        ln = re.sub(r"\*\*([^*]+)\*\*", r"*\1*", ln)
        ln = re.sub(r"`([^`]+)`", r"~\1~", ln)
        out.append(ln)
    text = "\n".join(out)

    return re.sub(r"\x00(\d+)\x00", lambda m: blocks[int(m.group(1))], text)


def org_to_md(text: str) -> str:
    """Convert an org reply back to markdown for posting. Replies are usually
    prose, so this is deliberately minimal: src blocks -> fenced code, org links
    and inline code back to markdown; everything else is posted as typed."""
    text = (text or "").replace("\r\n", "\n")

    def src(m):
        first = m.group(0).split("\n", 1)[0]
        lm = re.match(r"[ \t]*#\+begin_src\s+(\S+)", first, re.I)
        return f"```{lm.group(1) if lm else ''}\n{m.group(1)}\n```"

    text = _SRC_RE.sub(src, text)
    text = re.sub(r"\[\[([^\]]+)\]\[([^\]]+)\]\]", r"[\2](\1)", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"~([^~]+)~", r"`\1`", text)
    return text.strip()


# --------------------------------------------------------------------------- #
# Pure rendering: conversations -> org text
# --------------------------------------------------------------------------- #
def render_org(pr: dict, convs: list, root: str = None) -> str:
    repo = f"{pr['owner']}/{pr['repo']}"
    out = [
        f"#+TITLE: PR #{pr['number']} {repo} — {pr['title']}",
        f"#+GITHUB_PR: repo={repo} number={pr['number']}",
        f"#+GITHUB_URL: {pr['url']}",
    ]
    if root:
        out.append(f"#+GITHUB_WORKTREE: {root}")
    out += [
        "# Conversations are sorted newest-reply-first. A review thread's heading is",
        "# its file:line, tagged :resolved: / :outdated: when so; the links line below",
        "# opens the file locally, at the comment's revision, or on GitHub. To reply:",
        "# add a '** ' heading with an EMPTY author and NO properties under a thread,",
        "# type your reply, then C-c C-c. To resolve a thread: put [d] at the end of",
        "# any of its '** ' headings, then C-c C-c.  C-c C-g refetches.",
        "",
    ]
    for c in convs:
        if c["kind"] == "review":
            head = f"* {c['path']}:{c['line']}" if c.get("path") else "* (file)"
            tag = {"resolved": " :resolved:", "outdated": " :outdated:"}.get(c["state"], "")
            out.append(head + tag)
        else:
            out.append("* General discussion")
        out.append(":PROPERTIES:")
        out.append(f":GH_KIND: {c['kind']}")
        out.append(f":GH_STATE: {c['state']}")
        if c["kind"] == "review":
            out.append(f":GH_THREAD: {c['thread_id']}")
            out.append(f":GH_REPLY_TO: {c['reply_to']}")
            if c.get("path"):
                out.append(f":GH_PATH: {c['path']}")
        out.append(":END:")
        if c.get("truncated"):
            out.append("# (only the first 100 comments of this thread were fetched)")
        if c["kind"] == "review":
            links = c.get("links") or []
            if links:
                out.append("- " + "  ·  ".join(links))
        for m in c["messages"]:
            out.append(f"** {_fmt_dt(m['created'])} {m['author']}")
            out.append(":PROPERTIES:")
            out.append(f":GH_COMMENT: {m['id']}")
            out.append(f":GH_CREATED: {m['created']}")
            out.append(":END:")
            body = md_to_org(m["body"]).rstrip()
            if body:
                out.append(body)
            if m.get("url"):
                out.append("")
                out.append(f"[[{m['url']}][🔗 view comment on GitHub]]")
        out.append("")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------- #
# Pure parsing: org text -> conversations (for reply detection)
# --------------------------------------------------------------------------- #
# A heading is one or two stars, then either whitespace+title or nothing at all
# (a hand-added empty-author reply is often just "**"). The mandatory boundary
# after the stars keeps markdown bold ("**bold**") from matching as a heading.
_H_RE = re.compile(r"^(\*{1,2})([ \t].*)?$")
_PROP_RE = re.compile(r"^\s*:([A-Za-z0-9_]+):\s*(.*?)\s*$")


def parse_org(text: str) -> dict:
    meta = {"repo": None, "number": None, "url": None}
    conversations: list[dict] = []
    cur = curmsg = drawer = None

    def close_msg():
        nonlocal curmsg
        if curmsg is not None:
            curmsg["body"] = "\n".join(curmsg.pop("_body")).strip()
            cur["messages"].append(curmsg)
            curmsg = None

    def close_conv():
        nonlocal cur
        close_msg()
        if cur is not None:
            conversations.append(cur)
            cur = None

    for raw in text.split("\n"):
        if raw.startswith("#+GITHUB_PR:"):
            for tok in raw.split(":", 1)[1].split():
                if tok.startswith("repo="):
                    meta["repo"] = tok[5:]
                elif tok.startswith("number="):
                    meta["number"] = int(tok[7:]) if tok[7:].isdigit() else None
            continue
        if raw.startswith("#+GITHUB_URL:"):
            meta["url"] = raw.split(":", 1)[1].strip()
            continue
        if raw.startswith("#"):
            if curmsg is not None and not raw.startswith("#+"):
                curmsg["_body"].append(raw)
            continue

        h = _H_RE.match(raw)
        if h and drawer is None:
            title = (h.group(2) or "").strip()
            if len(h.group(1)) == 1:
                close_conv()
                cur = {"header": title, "props": {}, "messages": []}
            else:
                if cur is None:
                    cur = {"header": "", "props": {}, "messages": []}
                close_msg()
                curmsg = {"author": title, "props": {}, "_body": []}
            continue

        if raw.strip() == ":PROPERTIES:":
            drawer = "msg" if curmsg is not None else "conv"
            continue
        if raw.strip() == ":END:":
            drawer = None
            continue
        if drawer is not None:
            pm = _PROP_RE.match(raw)
            if pm:
                target = curmsg["props"] if drawer == "msg" else cur["props"]
                target[pm.group(1)] = pm.group(2)
            continue

        if curmsg is not None:
            curmsg["_body"].append(raw)

    close_conv()
    return {"meta": meta, "conversations": conversations}


# --------------------------------------------------------------------------- #
# Pure diff: parsed buffer -> reply plan
# --------------------------------------------------------------------------- #
def _preview(md: str) -> str:
    line = (md or "").strip().splitlines()
    s = line[0] if line else ""
    return (s[:50] + "…") if len(s) > 50 else s


_DONE_RE = re.compile(r"\[[dD]\]\s*$")


def compute_plan(parsed: dict) -> dict:
    """Find each conversation's pending reply and/or resolve request.

    - Reply: the LAST `**` heading whose author is empty and which carries no
      `:GH_COMMENT:` mapping — exactly the heading you add by hand.
    - Resolve: a `[d]` at the end of ANY `**` heading of a review thread (the
      same marker teamwork uses to complete a task), unless already resolved.
    Everything else is left untouched."""
    actions, problems = [], []
    repo, number = parsed["meta"]["repo"], parsed["meta"]["number"]
    if not repo or not number:
        problems.append("buffer is missing its #+GITHUB_PR: repo=.. number=.. header")

    for c in parsed["conversations"]:
        msgs = c["messages"]
        if not msgs:
            continue
        kind = c["props"].get("GH_KIND")
        is_issue = kind == "issue" or (kind is None and "General discussion" in c["header"])

        # -- reply: a hand-added empty-author heading as the last message ------
        last = msgs[-1]
        if not last["author"].strip() and "GH_COMMENT" not in last["props"]:
            body = org_to_md(last["body"])
            if not body:
                problems.append(f"empty reply under {c['header']!r} — "
                                "add text or delete the blank heading")
            elif is_issue:
                actions.append({"type": "issue_reply", "repo": repo, "number": number,
                                "body": body,
                                "summary": f"comment on the PR discussion: \"{_preview(body)}\""})
            else:
                reply_to = c["props"].get("GH_REPLY_TO")
                if not reply_to:
                    problems.append(f"conversation {c['header']!r} has no :GH_REPLY_TO: "
                                    "property — cannot post a reply")
                else:
                    where = c["props"].get("GH_PATH") or c["header"]
                    actions.append({"type": "review_reply", "repo": repo, "number": number,
                                    "reply_to": reply_to, "body": body,
                                    "summary": f"reply on {where}: \"{_preview(body)}\""})

        # -- resolve: a [d] marker on any heading of a review thread ------------
        if not is_issue and any(_DONE_RE.search(m["author"]) for m in msgs):
            if c["props"].get("GH_STATE") == "resolved":
                pass  # already resolved on GitHub — nothing to do
            elif not c["props"].get("GH_THREAD"):
                problems.append(f"cannot resolve {c['header']!r}: no :GH_THREAD: property")
            else:
                where = c["props"].get("GH_PATH") or c["header"]
                actions.append({"type": "resolve_thread",
                                "thread_id": c["props"]["GH_THREAD"],
                                "summary": f"resolve thread on {where}"})
    return {"actions": actions, "problems": problems}


def public_action(a: dict) -> dict:
    """The plan is already JSON-clean, but keep the buffer body out of previews."""
    return {k: v for k, v in a.items() if k != "body"}


# --------------------------------------------------------------------------- #
# Apply (streaming, ordered, with retry + abort)
# --------------------------------------------------------------------------- #
def _emit(obj: dict):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def resolve_thread(thread_id: str):
    graphql("mutation($id:ID!){resolveReviewThread(input:{threadId:$id})"
            "{thread{isResolved}}}", id=thread_id)


def _do_action(a: dict):
    if a["type"] == "review_reply":
        gh_post(f"/repos/{a['repo']}/pulls/{a['number']}/comments/{a['reply_to']}/replies",
                {"body": a["body"]})
    elif a["type"] == "issue_reply":
        gh_post(f"/repos/{a['repo']}/issues/{a['number']}/comments", {"body": a["body"]})
    elif a["type"] == "resolve_thread":
        resolve_thread(a["thread_id"])


def apply_stream(plan: dict):
    actions = plan["actions"]
    _emit({"event": "begin", "count": len(actions)})
    applied, aborted = 0, False
    for idx, a in enumerate(actions):
        _emit({"event": "start", "idx": idx, "summary": a.get("summary", a["type"])})
        err = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                _do_action(a)
                err = None
                break
            except Exception as e:  # noqa: BLE001 - report any failure to the UI
                err = f"{type(e).__name__}: {e}"
                if attempt < MAX_ATTEMPTS:
                    _emit({"event": "retry", "idx": idx, "attempt": attempt, "error": err})
                    time.sleep(min(BACKOFF_BASE * attempt, 5))
        if err is None:
            applied += 1
            _emit({"event": "ok", "idx": idx})
        else:
            _emit({"event": "fail", "idx": idx, "attempts": MAX_ATTEMPTS, "error": err})
            aborted = True
            break
    _emit({"event": "done", "aborted": aborted, "applied": applied, "total": len(actions)})


# --------------------------------------------------------------------------- #
# Subcommands
# --------------------------------------------------------------------------- #
def cmd_ping(_args):
    print(f"OK: authenticated as {run_gh(['api', 'user', '--jq', '.login']).strip()} via gh")


def cmd_pull(args):
    pr = resolve_pr(args.pr, args.repo)
    threads = _paginate(_Q_THREADS, ["reviewThreads"],
                        pr["owner"], pr["repo"], pr["number"])
    issue = _paginate(_Q_ISSUE, ["comments"],
                      pr["owner"], pr["repo"], pr["number"])
    convs = build_conversations(threads, issue)
    root = annotate_local_links(convs, pr, args.worktree)
    sys.stderr.write(f"PR #{pr['number']} {pr['owner']}/{pr['repo']}: "
                     f"{len(threads)} thread(s), {len(issue)} discussion comment(s)"
                     + (f"; local checkout {root}" if root else "") + "\n")
    org = render_org(pr, convs, root)
    (open(args.out, "w", encoding="utf-8") if args.out else sys.stdout).write(org)


def cmd_submit(args):
    parsed = parse_org(pathlib.Path(args.file).read_text(encoding="utf-8"))
    plan = compute_plan(parsed)
    if args.json:
        print(json.dumps({"actions": [public_action(a) for a in plan["actions"]],
                          "problems": plan["problems"]}, ensure_ascii=False))
        return
    if args.apply:
        if plan["problems"]:
            _emit({"event": "error", "problems": plan["problems"]})
            raise SystemExit(2)
        apply_stream(plan)
        return
    if plan["problems"]:
        print("PROBLEMS:")
        for p in plan["problems"]:
            print(f"  ! {p}")
    if not plan["actions"]:
        print("No replies to submit.")
        return
    print(f"PLAN ({len(plan['actions'])} reply/replies):")
    for a in plan["actions"]:
        print(f"  {a['summary']}")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="github_pr")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping", help="gh auth sanity check").set_defaults(func=cmd_ping)

    pl = sub.add_parser("pull", help="fetch a PR's comments into an org buffer")
    pl.add_argument("--pr", required=True, help="PR url, number, or branch")
    pl.add_argument("--repo", default=None, help="owner/repo (for a bare number)")
    pl.add_argument("--worktree", default=None,
                    help="local checkout to link files from (if its remote matches the PR)")
    pl.add_argument("--out", default=None)
    pl.set_defaults(func=cmd_pull)

    sb = sub.add_parser("submit", help="post pending replies")
    sb.add_argument("--file", required=True)
    sb.add_argument("--apply", action="store_true", help="post the replies (streams events)")
    sb.add_argument("--json", action="store_true", help="emit the plan as JSON and exit")
    sb.set_defaults(func=cmd_submit)

    args = ap.parse_args(argv)
    try:
        args.func(args)
    except RuntimeError as e:
        sys.stderr.write(str(e) + "\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
