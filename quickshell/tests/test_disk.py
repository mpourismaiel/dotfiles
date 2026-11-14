#!/usr/bin/env python3
"""Offline tests for the pill's Disk manager (diskbridge.py + diskscan.py + diskrules.py).

Everything happens inside one throwaway directory made by tempfile: a fake $HOME
with fake projects, caches, thumbnails and downloads. The bridge runs as a
subprocess with HOME pointing there, so its cache, its state, its guard and the
Trash all live in the fake home. Nothing outside that directory is read for
removal or touched. Run:  python3 quickshell/tests/test_disk.py
"""

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PILL = os.path.join(HERE, "..", "pill")
BRIDGE = os.path.join(PILL, "diskbridge.py")
sys.dont_write_bytecode = True
sys.path.insert(0, PILL)
import diskbridge as db  # noqa: E402
import diskrules as R  # noqa: E402
import diskscan as S  # noqa: E402

FAILS = []


def check(name, cond, extra=""):
    print(
        ("ok   " if cond else "FAIL ")
        + name
        + ((" — " + str(extra)) if extra and not cond else "")
    )
    if not cond:
        FAILS.append(name)


def write(path, data=b"x", size=0):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data if not size else os.urandom(size))


def git(cwd, *args):
    env = dict(
        os.environ,
        GIT_AUTHOR_NAME="t",
        GIT_AUTHOR_EMAIL="t@t",
        GIT_COMMITTER_NAME="t",
        GIT_COMMITTER_EMAIL="t@t",
        GIT_CONFIG_GLOBAL="/dev/null",
        GIT_CONFIG_SYSTEM="/dev/null",
    )
    return subprocess.run(
        ["git", "-C", cwd, "-c", "init.defaultBranch=main"] + list(args),
        env=env,
        capture_output=True,
        text=True,
    )


def bridge(home, *args, config=None):
    env = {
        k: v for k, v in os.environ.items() if not k.startswith("XDG_") and k != "DEMO"
    }
    env["HOME"] = home
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    cmd = [sys.executable, BRIDGE]
    if config is not None:
        cmd += ["--config", json.dumps(config)]
    r = subprocess.run(
        cmd + list(args), env=env, capture_output=True, text=True, timeout=120
    )
    out = []
    for ln in r.stdout.splitlines():
        try:
            out.append(json.loads(ln))
        except ValueError:
            pass
    return out


def event(events, name):
    return next((e for e in events if e.get("event") == name), None)


def png(path, uri, mtime, compressed=False):
    def chunk(typ, data):
        return (
            struct.pack(">I", len(data))
            + typ
            + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        )

    def text(key, val):
        if compressed:
            return chunk(b"zTXt", key + b"\0\0" + zlib.compress(val))
        return chunk(b"tEXt", key + b"\0" + val)

    body = S.PNG_SIG + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
    body += text(b"Thumb::URI", uri.encode()) + text(
        b"Thumb::MTime", str(int(mtime)).encode()
    )
    body += chunk(b"IDAT", zlib.compress(b"\0\0")) + chunk(b"IEND", b"")
    write(path, body)


