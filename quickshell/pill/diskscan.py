#!/usr/bin/env python3
# diskscan.py — the read-only scanners behind the pill's Disk window. Imported by
# diskbridge.py (which owns the CLI, the cleanup plan and the only code that ever
# removes anything). NOTHING in this file writes, moves or deletes: it walks,
# stats, reads a few headers and asks tools (git, docker, pacman, flatpak) for
# facts.
#
# Every scanner fills one "section" of the scan and registers the things that
# could be removed as *items*:
#
#   item = {id, section, kind, title, sub, paths[], bytes, reclaim, mtime,
#           tier (free|cost|state|data — see diskrules.py), why, restore,
#           method (rm | contents | trash | cmd | terminal | list),
#           argv / cmd (what would run), warn[], offer (suggested by default)}
#
# Sizes are allocated bytes (st_blocks*512, so sparse files count as what they
# really occupy), hardlinks counted once per pass; `reclaim` leaves out bytes
# that other hardlinks keep alive (uv / pnpm / bun stores).
#
# Sections: home (rollup + media + games found by fingerprint), projects,
# caches, packages, docker, steam, thumbnails, downloads, bins, system.
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import struct
import subprocess
import threading
import time
import urllib.parse
import zlib
from concurrent.futures import ThreadPoolExecutor

import diskrules as R

HOME = os.path.expanduser("~")
XDG = {
    "$CACHE": os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"),
    "$DATA": os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"),
    "$CONFIG": os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"),
}
SIZE_FLOOR = 8 << 20  # directories at least this big are remembered for Files
MEDIA_KINDS = ("video", "audio", "image", "archive", "model", "diskimage")
GIT_ENV = dict(os.environ, GIT_OPTIONAL_LOCKS="0", LC_ALL="C", GIT_TERMINAL_PROMPT="0")


# ---- small helpers -------------------------------------------------------------
def expand(p):
    for k, v in XDG.items():
        if p.startswith(k):
            return v + p[len(k) :]
    return os.path.expanduser(p)


def tilde(p):
    return "~" + p[len(HOME) :] if p == HOME or p.startswith(HOME + "/") else p


def run(cmd, timeout=20, cwd=None, env=None):
    """(returncode, stdout) — never raises; rc 127 when the binary is missing."""
    try:
        r = subprocess.run(
            cmd,
            cwd=cwd,
            env=env,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            errors="replace",
        )
        return r.returncode, r.stdout
    except FileNotFoundError:
        return 127, ""
    except (subprocess.TimeoutExpired, OSError):
        return 124, ""


def have(name):
    return shutil.which(name) is not None


def alloc(st):
    return st.st_blocks * 512


def item_id(kind, key):
    return hashlib.sha1(
        (kind + "\0" + key).encode("utf-8", "surrogateescape")
    ).hexdigest()[:12]


def q(path):
    return shlex.quote(path)


def rm_cmd(paths):
    return "rm -rf -- " + " ".join(q(p) for p in paths)


def parse_size(s):
    """'17.81GB (18%)' / '4.2 GiB' / '512kB' → bytes."""
    m = re.match(r"\s*([\d.]+)\s*([kKMGTP]?)(i?)B?", s or "")
    if not m:
        return 0
    mult = {"": 1, "k": 1, "K": 1, "M": 2, "G": 3, "T": 4, "P": 5}[m.group(2)]
    base = 1024 if m.group(3) else 1000
    if m.group(2) == "":
        return int(float(m.group(1)))
    return int(float(m.group(1)) * base**mult)


def du(path, seen=None, detail=False, dev=None):
    """Allocated size of a tree, never following symlinks or leaving its device.
    → {bytes, reclaim, files, newest, denied} (+ kinds, oldest, stateful when
    `detail`). `seen` dedupes hardlinked inodes across calls."""
    if seen is None:
        seen = set()
    out = {"bytes": 0, "reclaim": 0, "files": 0, "newest": 0, "denied": 0}
    kinds = {}
    oldest = 0
    stateful = []
    try:
        st = os.lstat(path)
    except OSError:
        return out
    if not stat.S_ISDIR(st.st_mode):
        out.update(
            bytes=alloc(st),
            reclaim=alloc(st) if st.st_nlink == 1 else 0,
            files=1,
            newest=st.st_mtime,
        )
        return out
    if dev is None:
        dev = st.st_dev
    out["bytes"] = out["reclaim"] = alloc(st)
    stack = [path]
    while stack:
        d = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            out["denied"] += 1
            continue
        with it:
            for e in it:
                try:
                    s = e.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISDIR(s.st_mode):
                    if s.st_dev != dev:
                        continue
                    out["bytes"] += alloc(s)
                    out["reclaim"] += alloc(s)
                    stack.append(e.path)
                    continue
                b = alloc(s)
                if s.st_nlink > 1:
                    k = (s.st_dev, s.st_ino)
                    if k in seen:
                        continue
                    seen.add(k)
                else:
                    out["reclaim"] += b
                out["bytes"] += b
                out["files"] += 1
                if s.st_mtime > out["newest"]:
                    out["newest"] = s.st_mtime
                if detail:
                    k = R.ext_kind(e.name)
                    kinds[k] = kinds.get(k, 0) + b
                    if not oldest or s.st_mtime < oldest:
                        oldest = s.st_mtime
                    if (
                        e.name in R.STATEFUL_NAMES
                        or e.name.endswith(R.STATEFUL_SUFFIXES)
                    ) and len(stateful) < 3:
                        stateful.append(e.name)
    if detail:
        out.update(kinds=kinds, oldest=oldest, stateful=stateful)
    return out


class Scan:
    """One scan in progress: config, the items found, remembered sizes."""

    def __init__(self, config=None, progress=None):
        c = config or {}
        self.now = time.time()
        self.stale_days = int(c.get("staleDays") or 180)
        roots = [expand(p) for p in (c.get("projectDirs") or [])]
        if not roots:
            roots = [expand(p) for p in R.PROJECT_ROOT_GUESSES]
        self.project_roots = [
            p
            for p in dict.fromkeys(os.path.realpath(r) for r in roots)
            if os.path.isdir(p)
        ]
        self.game_dirs = [
            os.path.realpath(expand(p))
            for p in (c.get("gameDirs") or [])
            if os.path.isdir(expand(p))
        ]
        self.extra_dirs = [
            os.path.realpath(expand(p))
            for p in (c.get("extraDirs") or [])
            if os.path.isdir(expand(p))
        ]
        self.home = os.path.realpath(c.get("home") or HOME)
        self.items = {}
        self.sizes = {}  # path → [bytes, newest]   (dirs ≥ SIZE_FLOOR)
        self.sections = {}
        self.lock = threading.Lock()
        self._progress = progress or (lambda *a, **k: None)
        self.shared = {}  # facts one scanner leaves for another

    def progress(self, section, state, **kw):
        self._progress(section, state, **kw)

    def add(self, section, kind, key, **kw):
        """Register a removable thing; returns its id."""
        iid = item_id(kind, key)
        paths = kw.pop("paths", None) or []
        it = dict(
            id=iid,
            section=section,
            kind=kind,
            title="",
            sub="",
            paths=paths,
            bytes=0,
            reclaim=None,
            mtime=0,
            tier="data",
            why="",
            restore="",
            method="trash",
            cmd="",
            argv=None,
            warn=[],
            offer=False,
        )
        it.update(kw)
        if it["reclaim"] is None:
            it["reclaim"] = it["bytes"]
        if not it["cmd"]:
            if it["method"] == "rm":
                it["cmd"] = rm_cmd(paths)
            elif it["method"] == "contents":
                it["cmd"] = "; ".join(
                    "find %s -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +" % q(p)
                    for p in paths
                )
            elif it["method"] == "trash":
                it["cmd"] = "gio trash -- " + " ".join(q(p) for p in paths)
            elif it["argv"]:
                it["cmd"] = " ".join(q(a) for a in it["argv"])
        with self.lock:
            self.items[iid] = it
        return iid

    def age_days(self, ts):
        return (self.now - ts) / 86400 if ts else None


# ---- disk ----------------------------------------------------------------------
REAL_FS = {
    "ext2",
    "ext3",
    "ext4",
    "btrfs",
    "xfs",
    "f2fs",
    "zfs",
    "vfat",
    "exfat",
    "ntfs",
    "ntfs3",
    "bcachefs",
    "jfs",
    "reiserfs",
    "fuseblk",
}


def scan_disk(sc):
    mounts, seen = [], set()
    try:
        lines = open("/proc/self/mountinfo").read().splitlines()
    except OSError:
        lines = []
    for ln in lines:
        left, _, right = ln.partition(" - ")
        f, r = left.split(), right.split()
        if len(f) < 5 or len(r) < 2 or r[0] not in REAL_FS:
            continue
        mp = f[4].replace("\\040", " ")
        try:
            v = os.statvfs(mp)
            dev = os.stat(mp).st_dev
        except OSError:
            continue
        if dev in seen or v.f_blocks == 0:
            continue
        seen.add(dev)
        total = v.f_blocks * v.f_frsize
        mounts.append(
            dict(
                mount=mp,
                fstype=r[0],
                device=r[1],
                total=total,
                free=v.f_bavail * v.f_frsize,
                used=total - v.f_bfree * v.f_frsize,
                dev=dev,
            )
        )
    mounts.sort(key=lambda m: -m["total"])
    try:
        hdev = os.stat(sc.home).st_dev
    except OSError:
        hdev = None
    main = next((m for m in mounts if m["dev"] == hdev), mounts[0] if mounts else None)
    return dict(mounts=mounts, main=main, home=sc.home)


# ---- home walk: rollup, media, games by fingerprint ------------------------------
def game_engine(names, path):
    """Fingerprint a game folder from the names directly inside it."""
    if "renpy" in names and "game" in names:
        return "Ren'Py"
    if any(n.endswith("_Data") for n in names) and (
        "UnityPlayer.so" in names
        or "UnityPlayer.dll" in names
        or any(n.endswith((".x86_64", ".exe")) for n in names)
    ):
        return "Unity"
    if "nw.pak" in names or (
        "www" in names and any(n.endswith(".exe") or n == "nw" for n in names)
    ):
        return "RPG Maker / NW.js"
    if any(n.endswith(".pck") for n in names) and any(
        n.endswith((".x86_64", ".exe")) for n in names
    ):
        return "Godot"
    if (
        "Engine" in names
        and any(n.endswith(".exe") or n.endswith(".sh") for n in names)
        and len(names) < 12
    ):
        return "Unreal"
    return None


