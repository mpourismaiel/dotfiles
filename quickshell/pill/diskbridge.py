#!/usr/bin/env python3
# diskbridge.py — backend of the pill's Disk window (DiskState.qml / DiskWindow.qml).
# Line-delimited JSON on stdout, like every pill bridge. The scanners live in
# diskscan.py (read-only), the rule tables in diskrules.py.
#
# Files (override the two directories with a LEADING `--state DIR --cache DIR`):
#   ~/.cache/pill/disk/scan.json        the last scan (sections + removable items)
#   ~/.cache/pill/disk/sizes.json       size of every big directory (Files browser)
#   ~/.cache/pill/disk/adhoc.json       items made from the Files browser
#   ~/.cache/pill/disk/verify-*.json    what a review showed (apply needs its token)
#   ~/.local/state/pill/disk/reports/   one .md + .json per cleanup, kept
#
# Commands (a leading `--config JSON` carries the user's settings):
#   scan [--only a,b]     run the scanners; prints {"event":"progress"|"section"|"done"}
#   snapshot              print the cached scan as one {"event":"snapshot"} line
#   ls PATH               a dired-style listing with real sizes
#   item PATH…            make removable items for arbitrary paths (Files browser)
#   verify ID…            re-check items against the disk NOW → fresh facts + token
#   script ID…            the same plan as a shell script (to copy, edit, run yourself)
#   apply TOKEN --ack TIERS   remove exactly what `verify` showed. Refuses unless
#                         every risk tier in the plan is acknowledged, re-checks each
#                         path again, and writes a report.
#   terminal ID           open a terminal on an item's command (root / interactive)
#   reports               list past cleanup reports
#   reveal PATH           show a path in the file manager
#
# Safety model — the only code in the pill that removes user files is `apply`:
#   · nothing is removed without a token from `verify` (so it is exactly what the
#     review showed) plus an acknowledgment for every tier involved;
#   · every path passes `guard()` right before removal (never /, $HOME, a mount
#     point, a .git, a symlinked directory, or anything outside the user's home —
#     system paths only ever become a command for a terminal);
#   · dependency / build directories must still classify as such; projects and
#     worktrees get their git state re-read; duplicates are compared byte for byte;
#   · your own files go to the Trash (gio trash) and are never unlinked directly.
import filecmp
import hashlib
import json
import os
import select
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # no __pycache__ next to the config
sys.path.insert(0, HERE)
import diskrules as R  # noqa: E402
import diskscan as S  # noqa: E402

HOME = S.HOME
STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"),
    "pill",
    "disk",
)
CACHE = os.path.join(S.XDG["$CACHE"], "pill", "disk")
SECTIONS = [
    "home",
    "projects",
    "caches",
    "packages",
    "docker",
    "games",
    "thumbnails",
    "downloads",
    "bins",
    "system",
]
_out_lock = threading.Lock()


def emit(obj):
    with _out_lock:
        sys.stdout.write(
            json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n"
        )
        sys.stdout.flush()


def read_json(path, default=None):
    try:
        with open(path, errors="surrogateescape") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", errors="surrogateescape") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def cache_path(name):
    return os.path.join(CACHE, name)


