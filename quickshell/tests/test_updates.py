#!/usr/bin/env python3
"""Offline tests for the pill updater (updatebridge.py + updatehelper.py).

No root, no network, no real pacman: the orchestrator is pointed at a scripted
stand-in for pacman through the helper's `fake` mode (PILL_UPDATE_FAKE), in a
throwaway state directory. Run:  python3 quickshell/tests/test_updates.py
"""

import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PILL = os.path.join(HERE, "..", "pill")
BRIDGE = os.path.join(PILL, "updatebridge.py")
sys.dont_write_bytecode = True
sys.path.insert(0, PILL)
import updatebridge as ub  # noqa: E402

FAKE = r"""
import sys, time
def say(s): sys.stdout.write(s + "\n"); sys.stdout.flush()
def ask(q):
    sys.stdout.write(q); sys.stdout.flush()
    return sys.stdin.readline().strip().lower()
say(":: Synchronizing package databases...")
say(" core downloading...")
say(":: Starting full system upgrade...")
%(pre)s
say("resolving dependencies...")
say("")
say("Packages (3) libdrm-2.4.1-1  mesa-26.2.1-1  openssl-3.6.2-1")
say("")
say("Total Download Size:   12.00 MiB")
if ask(":: Proceed with installation? [Y/n] ") == "n": sys.exit(1)
say(":: Retrieving packages...")
for p in ("libdrm-2.4.1-1-x86_64", "mesa-26.2.1-1-x86_64", "openssl-3.6.2-1-x86_64"):
    say(" %%s downloading..." %% p); time.sleep(0.05)
say("checking keys in keyring...")
%(mid)s
say(":: Processing package changes...")
for p in ("libdrm", "mesa", "openssl"):
    say("upgrading %%s..." %% p); time.sleep(0.05)
say("warning: /etc/mkinitcpio.conf installed as /etc/mkinitcpio.conf.pacnew")
say(":: Running post-transaction hooks...")
say("(1/2) Arming ConditionNeedsUpdate...")
say("(2/2) Updating the desktop file MIME type cache...")
"""

SCEN = {
    "plain": {"pre": "", "mid": ""},
    "replace": {
        "pre": 'if ask(":: Replace jack2 with extra/pipewire-jack? [Y/n] ") == "n": say("kept")',
        "mid": "",
    },
    "remove": {
        "pre": 'a = ask(":: rustup and rust are in conflict. Remove rust? [y/N] ")\n'
        'if a != "y":\n    say("error: unresolvable package conflicts detected")\n    sys.exit(1)',
        "mid": "",
    },
    "key": {
        "pre": "",
        "mid": 'if ask(":: Import PGP key 9A1B22C3D4E5F607, \\"unknown <repo@example.org>\\"? [Y/n] ") == "n": sys.exit(1)',
    },
    "provider": {
        "pre": 'say(":: There are 2 providers available for jack:")\nsay(":: Repository extra")\n'
        'say("   1) jack2  2) pipewire-jack")\nsay("")\n'
        'say("chose " + ask("Enter a number (default=1): "))',
        "mid": "",
    },
    "conflict": {
        "pre": "",
        "mid": 'say("error: failed to commit transaction (conflicting files)")\n'
        'say("foo: /usr/lib/x exists in filesystem")\nsys.exit(1)',
    },
    "slow": {"pre": 'ask(":: Replace a with extra/b? [Y/n] ")', "mid": ""},
}
PENDING = [
    {
        "name": n,
        "old": "1",
        "new": "2",
        "source": "pacman",
        "cls": "optional",
        "restart": "",
    }
    for n in ("libdrm", "mesa", "openssl")
]
fails = []


def check(name, cond, extra=""):
    print(
        ("ok   " if cond else "FAIL ")
        + name
        + (("  " + str(extra)) if (extra and not cond) else "")
    )
    if not cond:
        fails.append(name)