def scan_home(sc):
    """One pass over $HOME (same device only). Remembers the size of every big
    directory (for the Files browser + other sections), collects video and other
    large files that no game / dependency / cache tree already claims, and finds
    non-Steam games by engine fingerprint."""
    seen = set()
    vids = {}  # dir → [count, bytes, newest]
    big = []  # (bytes, path, mtime, kind)
    games = []  # {path, bytes, newest, engine}
    libs = []  # game-library directories
    prefixes = []
    dupc = []  # (size, path) candidates for duplicate detection
    proj = set(sc.project_roots)
    cache_root = XDG["$CACHE"]
    trash = os.path.join(XDG["$DATA"], "Trash")
    forced_libs = set(sc.game_dirs)
    try:
        home_dev = os.stat(sc.home).st_dev
    except OSError:
        return dict(
            top=[],
            videos=dict(dirs=[], files=[], count=0, bytes=0),
            games=[],
            big=[],
            dups=[],
        )
    count = [0]

    def walk(d, claim, depth):
        """→ (bytes, newest, engine-or-None)"""
        try:
            ents = list(os.scandir(d))
        except OSError:
            return 0, 0, None
        names = {e.name for e in ents}
        engine = None
        prefix_root = False
        if claim is None:
            if d in proj:
                claim = "project"
            elif d == cache_root or d == trash:
                claim = "cache"
            elif "steamapps" in names:
                claim = "steam"
            elif "drive_c" in names and "system.reg" in names:
                claim = "prefix"
                prefix_root = True
            else:
                engine = game_engine(names, d)
                if engine:
                    claim = "game"
        total = newest = 0
        kids = []  # (path, bytes, newest, engine) of sub-directories
        for e in ents:
            try:
                s = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISDIR(s.st_mode):
                if s.st_dev != home_dev:
                    continue
                sub = claim
                if sub is None and (e.name in R.DEP_NAMES or e.name == ".git"):
                    sub = "deps"
                b, n, eng = walk(e.path, sub, depth + 1)
                b += alloc(s)
                total += b
                newest = max(newest, n)
                if claim is None:
                    kids.append((e.path, b, n, eng))
                continue
            b = alloc(s)
            if s.st_nlink > 1:
                k = (s.st_dev, s.st_ino)
                if k in seen:
                    continue
                seen.add(k)
            total += b
            count[0] += 1
            if s.st_mtime > newest:
                newest = s.st_mtime
            if b < (1 << 20) or not stat.S_ISREG(s.st_mode):
                continue
            if claim in ("game", None) and b >= (50 << 20):
                dupc.append((s.st_size, e.path))
            if claim is not None:
                continue
            kind = R.ext_kind(e.name)
            if kind == "video":
                v = vids.setdefault(d, [0, 0, 0])
                v[0] += 1
                v[1] += b
                v[2] = max(v[2], s.st_mtime)
            if b >= (100 << 20) or (kind == "video" and b >= (20 << 20)):
                big.append((b, e.path, s.st_mtime, kind))
        if engine:
            games.append(dict(path=d, bytes=total, newest=newest, engine=engine))
        elif prefix_root and depth > 0:
            prefixes.append(dict(path=d, bytes=total, newest=newest))
        elif claim is None and kids:
            # a folder whose sub-folders are mostly games is a game library: the
            # rest of its sub-folders are games too (HTML / unknown engines)
            g = [k for k in kids if k[3]]
            if d in forced_libs or (len(g) >= 3 and len(g) * 2 >= len(kids)):
                libs.append(d)
                for p, b, n, eng in kids:
                    if not eng and b >= (16 << 20):
                        games.append(dict(path=p, bytes=b, newest=n, engine="unknown"))
        if total >= SIZE_FLOOR:
            sc.sizes[d] = [total, int(newest)]
        if depth == 1:
            sc.progress("home", "running", at=tilde(d), files=count[0])
        return total, newest, engine

    total, _, _ = walk(sc.home, None, 0)

    def in_lib(p):
        return any(p == lb or p.startswith(lb + "/") for lb in libs)

    # top-level rollup (depth 1, with depth 2 for the usual umbrella dirs)
    top = []
    umbrella = {".local", ".cache", ".config", ".var", "Documents"}
    try:
        for e in os.scandir(sc.home):
            if not e.is_dir(follow_symlinks=False):
                continue
            sz = sc.sizes.get(e.path)
            if not sz:
                continue
            row = dict(path=e.path, name=e.name, bytes=sz[0], newest=sz[1], kids=[])
            if e.name in umbrella:
                sub = [
                    (p, v)
                    for p, v in sc.sizes.items()
                    if os.path.dirname(p) == e.path
                    or (
                        e.name == ".local"
                        and os.path.dirname(os.path.dirname(p)) == e.path
                    )
                ]
                sub = [(p, v) for p, v in sub if p != os.path.join(e.path, "share")]
                sub.sort(key=lambda x: -x[1][0])
                row["kids"] = [
                    dict(
                        path=p, name=os.path.relpath(p, e.path), bytes=v[0], newest=v[1]
                    )
                    for p, v in sub[:8]
                ]
            top.append(row)
    except OSError:
        pass
    top.sort(key=lambda r: -r["bytes"])

    vdirs = [
        dict(path=d, count=v[0], bytes=v[1], newest=int(v[2]))
        for d, v in vids.items()
        if not in_lib(d)
    ]
    vdirs.sort(key=lambda r: -r["bytes"])
    bigf = [
        dict(bytes=b, path=p, mtime=int(m), kind=k)
        for b, p, m, k in sorted(big, reverse=True)
        if not in_lib(p)
    ]
    vfiles = [f for f in bigf if f["kind"] == "video"]
    games = [
        g
        for g in games
        if not any(g["path"].startswith(o["path"] + "/") for o in games if o is not g)
    ]
    sc.shared.update(
        games=games,
        libs=libs,
        prefixes=prefixes,
        dupc=dupc,
        big=bigf,
        home_bytes=total,
        home_files=count[0],
    )
    return dict(
        bytes=total,
        files=count[0],
        top=top,
        videos=dict(
            count=sum(v["count"] for v in vdirs),
            bytes=sum(v["bytes"] for v in vdirs),
            dirs=vdirs[:60],
            files=vfiles[:120],
        ),
        big=[f for f in bigf if f["kind"] != "video"][:150],
    )


# ---- projects --------------------------------------------------------------------
def _match(markers, names):
    for m in markers:
        if m.startswith("*"):
            if any(n.endswith(m[1:]) for n in names):
                return True
        elif m in names:
            return True
    return False


def classify_dir(name, siblings, path):
    """'deps' / 'build' / None for a directory, by name and marker files."""
    if name in R.DEP_NAMES:
        return "deps"
    if name in R.BUILD_NAMES or name.endswith(R.BUILD_SUFFIXES):
        return "build"
    m = R.MARKED_NAMES.get(name)
    if m:
        kind, sib, inside = m
        if _match(sib, siblings):
            return kind
        for i in inside:
            if os.path.lexists(os.path.join(path, i)):
                return kind
    return None


def is_project_root(names):
    if ".git" in names:
        return True
    if any(n in R.MANIFESTS for n in names):
        return True
    return any(n.endswith(tuple(R.MANIFEST_SUFFIXES)) for n in names)


def find_projects(roots, max_depth=4):
    """Top-most directories holding .git or a manifest, below each root."""
    found, loose = [], {}
    for root in roots:
        stack = [(root, 0)]
        while stack:
            d, depth = stack.pop()
            try:
                ents = list(os.scandir(d))
            except OSError:
                continue
            names = {e.name for e in ents}
            if is_project_root(names) and (depth > 0 or ".git" in names):
                found.append((d, root))
                continue
            for e in ents:
                try:
                    if e.is_dir(follow_symlinks=False):
                        if (
                            depth < max_depth
                            and not e.name.startswith(".")
                            and e.name not in R.DEP_NAMES
                        ):
                            stack.append((e.path, depth + 1))
                        elif depth >= max_depth:
                            found.append(
                                (e.path, root)
                            )  # too deep to tell: still account for it
                    else:
                        loose[root] = loose.get(root, 0) + alloc(
                            e.stat(follow_symlinks=False)
                        )
                except OSError:
                    pass
    return found, loose


def git(root, *args, timeout=15):
    return run(["git", "-C", root] + list(args), timeout=timeout, env=GIT_ENV)


def git_facts(root):
    """Everything that says whether a repo holds work that exists nowhere else."""
    f = dict(
        is_git=False,
        commit=0,
        dirty=0,
        unpushed=0,
        remote="",
        stash=0,
        worktree_of="",
        branch="",
    )
    dotgit = os.path.join(root, ".git")
    if not os.path.lexists(dotgit):
        return f
    f["is_git"] = True
    if os.path.isfile(dotgit):
        rc, out = git(root, "rev-parse", "--git-common-dir")
        if rc == 0 and out.strip():
            common = os.path.realpath(os.path.join(root, out.strip()))
            main = (
                os.path.dirname(common)
                if os.path.basename(common) == ".git"
                else common
            )
            if main != os.path.realpath(root):
                f["worktree_of"] = main
    rc, out = git(root, "log", "-1", "--format=%ct")
    if rc == 0 and out.strip().isdigit():
        f["commit"] = int(out.strip())
    rc, out = git(root, "status", "--porcelain", timeout=30)
    if rc == 0:
        f["dirty"] = sum(1 for ln in out.splitlines() if ln.strip())
    elif rc == 124:
        f["dirty"] = -1  # could not tell in time: treat as dirty
    rc, out = git(root, "remote", "get-url", "origin")
    if rc == 0 and out.strip():
        f["remote"] = out.strip()
    else:
        rc, out = git(root, "remote")
        names = out.split()
        if rc == 0 and names:
            rc, out = git(root, "remote", "get-url", names[0])
            f["remote"] = out.strip() or names[0]
    rc, out = git(root, "rev-list", "--count", "--branches", "--not", "--remotes")
    if rc == 0 and out.strip().isdigit():
        f["unpushed"] = int(out.strip()) if f["remote"] else 0
    rc, out = git(root, "rev-list", "--walk-reflogs", "--count", "refs/stash")
    if rc == 0 and out.strip().isdigit():
        f["stash"] = int(out.strip())
    rc, out = git(root, "branch", "--show-current")
    f["branch"] = out.strip() if rc == 0 else ""
    return f


def tracked_dirs(root):
    """Set of directories (relative) that hold git-tracked files, or None."""
    if not os.path.lexists(os.path.join(root, ".git")):
        return None
    rc, out = git(root, "ls-files", "-z", timeout=30)
    if rc != 0:
        return None
    dirs = set()
    for f in out.split("\0"):
        i = f.rfind("/")
        while i > 0:
            f = f[:i]
            if f in dirs:
                break
            dirs.add(f)
            i = f.rfind("/")
    return dirs


