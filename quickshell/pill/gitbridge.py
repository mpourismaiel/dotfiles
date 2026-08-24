#!/usr/bin/env python3
# gitbridge.py — git activity backend for the pill's "Done" work-history page.
# Aggregates finished work across a user-chosen set of project directories,
# filtered to a set of author emails, over a period. Mirrors orgbridge.py /
# hledgerbridge.py: plain JSON on stdout, best-effort (empty data on any error).
#
#   summary SINCE DIRS_JSON EMAILS_JSON
#       Local git only — fast, no network. SINCE is an ISO date ("YYYY-MM-DD")
#       or "" for all-time. DIRS_JSON / EMAILS_JSON are JSON arrays of strings.
#       Prints {commits, merges, branches, projects, repos, biggest:[…]} where
#       biggest is the largest commits by lines changed:
#         [{subject, add, del, hash, repo}, …]  (top 6, additive size desc)
#
#   prs SINCE DIRS_JSON [TTL]
#       GitHub PRs you authored that merged in the period, via the `gh` CLI.
#       Stale-while-revalidate: a cache file is always the fast answer; the
#       network is only hit when the cache is older than TTL seconds (default
#       900). Prints {prs, stale, at}. Never blocks `summary`.
#
# A repo directory is either a git work-tree itself, or a root whose immediate
# children are work-trees (so one "projects root" expands to many repos). Empty
# dirs/emails yield zeroed output — the page renders an empty state, never an
# error.
import sys, os, json, subprocess, hashlib, time, re

# ---- discovery -------------------------------------------------------------

def _expand(p):
    return os.path.abspath(os.path.expanduser(p))


def _is_repo(path):
    return os.path.isdir(os.path.join(path, ".git")) or os.path.isfile(
        os.path.join(path, ".git")
    )


def find_repos(dirs):
    """Each configured dir is a repo, or a root of repos (immediate children).
    De-duplicated, order-stable."""
    repos, seen = [], set()
    for d in dirs:
        base = _expand(d)
        if not os.path.isdir(base):
            continue
        cands = [base] if _is_repo(base) else [
            os.path.join(base, c) for c in sorted(os.listdir(base))
        ]
        for c in cands:
            if _is_repo(c) and c not in seen:
                seen.add(c)
                repos.append(c)
    return repos


def _git(repo, args, timeout=15):
    try:
        r = subprocess.run(
            ["git", "-C", repo] + args,
            capture_output=True, timeout=timeout,
        )
    except Exception:
        return ""
    if r.returncode != 0:
        return ""
    return r.stdout.decode("utf-8", "replace")


# ---- summary ---------------------------------------------------------------

# one record per commit, using unit separators so subjects with tabs survive.
_REC = "\x1e"   # between commits
_FLD = "\x1f"   # between fields


def repo_commits(repo, since, authors):
    """(commits, merges, list-of-{subject,add,del,hash}) for this repo in the
    period, authored by any of `authors`. Commits are counted once even if they
    sit on several local branches (git dedups across --branches)."""
    fmt = _REC + "%H" + _FLD + "%h" + _FLD + "%s"
    args = ["log", "--branches", "--no-merges", "--numstat",
            "--pretty=tformat:" + fmt]
    for a in authors:
        args.append("--author=" + a)
    if since:
        args.append("--since=" + since + " 00:00:00")
    out = _git(repo, args)
    commits = []
    for chunk in out.split(_REC):
        chunk = chunk.strip("\n")
        if not chunk:
            continue
        head, _, rest = chunk.partition("\n")
        parts = head.split(_FLD)
        if len(parts) < 3:
            continue
        add = dele = 0
        for line in rest.split("\n"):
            cols = line.split("\t")
            if len(cols) >= 2 and cols[0].isdigit() and cols[1].isdigit():
                add += int(cols[0]); dele += int(cols[1])
        commits.append({"subject": parts[2].strip(), "hash": parts[1],
                        "add": add, "del": dele, "repo": os.path.basename(repo)})
    # merge commits are a separate additive card
    margs = ["log", "--branches", "--merges", "--oneline"]
    for a in authors:
        margs.append("--author=" + a)
    if since:
        margs.append("--since=" + since + " 00:00:00")
    mout = _git(repo, margs)
    merges = len([ln for ln in mout.splitlines() if ln.strip()])
    return commits, merges