# ---- scan ------------------------------------------------------------------------
def overview(sc, disk, sec):
    """Where the space went, in the window's categories, + the best candidates."""

    def g(name, *keys, default=0):
        d = sec.get(name) or {}
        for k in keys:
            d = (d or {}).get(k) if isinstance(d, dict) else None
        return d or default

    libs = g("games", "libraries", default=[])
    # the package cache lives under /var/cache: count it once, as packages
    pac = g("packages", "pacman", "bytes")
    aur = sum(r["bytes"] for r in sc.shared.get("pkg_caches", []))
    cats = [
        dict(key="src", label="Project source", bytes=g("projects", "totals", "src") + g("projects", "totals", "git"), page="projects"),
        dict(key="dep", label="Dependencies", bytes=g("projects", "totals", "deps"), page="projects"),
        dict(key="bld", label="Build output", bytes=g("projects", "totals", "build"), page="projects"),
        dict(key="dock", label="Docker", bytes=g("docker", "bytes"), page="docker"),
        dict(key="vid", label="Videos", bytes=g("home", "videos", "bytes"), page="videos"),
        dict(key="game", label="Games", bytes=g("games", "bytes"), page="games"),
        dict(key="cache", label="Caches", bytes=g("caches", "bytes") + g("thumbnails", "bytes"), page="caches"),
        dict(key="pkg", label="Package caches", bytes=pac + aur, page="packages"),
        dict(key="sys", label="System", bytes=max(0, g("system", "bytes") - pac), page="system"),
    ]
    dl = sec.get("downloads") or {}
    dl_other = (
        sum(r["bytes"] for r in dl.get("rows", []) if not r.get("claimed")) if dl else 0
    )
    cats.insert(6, dict(key="dl", label="Downloads", bytes=dl_other, page="downloads"))
    used = (disk.get("main") or {}).get("used", 0)
    known = sum(c["bytes"] for c in cats)
    cats.append(
        dict(
            key="other",
            label="Everything else",
            bytes=max(0, used - known),
            page="files",
        )
    )
    offered = [i for i in sc.items.values() if i.get("offer")]
    # one offer per thing: "keep 2" and "keep 1" style alternatives overlap
    best = sorted(offered, key=lambda i: -i["reclaim"])[:14]
    tiers = {}
    for i in offered:
        t = tiers.setdefault(i["tier"], dict(count=0, bytes=0))
        t["count"] += 1
        t["bytes"] += i["reclaim"]
    return dict(
        categories=cats,
        used=used,
        best=[i["id"] for i in best],
        offered=tiers,
        offered_bytes=sum(i["reclaim"] for i in offered),
        libraries=libs,
    )


