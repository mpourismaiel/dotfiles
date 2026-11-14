#!/usr/bin/env python3
# updatebridge.py — system-update backend for the pill's Updates page (menu 20).
#
# Everything lives in plain files under the state directory (default
# ~/.local/state/pill/updates, override with a LEADING `--dir DIR`), so a file
# manager / text editor can take over at any point and an update keeps running
# when the pill reloads:
#
#   state.json            last check: pending packages, verdict, restart state
#   checks.jsonl          one line per check (the logbook's "check" entries)
#   <YYYY-MM-DD_HHMM>/    one directory per update run:
#       pacman.log        everything pacman printed (plain text)
#       flatpak.log       the flatpak step, when it ran
#       answers.log       each question pacman asked + what was answered
#       run.json          live progress (phase, counts, the open question)
#       summary.json      the result, written once at the end
#
# Commands (a leading `--sources a,b,c` names the enabled sources; default
# pacman,flatpak):
#
#   watch                 long-lived: prints one JSON snapshot per line whenever
#                         anything changes, runs the twice-daily check, and emits
#                         {"event":"notify",…} lines (each fires once).
#   snapshot              print one snapshot and exit
#   check                 ask the watcher for a check now (or run one inline with
#                         `check --now`, used by tests / first run)
#   start                 begin an update run (detached from the caller)
#   answer ID VALUE       answer the open question of run ID (y / n / a number)
#   stop ID               interrupt run ID (only offered before pacman commits)
#   terminal [repo|aur]   hand over to a terminal: `yay -Syu --repo` / `yay -Sua`
#   ack-news              mark the current Arch news items as read (clears HOLD)
#   ack-restart           forget a pending restart (you restarted another way)
#   open ID log|folder    open a run's log in the default editor / file manager
#   orchestrate ID        internal: the detached runner behind `start`
#
# Checking never touches the real pacman database: like `checkupdates`, it syncs
# a private copy under ~/.cache/pill/updates/db through fakeroot (so there is no
# partial-upgrade trap and no password). Updating runs `pacman -Syu` through
# pkexec + updatehelper.py; this side parses its output and relays questions.
import datetime
import email.utils
import fcntl
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"),
    "pill",
    "updates",
)
CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "pill", "updates"
)
SOURCES = ["pacman", "flatpak"]
INTERVAL = 12 * 3600  # twice a day
RETRY = 30 * 60  # after a failed check
KEEP_RUNS = 20
SECURITY_URL = "https://security.archlinux.org/issues/all.json"
NEWS_URL = "https://archlinux.org/feeds/news/"
ENV_C = dict(os.environ, LC_ALL="C", LANG="C")

# ---- judgement tables -------------------------------------------------------
CORE = re.compile(
    r"^(linux(-lts|-zen|-hardened)?(-headers)?|linux-firmware.*|.*-ucode|systemd(-libs|-sysvcompat)?"
    r"|glibc|lib32-glibc|gcc-libs|pacman|archlinux-keyring|mesa|lib32-mesa|vulkan-(radeon|intel|icd-loader)"
    r"|nvidia.*|xorg-server|xorg-xwayland|wayland|kwin|plasma-workspace|plasma-desktop|kwayland|sddm"
    r"|qt6-(base|declarative|wayland)|pipewire(-pulse|-audio)?|wireplumber|networkmanager|openssl|openssh"
    r"|sudo|polkit|dbus(-broker)?|mkinitcpio|grub|firefox|chromium|google-chrome|quickshell.*|bluez"
    r"|util-linux|coreutils|bash|zsh|curl|ca-certificates.*|gnupg|cryptsetup|btrfs-progs|e2fsprogs)$"
)
REBOOT = re.compile(
    r"^(linux(-lts|-zen|-hardened)?|linux-firmware.*|.*-ucode|systemd(-libs)?|glibc"
    r"|nvidia.*|dbus(-broker)?|cryptsetup)$"
)
RELOGIN = re.compile(
    r"^(mesa|kwin|plasma-workspace|plasma-desktop|kwayland|wayland|xorg-xwayland"
    r"|qt6-(base|wayland|declarative)|pipewire|wireplumber|sddm)$"
)
PILL = re.compile(r"^quickshell.*$")
RESTART_RANK = {"": 0, "pill": 1, "relogin": 2, "reboot": 3}


def restart_of(name):
    if REBOOT.match(name):
        return "reboot"
    if RELOGIN.match(name):
        return "relogin"
    if PILL.match(name):
        return "pill"
    return ""


# ---- small helpers ----------------------------------------------------------
def now():
    return int(time.time())


