#!/usr/bin/env python3
"""Write pill/diskdemo.json — an invented but realistic disk scan.

Used by the pill's DEMO mode (`DEMO=true` → `diskbridge.py snapshot` answers with
it, so a screen recording never shows a real disk) and by the screenshot harness.
Everything is made up; the shapes come from the real scanner (diskscan.Scan.add,
diskbridge.overview) so they cannot drift. Re-run after changing a section's
shape:  python3 quickshell/tests/make_diskdemo.py
"""

import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PILL = os.path.join(HERE, "..", "pill")
sys.dont_write_bytecode = True
sys.path.insert(0, PILL)
import diskbridge as db  # noqa: E402
import diskscan as S  # noqa: E402

G, M = 1 << 30, 1 << 20
H = "/home/you"
NOW = int(time.time())
DAY = 86400


def ago(days):
    return NOW - int(days * DAY)


def main():
    sc = S.Scan({"home": H})
    sc.home = H
    P = H + "/Documents/projects"
    # ---- projects ----
    spec = [
        # rel, eco, src, deps, build, git, days, dirty, unpushed, stash, remote, lock
        (
            "work/atlas-web",
            ["node"],
            0.5,
            6.7,
            2.0,
            0.4,
            740,
            0,
            0,
            0,
            "git@github.com:acme/atlas-web.git",
            "pnpm-lock.yaml",
        ),
        (
            "work/mux-api",
            ["node"],
            0.4,
            4.1,
            0.6,
            0.3,
            430,
            0,
            0,
            0,
            "git@github.com:acme/mux-api.git",
            "package-lock.json",
        ),
        (
            "play/ledgerd",
            ["rust"],
            0.2,
            0.0,
            6.7,
            0.2,
            95,
            0,
            0,
            0,
            "git@github.com:you/ledgerd.git",
            "Cargo.lock",
        ),
        (
            "play/habit-android",
            ["gradle"],
            0.4,
            1.7,
            2.1,
            0.2,
            62,
            4,
            0,
            1,
            "git@github.com:you/habit-android.git",
            "",
        ),
        ("old/thesis-sim", ["python"], 1.5, 2.4, 0.0, 0.0, 1500, 0, 0, 0, "", ""),
        (
            "play/dotfiles",
            [],
            0.4,
            0.0,
            0.0,
            0.2,
            0.2,
            2,
            0,
            0,
            "git@github.com:you/dotfiles.git",
            "",
        ),
        (
            "old/portfolio-v2",
            ["node"],
            0.1,
            1.3,
            0.9,
            0.1,
            990,
            0,
            3,
            0,
            "git@github.com:you/portfolio.git",
            "yarn.lock",
        ),
        (
            "work/billing",
            ["python"],
            0.3,
            1.1,
            0.0,
            0.2,
            300,
            0,
            0,
            0,
            "git@github.com:acme/billing.git",
            "uv.lock",
        ),
    ]
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
        loose=120 * M,
    )
    for (
        rel,
        eco,
        src,
        deps,
        build,
        gitb,
        days,
        dirty,
        unpushed,
        stash,
        remote,
        lock,
    ) in spec:
        path = P + "/" + rel
        nogit = rel == "old/thesis-sim"
        status = (
            "active"
            if days < 30
            else "recent"
            if days < 180
            else "stale"
            if days < 730
            else "dormant"
        )
        keep = []
        if nogit:
            keep.append("not in git — this folder is the only copy")
        if dirty:
            keep.append("%d uncommitted files" % dirty)
        if unpushed:
            keep.append("%d unpushed commits" % unpushed)
        if stash:
            keep.append("1 stash")
        ids, recl, flagged = [], 0, 0
        dep_name = {
            "node": "node_modules",
            "python": ".venv",
            "gradle": ".gradle",
            "rust": "",
        }.get(eco[0] if eco else "", "")
        bld_name = {
            "node": "dist" if "portfolio" in rel else ".next",
            "rust": "target",
            "gradle": "app/build",
        }.get(eco[0] if eco else "", "")
        if deps and dep_name:
            c = dict(
                kind="deps",
                lock=lock,
                bytes=int(deps * G),
                newest=ago(days),
                oldest=ago(days + 2),
            )
            tier, why, restore, warn = S.judge_candidate(
                c, dict(locks=[lock] if lock else [])
            )
            ids.append(
                sc.add(
                    "projects",
                    "deps",
                    path + "/" + dep_name,
                    title=dep_name,
                    sub=rel,
                    paths=[path + "/" + dep_name],
                    bytes=int(deps * G),
                    mtime=ago(days),
                    tier=tier,
                    why=why,
                    restore=restore,
                    warn=warn,
                    method="rm",
                    project=path,
                    offer=tier in ("free", "cost") and status != "active",
                )
            )
            recl += int(deps * G) if tier in ("free", "cost") else 0
            flagged += tier not in ("free", "cost")
        if build and bld_name:
            ids.append(
                sc.add(
                    "projects",
                    "build",
                    path + "/" + bld_name,
                    title=bld_name,
                    sub=rel,
                    paths=[path + "/" + bld_name],
                    bytes=int(build * G),
                    mtime=ago(days),
                    tier="free",
                    why="Build output; the project's build writes it again.",
                    method="rm",
                    project=path,
                    offer=status != "active",
                )
            )
            recl += int(build * G)
        whole = ""
        if status != "active":
            w = [k.capitalize() + "." for k in keep]
            clean = not w and remote
            whole = sc.add(
                "projects",
                "project",
                path,
                title="Whole project",
                sub=rel,
                paths=[path],
                bytes=int((src + deps + build + gitb) * G),
                mtime=ago(days),
                tier="cost" if clean else "data",
                why=("Clean and fully pushed to %s." % remote)
                if clean
                else "The project folder itself.",
                restore=("git clone " + remote) if remote else "",
                warn=w,
                method="trash",
                project=path,
            )
        if status == "active":
            verdict, tone = "active · leave", "leave"
        elif not recl and not flagged:
            verdict, tone = "nothing to reclaim", "none"
        elif flagged and not recl:
            verdict, tone = "look before removing", "stop"
        elif flagged:
            verdict, tone = "deps can go · some output needs a look", "warn"
        else:
            verdict, tone = "deps and build output can go", "safe"
        b = int((src + deps + build + gitb) * G)
        rows.append(
            dict(
                path=path,
                name=os.path.basename(rel),
                rel=rel,
                root=P,
                eco=eco,
                bytes=b,
                deps=int(deps * G),
                build=int(build * G),
                git=int(gitb * G),
                src=int(src * G),
                reclaim=recl,
                last=ago(days),
                commit=ago(days),
                status=status,
                dirty=dirty,
                unpushed=unpushed,
                stash=stash,
                remote=remote,
                nogit=nogit,
                worktree_of="",
                branch="main",
                docker="api" in rel,
                keep=keep,
                verdict=verdict,
                tone=tone,
                items=ids,
                whole=whole,
                tracked_skips=0,
            )
        )
        tot["count"] += 1
        tot["bytes"] += b
        tot["deps"] += int(deps * G)
        tot["build"] += int(build * G)
        tot["git"] += int(gitb * G)
        tot["src"] += int(src * G)
        tot["reclaim"] += recl
        if status in ("stale", "dormant"):
            tot["stale"] += 1
            tot["stale_reclaim"] += recl
    rows.sort(key=lambda r: -r["reclaim"])
    sec = {
        "projects": dict(roots=[P], totals=tot, projects=rows, staleDays=180, took=14.2)
    }

    # ---- caches ----
    known, other = [], []
    for key, label, path, gb, days, tier, note, argv in [
        (
            "go-build",
            "Go build cache",
            "~/.cache/go-build",
            18.2,
            3,
            "free",
            "Rebuilt on the next go build; costs CPU only.",
            ["go", "clean", "-cache"],
        ),
        (
            "npm",
            "npm cache",
            "~/.npm/_cacache",
            9.4,
            1,
            "cost",
            "Packages download again on the next install.",
            ["npm", "cache", "clean", "--force"],
        ),
        (
            "uv",
            "uv cache",
            "~/.cache/uv",
            6.1,
            0.5,
            "cost",
            "Prune drops unused entries; venvs hardlink into this cache.",
            ["uv", "cache", "prune"],
        ),
        (
            "cargo-registry",
            "Cargo registry",
            "~/.cargo/registry",
            5.0,
            40,
            "cost",
            "Crates download again on the next build.",
            None,
        ),
        (
            "firefox",
            "Firefox cache",
            "~/.cache/mozilla",
            1.9,
            0.1,
            "free",
            "Close Firefox first. Pages load from the network again.",
            None,
        ),
    ]:
        b = int(gb * G)
        recl = int(b * 0.35) if key == "uv" else b
        iid = sc.add(
            "caches",
            "cache",
            key,
            title=label,
            sub=path,
            paths=[H + path[1:]],
            bytes=b,
            reclaim=recl,
            mtime=ago(days),
            tier=tier,
            why=note,
            method="cmd" if argv else "contents",
            argv=argv,
            offer=tier == "free",
            warn=[
                "Only part of this frees up: the rest is hardlinked into project folders."
            ]
            if key == "uv"
            else [],
        )
        known.append(
            dict(
                id=iid,
                key=key,
                label=label,
                path=H + path[1:],
                bytes=b,
                reclaim=recl,
                newest=ago(days),
                tier=tier,
                note=note,
                heavy=False,
            )
        )
    iid = sc.add(
        "caches",
        "cache",
        "other-hypr",
        title="old-rice-installer",
        sub="~/.cache/old-rice-installer",
        paths=[H + "/.cache/old-rice-installer"],
        bytes=int(2.8 * G),
        mtime=ago(520),
        tier="free",
        method="contents",
        why="In the cache folder, so its owner is expected to cope with it vanishing. I do not know this one specifically.",
    )
    other.append(
        dict(
            id=iid,
            key="other:old-rice-installer",
            label="old-rice-installer",
            path=H + "/.cache/old-rice-installer",
            bytes=int(2.8 * G),
            reclaim=int(2.8 * G),
            newest=ago(520),
            tier="free",
            stale=True,
            note="Unrecognised cache folder, untouched for 520 days.",
            heavy=False,
        )
    )
    tools = [
        dict(
            key="android-sdk",
            label="Android SDK",
            path=H + "/Android/Sdk",
            bytes=int(8.4 * G),
            newest=ago(60),
            note="Platforms and build-tools; manage with sdkmanager.",
        ),
        dict(
            key="ollama",
            label="Ollama models",
            path=H + "/.ollama",
            bytes=int(11.6 * G),
            newest=ago(12),
            note="Remove single models with `ollama rm <name>`.",
        ),
    ]
    sec["caches"] = dict(
        known=known,
        other=other,
        tools=tools,
        bytes=sum(r["bytes"] for r in known + other),
        reclaim=sum(r["reclaim"] for r in known + other),
        took=8.1,
    )

    # ---- packages ----
    pk = []
    i1 = sc.add(
        "packages",
        "pkgcache",
        "pacman-keep2",
        title="Package cache: keep the 2 newest versions of each package",
        sub="/var/cache/pacman/pkg/",
        bytes=int(11.2 * G),
        tier="cost",
        method="terminal",
        cmd="sudo paccache -rk2",
        warn=["Needs administrator rights."],
        offer=True,
        why="Old versions are only needed to downgrade; they download again on demand.",
    )
    i2 = sc.add(
        "packages",
        "pkgcache",
        "pacman-keep1",
        title="Package cache: keep only the newest version",
        sub="/var/cache/pacman/pkg/",
        bytes=int(14.9 * G),
        tier="cost",
        method="terminal",
        cmd="sudo paccache -rk1",
        warn=["Needs administrator rights."],
        why="Old versions are only needed to downgrade; they download again on demand.",
    )
    pk.append(
        dict(
            key="pacman",
            title="Pacman package cache",
            bytes=int(18.3 * G),
            note="3104 files for 1210 packages",
            rows=[
                dict(
                    id=i1,
                    label="Keep the 2 newest versions of each package",
                    bytes=int(11.2 * G),
                    note="sudo paccache -rk2",
                    tier="cost",
                ),
                dict(
                    id=i2,
                    label="Keep only the newest version",
                    bytes=int(14.9 * G),
                    note="sudo paccache -rk1",
                    tier="cost",
                ),
            ],
        )
    )
    i3 = sc.add(
        "packages",
        "orphans",
        "pacman-orphans",
        title="23 orphan packages",
        sub="installed as dependencies, no longer required",
        bytes=int(1.4 * G),
        tier="state",
        method="terminal",
        cmd="sudo pacman -Rns $(pacman -Qdtq)",
        why="Installed as a dependency of something that is gone.",
        warn=[
            "Needs administrator rights.",
            "Read the list first: tools you use directly can show up here if they were first installed as a dependency.",
        ],
        detail=[
            "electron31  412.0 MB",
            "rust-docs  388.1 MB",
            "qt5-webengine  201.7 MB",
        ],
    )
    pk.append(
        dict(
            key="orphans",
            title="Orphan packages",
            bytes=int(1.4 * G),
            note="23 packages nothing depends on",
            rows=[
                dict(
                    id=i3,
                    label="electron31, rust-docs, qt5-webengine …",
                    bytes=int(1.4 * G),
                    note="sudo pacman -Rns $(pacman -Qdtq) — review the list in the terminal first",
                    tier="state",
                )
            ],
        )
    )
    i4 = sc.add(
        "packages",
        "trash",
        "trash",
        title="Empty the Trash",
        sub="212 items",
        paths=[H + "/.local/share/Trash"],
        bytes=int(3.1 * G),
        mtime=ago(2),
        tier="data",
        method="cmd",
        argv=["gio", "trash", "--empty"],
        why="Things you already threw away. Emptying is what actually frees the space.",
        warn=["After this they cannot be restored from the Trash."],
    )
    pk.append(
        dict(
            key="trash",
            title="Trash",
            bytes=int(3.1 * G),
            note="212 items waiting in the Trash",
            rows=[
                dict(
                    id=i4,
                    label="Empty the Trash",
                    bytes=int(3.1 * G),
                    note="gio trash --empty",
                    tier="data",
                )
            ],
        )
    )
    sec["packages"] = dict(
        groups=pk,
        bytes=sum(g["bytes"] for g in pk),
        pacman=dict(bytes=int(18.3 * G)),
        took=1.2,
    )

    # ---- docker ----
    dr = []
    for kind, title, sub, gb, tier, argv, why, warn, offer in [
        (
            "build-cache",
            "Build cache",
            "412 layers not in use",
            12.6,
            "free",
            ["docker", "builder", "prune", "-f"],
            "Cached build steps. The next build of each image is slower once.",
            [],
            True,
        ),
        (
            "dangling",
            "Dangling images",
            "96 untagged images",
            4.2,
            "free",
            ["docker", "image", "prune", "-f"],
            "Untagged layers left behind when an image was rebuilt. No container uses them.",
            [],
            True,
        ),
        (
            "anon-volumes",
            "Anonymous volumes no container uses",
            "17 volumes",
            2.9,
            "state",
            ["docker", "volume", "prune", "-f"],
            "Unnamed volumes left by removed containers.",
            [
                "Volumes hold data — a database that ran in a removed container may be in one of these."
            ],
            False,
        ),
    ]:
        iid = sc.add(
            "docker",
            "docker",
            kind,
            title=title,
            sub=sub,
            bytes=int(gb * G),
            tier=tier,
            method="cmd",
            argv=argv,
            why=why,
            warn=warn,
            offer=offer,
        )
        dr.append(
            dict(
                id=iid,
                label=title,
                sub=sub,
                bytes=int(gb * G),
                tier=tier,
                note=" ".join(argv),
            )
        )
    sec["docker"] = dict(
        available=True,
        totals=dict(
            images=int(21.4 * G),
            containers=int(0.6 * G),
            volumes=int(6.3 * G),
            cache=int(12.6 * G),
        ),
        bytes=int(40.9 * G),
        rows=dr,
        counts=dict(
            images=141,
            dangling=96,
            containers=22,
            running=4,
            volumes=31,
            named_unused=3,
            named_unused_bytes=int(1.8 * G),
        ),
        compose=[
            dict(
                name="mux-api",
                dir=P + "/work/mux-api",
                containers=3,
                running=0,
                orphaned=False,
            ),
            dict(
                name="old-shop",
                dir=P + "/work/old-shop",
                containers=2,
                running=0,
                orphaned=True,
            ),
        ],
        took=6.4,
    )

    # ---- games ----
    steam_games = []
    for appid, name, gb, played in [
        ("1", "Star Hauler", 62.0, 20),
        ("2", "Deep Vaults II", 41.5, 400),
        ("3", "Tiny Kingdoms", 9.8, 0),
        ("4", "Orbit Golf", 3.2, 75),
    ]:
        note = "never played" if not played else "last played %d days ago" % played
        iid = sc.add(
            "games",
            "steam-game",
            appid,
            title=name,
            sub="Steam · " + note,
            paths=[H + "/.local/share/Steam/steamapps/common/" + name],
            bytes=int(gb * G),
            mtime=ago(played) if played else ago(300),
            tier="cost",
            method="cmd",
            argv=["steam", "steam://uninstall/" + appid],
            why="A Steam game; Steam downloads it again whenever you want it back.",
            warn=[
                "This opens Steam's own uninstall dialog — Steam does the removing.",
                "Saves that are not in Steam Cloud stay in the game's compatibility folder until that is removed too.",
            ],
        )
        steam_games.append(
            dict(
                appid=appid,
                name=name,
                path=H + "/.local/share/Steam/steamapps/common/" + name,
                bytes=int(gb * G),
                played=ago(played) if played else 0,
                updated=ago(300),
                id=iid,
            )
        )
    sh = sc.add(
        "games",
        "steam-shadercache",
        "shader",
        title="Shader cache of games that are not installed",
        sub="3 folders",
        paths=[H + "/.local/share/Steam/steamapps/shadercache/9"],
        bytes=int(1.5 * G),
        tier="free",
        method="rm",
        why="Compiled shaders; Steam rebuilds them.",
        offer=True,
    )
    other_games = []
    for name, gb, eng, days in [
        ("Lantern Road v0.9", 6.4, "Ren'Py", 200),
        ("Lantern Road v0.7", 5.9, "Ren'Py", 420),
        ("Moss & Gears", 2.2, "Unity", 600),
    ]:
        p = H + "/Games/loose/" + name
        iid = sc.add(
            "games",
            "game",
            p,
            title=name,
            sub=eng + " · ~/Games/loose",
            paths=[p],
            bytes=int(gb * G),
            mtime=ago(days),
            tier="data",
            method="trash",
            why="A game folder outside any launcher. Nothing can download it again for you.",
            warn=["Saves may be inside the folder."],
        )
        other_games.append(
            dict(
                id=iid,
                name=name,
                path=p,
                bytes=int(gb * G),
                newest=ago(days),
                engine=eng,
                stem="lantern road" if "Lantern" in name else "moss",
                versions=2 if "Lantern" in name else 1,
            )
        )
    sb = sum(g["bytes"] for g in steam_games)
    sec["games"] = dict(
        steam=dict(
            root=H + "/.local/share/Steam",
            libraries=[H + "/.local/share/Steam"],
            games=steam_games,
            never=1,
            bytes=sb,
            tools=[
                dict(name="Proton 10.0", path="", bytes=int(1.4 * G)),
                dict(
                    name="GE-Proton9-20",
                    path=H + "/.local/share/Steam/compatibilitytools.d/GE-Proton9-20",
                    bytes=int(1.3 * G),
                    id="",
                    custom=True,
                    used=False,
                ),
            ],
            extras=[
                dict(
                    key="compatdata",
                    label="Compatibility data (Proton prefix)",
                    bytes=int(4.1 * G),
                    orphan_bytes=0,
                    orphans=0,
                    id="",
                ),
                dict(
                    key="shadercache",
                    label="Shader cache",
                    bytes=int(2.3 * G),
                    orphan_bytes=int(1.5 * G),
                    orphans=3,
                    id=sh,
                ),
            ],
        ),
        other=other_games,
        libraries=[H + "/Games/loose"],
        misc=[
            dict(
                key="wine",
                label="Wine prefix",
                path=H + "/.wine",
                bytes=int(4.8 * G),
                newest=ago(90),
            )
        ],
        count=len(steam_games) + len(other_games),
        bytes=sb + sum(o["bytes"] for o in other_games),
        took=0.9,
    )

    # ---- thumbnails ----
    th_root = H + "/.cache/thumbnails"
    d1 = sc.add(
        "thumbnails",
        "thumbs-dead",
        th_root,
        title="Thumbnails of files that are gone or changed",
        sub="41208 orphaned · 311 outdated",
        paths=[th_root],
        bytes=int(3.9 * G),
        tier="free",
        method="list",
        listing="",
        offer=True,
        cmd="xargs -d '\\n' rm -f -- < ~/.cache/pill/disk/thumbnails-dead.list",
        why="Previews of files that no longer exist, or changed since the preview was made. Nothing can ever show them again.",
    )
    d2 = sc.add(
        "thumbnails",
        "thumbs-all",
        th_root + "/*",
        title="Every thumbnail",
        sub="~/.cache/thumbnails",
        paths=[th_root],
        bytes=int(4.6 * G),
        tier="free",
        method="contents",
        why="All previews. File managers and image viewers draw them again as you browse — folders open slower the first time.",
    )
    sec["thumbnails"] = dict(
        root=th_root,
        buckets=[
            dict(name="x-large", count=31110, bytes=int(3.6 * G)),
            dict(name="large", count=9820, bytes=int(0.8 * G)),
            dict(name="normal", count=12640, bytes=int(0.2 * G)),
        ],
        bytes=int(4.6 * G),
        count=53570,
        state=dict(
            orphan=dict(count=41208, bytes=int(3.88 * G)),
            stale=dict(count=311, bytes=int(0.02 * G)),
            ok=dict(count=11890, bytes=int(0.68 * G)),
            away=dict(count=161, bytes=int(0.02 * G)),
            unknown=dict(count=0, bytes=0),
        ),
        dead_bytes=int(3.9 * G),
        ids=dict(dead=d1, all=d2),
        where=[
            dict(path=H + "/Downloads/camera-import", count=30120, bytes=int(3.1 * G)),
            dict(path=H + "/Pictures/2019", count=11088, bytes=int(0.78 * G)),
        ],
        extra=[
            dict(
                label="mpv thumbnails and shader cache",
                path=H + "/.cache/mpv",
                bytes=74 * M,
                newest=ago(1),
            )
        ],
        took=21.0,
    )

    # ---- downloads ----
    dl_rows = []
    for name, gb, days, kind, isdir, secret in [
        ("ubuntu-24.04.iso", 5.8, 580, "diskimage", False, False),
        ("lecture-recordings", 12.4, 240, "folder", True, False),
        ("dataset.tar.zst", 3.1, 90, "archive", False, False),
        ("dataset", 7.7, 90, "folder", True, False),
        ("installer-linux-x64.AppImage", 0.4, 30, "installer", False, False),
        ("backup-codes.txt", 0.0011, 800, "document", False, True),
    ]:
        p = H + "/Downloads/" + name
        iid = ""
        if not secret:
            iid = sc.add(
                "downloads",
                "download",
                p,
                title=name,
                sub="downloaded %d days ago" % days,
                paths=[p],
                bytes=int(gb * G),
                mtime=ago(days),
                tier="data",
                method="trash",
                why="Something you downloaded."
                + (
                    " Installers and packages can usually be downloaded again."
                    if kind in ("installer", "diskimage")
                    else ""
                ),
            )
        dl_rows.append(
            dict(
                name=name,
                path=p,
                dir=isdir,
                bytes=int(gb * G),
                mtime=ago(days),
                newest=ago(days),
                kind=kind,
                secret=secret,
                claimed=False,
                id=iid,
            )
        )
    arch = next(r for r in dl_rows if r["name"] == "dataset.tar.zst")
    dup = sc.add(
        "downloads",
        "duplicate",
        H + "/Videos/talks/keynote (1).mp4",
        title="keynote (1).mp4",
        sub="same content as ~/Videos/talks/keynote.mp4",
        paths=[H + "/Videos/talks/keynote (1).mp4"],
        bytes=int(2.2 * G),
        tier="data",
        method="trash",
        verify_same=H + "/Videos/talks/keynote.mp4",
        why="Same size and matching samples as ~/Videos/talks/keynote.mp4; compared byte for byte before it is removed.",
    )
    dlb = sum(r["bytes"] for r in dl_rows)
    sec["downloads"] = dict(
        root=H + "/Downloads",
        bytes=dlb,
        count=len(dl_rows),
        rows=dl_rows,
        secrets=1,
        ages=dict(month=0, year=int(23.6 * G), older=int(5.8 * G)),
        kinds=[["folder", int(20.1 * G)], ["diskimage", int(5.8 * G)]],
        archives=[
            dict(
                name=arch["name"],
                path=arch["path"],
                bytes=arch["bytes"],
                id=arch["id"],
                unpacked=H + "/Downloads/dataset",
            )
        ],
        dups=[
            dict(
                size=int(2.2 * G),
                keep=H + "/Videos/talks/keynote.mp4",
                extra=[H + "/Videos/talks/keynote (1).mp4"],
                ids=[dup],
            )
        ],
        dup_bytes=int(2.2 * G),
        took=0.3,
    )

    # ---- programs, system, home ----
    b1 = sc.add(
        "bins",
        "binary",
        H + "/bin/blender-4.1",
        title="blender-4.1",
        sub="~/bin",
        paths=[H + "/bin/blender-4.1"],
        bytes=int(1.2 * G),
        mtime=ago(400),
        tier="data",
        method="trash",
        why="A program you installed by hand. The system also has a command with this name from a package.",
    )
    sec["bins"] = dict(
        groups=[
            dict(
                path=H + "/bin",
                system=False,
                bytes=int(1.9 * G),
                repo=False,
                note="",
                rows=[
                    dict(
                        name="blender-4.1",
                        path=H + "/bin/blender-4.1",
                        dir=True,
                        bytes=int(1.2 * G),
                        mtime=ago(400),
                        shadow=True,
                        appimage=False,
                        id=b1,
                    ),
                    dict(
                        name="notes.AppImage",
                        path=H + "/bin/notes.AppImage",
                        dir=False,
                        bytes=int(0.7 * G),
                        mtime=ago(50),
                        shadow=False,
                        appimage=True,
                        id="",
                    ),
                ],
            )
        ],
        bytes=int(1.9 * G),
        took=0.4,
    )
    sec["system"] = dict(
        rows=[
            dict(path="/var/cache", bytes=int(19.0 * G), denied=0),
            dict(path="/usr/lib", bytes=int(14.2 * G), denied=0),
            dict(path="/usr/share", bytes=int(8.3 * G), denied=0),
            dict(path="/opt", bytes=int(3.1 * G), denied=0),
            dict(path="/var/lib", bytes=int(2.7 * G), denied=4),
        ],
        bytes=int(47.3 * G),
        kernels=[dict(name="7.3.4-arch1-1", running=True, owned=True, bytes=140 * M)],
        denied=1,
        took=11.0,
    )
    vd = [
        dict(path=H + "/Videos/talks", count=41, bytes=int(22.0 * G), newest=ago(30)),
        dict(
            path=H + "/Videos/screen-recordings",
            count=118,
            bytes=int(9.4 * G),
            newest=ago(3),
        ),
        dict(
            path=H + "/Downloads/lecture-recordings",
            count=36,
            bytes=int(12.4 * G),
            newest=ago(240),
        ),
    ]
    vf = [
        dict(
            bytes=int(4.1 * G),
            path=H + "/Videos/talks/keynote.mp4",
            mtime=ago(200),
            kind="video",
        ),
        dict(
            bytes=int(2.2 * G),
            path=H + "/Videos/talks/keynote (1).mp4",
            mtime=ago(199),
            kind="video",
        ),
        dict(
            bytes=int(1.6 * G),
            path=H + "/Videos/screen-recordings/demo-take-7.mkv",
            mtime=ago(3),
            kind="video",
        ),
    ]
    top = [
        dict(path=H + "/" + n, name=n, bytes=int(gb * G), newest=ago(1), kids=[])
        for n, gb in [
            (".local", 131.0),
            ("Documents", 52.0),
            (".cache", 48.0),
            ("Videos", 31.4),
            ("Downloads", 29.4),
            ("Games", 14.5),
        ]
    ]
    sec["home"] = dict(
        bytes=int(331 * G),
        files=2_914_332,
        top=top,
        videos=dict(count=195, bytes=int(43.8 * G), dirs=vd, files=vf),
        big=[],
        took=64.0,
    )

    total = 512 * G
    disk = dict(
        mounts=[
            dict(
                mount="/",
                fstype="ext4",
                device="/dev/nvme0n1p2",
                total=total,
                free=64 * G,
                used=total - 70 * G,
                dev=1,
            )
        ],
        home=H,
    )
    disk["main"] = disk["mounts"][0]
    sc.shared["pkg_caches"] = []
    ov = db.overview(sc, disk, sec)
    scan = dict(
        version=1,
        at=NOW - 240,
        took=93.0,
        disk=disk,
        overview=ov,
        sections=sec,
        items=sc.items,
        demo=True,
    )
    out = os.path.join(PILL, "diskdemo.json")
    with open(out, "w") as f:
        json.dump(scan, f, ensure_ascii=False, indent=1)
    print("wrote", out, len(sc.items), "items")


if __name__ == "__main__":
    main()