def cmd_scan(config, only):
    t0 = time.time()
    prev = read_json(cache_path("scan.json"), {}) or {}
    last_prog = [0.0]

    def progress(section, state, **kw):
        now = time.time()
        if state == "running" and now - last_prog[0] < 0.25:
            return
        last_prog[0] = now
        emit(dict(event="progress", section=section, state=state, **kw))

    sc = S.Scan(config, progress)
    disk = S.scan_disk(sc)
    emit(dict(event="disk", disk=disk))
    want = [s for s in SECTIONS if not only or s in only]
    sec = {}
    funcs = dict(
        home=S.scan_home,
        projects=S.scan_projects,
        caches=S.scan_caches,
        packages=S.scan_packages,
        docker=S.scan_docker,
        games=S.scan_games,
        downloads=S.scan_downloads,
        bins=S.scan_bins,
        system=S.scan_system,
        thumbnails=lambda s: S.scan_thumbnails(s, CACHE),
    )

    def run_one(name):
        ts = time.time()
        progress(name, "start")
        try:
            data = funcs[name](sc)
        except Exception as e:  # one broken scanner must not lose the others
            data = dict(error="%s: %s" % (type(e).__name__, e))
        data["took"] = round(time.time() - ts, 1)
        sec[name] = data
        emit(
            dict(
                event="section",
                name=name,
                data=data,
                items={k: v for k, v in sc.items.items() if v["section"] == name},
            )
        )
        progress(name, "done", took=data["took"])

    # wave 1 is independent; wave 2 reads what wave 1 left in sc.shared
    wave1 = [
        s
        for s in want
        if s in ("home", "projects", "caches", "docker", "thumbnails", "system")
    ]
    wave2 = [s for s in want if s in ("packages", "games", "downloads", "bins")]
    for wave in (wave1, wave2):
        threads = [
            threading.Thread(target=run_one, args=(n,), daemon=True) for n in wave
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
    # a partial scan keeps the other sections (and their items) from the last one
    items = dict(sc.items)
    if only:
        for n, d in (prev.get("sections") or {}).items():
            sec.setdefault(n, d)
        for k, v in (prev.get("items") or {}).items():
            if v.get("section") not in want:
                items.setdefault(k, v)
        sc.items = items
    ov = overview(sc, disk, sec)
    scan = dict(
        version=1,
        at=int(t0),
        took=round(time.time() - t0, 1),
        disk=disk,
        overview=ov,
        sections=sec,
        items=items,
    )
    write_json(cache_path("scan.json"), scan)
    sizes = (
        read_json(cache_path("sizes.json"), {}) if only and "home" not in want else {}
    )
    sizes.update(sc.sizes)
    write_json(cache_path("sizes.json"), sizes)
    emit(dict(event="done", at=scan["at"], took=scan["took"], disk=disk, overview=ov))


def demo_scan():
    """DEMO=true (safe screen recording): an invented disk, never the real one."""
    if not os.environ.get("DEMO"):
        return None
    demo = read_json(os.path.join(HERE, "diskdemo.json"))
    if demo:
        demo["at"] = int(time.time()) - 240
    return demo


def cmd_snapshot():
    demo = demo_scan()
    if demo:
        emit(dict(event="snapshot", scan=demo))
        return
    scan = read_json(cache_path("scan.json"))
    if not scan:
        emit(dict(event="empty"))
        return
    scan["disk"] = S.scan_disk(S.Scan({}))  # free space is always current
    emit(dict(event="snapshot", scan=scan))


# ---- items -----------------------------------------------------------------------
def all_items():
    demo = demo_scan()
    if demo:
        return demo["items"]
    items = dict((read_json(cache_path("scan.json"), {}) or {}).get("items") or {})
    items.update(read_json(cache_path("adhoc.json"), {}) or {})
    return items


def cmd_item(paths):
    """Removable items for arbitrary paths — what the Files browser flags."""
    sc = S.Scan({})
    adhoc = read_json(cache_path("adhoc.json"), {}) or {}
    out = []
    for p in paths:
        p = os.path.abspath(p)
        try:
            st = os.lstat(p)
        except OSError:
            continue
        isdir = stat.S_ISDIR(st.st_mode)
        parent = os.path.dirname(p)
        name = os.path.basename(p)
        try:
            sibs = set(os.listdir(parent))
        except OSError:
            sibs = set()
        size = (
            S.du(p, detail=True)
            if isdir
            else dict(
                bytes=S.alloc(st), reclaim=S.alloc(st), newest=st.st_mtime, files=1
            )
        )
        kind = S.classify_dir(name, sibs, p) if isdir else None
        warn = []
        if kind:
            proj = dict(locks=[n for n in R.LOCKFILES if n in sibs])
            c = dict(
                kind=kind,
                lock=next((n for n in R.DEP_LOCKS.get(name, ()) if n in sibs), ""),
                **size,
            )
            tier, why, restore, warn = S.judge_candidate(c, proj)
            method = "rm"
        elif p.startswith(S.XDG["$CACHE"] + "/"):
            tier, why, restore, method, kind = (
                "free",
                "Inside the cache folder; its program is expected to cope with it vanishing.",
                "",
                "rm",
                "cache",
            )
        else:
            tier, why, restore, method, kind = (
                "data",
                "A file or folder of yours.",
                "",
                "trash",
                "file",
            )
            if isdir and os.path.lexists(os.path.join(p, ".git")):
                f = S.git_facts(p)
                if f["dirty"]:
                    warn.append("A git repository with uncommitted changes.")
                if f["unpushed"]:
                    warn.append(
                        "A git repository with %d unpushed commits." % f["unpushed"]
                    )
                if not f["remote"]:
                    warn.append(
                        "A git repository with no remote — its history exists only here."
                    )
            if S.SECRET_RE.search(name):
                warn.append(
                    "The name looks like a key, credential or backup-code file."
                )
        iid = sc.add(
            "files",
            kind,
            p,
            title=name,
            sub=S.tilde(parent),
            paths=[p],
            bytes=size["bytes"],
            reclaim=size.get("reclaim", size["bytes"]),
            mtime=int(size.get("newest") or st.st_mtime),
            tier=tier,
            why=why,
            restore=restore,
            warn=warn,
            method=method,
        )
        adhoc[iid] = sc.items[iid]
        out.append(sc.items[iid])
    # keep the ad-hoc file from growing without bound
    if len(adhoc) > 2000:
        adhoc = dict(list(adhoc.items())[-1000:])
    write_json(cache_path("adhoc.json"), adhoc)
    emit(dict(event="items", items=out))


# ---- guard -----------------------------------------------------------------------
def guard(path, item):
    """Why `path` must not be removed, or "" when it may be."""
    if not path or not path.startswith("/") or os.path.normpath(path) != path:
        return "not a plain absolute path"
    home = os.path.realpath(HOME)
    if path in ("/", home) or (home + "/").startswith(path + "/"):
        return "refusing: this is your home folder or above it"
    if os.path.ismount(path):
        return "refusing: a mount point"
    real_parent = os.path.realpath(os.path.dirname(path))
    if real_parent != os.path.dirname(path):
        return "refusing: reached through a symlink"
    ok_roots = (home + "/", "/tmp/", "/var/tmp/")
    if not path.startswith(ok_roots):
        return (
            "outside your home folder — system paths are only ever handed to a terminal"
        )
    name = os.path.basename(path)
    if "/.git/" in path + "/":
        return "refusing: inside or equal to a .git folder"
    if os.path.dirname(path) == home and name in R.PROTECTED_NAMES:
        return "refusing: a protected folder (%s)" % name
    if path in (STATE, CACHE) or path.startswith((STATE + "/", CACHE + "/")):
        return "refusing: the disk manager's own files"
    if not os.path.lexists(path):
        return "gone"
    if item.get("kind") in ("deps", "build") and item.get("method") == "rm":
        try:
            sibs = set(os.listdir(os.path.dirname(path)))
        except OSError:
            sibs = set()
        if os.path.islink(path) or not os.path.isdir(path):
            return "no longer a directory"
        if S.classify_dir(name, sibs, path) != item["kind"]:
            return "no longer looks like a %s folder" % (
                "dependency" if item["kind"] == "deps" else "build"
            )
    return ""


def verify_item(it):
    """The item as it is on disk right now: {…item, status, reason, bytes_now}."""
    v = dict(it)
    v["status"], v["reason"] = "ok", ""
    m = it["method"]
    if m in ("cmd", "terminal"):
        argv = it.get("argv") or []
        if m == "cmd" and (not argv or not shutil.which(argv[0])):
            v["status"], v["reason"] = (
                "blocked",
                "%s is not installed" % (argv[0] if argv else "the command"),
            )
        v["bytes_now"] = it["bytes"]
        if it.get("kind") == "worktree":
            f = S.git_facts(it["paths"][0]) if os.path.isdir(it["paths"][0]) else None
            if f is None:
                v["status"], v["reason"] = "gone", "already gone"
            elif (f["dirty"] or f["unpushed"]) and not it.get("warn"):
                v["status"], v["reason"] = (
                    "blocked",
                    "the worktree has new uncommitted or unpushed work since the scan",
                )
        return v
    paths, total = [], 0
    for p in it["paths"]:
        why = guard(p, it)
        if why == "gone":
            continue
        if why:
            v["status"], v["reason"] = "blocked", "%s: %s" % (S.tilde(p), why)
            return v
        paths.append(p)
    if not paths:
        v["status"], v["reason"], v["bytes_now"] = "gone", "already gone", 0
        return v
    v["paths"] = paths
    if m == "list":
        lst = it.get("listing") or ""
        try:
            with open(lst, errors="surrogateescape") as f:
                n = sum(1 for _ in f)
        except OSError:
            v["status"], v["reason"] = (
                "blocked",
                "the list of files is missing — scan again",
            )
            return v
        v["bytes_now"], v["count"] = it["bytes"], n
        return v
    seen = set()
    total = sum(S.du(p, seen)["bytes"] for p in paths)
    v["bytes_now"] = total
    if it.get("kind") == "project":
        f = S.git_facts(paths[0])
        fresh = []
        if f["dirty"]:
            fresh.append("uncommitted changes")
        if f["unpushed"]:
            fresh.append("%d unpushed commits" % f["unpushed"])
        if fresh and not it.get("warn"):
            v["status"], v["reason"] = (
                "blocked",
                "changed since the scan: " + ", ".join(fresh),
            )
    if it.get("verify_same"):
        keep = it["verify_same"]
        try:
            same = (
                os.path.isfile(keep)
                and not os.path.samefile(keep, paths[0])
                and filecmp.cmp(keep, paths[0], shallow=False)
            )
        except OSError:
            same = False
        if not same:
            v["status"], v["reason"] = (
                "blocked",
                "no longer identical to %s" % S.tilde(keep),
            )
    return v


def token_for(items):
    h = hashlib.sha256()
    for v in sorted(items, key=lambda v: v["id"]):
        h.update(
            json.dumps(
                [v["id"], v["method"], v["paths"], v.get("argv"), v.get("cmd")]
            ).encode()
        )
    return h.hexdigest()[:24]


def cmd_verify(ids):
    items = all_items()
    out, missing = [], []
    for i in dict.fromkeys(ids):
        it = items.get(i)
        if not it:
            missing.append(i)
            continue
        out.append(verify_item(it))
    ok = [v for v in out if v["status"] == "ok"]
    tok = token_for(ok)
    write_json(cache_path("verify-%s.json" % tok), dict(at=time.time(), items=ok))
    # old verify files are just clutter
    try:
        for n in os.listdir(CACHE):
            p = cache_path(n)
            if (
                n.startswith("verify-")
                and n != "verify-%s.json" % tok
                and time.time() - os.path.getmtime(p) > 86400
            ):
                os.unlink(p)
    except OSError:
        pass
    tiers = {}
    for v in ok:
        t = tiers.setdefault(v["tier"], dict(count=0, bytes=0))
        t["count"] += 1
        t["bytes"] += v.get("bytes_now", v["bytes"])
    emit(
        dict(
            event="verified",
            token=tok,
            at=int(time.time()),
            items=out,
            missing=missing,
            tiers=tiers,
            bytes=sum(v.get("bytes_now", v["bytes"]) for v in ok),
            script=script_for(ok),
        )
    )


# ---- script ----------------------------------------------------------------------
TIER_TITLE = dict(
    free="comes back by itself",
    cost="costs a download or a build to get back",
    state="holds state — look first",
    data="your files — cannot be recovered",
)


def item_lines(v):
    m = v["method"]
    if m == "trash":
        return ["gio trash -- " + " ".join(S.q(p) for p in v["paths"])]
    if m == "rm":
        return ["rm -rf -- " + " ".join(S.q(p) for p in v["paths"])]
    if m == "contents":
        return [
            "find %s -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +" % S.q(p)
            for p in v["paths"]
        ]
    if m == "list":
        return [v.get("cmd") or "# (list missing)"]
    lines = []
    if v.get("pre"):
        lines.append(" ".join(S.q(a) for a in v["pre"]) + " || true")
    lines.append(v.get("cmd") or " ".join(S.q(a) for a in (v.get("argv") or [])))
    return lines


def human(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return (
                ("%d %s" % (n, unit))
                if unit in ("B", "KB")
                else ("%.1f %s" % (n, unit))
            )
        n /= 1024


def script_for(items):
    lines = [
        "#!/bin/sh",
        "# Cleanup plan from the pill's Disk window — %s"
        % time.strftime("%Y-%m-%d %H:%M"),
        "# Read it, edit it, run it yourself. Each line removes exactly one thing.",
        "set -eu",
        "",
    ]
    for tier in R.TIERS:
        group = [v for v in items if v["tier"] == tier]
        if not group:
            continue
        lines.append(
            "# ---- %s (%s) ----"
            % (
                TIER_TITLE[tier],
                human(sum(v.get("bytes_now", v["bytes"]) for v in group)),
            )
        )
        for v in group:
            lines.append(
                "# %s — %s%s"
                % (
                    v["title"],
                    human(v.get("bytes_now", v["bytes"])),
                    ("  [" + v["sub"] + "]") if v.get("sub") else "",
                )
            )
            for w in v.get("warn") or []:
                lines.append("#   ! " + w)
            if v.get("restore"):
                lines.append("#   back with: " + v["restore"])
            lines += item_lines(v)
        lines.append("")
    return "\n".join(lines)


def cmd_script(ids):
    items = all_items()
    emit(
        dict(
            event="script",
            script=script_for([verify_item(items[i]) for i in ids if i in items]),
        )
    )


# ---- apply -----------------------------------------------------------------------
def remove_tree(path):
    """Remove a directory tree or a file. Never follows symlinks."""
    st = os.lstat(path)
    if stat.S_ISDIR(st.st_mode):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def apply_item(v):
    """→ (status, detail). status: removed | trashed | ran | manual | skipped | failed"""
    fresh = verify_item(v)
    if fresh["status"] != "ok":
        return "skipped", fresh["reason"]
    m = v["method"]
    try:
        if m == "terminal":
            return "manual", "run in a terminal: " + v["cmd"]
        if m == "cmd":
            if v.get("pre") and shutil.which(v["pre"][0]):
                subprocess.run(
                    v["pre"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=120,
                )
            rc, tail = run_bounded(v["argv"])
            if rc == 0:
                return "ran", tail
            return "failed", tail if rc is None else "exit %d: %s" % (rc, tail)
        if m == "trash":
            if not shutil.which("gio"):
                return (
                    "failed",
                    "gio is not installed; refusing to delete your files permanently instead",
                )
            r = subprocess.run(
                ["gio", "trash", "--"] + fresh["paths"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=600,
                text=True,
                errors="replace",
            )
            return (
                ("trashed", "")
                if r.returncode == 0
                else ("failed", r.stdout.strip()[-300:])
            )
        if m == "rm":
            for p in fresh["paths"]:
                remove_tree(p)
            return "removed", ""
        if m == "contents":
            for p in fresh["paths"]:
                for e in list(os.scandir(p)):
                    remove_tree(e.path)
            return "removed", ""
        if m == "list":
            root = os.path.realpath(v["paths"][0]) + "/"
            n = kept = 0
            with open(v["listing"], errors="surrogateescape") as f:
                for line in f:
                    p = line.rstrip("\n")
                    if (
                        not p.startswith(root)
                        or not p.endswith(".png")
                        or os.path.islink(p)
                    ):
                        kept += 1
                        continue
                    uri, mt = S.thumb_meta(p)
                    if S.thumb_state(uri, mt) not in ("orphan", "stale"):
                        kept += (
                            1  # its source came back, or the file is something else now
                        )
                        continue
                    try:
                        os.unlink(p)
                        n += 1
                    except OSError:
                        kept += 1
            return "removed", "%d files removed, %d left alone" % (n, kept)
    except subprocess.TimeoutExpired:
        return "failed", "timed out"
    except OSError as e:
        return "failed", str(e)
    return "failed", "unknown method " + m


STOP = [False]  # set by SIGTERM (the window's Stop button)


def run_bounded(argv, timeout=600, limit=2 << 20):
    """Run a tool's own cleaner with no terminal. → (returncode, last lines), or
    (None, why) when it had to be stopped: it ran too long, the user pressed
    Stop, or it kept printing — which is what a tool does when it asks a
    question, gets no answer (stdin is closed) and asks again forever."""
    p = subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    tail, total, why = b"", 0, ""
    deadline = time.time() + timeout
    fd = p.stdout.fileno()
    while True:
        if STOP[0]:
            why = "stopped by you"
        elif time.time() > deadline:
            why = "still running after %d minutes" % (timeout // 60)
        elif total > limit:
            why = (
                "it kept printing without finishing — probably waiting for an answer"
                " it cannot get here; run it in a terminal"
            )
        if why:
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(p.pid, sig)
                except OSError:
                    break
                try:
                    p.wait(5)
                    break
                except subprocess.TimeoutExpired:
                    continue
            return None, why
        ready, _, _ = select.select([fd], [], [], 0.5)
        if ready:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            total += len(chunk)
            tail = (tail + chunk)[-2000:]
        elif p.poll() is not None:
            break
    p.wait()
    lines = tail.decode("utf-8", "replace").strip().splitlines()[-3:]
    return p.returncode, "\n".join(lines)


def free_bytes():
    try:
        v = os.statvfs(HOME)
        return v.f_bavail * v.f_frsize
    except OSError:
        return 0


def cmd_apply(token, acks):
    data = read_json(cache_path("verify-%s.json" % token))
    if not data or not data.get("items"):
        emit(
            dict(
                event="applied",
                ok=False,
                error="This review has expired — review the plan again.",
            )
        )
        return
    if time.time() - data["at"] > 1800:
        emit(
            dict(
                event="applied",
                ok=False,
                error="The review is more than 30 minutes old — review the plan again.",
            )
        )
        return
    items = data["items"]
    need = {v["tier"] for v in items}
    if not need <= set(acks):
        emit(
            dict(
                event="applied",
                ok=False,
                error="Not acknowledged: " + ", ".join(sorted(need - set(acks))),
            )
        )
        return
    before = free_bytes()
    results = []
    signal.signal(signal.SIGTERM, lambda *_: STOP.__setitem__(0, True))
    for n, v in enumerate(items):
        emit(
            dict(
                event="applying",
                index=n,
                total=len(items),
                id=v["id"],
                title=v["title"],
            )
        )
        t0 = time.time()
        # Stop finishes the item in hand, leaves the rest on disk, still reports
        if STOP[0]:
            status, detail = "skipped", "stopped by you before it was reached"
        else:
            status, detail = apply_item(v)
        results.append(
            dict(
                id=v["id"],
                title=v["title"],
                sub=v.get("sub", ""),
                tier=v["tier"],
                method=v["method"],
                cmd="; ".join(item_lines(v)),
                bytes=v.get("bytes_now", v["bytes"]),
                status=status,
                detail=detail,
                took=round(time.time() - t0, 1),
            )
        )
        emit(
            dict(
                event="applied-item", index=n, id=v["id"], status=status, detail=detail
            )
        )
    after = free_bytes()
    try:
        os.unlink(cache_path("verify-%s.json" % token))
    except OSError:
        pass
    path = write_report(results, before, after)
    emit(
        dict(
            event="applied",
            ok=True,
            results=results,
            freed=after - before,
            free=after,
            report=path,
            manual=[r for r in results if r["status"] == "manual"],
        )
    )


def write_report(results, before, after):
    ts = time.strftime("%Y-%m-%d_%H%M%S")
    d = os.path.join(STATE, "reports")
    os.makedirs(d, exist_ok=True)
    done = [r for r in results if r["status"] in ("removed", "trashed", "ran")]
    md = [
        "# Disk cleanup — %s" % time.strftime("%Y-%m-%d %H:%M"),
        "",
        "- Free before: %s" % human(before),
        "- Free after: %s (%s more)" % (human(after), human(max(0, after - before))),
        "- Done: %d of %d items, %s by their size at review time"
        % (len(done), len(results), human(sum(r["bytes"] for r in done))),
        "",
    ]
    if any(r["status"] == "trashed" for r in results):
        md += [
            "Things sent to the Trash still take space until the Trash is emptied.",
            "",
        ]
    for tier in R.TIERS:
        group = [r for r in results if r["tier"] == tier]
        if not group:
            continue
        md += [
            "## %s" % TIER_TITLE[tier].capitalize(),
            "",
            "| | Item | Size | Result |",
            "|---|---|---:|---|",
        ]
        for r in group:
            mark = "x" if r["status"] in ("removed", "trashed", "ran") else " "
            md.append(
                "| [%s] | %s%s | %s | %s%s |"
                % (
                    mark,
                    r["title"],
                    (" — " + r["sub"]) if r["sub"] else "",
                    human(r["bytes"]),
                    r["status"],
                    (": " + r["detail"].replace("\n", " ").replace("|", "/"))
                    if r["detail"]
                    else "",
                )
            )
        md += ["", "```sh"] + [r["cmd"] for r in group] + ["```", ""]
    path = os.path.join(d, ts + ".md")
    with open(path, "w") as f:
        f.write("\n".join(md) + "\n")
    write_json(
        os.path.join(d, ts + ".json"),
        dict(at=int(time.time()), before=before, after=after, results=results),
    )
    return path


def cmd_reports():
    d = os.path.join(STATE, "reports")
    out = []
    try:
        names = sorted((n for n in os.listdir(d) if n.endswith(".json")), reverse=True)
    except OSError:
        names = []
    for n in names[:40]:
        j = read_json(os.path.join(d, n)) or {}
        rs = j.get("results") or []
        done = [r for r in rs if r["status"] in ("removed", "trashed", "ran")]
        out.append(
            dict(
                at=j.get("at", 0),
                path=os.path.join(d, n[:-5] + ".md"),
                items=len(rs),
                done=len(done),
                bytes=sum(r["bytes"] for r in done),
                freed=j.get("after", 0) - j.get("before", 0),
                titles=[r["title"] for r in done[:5]],
            )
        )
    emit(dict(event="reports", reports=out, dir=d))


# ---- helpers the window calls ------------------------------------------------------
def terminal_cmd(inner):
    script = inner + '; echo; read -n1 -rsp "Press any key to close…"'
    for term, args in (
        (os.environ.get("TERMINAL", ""), ["-e"]),
        ("konsole", ["-e"]),
        ("kitty", []),
        ("alacritty", ["-e"]),
        ("foot", []),
        ("gnome-terminal", ["--"]),
        ("xterm", ["-e"]),
    ):
        if term and shutil.which(term):
            return [term] + args + ["bash", "-c", script]
    return None


def cmd_terminal(iid):
    it = all_items().get(iid)
    if not it or not it.get("cmd"):
        emit(dict(event="terminal", ok=False, error="unknown item"))
        return
    # the command is shown and waits for Enter: nothing runs just because a window opened
    inner = "echo %s; echo; printf %s; read -r _; %s" % (
        S.q(it["title"] + " — " + it["why"]),
        S.q("$ " + it["cmd"] + "\n\nEnter runs it, Ctrl-C cancels. "),
        it["cmd"],
    )
    cmd = terminal_cmd(inner)
    if not cmd:
        emit(dict(event="terminal", ok=False, error="no terminal emulator found"))
        return
    subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    emit(dict(event="terminal", ok=True))


def cmd_reveal(path):
    target = path if os.path.isdir(path) else os.path.dirname(path)
    subprocess.Popen(
        ["xdg-open", target],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    emit(dict(event="revealed", path=target))


def main():
    global STATE, CACHE
    argv = sys.argv[1:]
    config = {}
    while argv and argv[0] in ("--state", "--cache", "--config"):
        flag, val = argv[0], argv[1]
        argv = argv[2:]
        if flag == "--state":
            STATE = val
        elif flag == "--cache":
            CACHE = val
        else:
            try:
                config = json.loads(val) or {}
            except ValueError:
                config = {}
    cmd = argv[0] if argv else "snapshot"
    args = argv[1:]
    if os.environ.get("DEMO") and cmd in ("scan", "apply", "item", "terminal"):
        # the demo disk is a picture: nothing is walked, made or removed
        if cmd == "scan":
            demo = demo_scan() or {}
            emit(dict(event="done", at=demo.get("at", 0), took=demo.get("took", 0), disk=demo.get("disk"), overview=demo.get("overview")))
        elif cmd == "apply":
            emit(dict(event="applied", ok=False, error="Demo mode: nothing is removed."))
        return 0
    if cmd == "scan":
        only = []
        if len(args) >= 2 and args[0] == "--only":
            only = [s for s in args[1].split(",") if s in SECTIONS]
        cmd_scan(config, only)
    elif cmd == "snapshot":
        cmd_snapshot()
    elif cmd == "ls":
        sizes = read_json(cache_path("sizes.json"), {}) or {}
        emit(dict(event="ls", **S.list_dir(args[0] if args else HOME, sizes)))
    elif cmd == "item":
        cmd_item(args)
    elif cmd == "verify":
        cmd_verify(args)
    elif cmd == "script":
        cmd_script(args)
    elif cmd == "apply":
        acks = []
        if len(args) >= 3 and args[1] == "--ack":
            acks = [a for a in args[2].split(",") if a in R.TIERS]
        cmd_apply(args[0] if args else "", acks)
    elif cmd == "terminal":
        cmd_terminal(args[0] if args else "")
    elif cmd == "reports":
        cmd_reports()
    elif cmd == "reveal":
        cmd_reveal(args[0] if args else HOME)
    else:
        emit(dict(event="error", error="unknown command " + cmd))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