def run(cmd, timeout=120, env=None):
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env or ENV_C,
            stdin=subprocess.DEVNULL,
        )
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def read_text(path, limit=1 << 20):
    try:
        with open(path, "rb") as f:
            try:
                f.seek(-limit, os.SEEK_END)
            except OSError:
                f.seek(0)
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def spawn_detached(cmd):
    try:
        subprocess.Popen(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except OSError:
        return False


def state_path(*p):
    return os.path.join(STATE, *p)


def load_state():
    return read_json(state_path("state.json"), {}) or {}


def save_state(st):
    os.makedirs(STATE, exist_ok=True)
    write_json(state_path("state.json"), st)


def boot_id():
    return read_text("/proc/sys/kernel/random/boot_id").strip()


def session_id():
    return os.environ.get("XDG_SESSION_ID", "")


# ---- checking ---------------------------------------------------------------
def last_upgrade_ts():
    """Epoch of the last `pacman -Syu` according to /var/log/pacman.log."""
    ts = 0
    for line in read_text("/var/log/pacman.log", 4 << 20).splitlines():
        if "starting full system upgrade" in line and line.startswith("["):
            try:
                ts = int(
                    datetime.datetime.fromisoformat(
                        line[1 : line.index("]")]
                    ).timestamp()
                )
            except ValueError:
                pass
    return ts


def check_pacman():
    """(packages, download_bytes, error) from a private, fakeroot-synced db."""
    if not shutil.which("pacman"):
        return [], 0, "absent"
    db = os.path.join(CACHE, "db")
    os.makedirs(db, exist_ok=True)
    local = os.path.join(db, "local")
    if not os.path.islink(local):
        try:
            os.symlink("/var/lib/pacman/local", local)
        except OSError:
            pass
    if shutil.which("fakeroot"):
        rc, _, err = run(
            [
                "fakeroot",
                "--",
                "pacman",
                "-Sy",
                "--disable-sandbox",
                "--dbpath",
                db,
                "--logfile",
                "/dev/null",
            ],
            timeout=180,
        )
        if rc != 0:
            return (
                [],
                0,
                (err.strip().splitlines() or ["could not sync package databases"])[-1],
            )
    elif shutil.which("checkupdates"):
        db = None
    else:
        return [], 0, "needs fakeroot (or pacman-contrib) to check without a password"

    if db:
        rc, out, _ = run(["pacman", "-Qu", "--dbpath", db])
    else:
        rc, out, _ = run(["checkupdates"], timeout=180)
    pkgs = []
    for line in out.splitlines():
        m = re.match(r"^(\S+) (\S+) -> (\S+)(\s+\[ignored\])?$", line.strip())
        if m and not m.group(4):
            pkgs.append(
                {
                    "name": m.group(1),
                    "old": m.group(2),
                    "new": m.group(3),
                    "source": "pacman",
                    "repo": "",
                    "size": 0,
                }
            )
    total = 0
    if db and pkgs:
        rc, out, _ = run(
            [
                "pacman",
                "-Sup",
                "--noconfirm",
                "--dbpath",
                db,
                "--print-format",
                "%n|%v|%s|%r",
            ]
        )
        info = {}
        for line in out.splitlines():
            p = line.split("|")
            if len(p) == 4 and p[2].isdigit():
                info[p[0]] = (int(p[2]), p[3])
                total += int(p[2])
        for p in pkgs:
            if p["name"] in info:
                p["size"], p["repo"] = info[p["name"]]
    return pkgs, total, ""


def check_flatpak():
    if not shutil.which("flatpak"):
        return [], "absent"
    rc, out, err = run(
        ["flatpak", "remote-ls", "--updates", "--columns=application,version,name"],
        timeout=120,
    )
    if rc != 0:
        return [], (err.strip().splitlines() or ["flatpak check failed"])[-1]
    pkgs = []
    for line in out.splitlines():
        p = line.split("\t")
        if p and p[0].strip():
            pkgs.append(
                {
                    "name": p[0].strip(),
                    "old": "",
                    "new": (p[1].strip() if len(p) > 1 else ""),
                    "source": "flatpak",
                    "repo": "flatpak",
                    "size": 0,
                    "title": (p[2].strip() if len(p) > 2 else ""),
                }
            )
    return pkgs, ""


def aur_helper():
    return shutil.which("yay") or shutil.which("paru")


def check_aur():
    h = aur_helper()
    if not h:
        return [], "absent"
    rc, out, err = run([h, "-Qua"], timeout=120, env=dict(os.environ, LC_ALL="C"))
    pkgs = []
    for line in out.splitlines():
        m = re.match(r"^(\S+) (\S+) -> (\S+)", line.strip())
        if m:
            pkgs.append(
                {
                    "name": m.group(1),
                    "old": m.group(2),
                    "new": m.group(3),
                    "source": "aur",
                    "repo": "aur",
                    "size": 0,
                }
            )
    return pkgs, ""


def check_firmware():
    if not shutil.which("fwupdmgr"):
        return [], "absent"
    rc, out, _ = run(
        ["fwupdmgr", "get-updates", "--json", "--no-unreported-check"], timeout=90
    )
    pkgs = []
    try:
        for dev in json.loads(out).get("Devices") or []:
            for rel in (dev.get("Releases") or [])[:1]:
                pkgs.append(
                    {
                        "name": dev.get("Name", "device"),
                        "old": dev.get("Version", ""),
                        "new": rel.get("Version", ""),
                        "source": "firmware",
                        "repo": "firmware",
                        "size": 0,
                    }
                )
    except ValueError:
        pass
    return pkgs, ""


def fetch(url, cache_name, timeout=15):
    """GET with a disk fallback, so an offline check still classifies."""
    path = os.path.join(CACHE, cache_name)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "pill-updates"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = r.read()
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        return data
    except Exception:
        try:
            with open(path, "rb") as f:
                return f.read()
        except OSError:
            return b""


def vercmp(a, b):
    rc, out, _ = run(["vercmp", a, b], timeout=5)
    try:
        return int(out.strip())
    except ValueError:
        return 0


def advisories_for(pkgs):
    """{name: {id, severity}} for pending packages with a fixed, open advisory."""
    try:
        groups = json.loads(fetch(SECURITY_URL, "security.json") or b"[]")
    except ValueError:
        groups = []
    pending = {p["name"]: p for p in pkgs if p["source"] == "pacman"}
    rank = {"Critical": 4, "High": 3, "Medium": 2, "Low": 1}
    found = {}
    for g in groups:
        fixed = g.get("fixed")
        if not fixed or g.get("status") in ("Not affected",):
            continue
        for name in g.get("packages") or []:
            p = pending.get(name)
            if not p:
                continue
            # still vulnerable now, and this update reaches the fixed version
            if vercmp(p["old"], fixed) < 0 and vercmp(p["new"], fixed) >= 0:
                sev = g.get("severity") or "Unknown"
                cur = found.get(name)
                if not cur or rank.get(sev, 0) > rank.get(cur["severity"], 0):
                    found[name] = {"id": g.get("name", ""), "severity": sev}
    return found


def news_since(ts, acked):
    items = []
    data = fetch(NEWS_URL, "news.xml")
    if not data or not ts:
        return items
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return items
    for it in root.iter("item"):
        link = (it.findtext("link") or "").strip()
        try:
            when = int(
                email.utils.parsedate_to_datetime(
                    it.findtext("pubDate") or ""
                ).timestamp()
            )
        except (TypeError, ValueError):
            continue
        if when > ts and link not in acked:
            items.append(
                {
                    "title": (it.findtext("title") or "").strip(),
                    "link": link,
                    "at": when,
                }
            )
    return items


def judge(pkgs, days):
    """Classify every package, return (counts, level, restart)."""
    counts = {"required": 0, "recommended": 0, "optional": 0}
    restart = ""
    for p in pkgs:
        if p["source"] not in ("pacman", "flatpak", "firmware"):
            p["cls"] = "optional"
            p["restart"] = ""
            continue
        if p.get("advisory"):
            p["cls"] = "required"
        elif p["source"] == "firmware" or (
            p["source"] == "pacman" and CORE.match(p["name"])
        ):
            p["cls"] = "recommended"
        else:
            p["cls"] = "optional"
        p["restart"] = (
            restart_of(p["name"])
            if p["source"] == "pacman"
            else ("reboot" if p["source"] == "firmware" else "")
        )
        counts[p["cls"]] += 1
        if RESTART_RANK[p["restart"]] > RESTART_RANK[restart]:
            restart = p["restart"]
    total = sum(counts.values())
    if counts["required"]:
        level = "required"
    elif counts["recommended"] or (total and (days >= 7 or total >= 100)):
        level = "recommended"
    elif total:
        level = "optional"
    else:
        level = "none"
    return counts, level, restart


def do_check(sources):
    """Run a full check and persist it. Returns the new state dict."""
    os.makedirs(STATE, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)
    lock = open(os.path.join(CACHE, "check.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return load_state()  # another pill instance is already checking
    st = load_state()
    st["checking"] = True
    st["checkingSince"] = now()
    save_state(st)

    pkgs, src, errors = [], {}, []
    pp, dl, err = check_pacman()
    src["pacman"] = {
        "available": err != "absent",
        "count": len(pp),
        "error": "" if err == "absent" else err,
    }
    if err and err != "absent":
        errors.append(err)
    pkgs += pp
    for key, fn in (
        ("flatpak", check_flatpak),
        ("aur", check_aur),
        ("firmware", check_firmware),
    ):
        got, err = fn()
        src[key] = {
            "available": err != "absent",
            "count": len(got),
            "error": "" if err == "absent" else err,
        }
        pkgs += got
    if aur_helper():
        src["aur"]["helper"] = os.path.basename(aur_helper())

    last = last_upgrade_ts()
    days = (now() - last) / 86400.0 if last else 0
    adv = advisories_for(pkgs)
    for p in pkgs:
        if p["name"] in adv and p["source"] == "pacman":
            p["advisory"] = adv[p["name"]]
    # the verdict only weighs what the Update button will actually install
    counted = [p for p in pkgs if p["source"] in sources]
    for p in pkgs:
        if p["source"] not in sources:
            p["cls"], p["restart"] = "optional", ""
    counts, level, restart = judge(counted, days)
    order = {"required": 0, "recommended": 1, "optional": 2}
    pkgs.sort(
        key=lambda p: (
            0 if p["source"] in sources else 1,
            order[p["cls"]],
            -RESTART_RANK[p.get("restart", "")],
            p["name"],
        )
    )

    ok = not errors
    st = load_state()
    st.update(
        {
            "checking": False,
            "lastAttempt": now(),
            "error": "; ".join(errors),
            "sources": src,
        }
    )
    if ok:
        hold = news_since(last, st.get("ackedNews") or [])
        st.update(
            {
                "checkedAt": now(),
                "packages": pkgs,
                "counts": dict(counts, total=sum(counts.values())),
                "level": level,
                "restart": restart,
                "downloadBytes": dl if "pacman" in sources else 0,
                "daysBehind": round(days, 1),
                "lastUpgrade": last,
                "hold": hold,
            }
        )
        entry = {
            "at": now(),
            "total": sum(counts.values()),
            "level": level,
            "required": counts["required"],
            "recommended": counts["recommended"],
            "optional": counts["optional"],
            "bytes": st["downloadBytes"],
            "restart": restart,
            "hold": len(hold),
        }
        path = state_path("checks.jsonl")
        lines = read_text(path).splitlines()[-59:] + [json.dumps(entry)]
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(path + ".tmp", path)
    save_state(st)
    fcntl.flock(lock, fcntl.LOCK_UN)
    return st


# ---- runs -------------------------------------------------------------------
def run_dirs():
    out = [d for d in glob.glob(state_path("20*_*")) if os.path.isdir(d)]
    return sorted(out, reverse=True)


def run_json(rid):
    return read_json(state_path(rid, "run.json"), None)


def active_run():
    for d in run_dirs()[:3]:
        r = read_json(os.path.join(d, "run.json"), None)
        if r and r.get("status") in ("auth", "running", "asking"):
            # a runner that died without finishing must not block the UI forever
            if now() - int(r.get("beat", r.get("startedAt", 0))) > 90:
                r["status"] = "failed"
                r["error"] = "the update runner stopped unexpectedly"
                r["endedAt"] = now()
                write_json(os.path.join(d, "run.json"), r)
                continue
            return r
    return None


PROMPT_END = re.compile(r"(\[[Yy]/[Nn]\]|\(default=[^)]*\):|\?)\s*$")


def packager_key(keyid):
    """(known, fingerprint, uid) — is this key in the installed Arch keyring?"""
    ring = "/usr/share/pacman/keyrings/archlinux.gpg"
    if not shutil.which("gpg") or not os.path.exists(ring):
        return None, "", ""
    rc, out, _ = run(["gpg", "--show-keys", "--with-colons", ring], timeout=20)
    fpr, uid, hit = "", "", False
    cur_fpr = ""
    for line in out.splitlines():
        f = line.split(":")
        if f[0] == "pub":
            if hit:
                break
            cur_fpr, uid = "", ""
        elif f[0] == "fpr" and len(f) > 9:
            if not cur_fpr:
                cur_fpr = f[9]
            if f[9].endswith(keyid.upper()):
                hit, fpr = True, cur_fpr
        elif f[0] == "uid" and len(f) > 9 and not uid:
            uid = f[9]
    if not hit:
        return False, "", ""
    return True, " ".join(fpr[i : i + 4] for i in range(0, len(fpr), 4)), uid


def required_by(pkg):
    rc, out, _ = run(["pacman", "-Qi", pkg], timeout=10)
    for line in out.splitlines():
        if line.startswith("Required By"):
            v = line.split(":", 1)[1].split()
            if v and v[0] != "None":
                return ", ".join(v[:6]) + (
                    " + %d more" % (len(v) - 6) if len(v) > 6 else ""
                )
    return "nothing installed"


def installed_version(pkg):
    rc, out, _ = run(["pacman", "-Q", pkg], timeout=10)
    return out.strip() or pkg


def describe_prompt(raw, recent):
    """Turn pacman's question into a card: title, facts, and answer buttons."""
    text = raw.strip()
    yes_default = "[Y/n]" in text
    yn = [
        {"id": "y", "label": "Yes", "default": yes_default, "danger": False},
        {"id": "n", "label": "No", "default": not yes_default, "danger": False},
    ]

    m = re.search(r"Replace (\S+) with (\S+)\?", text)
    if m:
        old, new = m.group(1), m.group(2)
        yn[0]["label"], yn[1]["label"] = "Yes, replace", "No, keep " + old
        return {
            "kind": "replace",
            "tone": "ask",
            "label": "Replace",
            "title": "Swap %s for %s?" % (old, new.split("/")[-1]),
            "kv": [
                ["Goes", installed_version(old)],
                ["Comes", new],
                ["Used by", required_by(old)],
            ],
            "options": yn,
            "simple": True,
        }

    m = re.search(r"(\S+) and (\S+) are in conflict.*Remove (\S+)\?", text)
    if m:
        gone = m.group(3)
        keep = m.group(1) if m.group(1) != gone else m.group(2)
        yn[0].update(label="Yes, remove " + gone, danger=True)
        yn[1]["label"] = "No, stop update"
        return {
            "kind": "remove",
            "tone": "danger",
            "label": "Remove",
            "title": "Remove %s so %s can install?" % (gone, keep),
            "kv": [
                ["Removes", installed_version(gone)],
                ["Needed by", required_by(gone)],
                ["If no", "the update stops, nothing is changed"],
            ],
            "options": [yn[1], yn[0]] if not yes_default else yn,
            "simple": False,
        }

    m = re.search(r'Import PGP key (\S+?),\s*"?(.*?)"?\?\s*\[', text)
    if m:
        keyid, who = m.group(1), m.group(2)
        known, fpr, uid = packager_key(keyid)
        if known:
            yn[0]["label"], yn[1]["label"] = "Yes, import", "No, stop update"
            return {
                "kind": "key",
                "tone": "ask",
                "label": "New key",
                "title": "Trust a new packager key?",
                "kv": [
                    ["Key", who],
                    ["Fingerprint", fpr],
                    ["Check", "in the installed Arch keyring"],
                ],
                "checkOk": True,
                "options": yn,
                "simple": False,
            }
        yn[0].update(label="Yes, import anyway", danger=True, default=False)
        yn[1].update(label="No, stop update", default=True)
        return {
            "kind": "key",
            "tone": "danger",
            "label": "New key · not recognised",
            "title": "This key is not a known Arch packager.",
            "kv": [
                ["Key", who],
                ["Key ID", keyid],
                [
                    "Check",
                    "not in the installed Arch keyring"
                    if known is False
                    else "could not be checked (gpg unavailable)",
                ],
                ["Advice", "stop and verify the fingerprint yourself"],
            ],
            "checkOk": False,
            "options": [yn[1], yn[0]],
            "simple": False,
        }

    if re.search(r"Enter a number", text):
        what, opts = "", []
        for line in recent[-12:]:
            mm = re.search(
                r"There are \d+ providers available for (\S+?):?$", line.strip()
            )
            if mm:
                what, opts = mm.group(1), []
            for num, name in re.findall(r"(\d+)\)\s+(\S+)", line):
                opts.append((num, name))
        dm = re.search(r"default=(\d+)", text)
        dflt = dm.group(1) if dm else "1"
        return {
            "kind": "provider",
            "tone": "ask",
            "label": "Choose one",
            "title": "Which package should provide %s?" % (what or "this"),
            "kv": [],
            "simple": False,
            "options": [
                {
                    "id": n,
                    "label": "%s · %s" % (n, name),
                    "default": n == dflt,
                    "danger": False,
                }
                for n, name in opts
            ],
        }

    m = re.search(r"File (\S+) is corrupted.*delete it\?", text)
    if m:
        yn[0]["label"], yn[1]["label"] = "Yes, delete and retry", "No, stop update"
        return {
            "kind": "corrupt",
            "tone": "ask",
            "label": "Delete and retry",
            "title": "A download arrived damaged.",
            "kv": [["File", os.path.basename(m.group(1))]],
            "options": yn,
            "simple": True,
        }

    if "[Y/n]" in text or "[y/N]" in text:
        return {
            "kind": "unknown",
            "tone": "ask",
            "label": "Question",
            "title": "pacman is asking something the pill does not recognise.",
            "kv": [],
            "options": yn,
            "simple": False,
        }
    return {
        "kind": "free",
        "tone": "ask",
        "label": "Question",
        "title": "pacman is waiting for typed input.",
        "kv": [],
        "options": [],
        "simple": False,
    }


PHASES = [
    ("keyring", "Keyring"),
    ("sync", "Sync"),
    ("resolve", "Resolve"),
    ("download", "Download"),
    ("install", "Install"),
    ("hooks", "Hooks"),
    ("flatpak", "Flatpak"),
]
WEIGHT = {
    "keyring": 2,
    "sync": 3,
    "resolve": 3,
    "download": 35,
    "install": 42,
    "hooks": 10,
    "flatpak": 5,
}


class Runner:
    """The detached orchestrator for one update run."""

    def __init__(self, rid, sources):
        self.rid = rid
        self.dir = state_path(rid)
        self.sources = sources
        st = load_state()
        pend = [p for p in st.get("packages") or [] if p["source"] in sources]
        self.pending = pend
        self.flatpak_n = len([p for p in pend if p["source"] == "flatpak"])
        self.pac_n = len([p for p in pend if p["source"] == "pacman"])
        self.keyring = any(p["name"] == "archlinux-keyring" for p in pend)
        keys = [
            k
            for k, _ in PHASES
            if not (k == "keyring" and not self.keyring)
            and not (k == "flatpak" and not ("flatpak" in sources and self.flatpak_n))
            and not (
                k in ("sync", "resolve", "download", "install", "hooks")
                and not ("pacman" in sources and self.pac_n)
            )
        ]
        self.r = {
            "id": rid,
            "dir": self.dir,
            "status": "auth",
            "phase": keys[0] if keys else "",
            "phases": [
                {"key": k, "label": dict(PHASES)[k], "state": "todo", "detail": ""}
                for k in keys
            ],
            "pkgIndex": 0,
            "pkgTotal": self.pac_n,
            "dlDone": 0,
            "dlTotal": self.pac_n,
            "current": "",
            "percent": 0,
            "prompt": None,
            "promptN": 0,
            "canStop": True,
            "startedAt": now(),
            "endedAt": 0,
            "beat": now(),
            "warnings": [],
            "pacnew": [],
            "error": "",
            "errorKind": "",
            "logTail": [],
            "restart": "",
            "updated": 0,
            "downloadBytes": st.get("downloadBytes", 0),
        }
        self.pos = 0
        self.lines = []
        self.asked = None
        self.asked_at = 0
        self.installed = []

    # -- bookkeeping --
    def save(self):
        self.r["beat"] = now()
        self.r["logTail"] = self.lines[-14:]
        self.r["percent"] = self.percent()
        write_json(os.path.join(self.dir, "run.json"), self.r)

    def ph(self, key):
        for p in self.r["phases"]:
            if p["key"] == key:
                return p
        return {"key": key, "state": "todo", "detail": ""}

    def enter(self, key, detail=None):
        seen = False
        for p in self.r["phases"]:
            if p["key"] == key:
                seen = True
                p["state"] = "active"
                if detail is not None:
                    p["detail"] = detail
            elif not seen and p["state"] != "done":
                p["state"] = "done"
        if seen:
            self.r["phase"] = key

    def percent(self):
        total = sum(WEIGHT[p["key"]] for p in self.r["phases"]) or 1
        got = 0.0
        for p in self.r["phases"]:
            w = WEIGHT[p["key"]]
            if p["state"] == "done":
                got += w
            elif p["state"] == "active":
                if p["key"] == "download" and self.r["dlTotal"]:
                    got += w * min(1, self.r["dlDone"] / self.r["dlTotal"])
                elif p["key"] == "install" and self.r["pkgTotal"]:
                    got += w * min(1, self.r["pkgIndex"] / self.r["pkgTotal"])
                elif p["key"] == "hooks" and self.r.get("hookTotal"):
                    got += w * min(1, self.r.get("hookIndex", 0) / self.r["hookTotal"])
        return int(round(100 * got / total))

    def note_answer(self, text, value, who):
        with open(os.path.join(self.dir, "answers.log"), "a", encoding="utf-8") as f:
            f.write(
                "%s  %s\n    -> %s (%s)\n"
                % (
                    datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    text.strip(),
                    value,
                    who,
                )
            )

    # -- pacman output --
    def feed(self, line):
        s = line.strip()
        if not s:
            return
        self.lines.append(line.rstrip())
        r = self.r
        if s.startswith(":: Synchronizing package databases"):
            self.enter("sync")
        elif s.startswith(":: Starting full system upgrade"):
            self.enter("resolve")
        elif s.startswith("Packages ("):
            m = re.match(r"Packages \((\d+)\)", s)
            if m:
                r["pkgTotal"] = r["dlTotal"] = int(m.group(1))
        elif s.startswith("Total Download Size:"):
            self.ph("download")["detail"] = s.split(":", 1)[1].strip()
        elif s.startswith(":: Retrieving packages"):
            self.enter("download")
        elif s.endswith(" downloading...") and r["phase"] == "download":
            r["dlDone"] += 1
            r["current"] = s[: -len(" downloading...")]
        elif re.match(
            r"^(checking keys in keyring|checking package integrity|loading package files"
            r"|checking for file conflicts|checking available disk space)",
            s,
        ):
            r["current"] = s.rstrip(".")
        elif s.startswith(":: Processing package changes"):
            self.enter("install")
            r["canStop"] = False
        elif re.match(
            r"^(\(\s*\d+/\d+\)\s+)?(upgrading|installing|reinstalling|downgrading|removing) \S+",
            s,
        ):
            m = re.match(r"^(?:\(\s*(\d+)/(\d+)\)\s+)?(\w+) (\S+?)(\.\.\.)?$", s)
            if m:
                if r["phase"] != "install":
                    self.enter("install")
                    r["canStop"] = False
                r["pkgIndex"] = int(m.group(1)) if m.group(1) else r["pkgIndex"] + 1
                if m.group(2):
                    r["pkgTotal"] = int(m.group(2))
                r["current"] = m.group(4)
                self.installed.append(m.group(4))
                self.ph("install")["detail"] = "%d / %d" % (
                    r["pkgIndex"],
                    r["pkgTotal"],
                )
        elif s.startswith(":: Running post-transaction hooks"):
            self.enter("hooks")
        elif r["phase"] == "hooks" and re.match(r"^\(\s*\d+/\d+\)", s):
            m = re.match(r"^\(\s*(\d+)/(\d+)\)\s*(.*)$", s)
            r["hookIndex"], r["hookTotal"] = int(m.group(1)), int(m.group(2))
            r["current"] = m.group(3).rstrip(".")
            self.ph("hooks")["detail"] = "%d / %d" % (r["hookIndex"], r["hookTotal"])
        elif s.startswith("warning:"):
            m = re.match(r"warning: (\S+) installed as (\S+\.pacnew)", s)
            if m:
                r["pacnew"].append({"file": m.group(1), "new": m.group(2)})
            m2 = re.match(r"warning: (\S+) saved as (\S+\.pacsave)", s)
            if m2:
                r["pacnew"].append({"file": m2.group(1), "new": m2.group(2)})
            r["warnings"].append(s)
            del r["warnings"][:-30]
        elif s.startswith("error:"):
            r["error"] = (r["error"] + "\n" + s).strip() if r["error"] else s
            low = s.lower()
            if "unable to lock database" in low:
                r["errorKind"] = "lock"
            elif "conflicting files" in low or "exists in filesystem" in low:
                r["errorKind"] = "conflict"
            elif "failed retrieving file" in low or "failed to retrieve" in low:
                r["errorKind"] = r["errorKind"] or "mirror"
            elif (
                "not enough free disk space" in low
                or "partition" in low
                and "full" in low
            ):
                r["errorKind"] = "disk"
        elif "exists in filesystem" in s:
            r["error"] = (r["error"] + "\n" + s).strip()
            r["errorKind"] = "conflict"
        elif s == "there is nothing to do":
            r["current"] = "nothing to do"

    def pump(self):
        """Read new pacman.log lines; returns True when anything changed."""
        path = os.path.join(self.dir, "pacman.log")
        try:
            with open(path, "rb") as f:
                f.seek(self.pos)
                data = f.read()
        except OSError:
            return False
        if not data:
            return False
        cut = data.rfind(b"\n")
        if cut < 0:
            return False
        self.pos += cut + 1
        for line in data[:cut].decode("utf-8", "replace").split("\n"):
            self.feed(line)
        return True

    def prompt(self):
        """Handle the helper's `pending` file (an unterminated line = a question)."""
        raw = read_text(os.path.join(self.dir, "pending"), 4096)
        r = self.r
        if not raw.strip():
            if r["status"] == "asking":
                r["status"], r["prompt"] = "running", None
                self.asked = None
                return True
            self.asked = None
            return False
        if raw != self.asked:
            self.asked, self.asked_at = raw, time.time()
            return False
        if r["prompt"] and r["prompt"].get("raw") == raw:
            return False
        if os.path.exists(os.path.join(self.dir, "answer")):
            return False  # an answer is on its way to pacman
        if time.time() - self.asked_at < (0.4 if PROMPT_END.search(raw) else 4):
            return False
        if re.search(r"Proceed with installation\? \[Y/n\]", raw):
            # the summary was shown before the user pressed Update — that click is the yes
            self.note_answer(raw, "y", "your Update click")
            self.send("y")
            self.asked = None
            return False
        card = describe_prompt(raw, self.lines)
        r["promptN"] += 1
        card.update(raw=raw.strip(), n=r["promptN"])
        r["prompt"], r["status"] = card, "asking"
        if self.r["phase"] in ("sync", "keyring"):
            self.enter("resolve")
        self.ph("resolve")["detail"] = "%d question%s" % (
            r["promptN"],
            "" if r["promptN"] == 1 else "s",
        )
        return True

    def send(self, value):
        tmp = os.path.join(self.dir, ".answer.tmp")
        with open(tmp, "w") as f:
            f.write(value)
        os.replace(tmp, os.path.join(self.dir, "answer"))

    # -- the run --
    def helper_cmd(self):
        helper = os.path.join(HERE, "updatehelper.py")
        fake = os.environ.get("PILL_UPDATE_FAKE")
        if fake:
            return [sys.executable, helper, self.dir, str(os.getuid()), "fake", fake]
        return [
            "pkexec",
            "/usr/bin/python3",
            helper,
            self.dir,
            str(os.getuid()),
            "keyring" if self.keyring else "full",
        ]

    def go(self):
        r = self.r
        self.save()
        rc = 0
        if "pacman" in self.sources and self.pac_n:
            try:
                proc = subprocess.Popen(
                    self.helper_cmd(),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    text=True,
                )
            except OSError as e:
                return self.finish("failed", "could not start pkexec: %s" % e)
            log = os.path.join(self.dir, "pacman.log")
            while True:
                rc = proc.poll()
                changed = False
                if r["status"] == "auth" and os.path.exists(log):
                    r["status"] = "running"
                    self.enter(r["phases"][0]["key"])
                    changed = True
                changed = self.pump() or changed
                changed = self.prompt() or changed
                if not r.get("stopped") and os.path.exists(os.path.join(self.dir, "stopped")):
                    r["stopped"] = changed = True
                if changed or now() - r["beat"] >= 10:
                    self.save()
                if rc is not None:
                    break
                time.sleep(0.15)
            self.pump()
            err = (proc.stderr.read() or "").strip()
            code = read_text(os.path.join(self.dir, "exit")).strip()
            if code == "":
                # the helper never ran: the password dialog was dismissed or failed
                if (
                    rc in (126, 127)
                    or "dismissed" in err.lower()
                    or "not authorized" in err.lower()
                ):
                    return self.finish("cancelled", "")
                return self.finish("failed", err or "the update helper did not start")
            if code != "0":
                if r.get("stopped"):
                    return self.finish("stopped", "")
                return self.finish(
                    "failed", r["error"] or "pacman exited with status %s" % code
                )
            for p in r["phases"]:
                if p["key"] != "flatpak":
                    p["state"] = "done"
        if "flatpak" in self.sources and self.flatpak_n and shutil.which("flatpak"):
            r["status"] = "running"
            self.enter(
                "flatpak",
                "%d app%s" % (self.flatpak_n, "" if self.flatpak_n == 1 else "s"),
            )
            r["current"] = "flatpak"
            self.save()
            with open(os.path.join(self.dir, "flatpak.log"), "w") as f:
                frc = subprocess.call(
                    ["flatpak", "update", "-y", "--noninteractive"],
                    stdin=subprocess.DEVNULL,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                    env=ENV_C,
                )
            if frc != 0:
                r["warnings"].append(
                    "flatpak update exited with status %d (see flatpak.log)" % frc
                )
            self.ph("flatpak")["state"] = "done"
        self.finish("done", "")

    def finish(self, status, error):
        r = self.r
        r.update(status=status, endedAt=now(), prompt=None, canStop=False, current="")
        if error:
            r["error"] = error
        if status == "cancelled":
            # nothing happened — leave no trace in the logbook
            shutil.rmtree(self.dir, ignore_errors=True)
            return
        level = ""
        reasons = []
        for name in self.installed:
            lv = restart_of(name)
            if lv:
                reasons.append({"name": name, "level": lv})
                if RESTART_RANK[lv] > RESTART_RANK[level]:
                    level = lv
        # ground truth for the kernel: its modules for the running release are gone
        if self.installed and not os.path.isdir(
            "/usr/lib/modules/" + os.uname().release
        ):
            level = "reboot"
            if not any(x["level"] == "reboot" for x in reasons):
                reasons.append({"name": "linux", "level": "reboot"})
        r["restart"] = level
        r["restartReasons"] = reasons[:12]
        r["updated"] = len(self.installed)
        self.save()
        write_json(
            os.path.join(self.dir, "summary.json"),
            {
                "id": self.rid,
                "status": status,
                "startedAt": r["startedAt"],
                "endedAt": r["endedAt"],
                "updated": r["updated"],
                "packages": self.installed,
                "restart": level,
                "restartReasons": r["restartReasons"],
                "warnings": r["warnings"],
                "pacnew": r["pacnew"],
                "error": r["error"],
                "errorKind": r["errorKind"],
                "flatpak": self.flatpak_n if status == "done" else 0,
            },
        )
        if level:
            st = load_state()
            cur = (st.get("pendingRestart") or {}).get("level", "")
            if RESTART_RANK[level] >= RESTART_RANK[cur]:
                st["pendingRestart"] = {
                    "level": level,
                    "reasons": r["restartReasons"],
                    "since": now(),
                    "bootId": boot_id(),
                    "session": session_id(),
                    "run": self.rid,
                }
                save_state(st)
        for d in run_dirs()[KEEP_RUNS:]:
            shutil.rmtree(d, ignore_errors=True)
        if status in ("done", "stopped", "failed") and not os.environ.get(
            "PILL_UPDATE_FAKE"
        ):
            do_check(self.sources)


# ---- snapshot for the pill --------------------------------------------------
SOURCE_META = [
    ("pacman", "pacman", "official repos · asks for your password", "deployed_code"),
    ("flatpak", "flatpak", "apps · no password", "apps"),
    (
        "aur",
        "aur",
        "builds from source, can ask questions · opens in a terminal",
        "construction",
    ),
    ("firmware", "firmware", "fwupd device firmware", "memory"),
]


def clear_restart_if_done(st):
    pr = st.get("pendingRestart")
    if not pr:
        return False
    if pr.get("bootId") and pr["bootId"] != boot_id():
        st["pendingRestart"] = None
        return True
    if (
        pr.get("level") == "relogin"
        and pr.get("session")
        and session_id()
        and pr["session"] != session_id()
    ):
        st["pendingRestart"] = None
        return True
    return False


def history(limit_checks=10):
    out = []
    for d in run_dirs()[:KEEP_RUNS]:
        rid = os.path.basename(d)
        s = read_json(os.path.join(d, "summary.json"), None)
        r = read_json(os.path.join(d, "run.json"), None) or {}
        if s:
            out.append(
                {
                    "kind": "update",
                    "id": rid,
                    "at": s.get("startedAt", 0),
                    "status": s.get("status"),
                    "updated": s.get("updated", 0),
                    "seconds": max(0, s.get("endedAt", 0) - s.get("startedAt", 0)),
                    "restart": s.get("restart", ""),
                    "restartReasons": s.get("restartReasons", []),
                    "warnings": s.get("warnings", [])[-8:],
                    "pacnew": s.get("pacnew", []),
                    "error": s.get("error", ""),
                    "errorKind": s.get("errorKind", ""),
                    "flatpak": s.get("flatpak", 0),
                    "dir": d,
                    "phases": r.get("phases", []),
                    "logTail": r.get("logTail", []),
                    "pkgIndex": r.get("pkgIndex", 0),
                    "pkgTotal": r.get("pkgTotal", 0),
                }
            )
    checks = []
    for line in read_text(state_path("checks.jsonl")).splitlines()[-limit_checks:]:
        try:
            c = json.loads(line)
        except ValueError:
            continue
        c["kind"] = "check"
        c["id"] = "check-%d" % c.get("at", 0)
        checks.append(c)
    out += checks
    out.sort(key=lambda e: e.get("at", 0), reverse=True)
    return out


def snapshot(sources, checking=False):
    st = load_state()
    if clear_restart_if_done(st):
        save_state(st)
    src = st.get("sources") or {}
    rows = []
    for key, label, desc, icon in SOURCE_META:
        s = src.get(key) or {}
        avail = s.get("available", key in ("pacman", "flatpak"))
        if key == "aur" and s.get("helper"):
            label = "aur · " + s["helper"]
        if key == "firmware" and not avail:
            desc = "fwupd not installed · appears if you add it"
        rows.append(
            {
                "key": key,
                "label": label,
                "desc": s.get("error") or desc,
                "icon": icon,
                "count": s.get("count", 0),
                "available": bool(avail),
                "enabled": key in sources and bool(avail),
                "togglable": key in ("pacman", "flatpak") and bool(avail),
                "failed": bool(s.get("error")),
            }
        )
    pkgs = st.get("packages") or []
    included = [p for p in pkgs if p["source"] in sources]
    counts = {"required": 0, "recommended": 0, "optional": 0}
    for p in included:
        counts[p.get("cls", "optional")] += 1
    counts["total"] = len(included)
    checked = st.get("checkedAt", 0)
    return {
        "ready": True,
        # a check that died mid-way must not leave the page "checking…" forever
        "checking": bool(checking or (st.get("checking")
                                      and now() - st.get("checkingSince", 0) < 300)),
        "checkedAt": checked * 1000,
        "nextAt": (checked + INTERVAL) * 1000 if checked else 0,
        "error": st.get("error", ""),
        "level": st.get("level", "none") if included else "none",
        "counts": counts,
        "packages": pkgs,
        "sources": rows,
        "hold": st.get("hold") or [],
        "restart": st.get("restart", ""),
        "downloadBytes": st.get("downloadBytes", 0),
        "daysBehind": st.get("daysBehind", 0),
        "pendingRestart": st.get("pendingRestart"),
        "run": active_run(),
        "history": history(),
        "dir": STATE,
        "aurHelper": os.path.basename(aur_helper() or ""),
    }


def demo_snapshot():
    t = now()
    pk = [
        (
            "openssl",
            "3.6.1-1",
            "3.6.2-1",
            "required",
            "",
            {"id": "AVG-2901", "severity": "High"},
        ),
        (
            "firefox",
            "158.0-1",
            "158.0.2-1",
            "required",
            "",
            {"id": "AVG-2903", "severity": "Critical"},
        ),
        ("linux", "7.2.14.arch1-1", "7.2.16.arch1-1", "recommended", "reboot", None),
        ("systemd", "260.1-1", "260.2-1", "recommended", "reboot", None),
        ("mesa", "1:26.2.0-1", "1:26.2.1-1", "recommended", "relogin", None),
        ("kwin", "6.7.1-1", "6.7.2-1", "recommended", "relogin", None),
        ("pipewire", "1:1.6.2-1", "1:1.6.3-1", "recommended", "relogin", None),
        ("ripgrep", "15.1.0-1", "15.2.0-1", "optional", "", None),
        ("imagemagick", "7.1.2.8-1", "7.1.2.9-1", "optional", "", None),
    ]
    pkgs = [
        {
            "name": n,
            "old": o,
            "new": v,
            "cls": c,
            "restart": r,
            "source": "pacman",
            "repo": "extra",
            "size": 9 << 20,
            **({"advisory": a} if a else {}),
        }
        for n, o, v, c, r, a in pk
    ]
    return {
        "ready": True,
        "checking": False,
        "checkedAt": (t - 1800) * 1000,
        "nextAt": (t + INTERVAL - 1800) * 1000,
        "error": "",
        "level": "required",
        "counts": {"required": 2, "recommended": 5, "optional": 2, "total": 9},
        "packages": pkgs,
        "hold": [],
        "restart": "reboot",
        "downloadBytes": 612 << 20,
        "daysBehind": 9,
        "pendingRestart": None,
        "run": None,
        "dir": STATE,
        "aurHelper": "yay",
        "sources": [
            {
                "key": k,
                "label": lb,
                "desc": d,
                "icon": ic,
                "count": c,
                "available": True,
                "enabled": k in SOURCES,
                "togglable": k in ("pacman", "flatpak"),
                "failed": False,
            }
            for (k, lb, d, ic), c in zip(SOURCE_META, (9, 4, 2, 0))
        ],
        "history": [
            {
                "kind": "check",
                "id": "check-1",
                "at": t - 1800,
                "total": 9,
                "level": "required",
                "required": 2,
                "recommended": 5,
                "optional": 2,
                "bytes": 612 << 20,
                "restart": "reboot",
                "hold": 0,
            },
            {
                "kind": "update",
                "id": "demo",
                "at": t - 9 * 86400,
                "status": "done",
                "updated": 112,
                "seconds": 372,
                "restart": "reboot",
                "restartReasons": [],
                "warnings": [],
                "pacnew": [],
                "error": "",
                "errorKind": "",
                "flatpak": 3,
                "dir": STATE,
                "phases": [],
                "logTail": [":: Running post-transaction hooks..."],
                "pkgIndex": 112,
                "pkgTotal": 112,
            },
        ],
    }


# ---- watcher ----------------------------------------------------------------
def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def notify_events(snap, st):
    """Decide which one-shot notifications are due; mutates st['notified']."""
    n = st.setdefault("notified", {})
    out = []
    rank = {"none": 0, "optional": 1, "recommended": 2, "required": 3}
    level = snap["level"]
    seen = n.get("level", "none")
    advs = sorted(
        {
            p["advisory"]["id"]
            for p in snap["packages"]
            if p.get("advisory") and p.get("cls") == "required"
        }
    )
    new_advs = [a for a in advs if a not in (n.get("advisories") or [])]
    if level == "required" and (rank[seen] < 3 or new_advs):
        names = [p["name"] for p in snap["packages"] if p.get("cls") == "required"]
        out.append(
            {
                "kind": "required",
                "count": len(names),
                "names": names[:4],
                "total": snap["counts"]["total"],
            }
        )
    elif level == "recommended" and rank[seen] < 2:
        names = [p["name"] for p in snap["packages"] if p.get("cls") == "recommended"]
        out.append(
            {
                "kind": "recommended",
                "count": snap["counts"]["total"],
                "names": names[:3],
                "restart": snap["restart"],
            }
        )
    if rank[level] != rank[seen] or new_advs:
        n["level"] = level
        n["advisories"] = advs
    links = [h["link"] for h in snap["hold"]]
    fresh = [h for h in snap["hold"] if h["link"] not in (n.get("news") or [])]
    if fresh and snap["counts"]["total"]:
        out.append(
            {
                "kind": "hold",
                "title": fresh[0]["title"],
                "link": fresh[0]["link"],
                "count": len(snap["hold"]),
            }
        )
        n["news"] = links
    runs = n.setdefault("runs", {})
    r = snap["run"]
    if r and r["status"] == "asking" and r.get("prompt"):
        key = "%s#%d" % (r["id"], r["prompt"]["n"])
        if runs.get("ask") != key:
            runs["ask"] = key
            out.append({"kind": "ask", "run": r["id"], "prompt": r["prompt"]})
    for h in snap["history"][:3]:
        if h["kind"] != "update" or h["status"] not in ("done", "failed"):
            continue
        if h["id"] in (runs.get("ended") or []) or now() - h["at"] - h["seconds"] > 600:
            continue
        runs["ended"] = ([h["id"]] + (runs.get("ended") or []))[:10]
        out.append(
            {
                "kind": h["status"],
                "run": h["id"],
                "updated": h["updated"],
                "seconds": h["seconds"],
                "restart": h["restart"],
                "error": h["error"],
                "pkgIndex": h["pkgIndex"],
                "pkgTotal": h["pkgTotal"],
            }
        )
    return out


def watch(sources):
    if os.environ.get("DEMO"):
        emit(demo_snapshot())
        while True:
            time.sleep(3600)
    os.makedirs(STATE, exist_ok=True)
    started = now()
    last_hash = last_run = ""
    checker = None
    while True:
        st = load_state()
        req = state_path("check-request")
        wanted = os.path.exists(req)
        checked = st.get("checkedAt", 0)
        attempt = st.get("lastAttempt", 0)
        due = (
            now() - checked >= INTERVAL
            and now() - attempt >= RETRY
            and now() - started >= 45
        )
        busy = checker is not None and checker.poll() is None
        if (wanted or due) and not busy and not active_run():
            try:
                os.unlink(req)
            except OSError:
                pass
            checker = subprocess.Popen(
                [
                    sys.executable,
                    os.path.abspath(__file__),
                    "--dir",
                    STATE,
                    "--sources",
                    ",".join(sources),
                    "check",
                    "--now",
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            busy = True
        snap = snapshot(sources, checking=busy)
        # the package list is large; while an update runs only `run` changes, so
        # send just that (a small line) instead of the whole snapshot each tick
        base = dict(snap, run=None)
        h = hashlib.md5(json.dumps(base, sort_keys=True).encode()).hexdigest()
        rh = hashlib.md5(json.dumps(snap["run"], sort_keys=True).encode()).hexdigest()
        changed = h != last_hash or rh != last_run
        if h != last_hash:
            emit(snap)
        elif rh != last_run:
            emit({"event": "run", "run": snap["run"]})
        last_hash, last_run = h, rh
        if changed and not busy:
            st = load_state()
            events = notify_events(snap, st)
            save_state(st)
            for e in events:
                emit(dict(e, event="notify"))
        time.sleep(0.35 if snap["run"] else 1.5)


# ---- commands ---------------------------------------------------------------
def cmd_start(sources):
    if active_run():
        return emit({"ok": False, "error": "an update is already running"})
    rid = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    d = state_path(rid)
    n = 1
    while os.path.exists(d):
        n += 1
        d = state_path("%s-%d" % (rid, n))
    rid = os.path.basename(d)
    os.makedirs(d)
    write_json(
        os.path.join(d, "run.json"),
        {
            "id": rid,
            "dir": d,
            "status": "auth",
            "phases": [],
            "startedAt": now(),
            "beat": now(),
            "percent": 0,
            "prompt": None,
            "logTail": [],
            "canStop": True,
        },
    )
    cmd = [
        sys.executable,
        os.path.abspath(__file__),
        "--dir",
        STATE,
        "--sources",
        ",".join(sources),
        "orchestrate",
        rid,
    ]
    ok = False
    if shutil.which("systemd-run") and not os.environ.get("PILL_UPDATE_FAKE"):
        # its own transient unit: a pill reload (or a Qt upgrade restarting the
        # shell) cannot take the transaction down with it
        env = []
        for k in (
            "PATH",
            "HOME",
            "XDG_STATE_HOME",
            "XDG_CACHE_HOME",
            "XDG_RUNTIME_DIR",
            "XDG_SESSION_ID",
            "DBUS_SESSION_BUS_ADDRESS",
            "WAYLAND_DISPLAY",
            "DISPLAY",
        ):
            if os.environ.get(k):
                env.append("--setenv=%s=%s" % (k, os.environ[k]))
        rc, _, _ = run(
            [
                "systemd-run",
                "--user",
                "--collect",
                "--quiet",
                "--unit=pill-update-" + re.sub(r"[^A-Za-z0-9]", "-", rid),
            ]
            + env
            + cmd,
            timeout=15,
            env=os.environ,
        )
        ok = rc == 0
    if not ok:
        ok = spawn_detached(cmd)
    if not ok:
        shutil.rmtree(d, ignore_errors=True)
    emit({"ok": ok, "id": rid})


def cmd_answer(rid, value):
    r = run_json(rid)
    if not r or r.get("status") != "asking" or not r.get("prompt"):
        return emit({"ok": False, "error": "that run is not waiting for an answer"})
    if not re.match(r"^[yn]$|^\d{1,3}$", value):
        return emit({"ok": False, "error": "answers are y, n or a number"})
    d = state_path(rid)
    with open(os.path.join(d, "answers.log"), "a", encoding="utf-8") as f:
        f.write(
            "%s  %s\n    -> %s (you)\n"
            % (
                datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                r["prompt"]["raw"],
                value,
            )
        )
    tmp = os.path.join(d, ".answer.tmp")
    with open(tmp, "w") as f:
        f.write(value)
    os.replace(tmp, os.path.join(d, "answer"))
    emit({"ok": True})


def cmd_stop(rid):
    r = run_json(rid)
    if not r or r.get("status") not in ("running", "asking", "auth"):
        return emit({"ok": False, "error": "that run is not active"})
    if not r.get("canStop", False):
        return emit(
            {
                "ok": False,
                "error": "pacman is already installing; stopping now would be unsafe",
            }
        )
    open(state_path(rid, "stopped"), "w").close()
    open(state_path(rid, "stop"), "w").close()
    emit({"ok": True})


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


def cmd_terminal(what):
    r = active_run()
    if r and r.get("canStop", False):
        cmd_stop_quiet(r["id"])
        time.sleep(1.2)
    h = aur_helper()
    if what == "aur":
        inner = (h or "yay") + " -Sua"
    elif h and os.path.basename(h) == "yay":
        inner = "yay -Syu --repo"
    elif h:
        inner = "paru -Syu --repo"
    else:
        inner = "sudo pacman -Syu"
    cmd = terminal_cmd(inner)
    if not cmd:
        return emit({"ok": False, "error": "no terminal emulator found"})
    ok = spawn_detached(cmd)
    if ok:
        os.makedirs(STATE, exist_ok=True)
        st = load_state()
        st["handedOver"] = now()
        save_state(st)
    emit({"ok": ok, "command": inner})


def cmd_stop_quiet(rid):
    r = run_json(rid)
    if r:
        open(state_path(rid, "stopped"), "w").close()
        open(state_path(rid, "stop"), "w").close()


def cmd_open(rid, what):
    d = state_path(rid) if rid and rid != "-" else STATE
    if not os.path.isdir(d):
        return emit({"ok": False, "error": "no such run"})
    log = os.path.join(d, "pacman.log")
    if what == "log":
        target = log if os.path.exists(log) else d
        ok = spawn_detached(["xdg-open", target])
    elif shutil.which("dolphin") and os.path.exists(log):
        ok = spawn_detached(["dolphin", "--select", log])
    else:
        ok = spawn_detached(["xdg-open", d])
    emit({"ok": ok})


def main():
    global STATE, SOURCES
    args = sys.argv[1:]
    while args and args[0] in ("--dir", "--sources"):
        if len(args) < 2:
            break
        if args[0] == "--dir" and args[1]:
            STATE = os.path.abspath(os.path.expanduser(args[1]))
        elif args[0] == "--sources":
            SOURCES = [s for s in args[1].split(",") if s]
        args = args[2:]
    cmd = args[0] if args else "snapshot"
    rest = args[1:]

    # DEMO mode (safe screen recording): fixed fake data, every action is a no-op
    if os.environ.get("DEMO") and cmd != "watch":
        return emit(demo_snapshot() if cmd == "snapshot" else {"ok": True})

    if cmd == "watch":
        watch(SOURCES)
    elif cmd == "snapshot":
        emit(snapshot(SOURCES))
    elif cmd == "check":
        if "--now" in rest:
            st = do_check(SOURCES)
            emit({"ok": not st.get("error"), "error": st.get("error", "")})
        else:
            os.makedirs(STATE, exist_ok=True)
            open(state_path("check-request"), "w").close()
            emit({"ok": True})
    elif cmd == "start":
        cmd_start(SOURCES)
    elif cmd == "orchestrate" and rest:
        Runner(rest[0], SOURCES).go()
    elif cmd == "answer" and len(rest) >= 2:
        cmd_answer(rest[0], rest[1])
    elif cmd == "stop" and rest:
        cmd_stop(rest[0])
    elif cmd == "terminal":
        cmd_terminal(rest[0] if rest else "repo")
    elif cmd == "ack-news":
        st = load_state()
        st["ackedNews"] = (
            (st.get("ackedNews") or []) + [h["link"] for h in st.get("hold") or []]
        )[-40:]
        st["hold"] = []
        save_state(st)
        emit({"ok": True})
    elif cmd == "ack-restart":
        st = load_state()
        st["pendingRestart"] = None
        save_state(st)
        emit({"ok": True})
    elif cmd == "open" and len(rest) >= 2:
        cmd_open(rest[0], rest[1])
    else:
        emit({"ok": False, "error": "unknown command"})
        sys.exit(2)


if __name__ == "__main__":
    main()