def scan_project(root, group_root):
    """Walk one project: bytes by kind + every dependency / build directory."""
    p = dict(
        path=root,
        root=group_root,
        bytes=0,
        deps=0,
        build=0,
        git=0,
        src=0,
        scratch=0,
        newest=0,
        eco=[],
        locks=[],
        docker=False,
        env=False,
        cands=[],
        tracked_skips=0,
    )
    tracked = tracked_dirs(root)
    seen = set()
    try:
        dev = os.lstat(root).st_dev
    except OSError:
        return p

    def walk(d, rel):
        try:
            ents = list(os.scandir(d))
        except OSError:
            return
        names = {e.name for e in ents}
        if rel == "":
            p["eco"] = sorted(
                {R.MANIFESTS[n] for n in names if n in R.MANIFESTS}
                | {
                    v
                    for s, v in R.MANIFEST_SUFFIXES.items()
                    if any(n.endswith(s) for n in names)
                }
            )
            p["locks"] = [n for n in R.LOCKFILES if n in names]
            p["docker"] = any(
                n == "Dockerfile" or n.startswith(("docker-compose", "compose.y"))
                for n in names
            )
            p["env"] = any(
                n == ".env"
                or n.startswith(".env.")
                and not n.endswith((".example", ".sample", ".template"))
                for n in names
            )
        for e in ents:
            try:
                s = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISDIR(s.st_mode):
                if s.st_dev != dev:
                    continue
                r = e.name if not rel else rel + "/" + e.name
                if e.name == ".git":
                    p["git"] += du(e.path, seen)["bytes"]
                    continue
                kind = classify_dir(e.name, names, e.path)
                if kind and tracked is not None and r in tracked:
                    p["tracked_skips"] += 1
                    kind = None
                if kind:
                    st = du(e.path, seen, detail=(kind == "build"))
                    p[kind] += st["bytes"]
                    lock = next(
                        (n for n in R.DEP_LOCKS.get(e.name, ()) if n in names), ""
                    )
                    p["cands"].append(
                        dict(
                            path=e.path, rel=r, name=e.name, kind=kind, lock=lock, **st
                        )
                    )
                    continue
                if e.name in R.SCRATCH_NAMES:
                    p["scratch"] += du(e.path, seen)["bytes"]
                    continue
                p["src"] += alloc(s)
                walk(e.path, r)
            else:
                b = alloc(s)
                if s.st_nlink > 1:
                    k = (s.st_dev, s.st_ino)
                    if k in seen:
                        continue
                    seen.add(k)
                p["src"] += b
                if s.st_mtime > p["newest"]:
                    p["newest"] = s.st_mtime

    walk(root, "")
    p["bytes"] = p["deps"] + p["build"] + p["git"] + p["src"] + p["scratch"]
    return p


def _plural(n, word):
    return "%d %s%s" % (n, word, "" if n == 1 else "s")


def judge_candidate(c, p):
    """→ (tier, why, restore, warn[]) for one dependency / build directory."""
    warn = []
    if c["kind"] == "deps":
        lock = c["lock"] or next((n for n in p["locks"]), "")
        if lock:
            return (
                "cost",
                "Dependencies pinned by %s." % lock,
                R.LOCKFILES.get(lock, ""),
                warn,
            )
        warn.append(
            "No lockfile next to it: the exact versions installed here are not recorded anywhere."
        )
        return "state", "Dependencies with nothing pinning their versions.", "", warn
    kinds = c.get("kinds") or {}
    media = sum(kinds.get(k, 0) for k in MEDIA_KINDS)
    span = (c["newest"] - c["oldest"]) / 86400 if c.get("oldest") else 0
    if c["bytes"] > (200 << 20) and media * 2 > c["bytes"] and span > 3:
        warn.append(
            "Mostly media and archives, written over %d days. A build does not produce that — this looks like data kept in a build folder."
            % span
        )
        return "data", "Named like build output, but holds data.", "", warn
    if c.get("stateful"):
        warn.append(
            "Holds %s — possibly state, not just build output."
            % ", ".join(c["stateful"])
        )
        return "state", "Build output with databases or .env files inside.", "", warn
    return "free", "Build output; the project's build writes it again.", "", warn


def scan_projects(sc):
    found, loose = find_projects(sc.project_roots)
    # worktrees that live outside the project roots still belong to a project
    known = {p for p, _ in found}
    extra = []
    for root, _ in list(found):
        if os.path.isdir(os.path.join(root, ".git")) and os.path.isdir(
            os.path.join(root, ".git", "worktrees")
        ):
            rc, out = git(root, "worktree", "list", "--porcelain")
            for ln in out.splitlines() if rc == 0 else ():
                if ln.startswith("worktree "):
                    w = ln[9:]
                    if w not in known and os.path.isdir(w):
                        known.add(w)
                        extra.append((w, os.path.dirname(w)))
    found += extra
    total = len(found)
    done = [0]

    def one(arg):
        root, group = arg
        p = scan_project(root, group)
        p.update(git_facts(root))
        done[0] += 1
        sc.progress("projects", "running", at=tilde(root), done=done[0], total=total)
        return p

    with ThreadPoolExecutor(6) as ex:
        raw = list(ex.map(one, found))

    rows = []
    tot = dict(
        count=0,
        bytes=0,
        deps=0,
        build=0,
        git=0,
        src=0,
        reclaim=0,
        stale=0,
        stale_reclaim=0,
        worktrees=0,
    )
    for p in raw:
        last = max(p["commit"], int(p["newest"]))
        age = sc.age_days(last) or 0
        status = (
            "active"
            if age < 30
            else "recent"
            if age < sc.stale_days
            else "stale"
            if age < 730
            else "dormant"
        )
        keep = []  # why the project itself matters
        has_git = os.path.lexists(os.path.join(p["path"], ".git"))
        if not has_git:
            keep.append("not in git — this folder is the only copy")
        if p["dirty"]:
            keep.append(
                "uncommitted changes"
                if p["dirty"] < 0
                else _plural(p["dirty"], "uncommitted file")
            )
        if p["unpushed"]:
            keep.append(_plural(p["unpushed"], "unpushed commit"))
        if p["stash"]:
            keep.append("%d stash%s" % (p["stash"], "" if p["stash"] == 1 else "es"))
        if has_git and not p["remote"] and not p["worktree_of"]:
            keep.append("no remote — commits exist only here")
        ids, recl, flagged = [], 0, 0
        # many small same-named dirs (__pycache__ …) become one item
        byname = {}
        for c in p["cands"]:
            byname.setdefault(c["name"], []).append(c)
        rel_base = os.path.relpath(p["path"], p["root"])
        for name, cs in byname.items():
            groups = (
                [cs]
                if len(cs) > 3 and all(c["bytes"] < (64 << 20) for c in cs)
                else [[c] for c in cs]
            )
            for g in groups:
                b = sum(c["bytes"] for c in g)
                if b < (256 << 10):
                    continue
                tier, why, restore, warn = judge_candidate(
                    max(g, key=lambda c: c["bytes"]), p
                )
                if len(g) > 1:
                    worst = max(
                        (judge_candidate(c, p) for c in g),
                        key=lambda j: R.TIERS.index(j[0]),
                    )
                    tier, why, restore, warn = worst
                title = g[0]["rel"] if len(g) == 1 else "%d × %s" % (len(g), name)
                iid = sc.add(
                    "projects",
                    g[0]["kind"],
                    "|".join(c["path"] for c in g),
                    title=title,
                    sub=rel_base,
                    paths=[c["path"] for c in g],
                    bytes=b,
                    reclaim=sum(c["reclaim"] for c in g),
                    mtime=int(max(c["newest"] for c in g)),
                    tier=tier,
                    why=why,
                    restore=restore,
                    warn=warn,
                    method="rm",
                    project=p["path"],
                    offer=(tier in ("free", "cost") and status != "active"),
                )
                ids.append(iid)
                if tier in ("free", "cost"):
                    recl += sum(c["reclaim"] for c in g)
                else:
                    flagged += 1
        # the whole project, for the ones that are not being worked on
        whole = ""
        if status != "active":
            if p["worktree_of"]:
                w = list(keep)
                whole = sc.add(
                    "projects",
                    "worktree",
                    p["path"],
                    title="Whole worktree",
                    sub=rel_base,
                    paths=[p["path"]],
                    bytes=p["bytes"],
                    mtime=last,
                    tier="state" if w else "cost",
                    why="A git worktree of %s; its branch%s stays in that repository."
                    % (
                        tilde(p["worktree_of"]),
                        " (" + p["branch"] + ")" if p["branch"] else "",
                    ),
                    restore="git -C %s worktree add %s %s"
                    % (q(p["worktree_of"]), q(p["path"]), p["branch"] or "<branch>"),
                    warn=[k.capitalize() + "." for k in w],
                    method="cmd",
                    argv=[
                        "git",
                        "-C",
                        p["worktree_of"],
                        "worktree",
                        "remove",
                        p["path"],
                    ],
                    project=p["path"],
                )
            else:
                w = [k.capitalize() + "." for k in keep]
                if p["env"]:
                    w.append("Has .env files, which are not in git.")
                if p["scratch"] > (1 << 20):
                    w.append("Has agent / editor scratch folders that are not in git.")
                clean = not w and p["remote"]
                whole = sc.add(
                    "projects",
                    "project",
                    p["path"],
                    title="Whole project",
                    sub=rel_base,
                    paths=[p["path"]],
                    bytes=p["bytes"],
                    mtime=last,
                    tier="cost" if clean else "data",
                    why=("Clean and fully pushed to %s." % p["remote"])
                    if clean
                    else "The project folder itself.",
                    restore=("git clone %s" % q(p["remote"])) if p["remote"] else "",
                    warn=w,
                    method="trash",
                    project=p["path"],
                )
        if status == "active":
            verdict, tone = "active · leave", "leave"
        elif recl + (flagged and 1) == 0 or (recl < (50 << 20) and not flagged):
            verdict, tone = "nothing to reclaim", "none"
        elif flagged and recl < (50 << 20):
            verdict, tone = "look before removing", "stop"
        elif flagged:
            verdict, tone = "deps can go · some output needs a look", "warn"
        else:
            verdict, tone = "deps and build output can go", "safe"
        rows.append(
            dict(
                path=p["path"],
                name=os.path.basename(p["path"]),
                rel=rel_base,
                root=p["root"],
                eco=p["eco"],
                bytes=p["bytes"],
                deps=p["deps"],
                build=p["build"],
                git=p["git"],
                src=p["src"] + p["scratch"],
                reclaim=recl,
                last=last,
                commit=p["commit"],
                status=status,
                dirty=p["dirty"],
                unpushed=p["unpushed"],
                stash=p["stash"],
                remote=p["remote"],
                nogit=not os.path.lexists(os.path.join(p["path"], ".git")),
                worktree_of=p["worktree_of"],
                branch=p["branch"],
                docker=p["docker"],
                keep=keep,
                verdict=verdict,
                tone=tone,
                items=ids,
                whole=whole,
                tracked_skips=p["tracked_skips"],
            )
        )
        tot["count"] += 1
        for k in ("bytes", "deps", "build", "git"):
            tot[k] += p[k]
        tot["src"] += p["src"] + p["scratch"]
        tot["reclaim"] += recl
        tot["worktrees"] += 1 if p["worktree_of"] else 0
        if status in ("stale", "dormant"):
            tot["stale"] += 1
            tot["stale_reclaim"] += recl
    rows.sort(key=lambda r: -r["reclaim"])
    tot["loose"] = sum(loose.values())
    return dict(
        roots=sc.project_roots, totals=tot, projects=rows, staleDays=sc.stale_days
    )