def make_home(tmp):
    home = os.path.join(tmp, "home")
    proj = os.path.join(home, "Documents", "projects")
    # alpha: clean, pushed, lockfile → deps "cost", dist "free"
    a = os.path.join(proj, "work", "alpha")
    write(os.path.join(a, "package.json"), b"{}")
    write(os.path.join(a, "package-lock.json"), b"{}")
    write(os.path.join(a, "src", "index.js"), b"x")
    write(os.path.join(a, ".gitignore"), b"node_modules\ndist\n")
    git(a, "init")
    git(a, "add", "-A")
    git(a, "commit", "-m", "one")
    remote = os.path.join(tmp, "alpha.git")
    subprocess.run(["git", "clone", "--bare", a, remote], capture_output=True)
    git(a, "remote", "add", "origin", remote)
    git(a, "fetch", "origin")
    write(os.path.join(a, "node_modules", "lib", "big.js"), size=600_000)
    write(os.path.join(a, "dist", "bundle.js"), size=400_000)
    # beta: no lockfile, dirty, no remote → deps "state", project matters
    b = os.path.join(proj, "work", "beta")
    write(os.path.join(b, "package.json"), b"{}")
    write(os.path.join(b, "main.js"), b"x")
    git(b, "init")
    git(b, "add", "-A")
    git(b, "commit", "-m", "one")
    write(os.path.join(b, "todo.txt"), b"unsaved")
    write(os.path.join(b, "node_modules", "dep", "x.js"), size=500_000)
    # gamma: a tracked "build" directory is source, not output
    g = os.path.join(proj, "gamma")
    write(os.path.join(g, "package.json"), b"{}")
    write(os.path.join(g, "build", "script.sh"), size=300_000)
    git(g, "init")
    git(g, "add", "-A")
    git(g, "commit", "-m", "one")
    # delta: not a project by its names — `build` without any manifest
    write(os.path.join(proj, "notes", "build", "plan.txt"), size=300_000)
    # caches
    write(os.path.join(home, ".cache", "pip", "wheels", "w.whl"), size=1_500_000)
    write(os.path.join(home, ".cache", "mystery", "blob"), size=40_000_000)
    old = time.time() - 400 * 86400
    os.utime(os.path.join(home, ".cache", "mystery", "blob"), (old, old))
    # downloads
    write(os.path.join(home, "Downloads", "old.iso"), size=2_000_000)
    write(os.path.join(home, "Downloads", "backup-codes.txt"), size=1_100_000)
    # thumbnails: one orphan (source gone), one valid, one stale, one for an unplugged drive
    th = os.path.join(home, ".cache", "thumbnails", "normal")
    pic = os.path.join(home, "Pictures", "a.jpg")
    write(pic, b"jpg")
    png(
        os.path.join(th, "orphan.png"),
        "file://" + os.path.join(home, "Pictures", "gone%20file.jpg"),
        1,
        compressed=True,
    )
    png(os.path.join(th, "valid.png"), "file://" + pic, os.stat(pic).st_mtime)
    png(os.path.join(th, "stale.png"), "file://" + pic, 5)
    png(os.path.join(th, "away.png"), "file:///run/media/nobody/USBSTICK/x.jpg", 1)
    return home, proj, a, b, g


def test_rules(tmp):
    d = os.path.join(tmp, "rules")
    os.makedirs(os.path.join(d, "node_modules"))
    os.makedirs(os.path.join(d, "build"))
    os.makedirs(os.path.join(d, "venv"))
    os.makedirs(os.path.join(d, ".gradle"))
    os.makedirs(os.path.join(d, "target"))
    check(
        "node_modules is deps by name",
        S.classify_dir("node_modules", set(), os.path.join(d, "node_modules"))
        == "deps",
    )
    check(
        "build without a manifest is not build output",
        S.classify_dir("build", {"build", "README"}, os.path.join(d, "build")) is None,
    )
    check(
        "build next to package.json is build output",
        S.classify_dir("build", {"build", "package.json"}, os.path.join(d, "build"))
        == "build",
    )
    check(
        "venv without pyvenv.cfg is not deps",
        S.classify_dir("venv", set(), os.path.join(d, "venv")) is None,
    )
    write(os.path.join(d, "venv", "pyvenv.cfg"), b"x")
    check(
        "venv with pyvenv.cfg is deps",
        S.classify_dir("venv", set(), os.path.join(d, "venv")) == "deps",
    )
    check(
        "~/.gradle (no gradle project beside it) is not deps",
        S.classify_dir(".gradle", {".config"}, os.path.join(d, ".gradle")) is None,
    )
    check(
        ".gradle in a gradle project is deps",
        S.classify_dir(".gradle", {"build.gradle.kts"}, os.path.join(d, ".gradle"))
        == "deps",
    )
    check(
        "target next to Cargo.toml is build output",
        S.classify_dir("target", {"Cargo.toml"}, os.path.join(d, "target")) == "build",
    )
    check(
        "tmp / logs / data are never guessed",
        all(
            S.classify_dir(n, {"package.json"}, d) is None
            for n in ("tmp", "logs", "data", "temp")
        ),
    )
    check(
        "ext kinds",
        R.ext_kind("a.MKV") == "video"
        and R.ext_kind("x.pkg.tar.zst") == "installer"
        and R.ext_kind("noext") == "other",
    )
    # a "build" folder full of media written over weeks is data, not build output
    c = dict(
        kind="build",
        lock="",
        bytes=300 << 20,
        newest=1000000 + 30 * 86400,
        oldest=1000000,
        kinds={"video": 290 << 20},
        stateful=[],
    )
    check(
        "media-heavy build dir is judged data",
        S.judge_candidate(c, dict(locks=[]))[0] == "data",
    )
    c = dict(
        kind="build",
        lock="",
        bytes=300 << 20,
        newest=1000100,
        oldest=1000000,
        kinds={"other": 300 << 20},
        stateful=[],
    )
    check(
        "ordinary build dir is free", S.judge_candidate(c, dict(locks=[]))[0] == "free"
    )
    c = dict(kind="deps", lock="", bytes=1, newest=1, oldest=1)
    check(
        "deps without a lockfile hold state",
        S.judge_candidate(c, dict(locks=[]))[0] == "state",
    )
    check(
        "deps with a lockfile cost a download",
        S.judge_candidate(dict(c, lock="uv.lock"), dict(locks=[]))[:3]
        == ("cost", "Dependencies pinned by uv.lock.", "uv sync"),
    )
    check(
        "parse_size",
        S.parse_size("17.81GB (18%)") == int(17.81e9)
        and S.parse_size("4 GiB") == 4 << 30
        and S.parse_size("512") == 512,
    )


