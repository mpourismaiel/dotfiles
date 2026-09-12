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
#   init                          create the starter journal (empty-state button)
#
# A LEADING `--dir DIR` points at the journal directory (Settings → Habit
# Tracker); it becomes `habiq --file DIR/habits.journal`. Without it habiq uses
# its own default (~/Documents/habits). The habiq binary is found on PATH
# (override: HABIQ_BIN).
import sys
import os
import json
import subprocess

HABIQ = os.environ.get("HABIQ_BIN", "habiq")


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
    argv = sys.argv[1:]
    journal = ""
    if argv and argv[0] == "--dir":
        d = os.path.expanduser(argv[1])
        journal = os.path.join(d, "habits.journal") if d else ""
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
    elif cmd == "init":
        write(["init"], journal)
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