# ---- caches ----------------------------------------------------------------------
def resolve_paths(row):
    """Every existing directory a cache / tool-data row points at."""
    out = []
    ask = row.get("ask")
    if ask and have(ask[0]):
        rc, o = run(ask, timeout=8)
        line = o.strip().splitlines()[-1].strip() if rc == 0 and o.strip() else ""
        if line.startswith("/"):
            out.append(line)
    for spec in row.get("env", ()):
        var, _, sub = spec.partition(":")
        v = os.environ.get(var)
        if v:
            out.append(v.rstrip("/") + sub)
    out += [expand(p) for p in row.get("paths", ())]
    res = []
    for p in out:
        if row.get("sub") and os.path.isdir(os.path.join(p, row["sub"])):
            p = os.path.join(p, row["sub"])
        rp = os.path.realpath(p)
        if os.path.isdir(rp) and rp not in res:
            res.append(rp)
        if res and (ask or row.get("env")) and len(res) >= 1 and p == out[0]:
            break  # the tool told us; don't add the default as a second location
    return res


def _size(sc, path, seen=None):
    """du, with numbers for the Files cache."""
    st = du(path, seen)
    if st["bytes"] >= SIZE_FLOOR:
        sc.sizes.setdefault(path, [st["bytes"], int(st["newest"])])
    return st


def scan_caches(sc):
    rows, known, tools = [], set(), []
    todo = [(row, p) for row in R.CACHES for p in resolve_paths(row)]

    def one(arg):
        row, path = arg
        return row, path, du(path)

    with ThreadPoolExecutor(4) as ex:
        res = list(ex.map(one, todo))
    packages = []
    for row, path, st in res:
        known.add(path)
        if st["bytes"] < (1 << 20):
            continue
        clean = row.get("clean")
        use_tool = bool(clean and have(clean[0]))
        note = row["note"]
        warn = []
        if row.get("hardlinked") and st["reclaim"] < st["bytes"] * 0.8:
            warn.append(
                "Only part of this frees up: the rest is hardlinked into project folders."
            )
        if row.get("closed"):
            warn.append("Close the browser first.")
        iid = sc.add(
            row.get("section", "caches"),
            "cache",
            row["key"] + "|" + path,
            title=row["label"],
            sub=tilde(path),
            paths=[path],
            bytes=st["bytes"],
            reclaim=st["reclaim"],
            mtime=int(st["newest"]),
            tier=row["tier"],
            why=note,
            restore="",
            warn=warn,
            method="cmd" if use_tool else "contents",
            argv=clean if use_tool else None,
            offer=(row["tier"] == "free"),
            pre=row.get("pre"),
        )
        r = dict(
            id=iid,
            key=row["key"],
            label=row["label"],
            path=path,
            bytes=st["bytes"],
            reclaim=st["reclaim"],
            newest=int(st["newest"]),
            tier=row["tier"],
            note=note,
            heavy=bool(row.get("heavy")),
        )
        (packages if row.get("section") == "packages" else rows).append(r)
    # Electron-style caches under ~/.config/<App>/
    cfg = XDG["$CONFIG"]
    try:
        apps = [e for e in os.scandir(cfg) if e.is_dir(follow_symlinks=False)]
    except OSError:
        apps = []
    for app in apps:
        paths = [
            os.path.join(app.path, d)
            for d in R.ELECTRON_CACHE_DIRS
            if os.path.isdir(os.path.join(app.path, d))
        ]
        if not paths:
            continue
        b = n = 0
        for p in paths:
            st = du(p)
            b += st["bytes"]
            n = max(n, st["newest"])
        if b < (64 << 20):
            continue
        iid = sc.add(
            "caches",
            "cache",
            "electron|" + app.path,
            title=app.name + " app cache",
            sub=tilde(app.path),
            paths=paths,
            bytes=b,
            mtime=int(n),
            tier="free",
            why="Web and GPU cache of the app; it refills as you use it.",
            warn=["Close %s first." % app.name],
            method="contents",
            offer=False,
        )
        rows.append(
            dict(
                id=iid,
                key="app:" + app.name,
                label=app.name + " app cache",
                path=app.path,
                bytes=b,
                reclaim=b,
                newest=int(n),
                tier="free",
                note="Web and GPU cache of the app; it refills as you use it.",
                heavy=False,
            )
        )
    # whatever else sits in the cache directory
    other = []
    croot = XDG["$CACHE"]
    try:
        ents = [e for e in os.scandir(croot) if e.is_dir(follow_symlinks=False)]
    except OSError:
        ents = []
    skip = {"thumbnails", "pill"}
    unknown = [
        e
        for e in ents
        if e.name not in skip
        and not any(k == e.path or k.startswith(e.path + "/") for k in known)
    ]
    with ThreadPoolExecutor(4) as ex:
        sizes = list(ex.map(lambda e: du(e.path), unknown))
    for e, st in zip(unknown, sizes):
        if st["bytes"] < (32 << 20):
            continue
        age = sc.age_days(st["newest"]) or 0
        stale = age > sc.stale_days
        iid = sc.add(
            "caches",
            "cache",
            "other|" + e.path,
            title=e.name,
            sub=tilde(e.path),
            paths=[e.path],
            bytes=st["bytes"],
            reclaim=st["reclaim"],
            mtime=int(st["newest"]),
            tier="free" if stale else "cost",
            why="In the cache folder, so its owner is expected to cope with it vanishing. I do not know this one specifically.",
            warn=[]
            if stale
            else ["Still being written to — its program may be running."],
            method="contents",
            offer=False,
        )
        other.append(
            dict(
                id=iid,
                key="other:" + e.name,
                label=e.name,
                path=e.path,
                bytes=st["bytes"],
                reclaim=st["reclaim"],
                newest=int(st["newest"]),
                tier="free" if stale else "cost",
                stale=stale,
                note="Unrecognised cache folder%s."
                % (", untouched for %d days" % age if stale else ""),
                heavy=False,
            )
        )
    for row in R.TOOL_DATA:
        for path in resolve_paths(row):
            st = du(path)
            if st["bytes"] >= (64 << 20):
                tools.append(
                    dict(
                        key=row["key"],
                        label=row["label"],
                        path=path,
                        bytes=st["bytes"],
                        newest=int(st["newest"]),
                        note=row["note"],
                    )
                )
    rows.sort(key=lambda r: -r["bytes"])
    other.sort(key=lambda r: -r["bytes"])
    tools.sort(key=lambda r: -r["bytes"])
    sc.shared["pkg_caches"] = packages
    return dict(
        known=rows,
        other=other,
        tools=tools,
        bytes=sum(r["bytes"] for r in rows + other),
        reclaim=sum(r["reclaim"] for r in rows + other),
    )


# ---- packages (pacman / AUR helpers / flatpak / journal / trash) -------------------
def _vercmp():
    try:
        import pyalpm

        return pyalpm.vercmp
    except Exception:
        return None


PKG_RE = re.compile(r"^(.+)-([^-]+-[^-]+)-([^-]+)\.pkg\.tar\.[a-z0-9]+$")


def pacman_cache(sc):
    rc, out = run(["pacman-conf", "CacheDir"])
    dirs = (
        [d.strip() for d in out.splitlines() if d.strip()]
        if rc == 0
        else ["/var/cache/pacman/pkg/"]
    )
    files, total, partial = {}, 0, 0
    for d in dirs:
        try:
            it = list(os.scandir(d))
        except OSError:
            continue
        for e in it:
            try:
                s = e.stat(follow_symlinks=False)
            except OSError:
                continue
            if e.is_dir(follow_symlinks=False):
                partial += 1
                continue
            total += alloc(s)
            if e.name.endswith(".sig"):
                continue
            m = PKG_RE.match(e.name)
            if m:
                files.setdefault(m.group(1), []).append(
                    (m.group(2), alloc(s), s.st_mtime)
                )
    if not files:
        return None
    cmp_ = _vercmp()
    import functools

    keep = {1: 0, 2: 0, 3: 0}
    for name, vs in files.items():
        if cmp_:
            vs.sort(key=functools.cmp_to_key(lambda a, b: cmp_(b[0], a[0])))
        else:
            vs.sort(key=lambda v: -v[2])
        for k in keep:
            keep[k] += sum(v[1] for v in vs[k:])
    rc, out = run(["pacman", "-Qq"])
    installed = set(out.split()) if rc == 0 else set()
    uninstalled = sum(
        v[1] for n, vs in files.items() if installed and n not in installed for v in vs
    )
    return dict(
        dirs=dirs,
        bytes=total,
        files=sum(len(v) for v in files.values()),
        names=len(files),
        keep1=keep[1],
        keep2=keep[2],
        keep3=keep[3],
        uninstalled=uninstalled,
        partial=partial,
        paccache=have("paccache"),
    )