def repo_branches(repo, since):
    """Branches created in the period (all-time when since==""). creatordate is
    the branch tip's commit date — a good-enough, always-additive proxy."""
    out = _git(repo, ["for-each-ref", "--format=%(creatordate:short)",
                      "refs/heads"])
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    if not since:
        return len(lines)
    return len([ln for ln in lines if ln >= since])


def cmd_summary(since, dirs, emails):
    repos = find_repos(dirs)
    all_commits, merges, branches, active = [], 0, 0, 0
    if emails:                                   # no emails → empty (by design)
        for repo in repos:
            cs, ms = repo_commits(repo, since, emails)
            if cs or ms:
                active += 1
            all_commits.extend(cs)
            merges += ms
            branches += repo_branches(repo, since)
    all_commits.sort(key=lambda c: (c["add"] + c["del"]), reverse=True)
    return {
        "commits": len(all_commits),
        "merges": merges,
        "branches": branches,
        "projects": active,
        "repos": len(repos),
        "biggest": all_commits[:6],
    }


# ---- prs (gh, cached) ------------------------------------------------------

def _cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    d = os.path.join(base, "quickshell-pill")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        pass
    return os.path.join(d, "done-prs.json")


def _cache_key(since, dirs):
    h = hashlib.sha1(("|".join(sorted(dirs)) + "@" + since).encode()).hexdigest()
    return h[:16]


def _cache_read():
    try:
        with open(_cache_path(), encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def _cache_write(store):
    try:
        with open(_cache_path(), "w", encoding="utf-8") as fh:
            json.dump(store, fh)
    except OSError:
        pass


_GH_REMOTE = re.compile(r"github\.com[:/]+([^/]+/[^/.]+)")


def _repo_slug(repo):
    url = _git(repo, ["remote", "get-url", "origin"], timeout=5).strip()
    m = _GH_REMOTE.search(url)
    return m.group(1) if m else None


def _gh_pr_count(slug, since):
    search = "is:pr author:@me is:merged"
    if since:
        search += " merged:>=" + since
    try:
        r = subprocess.run(
            ["gh", "pr", "list", "--repo", slug, "--state", "merged",
             "--search", search, "--json", "number", "--limit", "200"],
            capture_output=True, timeout=20,
        )
    except Exception:
        return None
    if r.returncode != 0:
        return None
    try:
        return len(json.loads(r.stdout.decode("utf-8", "replace") or "[]"))
    except ValueError:
        return None


def cmd_prs(since, dirs, ttl):
    key = _cache_key(since, dirs)
    store = _cache_read()
    entry = store.get(key)
    now = time.time()
    if entry and (now - entry.get("at", 0)) < ttl:
        return {"prs": entry.get("prs", 0), "stale": False, "at": entry.get("at")}
    # stale or missing → hit the network, fall back to any cached value on failure
    total, ok = 0, False
    for repo in find_repos(dirs):
        slug = _repo_slug(repo)
        if not slug:
            continue
        n = _gh_pr_count(slug, since)
        if n is not None:
            total += n
            ok = True
    if ok:
        store[key] = {"at": now, "prs": total}
        _cache_write(store)
        return {"prs": total, "stale": False, "at": now}
    if entry:                                    # network failed — serve stale
        return {"prs": entry.get("prs", 0), "stale": True, "at": entry.get("at")}
    return {"prs": 0, "stale": True, "at": 0}


# ---- main ------------------------------------------------------------------

def _jarr(s):
    try:
        v = json.loads(s)
        return [str(x) for x in v] if isinstance(v, list) else []
    except ValueError:
        return []


def main():
    # DEMO mode: serve deterministic fake git activity (demodata.py) instead of
    # scanning the user's real repos, so the pill is safe to record.
    if os.environ.get("DEMO"):
        import demodata
        demodata.run("git", sys.argv[1:])
        return
    argv = sys.argv[1:]
    cmd = argv[0] if argv else ""
    # a trailing PERIOD label is echoed back so the caller can drop stale responses
    # from a period it has since switched away from (see DoneState).
    period = ""
    try:
        if cmd == "summary" and len(argv) >= 4:
            period = argv[4] if len(argv) > 4 else ""
            out = cmd_summary(argv[1].strip(), _jarr(argv[2]), _jarr(argv[3]))
        elif cmd == "prs" and len(argv) >= 3:
            period = argv[3] if len(argv) > 3 else ""
            out = cmd_prs(argv[1].strip(), _jarr(argv[2]), 900)
        else:
            out = {}
    except Exception as e:                        # never crash the page
        out = {"error": str(e)[:200]}
    out["period"] = period
    sys.stdout.write(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
