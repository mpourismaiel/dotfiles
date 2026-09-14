#!/usr/bin/env python3
# habiqbridge.py — habiq backend for the pill's habit-tracker menu (the jungle).
#
# Thin wrapper over the `habiq` Go CLI (sibling repo ../habiq): every read
# command is habiq's own --json output passed through untouched, every write
# command shells out and reports {ok} / {ok:false, error}. All habit logic
# (streaks, rewards, freezes, per-week tree data) lives in habiq — the pill
# only renders.
#
#   weeks [N]                     habiq weeks --json [--weeks N] — the jungle dataset
#   status                        habiq status --json — today + current week per habit
#   history HABIT                 habiq history HABIT --json — full log (dialog list)
#   habits                        habiq habit list --json — definitions (add-form, member pickers)
#   freezes                       habiq freeze list --json — freeze dialog rows
#   log HABIT DATE VALUE [NOTE]   log a done entry (VALUE "" → bool done)
#   miss HABIT DATE [REASON]      log an explicit miss
#   edit HABIT DATE IDX VALUE [NOTE]   rewrite entry (VALUE "miss" → miss)
#   delete HABIT DATE IDX         remove an entry
#   freeze-add START END [HABIT] [NOTE]
#   freeze-remove IDX
#   unfreeze                      end active freezes as of today
#   habit-add JSON                {id, name?, schedule, type, unit?, target?,
#                                  reward, penalty?, offdayPenalty?, group?,
#                                  noStreak?} → habiq habit add …
#   habit-edit JSON               same payload → habiq habit edit … (rewrites
#                                  the directive block in place; ""s clear)
#   init                          create the starter journal (empty-state button)
#   git-status                    JSON {repo, branch, dirty, ahead, behind, last}
#                                 (best-effort fetch first so `behind` is current)
#   git-sync                      pull (ff-only) THEN push; {ok, pulled, committed,
#                                 pushed, changed} or {ok:false, error}
#
# A LEADING `--dir DIR` points at the journal directory (Settings → Habit
# Tracker); it becomes `habiq --file DIR/habits.journal`, and that same DIR is
# the git repo the sync commands operate on. Without it habiq (and git) use the
# default ~/Documents/habits.
#
# Binary resolution: HABIQ_BIN env wins, then PATH, then common install spots.
# The probing matters because the autostarted pill (systemd user session /
# login autostart) runs with the stock PATH — no ~/.local/bin, no ~/go/bin —
# so `which habiq` succeeds from a terminal but fails at boot.
import sys
import os
import json
import shutil
import subprocess
import datetime


def _find_habiq():
    env = os.environ.get("HABIQ_BIN")
    if env:
        return os.path.expanduser(env)
    found = shutil.which("habiq")
    if found:
        return found
    home = os.path.expanduser("~")
    for cand in (os.path.join(home, ".local", "bin", "habiq"),
                 os.path.join(home, "go", "bin", "habiq"),
                 os.path.join(home, "bin", "habiq"),
                 "/usr/local/bin/habiq"):
        if os.access(cand, os.X_OK):
            return cand
    return "habiq"  # let the OSError surface as the UI hint


HABIQ = _find_habiq()

# the journal directory doubles as the git repo the sync button operates on;
# `--dir` overrides it in main(), otherwise it matches habiq's default
GIT_DIR = os.path.expanduser("~/Documents/habits")