def scan_packages(sc):
    groups = []
    pm = None
    if have("pacman"):
        pm = pacman_cache(sc)
    if pm:
        rows = []
        if pm["paccache"]:
            for k, label in (
                (2, "Keep the 2 newest versions of each package"),
                (1, "Keep only the newest version"),
            ):
                b = pm["keep%d" % k]
                if b > (16 << 20):
                    iid = sc.add(
                        "packages",
                        "pkgcache",
                        "pacman-keep%d" % k,
                        title="Package cache: " + label.lower(),
                        sub=pm["dirs"][0],
                        bytes=b,
                        tier="cost",
                        why="Old versions are only needed to downgrade; they download again on demand.",
                        method="terminal",
                        cmd="sudo paccache -rk%d" % k,
                        warn=["Needs administrator rights."],
                        offer=(k == 2),
                    )
                    rows.append(
                        dict(
                            id=iid,
                            label=label,
                            bytes=b,
                            note="sudo paccache -rk%d" % k,
                            tier="cost",
                        )
                    )
        else:
            b = pm["keep1"]
            iid = sc.add(
                "packages",
                "pkgcache",
                "pacman-Sc",
                title="Package cache: drop everything not installed right now",
                sub=pm["dirs"][0],
                bytes=b,
                tier="cost",
                why="Old versions are only needed to downgrade; they download again on demand.",
                method="terminal",
                cmd="sudo pacman -Sc",
                warn=[
                    "Needs administrator rights.",
                    "paccache (package pacman-contrib) is not installed, so there is no keep-2 option: this keeps installed versions only.",
                ],
                offer=False,
            )
            rows.append(
                dict(
                    id=iid,
                    label="Drop every version that is not installed now",
                    bytes=b,
                    note="sudo pacman -Sc",
                    tier="cost",
                )
            )
            rows.append(
                dict(
                    id="",
                    label="Keeping the 2 newest instead would free",
                    bytes=pm["keep2"],
                    note="Install pacman-contrib, then: sudo paccache -rk2",
                    tier="cost",
                )
            )
        groups.append(
            dict(
                key="pacman",
                title="Pacman package cache",
                bytes=pm["bytes"],
                note="%d files for %d packages%s"
                % (
                    pm["files"],
                    pm["names"],
                    ", plus %d interrupted download folders" % pm["partial"]
                    if pm["partial"]
                    else "",
                ),
                rows=rows,
            )
        )
    # AUR helper caches (sized by the caches scanner)
    for r in sc.shared.get("pkg_caches", []):
        rows = [
            dict(
                id=r["id"],
                label="Everything in " + tilde(r["path"]),
                bytes=r["bytes"],
                note=r["note"],
                tier="cost",
            )
        ]
        rc, out = run(["pacman", "-Qq"])
        inst = set(out.split()) if rc == 0 else set()
        gone, gb = [], 0
        try:
            for e in os.scandir(r["path"]):
                if e.is_dir(follow_symlinks=False) and inst and e.name not in inst:
                    st = du(e.path)
                    if st["bytes"] > (1 << 20):
                        gone.append(e.path)
                        gb += st["bytes"]
        except OSError:
            pass
        if gone:
            iid = sc.add(
                "packages",
                "pkgcache",
                r["key"] + "-gone",
                title="%s: builds of packages no longer installed" % r["label"],
                sub=tilde(r["path"]),
                paths=gone,
                bytes=gb,
                tier="free",
                method="rm",
                offer=True,
                why="Build folders for %d AUR packages that are not installed any more."
                % len(gone),
            )
            rows.insert(
                0,
                dict(
                    id=iid,
                    label="Builds of %d packages no longer installed" % len(gone),
                    bytes=gb,
                    note="Nothing on the system uses these.",
                    tier="free",
                ),
            )
        groups.append(
            dict(
                key=r["key"],
                title=r["label"],
                bytes=r["bytes"],
                note=tilde(r["path"]),
                rows=rows,
            )
        )
    if have("pacman"):
        rc, out = run(["pacman", "-Qdtq"])
        orphans = out.split() if rc == 0 else []
        if orphans:
            rc, info = run(
                ["pacman", "-Qi"] + orphans,
                timeout=30,
                env=dict(os.environ, LC_ALL="C"),
            )
            sizes, name = {}, ""
            for ln in info.splitlines():
                if ln.startswith("Name"):
                    name = ln.split(":", 1)[1].strip()
                elif ln.startswith("Installed Size"):
                    sizes[name] = parse_size(ln.split(":", 1)[1])
            b = sum(sizes.values())
            top = sorted(sizes.items(), key=lambda x: -x[1])[:12]
            iid = sc.add(
                "packages",
                "orphans",
                "pacman-orphans",
                title="%d orphan packages" % len(orphans),
                sub="installed as dependencies, no longer required",
                bytes=b,
                tier="state",
                method="terminal",
                cmd="sudo pacman -Rns $(pacman -Qdtq)",
                offer=False,
                why="Installed as a dependency of something that is gone.",
                warn=[
                    "Needs administrator rights.",
                    "Read the list first: tools you use directly can show up here if they were first installed as a dependency.",
                ],
                detail=["%s  %s" % (n, s) for n, s in top],
            )
            groups.append(
                dict(
                    key="orphans",
                    title="Orphan packages",
                    bytes=b,
                    note="%d packages nothing depends on" % len(orphans),
                    rows=[
                        dict(
                            id=iid,
                            label=", ".join(n for n, _ in top[:6])
                            + (" …" if len(orphans) > 6 else ""),
                            bytes=b,
                            note="sudo pacman -Rns $(pacman -Qdtq) — review the list in the terminal first",
                            tier="state",
                        )
                    ],
                )
            )
    for d, label, cmd in (
        ("/var/cache/apt/archives", "APT package cache", "sudo apt clean"),
        ("/var/cache/dnf", "DNF package cache", "sudo dnf clean all"),
    ):
        if os.path.isdir(d):
            st = du(d)
            if st["bytes"] > (16 << 20):
                iid = sc.add(
                    "packages",
                    "pkgcache",
                    d,
                    title=label,
                    sub=d,
                    bytes=st["bytes"],
                    tier="cost",
                    method="terminal",
                    cmd=cmd,
                    why="Downloaded packages; they download again on demand.",
                    warn=["Needs administrator rights."],
                    offer=True,
                )
                groups.append(
                    dict(
                        key=d,
                        title=label,
                        bytes=st["bytes"],
                        note=d,
                        rows=[
                            dict(
                                id=iid,
                                label="Everything",
                                bytes=st["bytes"],
                                note=cmd,
                                tier="cost",
                            )
                        ],
                    )
                )
    if have("flatpak"):
        rc, apps = run(["flatpak", "list", "--app", "--columns=runtime"])
        rc2, rts = run(["flatpak", "list", "--runtime", "--columns=ref,size"])
        if rc == 0 and rc2 == 0:
            used = set(apps.split())
            unused, b = [], 0
            for ln in rts.splitlines():
                parts = ln.split("\t")
                ref = parts[0].strip()
                core = ref.split("/")[0]
                # only whole platforms / SDKs: extensions (GL drivers, themes,
                # codecs) are pulled in by other runtimes and cannot be judged here
                if (
                    ref
                    and ref not in used
                    and core.endswith((".Platform", ".Sdk"))
                ):
                    unused.append(ref)
                    b += (
                        parse_size(parts[1].replace("\xa0", " "))
                        if len(parts) > 1
                        else 0
                    )
            if unused:
                iid = sc.add(
                    "packages",
                    "flatpak",
                    "flatpak-unused",
                    title="Flatpak runtimes no app uses",
                    sub="%d runtimes" % len(unused),
                    bytes=b,
                    tier="cost",
                    method="terminal",
                    cmd="flatpak uninstall --unused",
                    offer=True,
                    why="Runtimes left behind by removed or updated apps. Flatpak itself decides the final list.",
                    detail=unused[:12],
                )
                groups.append(
                    dict(
                        key="flatpak",
                        title="Flatpak",
                        bytes=b,
                        note="%d runtimes look unused" % len(unused),
                        rows=[
                            dict(
                                id=iid,
                                label=", ".join(u.split("/")[0] for u in unused[:4]),
                                bytes=b,
                                note="flatpak uninstall --unused",
                                tier="cost",
                            )
                        ],
                    )
                )
    if have("journalctl"):
        rc, out = run(["journalctl", "--disk-usage"])
        m = re.search(r"take up ([\d.]+\s*[KMGT]i?B?)", out)
        b = parse_size(
            m.group(1).replace("K", "Ki").replace("M", "Mi").replace("G", "Gi")
            if m and "i" not in m.group(1)
            else (m.group(1) if m else "")
        )
        if b > (512 << 20):
            iid = sc.add(
                "packages",
                "journal",
                "journal",
                title="System journal older than the newest 500 MB",
                sub="/var/log/journal",
                bytes=max(0, b - (500 << 20)),
                tier="free",
                method="terminal",
                cmd="sudo journalctl --vacuum-size=500M",
                why="Old system logs.",
                warn=["Needs administrator rights."],
                offer=True,
            )
            groups.append(
                dict(
                    key="journal",
                    title="System journal",
                    bytes=b,
                    note="/var/log/journal",
                    rows=[
                        dict(
                            id=iid,
                            label="Everything but the newest 500 MB",
                            bytes=max(0, b - (500 << 20)),
                            note="sudo journalctl --vacuum-size=500M",
                            tier="free",
                        )
                    ],
                )
            )
    core = "/var/lib/systemd/coredump"
    if os.path.isdir(core):
        st = du(core)
        if st["bytes"] > (64 << 20):
            groups.append(
                dict(
                    key="coredump",
                    title="Crash dumps",
                    bytes=st["bytes"],
                    note=core + " — systemd expires these by itself",
                    rows=[
                        dict(
                            id="",
                            label="%d crash dumps" % st["files"],
                            bytes=st["bytes"],
                            note="sudo rm /var/lib/systemd/coredump/*",
                            tier="free",
                        )
                    ],
                )
            )
    trash = os.path.join(XDG["$DATA"], "Trash")
    if os.path.isdir(trash):
        st = du(trash)
        try:
            n = len(os.listdir(os.path.join(trash, "files")))
        except OSError:
            n = 0
        if st["bytes"] > (1 << 20):
            iid = sc.add(
                "packages",
                "trash",
                "trash",
                title="Empty the Trash",
                sub=_plural(n, "item"),
                paths=[trash],
                bytes=st["bytes"],
                mtime=int(st["newest"]),
                tier="data",
                method="cmd",
                argv=["gio", "trash", "--empty"],
                offer=False,
                why="Things you already threw away. Emptying is what actually frees the space.",
                warn=["After this they cannot be restored from the Trash."],
            )
            groups.append(
                dict(
                    key="trash",
                    title="Trash",
                    bytes=st["bytes"],
                    note=_plural(n, "item") + " waiting in the Trash",
                    rows=[
                        dict(
                            id=iid,
                            label="Empty the Trash",
                            bytes=st["bytes"],
                            note="gio trash --empty",
                            tier="data",
                        )
                    ],
                )
            )
    return dict(groups=groups, bytes=sum(g["bytes"] for g in groups), pacman=pm)