def test_sizes(tmp):
    d = os.path.join(tmp, "sizes")
    write(os.path.join(d, "a"), size=200_000)
    os.link(os.path.join(d, "a"), os.path.join(d, "b"))
    with open(os.path.join(d, "sparse"), "wb") as f:
        f.truncate(50 << 20)
    st = S.du(d)
    check("a hardlinked file counts once", 190_000 < st["bytes"] < 260_000, st)
    check("hardlinked bytes are not reclaimable alone", st["reclaim"] < 60_000, st)
    check("a sparse file counts as what it occupies", st["bytes"] < (1 << 20), st)
    os.symlink("/", os.path.join(d, "rootlink"))
    check("symlinks are not followed", S.du(d)["bytes"] < (1 << 20))


def test_thumbs(home):
    th = os.path.join(home, ".cache", "thumbnails", "normal")

    def state(n):
        return S.thumb_state(*S.thumb_meta(os.path.join(th, n)))

    check(
        "zTXt-compressed URI is read",
        S.thumb_meta(os.path.join(th, "orphan.png"))[0].endswith("gone%20file.jpg"),
    )
    check("thumbnail of a vanished file is an orphan", state("orphan.png") == "orphan")
    check("thumbnail of an unchanged file is ok", state("valid.png") == "ok")
    check("thumbnail older than its file is stale", state("stale.png") == "stale")
    check("thumbnail for an unplugged drive is left alone", state("away.png") == "away")


def test_guard(home, a):
    old_home, old_state, old_cache = db.HOME, db.STATE, db.CACHE
    db.HOME = home
    try:
        nm = os.path.join(a, "node_modules")
        item = dict(kind="deps", method="rm")
        check("guard lets a real node_modules through", db.guard(nm, item) == "")
        check("guard refuses the home folder", db.guard(home, item) != "")
        check("guard refuses /", db.guard("/", item) != "")
        check(
            "guard refuses a parent of home",
            db.guard(os.path.dirname(home), item) != "",
        )
        check(
            "guard refuses a .git folder",
            "git" in db.guard(os.path.join(a, ".git"), dict(kind="file", method="rm")),
        )
        check(
            "guard refuses inside .git",
            db.guard(os.path.join(a, ".git", "objects"), dict(kind="file", method="rm"))
            != "",
        )
        check(
            "guard refuses ~/Documents",
            "protected"
            in db.guard(
                os.path.join(home, "Documents"), dict(kind="file", method="trash")
            ),
        )
        check(
            "guard refuses system paths",
            "outside" in db.guard("/usr/lib/python3", dict(kind="file", method="rm")),
        )
        check(
            "guard refuses relative / dotted paths",
            db.guard(nm + "/../src", item) != ""
            and db.guard("node_modules", item) != "",
        )
        check(
            "guard refuses a source dir posing as deps",
            db.guard(os.path.join(a, "src"), item) != "",
        )
        link = os.path.join(home, "linkdir")
        os.symlink(a, link)
        check(
            "guard refuses paths reached through a symlink",
            "symlink" in db.guard(os.path.join(link, "node_modules"), item),
        )
        os.unlink(link)
        check(
            "guard reports gone",
            db.guard(os.path.join(a, "nope"), dict(kind="file", method="rm")) == "gone",
        )
    finally:
        db.HOME, db.STATE, db.CACHE = old_home, old_state, old_cache