def run_git(args, timeout=30):
    """(rc, stdout, stderr) of a git run inside GIT_DIR. Never raises."""
    try:
        r = subprocess.run(["git", "-C", GIT_DIR] + args,
                           capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def git_counts():
    """(ahead, behind) vs the upstream branch; (0, 0) if there's no upstream."""
    rc, counts, _ = run_git(["rev-list", "--left-right", "--count",
                             "HEAD...@{upstream}"])
    if rc == 0 and counts:
        parts = counts.split()
        if len(parts) == 2:
            return int(parts[0]), int(parts[1])
    return 0, 0


def cmd_git_status():
    """Snapshot for the pill's sync strip: branch, dirty file count, ahead/behind
    the upstream, last commit subject. A best-effort fetch runs first so `behind`
    reflects the real remote (that's the point — telling you a sync is due); an
    offline fetch just falls back to the last-known counts."""
    rc, _, _ = run_git(["rev-parse", "--git-dir"])
    if rc != 0:
        return {"repo": False}
    run_git(["fetch", "--quiet"], timeout=20)   # best-effort; ignore failure
    _, branch, _ = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    _, porcelain, _ = run_git(["status", "--porcelain"])
    dirty = len([l for l in porcelain.splitlines() if l.strip()])
    ahead, behind = git_counts()
    _, last, _ = run_git(["log", "-1", "--format=%h %s"])
    return {"repo": True, "branch": branch, "dirty": dirty,
            "ahead": ahead, "behind": behind, "last": last}


def cmd_git_sync():
    """One-button sync: pull first, then push. Local edits are committed, then
    replayed on top of the remote with a rebase (so pulled changes come in and
    history stays linear). It NEVER writes conflict markers: a rebase that hits a
    real conflict is aborted — restoring the tree untouched — and reported for
    the user to resolve in a terminal. Clean divergences (edits to different
    lines) rebase through and sync in one press."""
    rc, _, _ = run_git(["rev-parse", "--git-dir"])
    if rc != 0:
        return {"ok": False, "error": "not a git repo"}
    rc, _, err = run_git(["fetch", "--quiet"], timeout=60)
    if rc != 0:
        return {"ok": False, "error": err[-200:] or "fetch failed"}
    _, before, _ = run_git(["rev-parse", "HEAD"])
    # commit local edits first so the working tree is clean for the rebase
    _, porcelain, _ = run_git(["status", "--porcelain"])
    committed = False
    if porcelain.strip():
        run_git(["add", "-A"])
        today = datetime.date.today().isoformat()
        rc, _, err = run_git(["commit", "-m", "pill: habit entries %s" % today])
        if rc != 0:
            return {"ok": False, "error": err[-200:] or "commit failed"}
        committed = True
    # ---- pull first: rebase local commits onto the remote. On a real conflict
    #      abort cleanly (tree back to exactly here) so the user handles it. ----
    ahead, behind = git_counts()
    pulled = False
    if behind:
        rc, _, err = run_git(["rebase", "@{upstream}"], timeout=60)
        if rc != 0:
            run_git(["rebase", "--abort"])
            return {"ok": False, "committed": committed,
                    "error": "conflicts — pull and resolve in a terminal"}
        pulled = True
    # ---- push whatever we're now ahead by ----
    ahead, _ = git_counts()
    pushed = False
    if ahead or committed:
        rc, _, err = run_git(["push", "--quiet"], timeout=60)
        if rc != 0:
            tail = err[-200:]
            if "rejected" in err or "non-fast-forward" in err or "fetch first" in err:
                tail = "push rejected — remote moved, sync again"
            return {"ok": False, "committed": committed, "error": tail}
        pushed = True
    _, after, _ = run_git(["rev-parse", "HEAD"])
    return {"ok": True, "pulled": pulled, "committed": committed,
            "pushed": pushed, "changed": before != after}


def run_habiq(args, journal):
    cmd = [HABIQ]
    if journal:
        cmd += ["--file", journal]
    cmd += args
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30)


def read(args, journal, empty):
    """Read command: pass habiq's JSON through; on failure print the empty shape
    (plus the error so the UI can show a hint)."""
    try:
        p = run_habiq(args + ["--json"], journal)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(json.dumps({"empty": empty, "error": str(e)}) if isinstance(empty, dict)
              else json.dumps(empty))
        return
    if p.returncode != 0:
        err = (p.stderr or "").strip()
        if isinstance(empty, dict):
            out = dict(empty)
            out["error"] = err
            print(json.dumps(out))
        else:
            print(json.dumps(empty))
        return
    sys.stdout.write(p.stdout)


def write(args, journal):
    try:
        p = run_habiq(args, journal)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return
    if p.returncode != 0:
        print(json.dumps({"ok": False, "error": (p.stderr or "").strip()}))
    else:
        print(json.dumps({"ok": True}))