# ---- docker ----------------------------------------------------------------------
def scan_docker(sc):
    if not have("docker"):
        return dict(available=False, reason="Docker is not installed.")
    rc, out = run(
        ["docker", "system", "df", "-v", "--format", "{{json .}}"], timeout=90
    )
    if rc != 0 or not out.strip():
        return dict(
            available=False,
            reason="The Docker daemon did not answer (not running, or this user is not in the docker group).",
        )
    try:
        data = json.loads(out.strip().splitlines()[0])
    except ValueError:
        return dict(available=False, reason="Could not read Docker's answer.")
    imgs, conts, vols, cache = (
        data.get(k) or [] for k in ("Images", "Containers", "Volumes", "BuildCache")
    )

    def sz(x, key="Size"):
        return parse_size(str(x.get(key, "0")))

    dangling = [
        i for i in imgs if i.get("Repository") == "<none>" or i.get("Tag") == "<none>"
    ]
    unused = [i for i in imgs if str(i.get("Containers", "0")) in ("0", "N/A")]
    stopped = [
        c for c in conts if c.get("State") not in ("running", "restarting", "paused")
    ]
    loose = [v for v in vols if str(v.get("Links", "0")) == "0"]
    anon = [v for v in loose if re.fullmatch(r"[0-9a-f]{64}", v.get("Name", ""))]
    idle = [b for b in cache if str(b.get("InUse", "false")).lower() != "true"]
    tot = dict(
        images=sum(sz(i, "UniqueSize") or sz(i) for i in imgs) if imgs else 0,
        containers=sum(sz(c) for c in conts),
        volumes=sum(sz(v) for v in vols),
        cache=sum(sz(b) for b in cache),
    )
    rc, summ = run(["docker", "system", "df", "--format", "{{json .}}"], timeout=60)
    for ln in summ.splitlines() if rc == 0 else ():
        try:
            j = json.loads(ln)
        except ValueError:
            continue
        key = {
            "Images": "images",
            "Containers": "containers",
            "Local Volumes": "volumes",
            "Build Cache": "cache",
        }.get(j.get("Type"))
        if key:
            tot[key] = parse_size(j.get("Size", "0"))
    rows = []

    def add(kind, title, sub, b, tier, argv, why, warn=(), offer=False):
        if b < (8 << 20):
            return
        iid = sc.add(
            "docker",
            "docker",
            kind,
            title=title,
            sub=sub,
            bytes=b,
            tier=tier,
            method="cmd",
            argv=argv,
            why=why,
            warn=list(warn),
            offer=offer,
        )
        rows.append(
            dict(id=iid, label=title, sub=sub, bytes=b, tier=tier, note=" ".join(argv))
        )

    add(
        "build-cache",
        "Build cache",
        _plural(len(idle), "layer") + " not in use",
        sum(sz(b) for b in idle),
        "free",
        ["docker", "builder", "prune", "-f"],
        "Cached build steps. The next build of each image is slower once.",
        offer=True,
    )
    add(
        "dangling",
        "Dangling images",
        _plural(len(dangling), "untagged image"),
        sum(sz(i, "UniqueSize") for i in dangling),
        "free",
        ["docker", "image", "prune", "-f"],
        "Untagged layers left behind when an image was rebuilt. No container uses them.",
        offer=True,
    )
    add(
        "unused-images",
        "All images without a container",
        _plural(len(unused), "image"),
        sum(sz(i, "UniqueSize") for i in unused),
        "cost",
        ["docker", "image", "prune", "-a", "-f"],
        "Images nothing runs from. Pulled or built again when needed.",
        [
            "Locally built images that are in no registry have to be rebuilt from their Dockerfile."
        ],
    )
    add(
        "stopped",
        "Stopped containers",
        _plural(len(stopped), "container"),
        sum(sz(c) for c in stopped),
        "state",
        ["docker", "container", "prune", "-f"],
        "Containers that are not running.",
        ["Anything written inside a container (not in a volume) goes with it."],
    )
    add(
        "anon-volumes",
        "Anonymous volumes no container uses",
        _plural(len(anon), "volume"),
        sum(sz(v) for v in anon),
        "state",
        ["docker", "volume", "prune", "-f"],
        "Unnamed volumes left by removed containers.",
        [
            "Volumes hold data — a database that ran in a removed container may be in one of these."
        ],
    )
    named = [v for v in loose if v not in anon]
    # compose projects → directories
    comp = {}
    rc, ps = run(["docker", "ps", "-a", "--format", "{{json .}}"], timeout=60)
    for ln in ps.splitlines() if rc == 0 else ():
        try:
            j = json.loads(ln)
        except ValueError:
            continue
        labels = dict(
            kv.split("=", 1) for kv in (j.get("Labels") or "").split(",") if "=" in kv
        )
        name = labels.get("com.docker.compose.project")
        if not name:
            continue
        c = comp.setdefault(
            name,
            dict(
                name=name,
                dir=labels.get("com.docker.compose.project.working_dir", ""),
                containers=0,
                running=0,
            ),
        )
        c["containers"] += 1
        c["running"] += 1 if j.get("State") == "running" else 0
    for c in comp.values():
        c["orphaned"] = bool(c["dir"]) and not os.path.isdir(c["dir"])
    return dict(
        available=True,
        totals=tot,
        bytes=sum(tot.values()),
        rows=rows,
        counts=dict(
            images=len(imgs),
            dangling=len(dangling),
            containers=len(conts),
            running=len(conts) - len(stopped),
            volumes=len(vols),
            named_unused=len(named),
            named_unused_bytes=sum(sz(v) for v in named),
        ),
        compose=sorted(comp.values(), key=lambda c: (not c["orphaned"], c["name"])),
    )


# ---- games: Steam + what the home walk fingerprinted ---------------------------------
def _acf(text):
    return dict(re.findall(r'^\s*"(\w+)"\s+"([^"]*)"\s*$', text, re.M))


TOOL_RE = re.compile(r"^(Proton|Steam Linux Runtime|Steamworks Common|SteamVR)", re.I)


def scan_games(sc):
    steam = None
    root = next(
        (
            os.path.realpath(expand(p))
            for p in R.STEAM_ROOTS
            if os.path.isdir(expand(p))
        ),
        None,
    )
    rows, tools, extras = [], [], []
    if root:
        libs = [root]
        try:
            vdf = open(
                os.path.join(root, "steamapps", "libraryfolders.vdf"), errors="replace"
            ).read()
            for p in re.findall(r'"path"\s+"([^"]+)"', vdf):
                p = os.path.realpath(p.replace("\\\\", "/"))
                if p not in libs and os.path.isdir(p):
                    libs.append(p)
        except OSError:
            pass
        try:
            cfg = open(
                os.path.join(root, "config", "config.vdf"), errors="replace"
            ).read()
        except OSError:
            cfg = ""
        installed = set()
        for lib in libs:
            sa = os.path.join(lib, "steamapps")
            try:
                names = os.listdir(sa)
            except OSError:
                continue
            for n in names:
                if not (n.startswith("appmanifest_") and n.endswith(".acf")):
                    continue
                try:
                    a = _acf(open(os.path.join(sa, n), errors="replace").read())
                except OSError:
                    continue
                appid = a.get("appid", "")
                installed.add(appid)
                path = os.path.join(sa, "common", a.get("installdir", ""))
                b = int(a.get("SizeOnDisk") or 0)
                played = int(a.get("LastPlayed") or 0)
                row = dict(
                    appid=appid,
                    name=a.get("name", appid),
                    path=path,
                    bytes=b,
                    played=played,
                    updated=int(a.get("LastUpdated") or 0),
                )
                if TOOL_RE.match(row["name"]):
                    tools.append(row)
                    continue
                age = sc.age_days(played)
                note = "never played" if not played else "last played %d days ago" % age
                row["id"] = sc.add(
                    "games",
                    "steam-game",
                    appid,
                    title=row["name"],
                    sub="Steam · " + note,
                    paths=[path],
                    bytes=b,
                    mtime=played or row["updated"],
                    tier="cost",
                    method="cmd",
                    argv=["steam", "steam://uninstall/" + appid],
                    why="A Steam game; Steam downloads it again whenever you want it back.",
                    warn=[
                        "This opens Steam's own uninstall dialog — Steam does the removing.",
                        "Saves that are not in Steam Cloud stay in the game's compatibility folder until that is removed too.",
                    ],
                )
                rows.append(row)
            for sub, label, tier, why in (
                (
                    "compatdata",
                    "Compatibility data (Proton prefix)",
                    "state",
                    "The Windows environment of a game — its saves and settings can live here.",
                ),
                (
                    "shadercache",
                    "Shader cache",
                    "free",
                    "Compiled shaders; Steam rebuilds them.",
                ),
            ):
                d = os.path.join(sa, sub)
                try:
                    ents = [e for e in os.scandir(d) if e.is_dir(follow_symlinks=False)]
                except OSError:
                    continue
                tb = ob = 0
                orphan = []
                for e in ents:
                    st = du(e.path)
                    tb += st["bytes"]
                    if e.name not in installed and st["bytes"] > (1 << 20):
                        orphan.append(e.path)
                        ob += st["bytes"]
                ex = dict(
                    key=sub,
                    label=label,
                    bytes=tb,
                    orphan_bytes=ob,
                    orphans=len(orphan),
                    id="",
                )
                if orphan:
                    ex["id"] = sc.add(
                        "games",
                        "steam-" + sub,
                        d,
                        title=label + " of games that are not installed",
                        sub=_plural(len(orphan), "folder"),
                        paths=orphan,
                        bytes=ob,
                        tier=tier,
                        method="rm",
                        why=why,
                        warn=[
                            "Saves of uninstalled games that were not in Steam Cloud are in here."
                        ]
                        if tier == "state"
                        else [],
                        offer=(tier == "free"),
                    )
                extras.append(ex)
        ct = os.path.join(root, "compatibilitytools.d")
        try:
            for e in os.scandir(ct):
                if e.is_dir(follow_symlinks=False):
                    st = du(e.path)
                    used = e.name in cfg
                    iid = sc.add(
                        "games",
                        "proton",
                        e.path,
                        title=e.name,
                        sub="custom Proton build"
                        + ("" if used else " · no game is set to use it"),
                        paths=[e.path],
                        bytes=st["bytes"],
                        mtime=int(st["newest"]),
                        tier="cost",
                        method="rm",
                        why="A compatibility tool you added to Steam; it can be downloaded again.",
                        warn=[
                            "Steam's config names this build — a game is set to use it."
                        ]
                        if used
                        else [],
                        offer=False,
                    )
                    tools.append(
                        dict(
                            name=e.name,
                            path=e.path,
                            bytes=st["bytes"],
                            id=iid,
                            custom=True,
                            used=used,
                        )
                    )
        except OSError:
            pass
        rows.sort(key=lambda r: -r["bytes"])
        steam = dict(
            root=root,
            libraries=libs,
            games=rows,
            tools=sorted(tools, key=lambda r: -r["bytes"]),
            extras=extras,
            bytes=sum(r["bytes"] for r in rows),
            never=sum(1 for r in rows if not r["played"]),
        )
    # non-Steam games found by fingerprint during the home walk
    other = []
    for g in sc.shared.get("games", []):
        if g["bytes"] < (16 << 20):
            continue
        name = os.path.basename(g["path"])
        iid = sc.add(
            "games",
            "game",
            g["path"],
            title=name,
            sub=g["engine"] + " · " + tilde(os.path.dirname(g["path"])),
            paths=[g["path"]],
            bytes=g["bytes"],
            mtime=int(g["newest"]),
            tier="data",
            method="trash",
            why="A game folder outside any launcher. Nothing can download it again for you.",
            warn=["Saves may be inside the folder."],
        )
        other.append(
            dict(
                id=iid,
                name=name,
                path=g["path"],
                bytes=g["bytes"],
                newest=int(g["newest"]),
                engine=g["engine"],
                stem=re.sub(
                    r"[\W_]*(v?\d+([._]\d+)*[a-z]?|pc|linux|win(dows)?|x64|x86_64|public|final|release|market|bkp)\b",
                    "",
                    name,
                    flags=re.I,
                )
                .strip(" -_.")
                .lower(),
            )
        )
    stems = {}
    for o in other:
        stems.setdefault(o["stem"], []).append(o)
    for o in other:
        o["versions"] = len(stems[o["stem"]]) if o["stem"] else 1
    other.sort(key=lambda r: -r["bytes"])
    misc = []
    for row in R.GAME_DIRS:
        for p in resolve_paths(row):
            if any(p == o["path"] or o["path"].startswith(p + "/") for o in other):
                continue
            st = du(p)
            if st["bytes"] >= (64 << 20):
                misc.append(
                    dict(
                        key=row["key"],
                        label=row["label"],
                        path=p,
                        bytes=st["bytes"],
                        newest=int(st["newest"]),
                    )
                )
    for pf in sc.shared.get("prefixes", []):
        if (
            pf["bytes"] >= (64 << 20)
            and not any(m["path"] == pf["path"] for m in misc)
            and "/steamapps/" not in pf["path"]
        ):
            misc.append(
                dict(
                    key="prefix",
                    label="Wine prefix",
                    path=pf["path"],
                    bytes=pf["bytes"],
                    newest=int(pf["newest"]),
                )
            )
    misc.sort(key=lambda r: -r["bytes"])
    return dict(
        steam=steam,
        other=other,
        libraries=sc.shared.get("libs", []),
        misc=misc,
        count=(len(steam["games"]) if steam else 0) + len(other),
        bytes=(steam["bytes"] if steam else 0) + sum(o["bytes"] for o in other),
    )