def bridge(state, *args):
    out = subprocess.run(
        [sys.executable, "-B", BRIDGE, "--dir", state, "--sources", "pacman"]
        + list(args),
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout.strip()
    return json.loads(out.splitlines()[-1]) if out else {}


def start(tmp, scen):
    state = os.path.join(tmp, scen)
    os.makedirs(state)
    with open(os.path.join(state, "state.json"), "w") as f:
        json.dump(
            {"packages": PENDING, "checkedAt": int(time.time()), "level": "optional"}, f
        )
    script = os.path.join(tmp, scen + ".py")
    with open(script, "w") as f:
        f.write(FAKE % SCEN[scen])
    env = dict(os.environ, PILL_UPDATE_FAKE=script)
    rid = "2026-01-01_0000"
    os.makedirs(os.path.join(state, rid))
    proc = subprocess.Popen(
        [
            sys.executable,
            "-B",
            BRIDGE,
            "--dir",
            state,
            "--sources",
            "pacman",
            "orchestrate",
            rid,
        ],
        env=env,
    )
    return state, rid, proc


def wait(state, rid, pred, secs=15):
    end = time.time() + secs
    r = None
    while time.time() < end:
        try:
            with open(os.path.join(state, rid, "run.json")) as f:
                r = json.load(f)
            if pred(r):
                return r
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    return r


def summary(state, rid):
    with open(os.path.join(state, rid, "summary.json")) as f:
        return json.load(f)


def main():
    tmp = tempfile.mkdtemp(prefix="pill-updtest-")

    # ---- pure functions ----
    pk = [
        {"name": "linux", "source": "pacman"},
        {"name": "ripgrep", "source": "pacman"},
        {
            "name": "openssl",
            "source": "pacman",
            "advisory": {"id": "AVG-1", "severity": "High"},
        },
    ]
    counts, level, restart = ub.judge(pk, 1)
    check(
        "judge: advisory -> required",
        level == "required" and counts["required"] == 1,
        counts,
    )
    check("judge: kernel needs reboot", restart == "reboot")
    _, l2, r2 = ub.judge([{"name": "ripgrep", "source": "pacman"}], 1)
    check("judge: leaf only -> optional, no restart", l2 == "optional" and r2 == "")
    _, l3, _ = ub.judge([{"name": "ripgrep", "source": "pacman"}], 9)
    check("judge: a week behind -> recommended", l3 == "recommended")
    check("judge: nothing -> none", ub.judge([], 30)[1] == "none")
    check(
        "restart_of mesa/quickshell",
        ub.restart_of("mesa") == "relogin"
        and ub.restart_of("quickshell-git") == "pill",
    )
    card = ub.describe_prompt(
        ':: Import PGP key 9A1B22C3D4E5F607, "unknown <repo@example.org>"? [Y/n] ', []
    )
    check(
        "unknown key: default flips to No, yes is danger",
        card["kind"] == "key"
        and card["options"][0]["id"] == "n"
        and card["options"][0]["default"]
        and card["options"][1]["danger"],
        card,
    )

    # ---- plain run: phases, counters, auto-answered "Proceed" ----
    state, rid, proc = start(tmp, "plain")
    proc.wait(30)
    s = summary(state, rid)
    r = wait(state, rid, lambda r: r["status"] == "done")
    check("plain: done", s["status"] == "done" and s["updated"] == 3, s)
    check("plain: restart from mesa", s["restart"] == "relogin", s["restart"])
    check(
        "plain: pacnew collected",
        s["pacnew"] and s["pacnew"][0]["file"] == "/etc/mkinitcpio.conf",
        s["pacnew"],
    )
    check(
        "plain: all phases done, 100%",
        all(p["state"] == "done" for p in r["phases"]) and r["percent"] == 100,
        r["phases"],
    )
    ans = open(os.path.join(state, rid, "answers.log")).read()
    check(
        "plain: Proceed answered by the click and logged",
        "Proceed with installation" in ans and "Update click" in ans,
    )
    log = open(os.path.join(state, rid, "pacman.log")).read()
    check(
        "plain: log is plain text with pacman's lines",
        "upgrading mesa..." in log and "\x1b" not in log,
    )
    st = json.load(open(os.path.join(state, "state.json")))
    check(
        "plain: pending restart persisted",
        (st.get("pendingRestart") or {}).get("level") == "relogin",
    )
    snap = bridge(state, "snapshot")
    check(
        "snapshot: history has the run",
        snap["history"]
        and snap["history"][0]["kind"] == "update"
        and snap["history"][0]["updated"] == 3,
    )

    # ---- replace: asks, waits, continues on "y" ----
    state, rid, proc = start(tmp, "replace")
    r = wait(state, rid, lambda r: r["status"] == "asking")
    check(
        "replace: paused on the question",
        r["status"] == "asking" and r["prompt"]["kind"] == "replace",
        r.get("prompt"),
    )
    check(
        "replace: raw line kept verbatim",
        r["prompt"]["raw"] == ":: Replace jack2 with extra/pipewire-jack? [Y/n]",
    )
    check(
        "replace: yes is the default, stop still allowed",
        r["prompt"]["options"][0]["default"] and r["canStop"],
    )
    check(
        "answer: rejects junk",
        bridge(state, "answer", rid, "yes please")["ok"] is False,
    )
    check("answer: accepts y", bridge(state, "answer", rid, "y")["ok"] is True)
    proc.wait(30)
    check("replace: finished after the answer", summary(state, rid)["status"] == "done")
    check(
        "replace: answer logged as yours",
        "(you)" in open(os.path.join(state, rid, "answers.log")).read(),
    )

    # ---- remove: default is No; answering n stops with nothing installed ----
    state, rid, proc = start(tmp, "remove")
    r = wait(state, rid, lambda r: r["status"] == "asking")
    o = r["prompt"]["options"]
    check(
        "remove: No is default and first; Yes is danger",
        r["prompt"]["kind"] == "remove"
        and o[0]["id"] == "n"
        and o[0]["default"]
        and o[1]["danger"],
        o,
    )
    bridge(state, "answer", rid, "n")
    proc.wait(30)
    s = summary(state, rid)
    check(
        "remove: declined -> failed, 0 installed",
        s["status"] == "failed" and s["updated"] == 0,
        s,
    )

    # ---- provider: numbered buttons ----
    state, rid, proc = start(tmp, "provider")
    r = wait(state, rid, lambda r: r["status"] == "asking")
    o = r["prompt"]["options"]
    check(
        "provider: one button per choice, default marked",
        r["prompt"]["kind"] == "provider"
        and [x["id"] for x in o] == ["1", "2"]
        and o[0]["default"]
        and "pipewire-jack" in o[1]["label"],
        r["prompt"],
    )
    bridge(state, "answer", rid, "2")
    proc.wait(30)
    check(
        "provider: answer reached pacman",
        "chose 2" in open(os.path.join(state, rid, "pacman.log")).read(),
    )

    # ---- key prompt mid-download ----
    state, rid, proc = start(tmp, "key")
    r = wait(state, rid, lambda r: r["status"] == "asking")
    check("key: asked", r["prompt"]["kind"] == "key", r.get("prompt"))
    bridge(state, "answer", rid, "n")
    proc.wait(30)
    check("key: refused -> failed", summary(state, rid)["status"] == "failed")

    # ---- file conflict: classified, nothing installed ----
    state, rid, proc = start(tmp, "conflict")
    proc.wait(30)
    s = summary(state, rid)
    check(
        "conflict: failed + classified",
        s["status"] == "failed"
        and s["errorKind"] == "conflict"
        and "exists in filesystem" in s["error"],
        s,
    )

    # ---- stop while a question is open ----
    state, rid, proc = start(tmp, "slow")
    wait(state, rid, lambda r: r["status"] == "asking")
    check("stop: accepted before commit", bridge(state, "stop", rid)["ok"] is True)
    proc.wait(30)
    check(
        "stop: recorded as stopped, not failed",
        summary(state, rid)["status"] == "stopped",
    )

    print("\n%s (%d failed)  [%s]" % ("PASS" if not fails else "FAIL", len(fails), tmp))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