def main():
    global GIT_DIR
    argv = sys.argv[1:]
    journal = ""
    if argv and argv[0] == "--dir":
        d = os.path.expanduser(argv[1])
        journal = os.path.join(d, "habits.journal") if d else ""
        if d:
            GIT_DIR = d
        argv = argv[2:]
    if not argv:
        print(json.dumps({"ok": False, "error": "no command"}))
        return
    cmd, a = argv[0], argv[1:]

    if cmd == "weeks":
        args = ["weeks"] + (["--weeks", a[0]] if a else [])
        read(args, journal, {"rows": [], "weekTotals": []})
    elif cmd == "status":
        read(["status"], journal, {"rows": [], "weekTotals": []})
    elif cmd == "history" and a:
        read(["history", a[0]], journal, [])
    elif cmd == "habits":
        read(["habit", "list"], journal, [])
    elif cmd == "freezes":
        read(["freeze", "list"], journal, [])
    elif cmd == "log" and len(a) >= 2:
        args = ["log", a[0], "--date", a[1]]
        if len(a) > 2 and a[2]:
            args.insert(2, a[2])
        if len(a) > 3 and a[3]:
            args += ["--reason", a[3]]
        write(args, journal)
    elif cmd == "miss" and len(a) >= 2:
        args = ["miss", a[0], "--date", a[1]]
        if len(a) > 2 and a[2]:
            args += ["--reason", a[2]]
        write(args, journal)
    elif cmd == "edit" and len(a) >= 4:
        args = ["edit", a[0], "--date", a[1], "--index", a[2]]
        if a[3] == "miss":
            args += ["--missed"]
        else:
            args += ["--value", a[3]]
        if len(a) > 4:
            args += ["--reason", a[4]]
        write(args, journal)
    elif cmd == "delete" and len(a) >= 3:
        write(["delete", a[0], "--date", a[1], "--index", a[2]], journal)
    elif cmd == "freeze-add" and len(a) >= 2:
        args = ["freeze", a[0], a[1]]
        if len(a) > 2 and a[2]:
            args.append(a[2])
        if len(a) > 3 and a[3]:
            args += ["--note", a[3]]
        write(args, journal)
    elif cmd == "freeze-remove" and a:
        write(["freeze", "remove", a[0]], journal)
    elif cmd == "unfreeze":
        write(["unfreeze"], journal)
    elif cmd == "habit-add" and a:
        try:
            spec = json.loads(a[0])
        except ValueError as e:
            print(json.dumps({"ok": False, "error": "bad payload: %s" % e}))
            return
        args = ["habit", "add", spec.get("id", "")]
        for key, flag in (("name", "--name"), ("schedule", "--schedule"),
                          ("type", "--type"), ("unit", "--unit"),
                          ("target", "--target"), ("reward", "--reward"),
                          ("penalty", "--penalty"),
                          ("offdayPenalty", "--offday-penalty"),
                          ("group", "--group")):
            v = spec.get(key)
            if v not in (None, ""):
                args += [flag, str(v)]
        if spec.get("noStreak"):
            args.append("--no-streak")
        write(args, journal)
    elif cmd == "habit-edit" and a:
        try:
            spec = json.loads(a[0])
        except ValueError as e:
            print(json.dumps({"ok": False, "error": "bad payload: %s" % e}))
            return
        args = ["habit", "edit", spec.get("id", "")]
        # every present key is passed, empty strings included — the CLI treats
        # '' as "clear back to default" (penalty→reward, no target, no group…)
        for key, flag in (("name", "--name"), ("schedule", "--schedule"),
                          ("type", "--type"), ("unit", "--unit"),
                          ("target", "--target"), ("reward", "--reward"),
                          ("penalty", "--penalty"),
                          ("offdayPenalty", "--offday-penalty"),
                          ("group", "--group")):
            if key in spec:
                args += [flag, str(spec[key])]
        if "noStreak" in spec:
            args += ["--streak", "off" if spec.get("noStreak") else "on"]
        write(args, journal)
    elif cmd == "init":
        write(["init"], journal)
    elif cmd == "git-status":
        print(json.dumps(cmd_git_status()))
    elif cmd == "git-sync":
        print(json.dumps(cmd_git_sync()))
    else:
        print(json.dumps({"ok": False, "error": "unknown command %r" % cmd}))


if __name__ == "__main__":
    # DEMO mode: serve a deterministic fake jungle (demodata.py) instead of the
    # real journal — safe habit data for screen recording.
    if os.environ.get("DEMO"):
        import demodata
        demodata.run("habiq", sys.argv[1:])
    else:
        main()