# ---- thumbnails --------------------------------------------------------------------
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def thumb_meta(path):
    """(uri, mtime) from a freedesktop thumbnail's tEXt / zTXt / iTXt chunks."""
    uri = mt = None
    try:
        with open(path, "rb") as f:
            if f.read(8) != PNG_SIG:
                return None, None
            while True:
                head = f.read(8)
                if len(head) < 8:
                    break
                n, typ = struct.unpack(">I4s", head)
                if typ in (b"IDAT", b"IEND"):
                    break
                if typ not in (b"tEXt", b"zTXt", b"iTXt") or n > (1 << 16):
                    f.seek(n + 4, 1)
                    continue
                data = f.read(n)
                f.seek(4, 1)
                key, _, rest = data.partition(b"\0")
                if key not in (b"Thumb::URI", b"Thumb::MTime"):
                    continue
                try:
                    if typ == b"zTXt":
                        val = zlib.decompress(rest[1:])
                    elif typ == b"iTXt":
                        comp = rest[0:1] == b"\x01"
                        body = rest[2:].split(b"\0", 2)[-1]
                        val = zlib.decompress(body) if comp else body
                    else:
                        val = rest
                except (zlib.error, IndexError):
                    continue
                if key == b"Thumb::URI":
                    uri = val.decode("utf-8", "replace")
                else:
                    mt = val.decode("ascii", "replace")
                if uri is not None and mt is not None:
                    break
    except OSError:
        pass
    return uri, mt


def thumb_state(uri, mt):
    """orphan / stale / ok / away (source on media that is not mounted) / unknown"""
    if not uri:
        return "unknown"
    if not uri.startswith("file://"):
        return "away"
    src = urllib.parse.unquote(uri[7:])
    if src.startswith(("/run/media/", "/media/", "/mnt/", "/run/user/")):
        top = "/".join(src.split("/")[:5])
        if not os.path.exists(top):
            return "away"
    try:
        s = os.stat(src)
    except OSError:
        return "orphan"
    try:
        if mt is not None and int(float(mt)) != int(s.st_mtime):
            return "stale"
    except ValueError:
        pass
    return "ok"


def scan_thumbnails(sc, list_dir=None):
    root = os.path.join(XDG["$CACHE"], "thumbnails")
    buckets, files = [], []
    try:
        subs = [e for e in os.scandir(root) if e.is_dir(follow_symlinks=False)]
    except OSError:
        subs = []
    for sub in subs:
        b = dict(name=sub.name, count=0, bytes=0)
        stack = [sub.path]
        while stack:
            d = stack.pop()
            try:
                for e in os.scandir(d):
                    if e.is_dir(follow_symlinks=False):
                        stack.append(e.path)
                        continue
                    s = e.stat(follow_symlinks=False)
                    b["count"] += 1
                    b["bytes"] += alloc(s)
                    if e.name.endswith(".png") and sub.name != "fail":
                        files.append((e.path, alloc(s)))
            except OSError:
                pass
        buckets.append(b)
    total = len(files)
    state = dict(orphan=[0, 0], stale=[0, 0], ok=[0, 0], away=[0, 0], unknown=[0, 0])
    dead = []
    where = {}  # top directory of the vanished sources → bytes
    done = [0]

    def one(arg):
        path, b = arg
        uri, mt = thumb_meta(path)
        st = thumb_state(uri, mt)
        done[0] += 1
        if done[0] % 5000 == 0:
            sc.progress("thumbnails", "running", done=done[0], total=total)
        return path, b, st, uri

    with ThreadPoolExecutor(8) as ex:
        for path, b, st, uri in ex.map(one, files, chunksize=256):
            state[st][0] += 1
            state[st][1] += b
            if st in ("orphan", "stale"):
                dead.append(path)
                if st == "orphan":
                    src = urllib.parse.unquote(uri[7:])
                    parts = src.split("/")
                    key = (
                        "/".join(parts[:5])
                        if src.startswith(sc.home + "/")
                        else "/".join(parts[:3])
                    )
                    w = where.setdefault(key, [0, 0])
                    w[0] += 1
                    w[1] += b
    listing = ""
    ids = dict(dead="", all="")
    db = state["orphan"][1] + state["stale"][1]
    if dead and list_dir:
        os.makedirs(list_dir, exist_ok=True)
        listing = os.path.join(list_dir, "thumbnails-dead.list")
        with open(listing, "w", errors="surrogateescape") as f:
            f.write("\n".join(dead) + "\n")
    if dead:
        ids["dead"] = sc.add(
            "thumbnails",
            "thumbs-dead",
            root,
            title="Thumbnails of files that are gone or changed",
            sub="%d orphaned · %d outdated" % (state["orphan"][0], state["stale"][0]),
            paths=[root],
            bytes=db,
            tier="free",
            method="list",
            listing=listing,
            offer=True,
            cmd="xargs -d '\\n' rm -f -- < " + q(listing) if listing else "",
            why="Previews of files that no longer exist, or changed since the preview was made. Nothing can ever show them again.",
        )
    allb = sum(b["bytes"] for b in buckets)
    if allb > (1 << 20):
        ids["all"] = sc.add(
            "thumbnails",
            "thumbs-all",
            root + "/*",
            title="Every thumbnail",
            sub=tilde(root),
            paths=[root],
            bytes=allb,
            tier="free",
            method="contents",
            offer=False,
            why="All previews. File managers and image viewers draw them again as you browse — folders open slower the first time.",
        )
    # mpv shelf thumbnails (this repo's mpv config) and similar single-purpose caches
    extra = []
    shelf = os.path.join(XDG["$CACHE"], "mpv")
    if os.path.isdir(shelf):
        st = du(shelf)
        if st["bytes"] > (1 << 20):
            extra.append(
                dict(
                    label="mpv thumbnails and shader cache",
                    path=shelf,
                    bytes=st["bytes"],
                    newest=int(st["newest"]),
                )
            )
    wh = sorted(([k, v[0], v[1]] for k, v in where.items()), key=lambda x: -x[2])[:12]
    return dict(
        root=root,
        buckets=sorted(buckets, key=lambda b: -b["bytes"]),
        bytes=allb,
        count=sum(b["count"] for b in buckets),
        state={k: dict(count=v[0], bytes=v[1]) for k, v in state.items()},
        dead_bytes=db,
        ids=ids,
        where=[dict(path=k, count=c, bytes=b) for k, c, b in wh],
        extra=extra,
    )


# ---- downloads ---------------------------------------------------------------------
SECRET_RE = re.compile(
    r"(\.pem|\.p8|\.p12|\.pfx|\.key|\.kdbx|id_rsa|id_ed25519|backup[-_ ]?codes?|recovery[-_ ]?(codes?|key)|\.gpg|\.asc)",
    re.I,
)


def downloads_dir():
    rc, out = run(["xdg-user-dir", "DOWNLOAD"], timeout=5)
    p = out.strip()
    if (
        rc == 0
        and p
        and os.path.isdir(p)
        and os.path.realpath(p) != os.path.realpath(HOME)
    ):
        return os.path.realpath(p)
    return os.path.join(HOME, "Downloads")