def test_flow(home, proj, a, b, g):
    cfg = dict(projectDirs=[proj], staleDays=180)
    ev = bridge(
        home, "scan", "--only", "projects,caches,thumbnails,downloads,home", config=cfg
    )
    done = event(ev, "done")
    check("scan finishes", bool(done))
    snap = event(bridge(home, "snapshot"), "snapshot")
    check(
        "snapshot returns the cached scan",
        bool(snap) and "projects" in snap["scan"]["sections"],
    )
    scan = snap["scan"]
    items = scan["items"]
    rows = {r["name"]: r for r in scan["sections"]["projects"]["projects"]}
    check(
        "three projects found, the manifest-less folder is not one",
        set(rows) == {"alpha", "beta", "gamma"},
        set(rows),
    )

    def find(pred):
        return next((i for i in items.values() if pred(i)), None)

    a_nm = find(lambda i: i["paths"] == [os.path.join(a, "node_modules")])
    a_dist = find(lambda i: i["paths"] == [os.path.join(a, "dist")])
    b_nm = find(lambda i: i["paths"] == [os.path.join(b, "node_modules")])
    check(
        "alpha node_modules: cost tier, npm ci",
        bool(a_nm) and a_nm["tier"] == "cost" and a_nm["restore"] == "npm ci",
        a_nm,
    )
    check("alpha dist: free tier", bool(a_dist) and a_dist["tier"] == "free", a_dist)
    check(
        "beta node_modules without a lockfile: state tier with a warning",
        bool(b_nm) and b_nm["tier"] == "state" and b_nm["warn"],
        b_nm,
    )
    check(
        "tracked build dir is not offered",
        not find(lambda i: i["paths"] == [os.path.join(g, "build")]),
    )
    check(
        "alpha is clean and pushed",
        rows["alpha"]["keep"] == [] and rows["alpha"]["remote"] != "",
        rows["alpha"]["keep"],
    )
    check(
        "beta shows why it matters",
        any("uncommitted" in k for k in rows["beta"]["keep"])
        and any("no remote" in k for k in rows["beta"]["keep"]),
        rows["beta"]["keep"],
    )
    check(
        "active projects are never suggested",
        not a_nm["offer"] and rows["alpha"]["status"] == "active",
    )
    check(
        "alpha bytes split into deps and build",
        rows["alpha"]["deps"] > 500_000 and rows["alpha"]["build"] > 300_000,
    )
    caches = scan["sections"]["caches"]
    check(
        "pip cache recognised",
        any(r["key"] == "pip" for r in caches["known"]),
        [r["key"] for r in caches["known"]],
    )
    check(
        "unknown old cache dir listed as stale",
        any(r["label"] == "mystery" and r["stale"] for r in caches["other"]),
    )
    dl = scan["sections"]["downloads"]
    iso = next(r for r in dl["rows"] if r["name"] == "old.iso")
    codes = next(r for r in dl["rows"] if r["name"] == "backup-codes.txt")
    check(
        "a download is a data-tier trash item",
        items[iso["id"]]["tier"] == "data" and items[iso["id"]]["method"] == "trash",
    )
    check(
        "credential-looking files are never offered",
        codes["secret"] and codes["id"] == "",
    )
    th = scan["sections"]["thumbnails"]
    check(
        "thumbnail states counted",
        th["state"]["orphan"]["count"] == 1
        and th["state"]["stale"]["count"] == 1
        and th["state"]["ok"]["count"] == 1
        and th["state"]["away"]["count"] == 1,
        th["state"],
    )
    dead = items[th["ids"]["dead"]]

    # ---- verify + apply ----
    v = event(
        bridge(
            home, "verify", a_nm["id"], a_dist["id"], dead["id"], iso["id"], "bogus"
        ),
        "verified",
    )
    check(
        "verify answers with a token and a script",
        bool(v) and len(v["token"]) == 24 and "node_modules" in v["script"],
    )
    check("verify reports unknown ids", v["missing"] == ["bogus"])
    check(
        "verify re-measures",
        all(i["status"] == "ok" and i["bytes_now"] > 0 for i in v["items"]),
        [(i["title"], i["status"], i["reason"]) for i in v["items"]],
    )
    check(
        "script trashes your files, never unlinks them",
        "gio trash -- " in v["script"]
        and "old.iso" in v["script"].split("gio trash")[1],
    )

    r = event(
        bridge(home, "apply", "0" * 24, "--ack", "free,cost,state,data"), "applied"
    )
    check("apply refuses an unknown token", r and not r["ok"])
    r = event(bridge(home, "apply", v["token"], "--ack", "free,cost"), "applied")
    check(
        "apply refuses when a tier is not acknowledged",
        r and not r["ok"] and "data" in r["error"],
        r,
    )
    check(
        "nothing was removed by the refused runs",
        os.path.isdir(a_nm["paths"][0]) and os.path.exists(iso["path"]),
    )

    # the world changes between review and removal: the valid thumbnail's source
    # vanishes (irrelevant), the orphan's source comes back (must be kept)
    write(os.path.join(home, "Pictures", "gone file.jpg"), b"back")
    os.utime(os.path.join(home, "Pictures", "gone file.jpg"), (1, 1))  # same mtime the thumbnail recorded
    r = event(bridge(home, "apply", v["token"], "--ack", "free,cost,data"), "applied")
    check("apply runs once everything is acknowledged", r and r["ok"], r)
    res = {x["title"]: x for x in r["results"]} if r and r.get("ok") else {}
    check(
        "node_modules removed",
        not os.path.exists(a_nm["paths"][0])
        and res.get(a_nm["title"], {}).get("status") == "removed",
        res.get(a_nm["title"]),
    )
    check("dist removed", not os.path.exists(a_dist["paths"][0]))
    check(
        "the project's source is untouched",
        os.path.exists(os.path.join(a, "src", "index.js"))
        and os.path.isdir(os.path.join(a, ".git")),
    )
    tdir = os.path.join(home, ".cache", "thumbnails", "normal")
    check(
        "stale thumbnail removed", not os.path.exists(os.path.join(tdir, "stale.png"))
    )
    check(
        "orphan whose source came back is kept",
        os.path.exists(os.path.join(tdir, "orphan.png")),
    )
    check(
        "valid and unplugged-drive thumbnails are kept",
        os.path.exists(os.path.join(tdir, "valid.png"))
        and os.path.exists(os.path.join(tdir, "away.png")),
    )
    iso_res = res.get("old.iso", {})
    if iso_res.get("status") == "trashed":
        check(
            "the download went to the Trash, not into the void",
            not os.path.exists(iso["path"])
            and os.path.exists(
                os.path.join(home, ".local", "share", "Trash", "files", "old.iso")
            ),
        )
    else:
        check(
            "when the Trash is unavailable the file is left alone",
            os.path.exists(iso["path"]) and iso_res.get("status") == "failed",
            iso_res,
        )
    check(
        "a report is written",
        bool(r.get("report"))
        and os.path.exists(r["report"])
        and "node_modules" in open(r["report"]).read(),
    )
    check(
        "the token is single-use",
        not event(
            bridge(home, "apply", v["token"], "--ack", "free,cost,data"), "applied"
        )["ok"],
    )
    reps = event(bridge(home, "reports"), "reports")
    check(
        "reports lists the run",
        reps and len(reps["reports"]) == 1 and reps["reports"][0]["done"] >= 3,
        reps,
    )

    # ---- a planned folder that stops being what it was is skipped ----
    v = event(bridge(home, "verify", b_nm["id"]), "verified")
    shutil.move(b_nm["paths"][0], b_nm["paths"][0] + ".real")
    os.makedirs(os.path.join(b, "elsewhere"))
    os.symlink(os.path.join(b, "elsewhere"), b_nm["paths"][0])
    r = event(bridge(home, "apply", v["token"], "--ack", "state"), "applied")
    check(
        "a path that became a symlink is skipped",
        r["ok"]
        and r["results"][0]["status"] == "skipped"
        and os.path.isdir(os.path.join(b, "elsewhere")),
        r["results"],
    )

    # ---- Files: ad-hoc items ----
    it = event(
        bridge(
            home,
            "item",
            b,
            os.path.join(home, "Downloads", "backup-codes.txt"),
            os.path.join(home, ".cache", "mystery"),
        ),
        "items",
    )["items"]
    byt = {i["title"]: i for i in it}
    check(
        "a dirty repo flagged in Files carries its warnings",
        byt["beta"]["tier"] == "data" and len(byt["beta"]["warn"]) >= 2,
        byt["beta"]["warn"],
    )
    check(
        "a key-looking file is warned about",
        any("key" in w for w in byt["backup-codes.txt"]["warn"]),
    )
    check(
        "something under ~/.cache is free",
        byt["mystery"]["tier"] == "free" and byt["mystery"]["method"] == "rm",
    )
    ls = event(bridge(home, "ls", a), "ls")
    check(
        "ls lists with kinds",
        {r["name"]: r["kind"] for r in ls["rows"]}.get(".git") == "git"
        and ls["parent"] == os.path.dirname(a),
    )
    v = event(bridge(home, "verify", os.path.basename(home)), "verified")
    check("verify of nothing known yields nothing to apply", v["items"] == [])


def main():
    tmp = tempfile.mkdtemp(prefix="pill-disk-test-")
    try:
        test_rules(tmp)
        test_sizes(tmp)
        home, proj, a, b, g = make_home(tmp)
        test_thumbs(home)
        test_guard(home, a)
        test_flow(home, proj, a, b, g)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)  # only ever the directory made above
    print("\n%s — %d failed" % ("FAIL" if FAILS else "PASS", len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