def _sample_hash(path, size):
    h = hashlib.sha1(str(size).encode())
    try:
        with open(path, "rb") as f:
            for off in (0, max(0, size // 2 - (1 << 19)), max(0, size - (1 << 20))):
                f.seek(off)
                h.update(f.read(1 << 20))
    except OSError:
        return None
    return h.hexdigest()


def find_dups(sc):
    """Large files with the same size and matching samples (start/middle/end).
    Verified byte-for-byte before anything is ever removed."""
    by = {}
    for size, path in sc.shared.get("dupc", []):
        by.setdefault(size, []).append(path)
    groups = []
    for size, paths in by.items():
        if len(paths) < 2:
            continue
        hs = {}
        for p in paths:
            h = _sample_hash(p, size)
            if h:
                hs.setdefault(h, []).append(p)
        for h, ps in hs.items():
            if len(ps) > 1:
                groups.append(
                    dict(size=size, paths=sorted(ps, key=lambda p: (len(p), p)))
                )
    groups.sort(key=lambda g: -g["size"] * (len(g["paths"]) - 1))
    return groups


def scan_downloads(sc):
    root = downloads_dir()
    libs = sc.shared.get("libs", [])
    rows, kinds, secrets = [], {}, 0
    dirnames = set()
    try:
        ents = list(os.scandir(root))
    except OSError:
        return dict(root=root, rows=[], kinds=[], bytes=0, dups=[], archives=[])
    for e in ents:
        try:
            s = e.stat(follow_symlinks=False)
        except OSError:
            continue
        isdir = stat.S_ISDIR(s.st_mode)
        if isdir:
            sz = sc.sizes.get(e.path)
            st = dict(bytes=sz[0], newest=sz[1]) if sz else du(e.path)
            b, newest = st["bytes"], st["newest"]
            kind = "folder"
            dirnames.add(e.name.lower())
        else:
            b, newest, kind = alloc(s), s.st_mtime, R.ext_kind(e.name)
        kinds[kind] = kinds.get(kind, 0) + b
        secret = bool(SECRET_RE.search(e.name))
        secrets += secret
        claimed = isdir and any(
            lb == e.path or lb.startswith(e.path + "/") for lb in libs
        )
        row = dict(
            name=e.name,
            path=e.path,
            dir=isdir,
            bytes=b,
            mtime=int(s.st_mtime),
            newest=int(newest),
            kind=kind,
            secret=secret,
            claimed=claimed,
            id="",
        )
        if b >= (1 << 20) and not secret and not claimed:
            age = sc.age_days(s.st_mtime) or 0
            row["id"] = sc.add(
                "downloads",
                "download",
                e.path,
                title=e.name,
                sub="downloaded %d days ago" % age,
                paths=[e.path],
                bytes=b,
                mtime=int(s.st_mtime),
                tier="data",
                method="trash",
                why="Something you downloaded."
                + (
                    " Installers and packages can usually be downloaded again."
                    if kind in ("installer", "diskimage")
                    else ""
                ),
            )
        rows.append(row)
    rows.sort(key=lambda r: -r["bytes"])
    # archives that were already unpacked next to them
    arch = []
    for r in rows:
        if r["kind"] != "archive" or r["dir"]:
            continue
        stem = re.sub(r"(\.tar)?\.[a-z0-9]+$", "", r["name"].lower())
        if stem in dirnames:
            arch.append(
                dict(
                    name=r["name"],
                    path=r["path"],
                    bytes=r["bytes"],
                    id=r["id"],
                    unpacked=os.path.join(root, stem),
                )
            )
    dups = []
    for g in find_dups(sc):
        keep, rest = g["paths"][0], g["paths"][1:]
        ids = [
            sc.add(
                "downloads",
                "duplicate",
                p,
                title=os.path.basename(p),
                sub="same content as " + tilde(keep),
                paths=[p],
                bytes=g["size"],
                tier="data",
                method="trash",
                verify_same=keep,
                why="Same size and matching samples as %s; compared byte for byte before it is removed."
                % tilde(keep),
            )
            for p in rest
        ]
        dups.append(dict(size=g["size"], keep=keep, extra=rest, ids=ids))
    total = sum(r["bytes"] for r in rows)
    ages = dict(month=0, year=0, older=0)
    for r in rows:
        a = sc.age_days(r["mtime"]) or 0
        ages["month" if a < 30 else "year" if a < 365 else "older"] += r["bytes"]
    return dict(
        root=root,
        bytes=total,
        count=len(rows),
        rows=rows[:400],
        secrets=secrets,
        ages=ages,
        kinds=sorted(([k, v] for k, v in kinds.items()), key=lambda x: -x[1]),
        archives=arch,
        dups=dups[:60],
        dup_bytes=sum(d["size"] * len(d["extra"]) for d in dups),
    )


# ---- binaries ----------------------------------------------------------------------
def scan_bins(sc):
    groups = []
    owned = None
    if have("pacman"):
        rc, out = run(["pacman", "-Qlq"], timeout=60)
        if rc == 0:
            owned = set(ln.rstrip("/") for ln in out.splitlines())
    sysbins = set()
    for d in ("/usr/bin", "/usr/local/bin"):
        try:
            sysbins |= set(os.listdir(d))
        except OSError:
            pass
    for d in R.BIN_DIRS:
        p = os.path.realpath(expand(d))
        try:
            ents = list(os.scandir(p))
        except OSError:
            continue
        system = not p.startswith(sc.home)
        rows = []
        for e in ents:
            try:
                s = e.stat(follow_symlinks=False)
            except OSError:
                continue
            isdir = stat.S_ISDIR(s.st_mode)
            if stat.S_ISLNK(s.st_mode):
                continue
            if system and owned is not None and e.path in owned:
                continue
            if isdir:
                sz = sc.sizes.get(e.path)
                st = dict(bytes=sz[0], newest=sz[1]) if sz else du(e.path)
            else:
                st = dict(bytes=alloc(s), newest=s.st_mtime)
            if st["bytes"] < (1 << 20):
                continue
            base = re.sub(r"[-_.]?v?\d.*$", "", e.name).lower()
            shadow = (not system) and (e.name in sysbins or (base and base in sysbins))
            row = dict(
                name=e.name,
                path=e.path,
                dir=isdir,
                bytes=st["bytes"],
                mtime=int(st["newest"] or s.st_mtime),
                shadow=shadow,
                appimage=e.name.lower().endswith(".appimage"),
                id="",
            )
            if not system:
                row["id"] = sc.add(
                    "bins",
                    "binary",
                    e.path,
                    title=e.name,
                    sub=tilde(p),
                    paths=[e.path],
                    bytes=st["bytes"],
                    mtime=row["mtime"],
                    tier="data",
                    method="trash",
                    why="A program you installed by hand."
                    + (
                        " The system also has a command with this name from a package."
                        if shadow
                        else ""
                    ),
                )
            rows.append(row)
        if rows:
            rows.sort(key=lambda r: -r["bytes"])
            groups.append(
                dict(
                    path=p,
                    system=system,
                    bytes=sum(r["bytes"] for r in rows),
                    rows=rows[:80],
                    repo=os.path.lexists(os.path.join(p, ".git")),
                    note="not owned by any package" if system else "",
                )
            )
    return dict(groups=groups, bytes=sum(g["bytes"] for g in groups if not g["system"]))


# ---- system rollup -----------------------------------------------------------------
def scan_system(sc):
    rows = []
    paths = [
        "/usr/lib",
        "/usr/share",
        "/usr/bin",
        "/usr/include",
        "/usr/local",
        "/usr/lib32",
        "/opt",
        "/var/cache",
        "/var/log",
        "/var/lib",
        "/var/tmp",
        "/srv",
        "/root",
    ]
    todo = []
    for p in paths:
        if not os.path.isdir(p) or os.path.islink(p):
            continue
        todo.append(p)

    def one(p):
        if p == "/var/lib":
            # docker's overlay mounts and data root are counted by the docker section
            tot = dict(bytes=0, newest=0, denied=0)
            try:
                for e in os.scandir(p):
                    if e.is_dir(follow_symlinks=False) and e.name not in (
                        "docker",
                        "containerd",
                    ):
                        st = du(e.path)
                        tot["bytes"] += st["bytes"]
                        tot["denied"] += st["denied"]
            except OSError:
                pass
            return tot
        return du(p)

    with ThreadPoolExecutor(4) as ex:
        for p, st in zip(todo, ex.map(one, todo)):
            rows.append(dict(path=p, bytes=st["bytes"], denied=st.get("denied", 0)))
    rows.sort(key=lambda r: -r["bytes"])
    kernels = []
    mod = "/usr/lib/modules"
    running = os.uname().release
    try:
        for e in os.scandir(mod):
            if e.is_dir(follow_symlinks=False):
                owned = True
                if have("pacman"):
                    owned = run(["pacman", "-Qqo", e.path])[0] == 0
                kernels.append(
                    dict(
                        name=e.name,
                        running=e.name == running,
                        owned=owned,
                        bytes=du(e.path)["bytes"],
                    )
                )
    except OSError:
        pass
    return dict(
        rows=rows,
        bytes=sum(r["bytes"] for r in rows),
        kernels=kernels,
        denied=sum(1 for r in rows if r["denied"]),
    )


# ---- Files browser -------------------------------------------------------------------
def mode_string(m):
    return stat.filemode(m)


def list_dir(path, sizes=None, budget=6.0):
    """A dired-style listing with real sizes. Directory sizes come from the last
    scan when it knows them, otherwise they are measured now (within `budget`
    seconds; what did not fit is marked partial)."""
    sizes = sizes or {}
    path = os.path.realpath(path)
    rows = []
    try:
        ents = list(os.scandir(path))
    except OSError as e:
        return dict(
            path=path, error=str(e.strerror or e), rows=[], parent=os.path.dirname(path)
        )
    names = {e.name for e in ents}
    deadline = time.time() + budget
    todo = []
    for e in ents:
        try:
            s = e.stat(follow_symlinks=False)
        except OSError:
            continue
        isdir = stat.S_ISDIR(s.st_mode)
        row = dict(
            name=e.name,
            path=e.path,
            dir=isdir,
            link="",
            mode=mode_string(s.st_mode),
            bytes=alloc(s),
            mtime=int(s.st_mtime),
            kind="",
            partial=False,
            cached=False,
        )
        if stat.S_ISLNK(s.st_mode):
            try:
                row["link"] = os.readlink(e.path)
            except OSError:
                pass
            row["kind"] = "link"
        elif isdir:
            row["kind"] = classify_dir(e.name, names, e.path) or (
                "git" if e.name == ".git" else "dir"
            )
            if e.path in sizes:
                row["bytes"], row["cached"] = sizes[e.path][0], True
            else:
                todo.append(row)
        else:
            row["kind"] = R.ext_kind(e.name)
        rows.append(row)

    def one(row):
        if time.time() > deadline:
            row["partial"] = True
            return
        row["bytes"] = du(row["path"])["bytes"]

    if todo:
        with ThreadPoolExecutor(6) as ex:
            list(ex.map(one, todo))
    rows.sort(key=lambda r: -r["bytes"])
    return dict(
        path=path,
        parent=os.path.dirname(path) if path != "/" else "",
        rows=rows,
        bytes=sum(r["bytes"] for r in rows),
        error="",
    )
