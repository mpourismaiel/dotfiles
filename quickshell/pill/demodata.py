#!/usr/bin/env python3
# demodata.py — deterministic fake-data generator for the pill's DEMO mode.
#
# When the pill is launched with DEMO=true in its environment, every data bridge
# (orgbridge / gcalbridge / hledgerbridge / gitbridge / clipbridge) inherits the
# variable through the QML Process that spawns it, checks it at the top of main(),
# and hands the whole invocation to demodata.run(kind, argv) instead of touching
# the user's real Emacs / Google / hledger / git / cliphist data. This makes the
# pill safe to screen-record: nothing personal is ever read.
#
# Everything here is a PURE FUNCTION of the calendar date (and, for relative
# views, of today's date). The same day always yields the same agenda, the same
# calendar events and the same finance transactions; the clipboard and the online
# accounts are fixed. Determinism comes from seeding a PRNG on a stable key
# (namespace + date) — no wall-clock, no randomness that changes between runs — so
# a recording can be paused, replayed and re-shot and the pill looks identical.
#
# The output of each command matches its real bridge's schema byte-for-byte (see
# each bridge header). demodata never imports the bridges; it re-implements just
# the shapes it needs.
import sys
import os
import json
import time
import hashlib
import random
import zlib
import struct
import datetime

# --------------------------------------------------------------------------- #
#  Determinism helpers
# --------------------------------------------------------------------------- #

_FIXED_TODAY = os.environ.get("DEMO_DATE", "")  # optional override for testing


def today():
    """The demo's 'now'. Real today, unless DEMO_DATE pins it (handy for shots)."""
    if _FIXED_TODAY:
        try:
            return datetime.date.fromisoformat(_FIXED_TODAY)
        except ValueError:
            pass
    return datetime.date.today()


def rng(*parts):
    """A PRNG seeded on a stable key so the same inputs always draw the same
    numbers, across processes and runs."""
    key = "|".join(str(p) for p in parts)
    seed = int.from_bytes(hashlib.sha256(key.encode()).digest()[:8], "big")
    return random.Random(seed)


def _pick(r, seq):
    return seq[r.randrange(len(seq))]


def iso(d):
    return d.isoformat()


def days_between(a, b):
    """[a, b] inclusive as date objects."""
    a = datetime.date.fromisoformat(a) if isinstance(a, str) else a
    b = datetime.date.fromisoformat(b) if isinstance(b, str) else b
    out, d = [], a
    while d <= b:
        out.append(d)
        d += datetime.timedelta(days=1)
    return out


def first_of_month(d):
    return datetime.date(d.year, d.month, 1)


def add_months(d, n):
    m = d.month - 1 + n
    y = d.year + m // 12
    m = m % 12 + 1
    leap = y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
    dim = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    return datetime.date(y, m, min(d.day, dim))


# =========================================================================== #
#  CLIPBOARD  (clipbridge.py: list)
# =========================================================================== #

# Fixed, believable-but-fake clipboard history, newest first. IDs descend so the
# menu's "newest" ordering is obvious. Two entries are images, generated as real
# PNGs into the cliphist cache dir so the preview actually renders.
_CLIP_CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell-pill", "clip",
)

_CLIP_TEXT = [
    "https://github.com/quickshell-mirror/quickshell",
    "def fib(n):\n    a, b = 0, 1\n    for _ in range(n):\n        a, b = b, a + b\n    return a",
    "The quick brown fox jumps over the lazy dog.",
    "git rebase -i HEAD~3",
    "Meeting moved to 3pm — conference room B on the 4th floor.",
    "rgb(122, 162, 247)",
    "npm install --save-dev vite@latest",
    "Reminder: pick up dry cleaning and book the dentist for next week.",
    "SELECT id, name FROM users WHERE active = true ORDER BY created_at DESC;",
    "€1,240.00",
    "a1b2c3d4  fix: return focus to previous window after closing overlay",
    "https://news.ycombinator.com/",
]


def _write_png(path, w, h, pixel):
    """Minimal RGB PNG encoder (no Pillow). `pixel(x, y) -> (r, g, b)`."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (None) per scanline
        for x in range(w):
            r, g, b = pixel(x, y)
            raw += bytes((r & 255, g & 255, b & 255))

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def _ensure_clip_images():
    """Create the two demo clipboard images if missing. Returns their specs."""
    try:
        os.makedirs(_CLIP_CACHE, exist_ok=True)
    except OSError:
        return []
    specs = []

    # 1: a soft diagonal gradient (mock "screenshot")
    p1 = os.path.join(_CLIP_CACHE, "demo-1.png")
    w1, h1 = 320, 200
    if not os.path.exists(p1):
        def px1(x, y):
            t = (x / w1 + y / h1) / 2
            return (int(60 + 120 * t), int(90 + 90 * (1 - t)), int(180 + 60 * t))
        try:
            _write_png(p1, w1, h1, px1)
        except OSError:
            pass
    specs.append({"path": p1, "w": w1, "h": h1})

    # 2: concentric rings (mock logo / graphic)
    p2 = os.path.join(_CLIP_CACHE, "demo-2.png")
    w2, h2 = 240, 240
    if not os.path.exists(p2):
        def px2(x, y):
            dx, dy = x - w2 / 2, y - h2 / 2
            ring = int((dx * dx + dy * dy) ** 0.5) // 12
            return (245, 200, 70) if ring % 2 else (36, 32, 28)
        try:
            _write_png(p2, w2, h2, px2)
        except OSError:
            pass
    specs.append({"path": p2, "w": w2, "h": h2})
    return specs


def clip_list():
    imgs = _ensure_clip_images()
    out = []
    nid = 1000
    # newest few text entries, then an image, then more text, then an image
    order = [("t", 0), ("t", 1), ("t", 2), ("i", 0), ("t", 3), ("t", 4),
             ("t", 5), ("t", 6), ("i", 1), ("t", 7), ("t", 8), ("t", 9),
             ("t", 10), ("t", 11)]
    for kind, idx in order:
        if kind == "t":
            out.append({"id": nid, "kind": "text",
                        "text": _CLIP_TEXT[idx].replace("\n", " ").strip()[:300],
                        "images": 0})
        elif idx < len(imgs) and os.path.exists(imgs[idx]["path"]):
            out.append({"id": nid, "kind": "image", "w": imgs[idx]["w"],
                        "h": imgs[idx]["h"], "path": imgs[idx]["path"]})
        nid -= 1
    return out


# =========================================================================== #
#  ONLINE ACCOUNTS  (gcalbridge.py: accounts)
# =========================================================================== #

_ACCOUNTS = [
    {"id": "kde-100241", "provider": "google", "label": "demo.user@gmail.com",
     "source": "kde", "removable": False},
    {"id": "g-3fa9c2b71e", "provider": "google", "label": "demo.work@company.com",
     "source": "pill", "removable": True},
    {"id": "p-7d2e04a9f5", "provider": "proton", "label": "Proton — Personal",
     "source": "pill", "removable": True},
]

# Account/calendar identity reused by the calendar-event generator so the two
# features agree on names + colours.
_CAL_GOOGLE = "demo.user@gmail.com"
_CAL_WORK = "demo.work@company.com"


def gcal_accounts():
    return {"accounts": [dict(a) for a in _ACCOUNTS], "errors": []}


# =========================================================================== #
#  CALENDAR EVENTS  (gcalbridge.py: fetch / read)
# =========================================================================== #

_PEOPLE = ["Sofia Martinez", "Liam Chen", "Amara Okafor", "Noah Weber",
           "Priya Nair", "Mateo Rossi", "Hannah Kim", "Lucas Silva",
           "Yuki Tanaka", "Emma Novak"]

# Recurring weekday meetings — the backbone that makes "each day has events"
# obvious. (weekday 0=Mon .. 4=Fri)
_STANDUP = {"summary": "Daily standup", "cal": "Work", "acct": _CAL_WORK,
            "color": "#4285f4", "start": "09:30", "end": "09:45",
            "loc": "Meet", "join": "https://meet.google.com/demo-stand-up"}


def _event(date_key, summary, start, end, cal, acct, color, loc="", desc="",
           people=(), all_day=False, join="", organizer="", status="confirmed"):
    """Build one normalized event object (gcalbridge.normalize schema)."""
    uid = hashlib.sha1((date_key + summary + start).encode()).hexdigest()[:16]
    atts = []
    for i, name in enumerate(people):
        atts.append({"name": name,
                     "response": "accepted" if i % 3 else "tentative",
                     "self": False})
    if people:
        atts.insert(0, {"name": "You", "response": "accepted", "self": True})
    return {
        "id": "demo-" + uid, "uid": uid + "@demo", "access": "owner",
        "source": "demo", "provider": "google", "account": acct,
        "calendar": cal, "color": color,
        "summary": summary, "allDay": all_day, "days": [date_key],
        "startKey": date_key, "endKey": date_key,
        "startTime": "" if all_day else start, "endTime": "" if all_day else end,
        "location": loc, "description": desc, "attendees": atts,
        "organizer": organizer or (acct if people else ""),
        "joinLink": join, "htmlLink": "https://calendar.google.com/",
        "status": status,
    }


def _events_for(d):
    """Deterministic list of events for a single date `d` (a date object)."""
    key = iso(d)
    wd = d.weekday()
    r = rng("gcal", key)
    evs = []

    # Weekday standup, every working day.
    if wd < 5:
        s = _STANDUP
        evs.append(_event(key, s["summary"], s["start"], s["end"], s["cal"],
                          s["acct"], s["color"], loc=s["loc"],
                          desc="Quick sync on yesterday / today / blockers.",
                          people=[_pick(r, _PEOPLE) for _ in range(3)],
                          join=s["join"]))

    # A rotating work meeting most weekdays.
    work_pool = [
        ("Sprint planning", "11:00", "12:00", "Discuss upcoming sprint scope."),
        ("1:1 with manager", "14:00", "14:30", "Career + priorities check-in."),
        ("Design review", "15:00", "16:00", "Walk through the new mockups."),
        ("Backend sync", "10:15", "10:45", "API contract + rollout plan."),
        ("Product demo", "16:30", "17:00", "Show progress to stakeholders."),
        ("Retro", "13:30", "14:15", "What went well / what to improve."),
    ]
    if wd < 5 and r.random() < 0.7:
        m = _pick(r, work_pool)
        evs.append(_event(key, m[0], m[1], m[2], "Work", _CAL_WORK, "#4285f4",
                          loc="Conference room B", desc=m[3],
                          people=[_pick(r, _PEOPLE) for _ in range(r.randint(2, 4))],
                          join="https://meet.google.com/demo-" + m[0].split()[0].lower()))

    # Personal / family events, likelier in the evening or on weekends.
    personal_pool = [
        ("Gym session", "18:30", "19:30", "Personal", _CAL_GOOGLE, "#33b679", "FitClub"),
        ("Dinner with friends", "20:00", "22:00", "Personal", _CAL_GOOGLE, "#33b679", "Trattoria Roma"),
        ("Language class", "19:00", "20:00", "Personal", _CAL_GOOGLE, "#33b679", "Online"),
        ("Call family", "19:30", "20:00", "Family", _CAL_GOOGLE, "#f6bf26", "Home"),
        ("Farmers market", "10:00", "11:30", "Personal", _CAL_GOOGLE, "#33b679", "Town square"),
        ("Board games night", "20:30", "23:00", "Personal", _CAL_GOOGLE, "#33b679", "Sam's place"),
    ]
    p_chance = 0.6 if wd >= 5 else 0.35
    if r.random() < p_chance:
        p = _pick(r, personal_pool)
        evs.append(_event(key, p[0], p[1], p[2], p[3], p[4], p[5], loc=p[6],
                          people=[_pick(r, _PEOPLE)] if r.random() < 0.5 else []))

    # Occasional all-day markers.
    allday_pool = ["Alex's birthday 🎂", "Public holiday", "Team offsite",
                   "Conference: FrontendConf", "Vacation day"]
    if r.random() < 0.08:
        a = _pick(r, allday_pool)
        evs.append(_event(key, a, "", "", "Personal", _CAL_GOOGLE, "#f6bf26",
                          all_day=True))

    return evs


def gcal_fetch(a, b):
    events = []
    for d in days_between(a, b):
        events.extend(_events_for(d))
    events.sort(key=lambda e: (e["startKey"], 0 if e["allDay"] else 1,
                               e["startTime"], e["summary"]))
    return {"events": events, "window": [a, b],
            "fetched": today().strftime("%Y-%m-%d %H:%M"),
            "errors": [], "accounts": [_CAL_GOOGLE, _CAL_WORK]}


def gcal_default_window():
    t = today()
    return (iso(t - datetime.timedelta(days=14)),
            iso(t + datetime.timedelta(days=60)))


# =========================================================================== #
#  ORG AGENDA  (orgbridge.py: day / range / deadlines / done)
# =========================================================================== #

_ORG_FILE = "/home/demo/org/tasks.org"

# Persistent undated to-dos, shown on every day (dated:false).
_ORG_PERSISTENT = [
    ("Reply to open code-review comments", "TODO", "B"),
    ("Water the plants", "TODO", ""),
    ("Read one chapter of 'Designing Data-Intensive Applications'", "TODO", "C"),
]

_ORG_DATED_POOL = [
    ("Prepare slides for sprint review", "A", "deadline"),
    ("Team sync — roadmap", "", "scheduled"),
    ("Submit expense report", "B", "deadline"),
    ("Pair on the auth refactor", "", "scheduled"),
    ("Write RFC for the new pipeline", "A", "deadline"),
    ("Review PR #482", "B", "scheduled"),
    ("1:1 prep notes", "", "scheduled"),
    ("Renew domain registration", "C", "deadline"),
    ("Plan Q3 objectives", "A", "scheduled"),
    ("Fix flaky integration test", "B", "deadline"),
    ("Update onboarding docs", "C", "scheduled"),
    ("Book flights for the offsite", "B", "deadline"),
]


def _org_day_items(datestr):
    """Dated agenda items for a specific day (deterministic), followed by the
    persistent undated to-do list. Mirrors pill-day output."""
    d = datetime.date.fromisoformat(datestr)
    r = rng("org", datestr)
    items = []
    # 0–3 dated items, fewer at weekends.
    n = r.choice([0, 0, 1, 1, 2, 3]) if d.weekday() < 5 else r.choice([0, 0, 1])
    used = set()
    pos = 200
    for _ in range(n):
        text, pri, typ = _pick(r, _ORG_DATED_POOL)
        if text in used:
            continue
        used.add(text)
        # A dated item is 'done' with modest probability, higher in the past.
        done = r.random() < (0.5 if d < today() else 0.15)
        items.append({"text": text, "todo": "DONE" if done else "TODO",
                      "priority": pri, "done": done, "file": _ORG_FILE,
                      "pos": pos, "type": typ, "dated": True})
        pos += 60
    # Persistent undated to-dos (active, shown every day).
    for text, todo, pri in _ORG_PERSISTENT:
        items.append({"text": text, "todo": todo, "priority": pri,
                      "done": False, "file": _ORG_FILE, "pos": pos,
                      "type": "", "dated": False})
        pos += 60
    return items


def org_day(datestr):
    return _org_day_items(datestr)


def org_range(a, b):
    """Dates in [a,b] carrying dated entries; done=t when all are done."""
    out = []
    for d in days_between(a, b):
        dated = [it for it in _org_day_items(iso(d)) if it["dated"]]
        if dated:
            out.append({"date": iso(d),
                        "done": all(it["done"] for it in dated)})
    return out


# Fixed, relative-to-today deadline set so the pill's LATE / TODAY / AHEAD
# buckets are always populated. (offset-in-days, text, priority)
_ORG_DEADLINES = [
    (-4, "Send the signed contract back", "A"),
    (-1, "Merge the release branch", "B"),
    (0, "Prepare slides for sprint review", "A"),
    (0, "Submit expense report", "B"),
    (1, "Write RFC for the new pipeline", "A"),
    (2, "Renew domain registration", "C"),
    (4, "Book flights for the offsite", "B"),
    (9, "Plan Q3 objectives", "A"),
    (16, "Annual performance self-review", "B"),
]


def org_deadlines(ahead=30):
    t = today()
    pos = 400
    out = []
    for delta, text, pri in _ORG_DEADLINES:
        if delta > ahead:
            continue
        dl = t + datetime.timedelta(days=delta)
        out.append({"text": text, "todo": "TODO", "priority": pri,
                    "done": False, "file": _ORG_FILE, "pos": pos,
                    "delta": delta, "date": iso(dl)})
        pos += 60
    out.sort(key=lambda x: x["delta"])
    return out


def org_done(a, b, period):
    """Work-history terminal facts for [a,b], deterministic by period."""
    r = rng("orgdone", period)
    scale = {"week": 1, "month": 4, "quarter": 12, "year": 50,
             "all": 80}.get(period, 4)
    done = max(2, r.randint(2 * scale, 5 * scale))
    cancelled = r.randint(0, max(1, scale // 2))
    pool = ["Auth refactor", "Ship the finance page", "Fix pagination bug",
            "Write onboarding docs", "Migrate CI to caches", "Design review",
            "Release 2.4.0", "Customer call follow-ups", "Refactor state store",
            "Triage inbox"]
    items = []
    total = 0.0
    for name in pool[:min(8, 3 + scale)]:
        h = round(r.uniform(1.5, 9.0) * (1 + scale / 20.0), 1)
        total += h
        items.append({"text": name, "hours": h})
    items.sort(key=lambda x: x["hours"], reverse=True)
    items = items[:8]
    return {"done": done, "cancelled": cancelled,
            "hours": round(sum(i["hours"] for i in items), 1),
            "items": items, "period": period}


# =========================================================================== #
#  GIT — "Done" work history  (gitbridge.py: summary / prs)
# =========================================================================== #

_GIT_SUBJECTS = [
    "feat: add demo-data generator for screen recordings",
    "fix: return focus to previous window after closing overlay",
    "refactor: extract finance state machine",
    "perf: cache calendar events in a rolling window",
    "feat: emoji picker with search + favorites",
    "fix: guard against empty org-agenda-files",
    "docs: document the DEMO seam",
    "test: cover the plan placement algorithm",
    "feat: block-blast puzzle in the pill",
    "chore: bump quickshell to latest",
]
_GIT_REPOS = ["awesome", "shledger", "pill-utils", "dotfiles"]


def git_summary(since, dirs, emails, period):
    r = rng("gitsum", period)
    scale = {"week": 1, "month": 4, "quarter": 12, "year": 48,
             "all": 90}.get(period, 4)
    commits = r.randint(6 * scale, 14 * scale)
    merges = r.randint(scale, 3 * scale)
    branches = r.randint(scale, 4 * scale)
    repos = len(_GIT_REPOS)
    projects = r.randint(2, repos)
    biggest = []
    for i in range(6):
        biggest.append({"subject": _GIT_SUBJECTS[i % len(_GIT_SUBJECTS)],
                        "add": r.randint(40, 600), "del": r.randint(5, 300),
                        "hash": hashlib.sha1((period + str(i)).encode()).hexdigest()[:7],
                        "repo": _pick(r, _GIT_REPOS)})
    biggest.sort(key=lambda c: c["add"] + c["del"], reverse=True)
    return {"commits": commits, "merges": merges, "branches": branches,
            "projects": projects, "repos": repos, "biggest": biggest,
            "period": period}


def git_prs(since, dirs, period):
    r = rng("gitprs", period)
    scale = {"week": 1, "month": 4, "quarter": 12, "year": 48,
             "all": 90}.get(period, 4)
    return {"prs": r.randint(scale, 3 * scale), "stale": False,
            "at": time.time(), "period": period}


# =========================================================================== #
#  FINANCE  (hledgerbridge.py: all commands)
#
#  One deterministic ledger is the single source of truth. Every command derives
#  its answer from the same generated transactions, so balances, the register,
#  per-day breakdowns, the forecast and the plan all agree with each other.
# =========================================================================== #

RATE_EUR_IRT = 60000.0  # fixed demo exchange rate: 1 EUR = 60,000 IRT (Toman)


def _conv(v, frm, to):
    if frm == to:
        return v
    if frm == "EUR" and to == "IRT":
        return v * RATE_EUR_IRT
    if frm == "IRT" and to == "EUR":
        return v / RATE_EUR_IRT
    return v


def _ledger_start():
    """First of the month, 10 months before today — a stable, clean origin."""
    return first_of_month(add_months(today(), -10))


# ---- account + merchant vocabulary ----------------------------------------

_CHECKING = "assets:bank:checking"
_SAVINGS = "assets:bank:savings"
_CASH = "assets:cash"
_RIAL = "assets:rial"
_CARD = "liabilities:creditcard"

_MERCHANTS = {
    "expenses:groceries": ["Rewe", "Aldi", "Lidl", "Edeka", "Trader Joe's",
                           "Whole Foods", "Farmers Market"],
    "expenses:dining": ["Sushi Bar", "Trattoria Roma", "Burger Joint",
                        "Thai Kitchen", "Café Lumen", "Falafel House"],
    "expenses:transport": ["Metro ticket", "Uber ride", "Bolt ride",
                           "Gas station", "Train fare"],
    "expenses:coffee": ["Blue Bottle", "Espresso Bar", "Corner Café",
                        "Roasters"],
    "expenses:shopping": ["Amazon order", "IKEA", "Zara", "Uniqlo",
                          "Bookshop"],
    "expenses:health": ["Pharmacy", "Physio", "Optician"],
    "expenses:entertainment": ["Cinema", "Concert ticket", "Steam", "Museum"],
}
_IRT_MERCHANTS = ["Taxi Tehran", "Bazaar shopping", "Restaurant Esfahan",
                  "Saffron & spices"]


def _mk(account, value, currency):
    return {"account": account, "value": value, "currency": currency}


def _expense(cat, amt, asset=_CHECKING, cur="EUR"):
    return [_mk(cat, round(amt, 2), cur), _mk(asset, round(-amt, 2), cur)]


def _income(cat, amt, asset=_CHECKING, cur="EUR"):
    return [_mk(cat, round(-amt, 2), cur), _mk(asset, round(amt, 2), cur)]


def _transfer(dst, src, amt, cur="EUR"):
    return [_mk(dst, round(amt, 2), cur), _mk(src, round(-amt, 2), cur)]


def _opening_txns():
    """Two opening-balance transactions (EUR + IRT) at the ledger origin."""
    d = iso(_ledger_start())
    eur = [_mk(_CHECKING, 2600.0, "EUR"), _mk(_SAVINGS, 4000.0, "EUR"),
           _mk(_CASH, 150.0, "EUR"), _mk(_CARD, -420.0, "EUR"),
           _mk("equity:opening", -6330.0, "EUR")]
    irt = [_mk(_RIAL, 40000000.0, "IRT"), _mk("equity:opening", -40000000.0, "IRT")]
    return [(d, "Opening balances", eur), (d, "Opening balances", irt)]


def _recurring(d, forecast=False):
    """Periodic transactions for date `d`. These exist both as real history and
    (with `forecast=True`, adding monthly budget lumps) as the forecast stream."""
    dom = d.day
    r = rng("finrec", iso(d))
    out = []
    if dom == 1:
        out.append(("Monthly rent", _expense("expenses:rent", 1200.0)))
    if dom == 25:
        out.append(("Salary — Acme Corp", _income("income:salary", 3500.0)))
    if dom == 3:
        out.append(("Netflix", _expense("expenses:subscriptions", 12.99)))
    if dom == 4:
        out.append(("Spotify", _expense("expenses:subscriptions", 9.99)))
    if dom == 7:
        out.append(("iCloud storage", _expense("expenses:subscriptions", 2.99)))
    if dom == 9:
        out.append(("GitHub Pro", _expense("expenses:subscriptions", 4.0)))
    if dom == 5:
        out.append(("Electricity", _expense("expenses:utilities", 64.0)))
    if dom == 6:
        out.append(("Internet", _expense("expenses:utilities", 39.99)))
    if dom == 8:
        out.append(("Water", _expense("expenses:utilities", 27.5)))
    if dom == 10:
        out.append(("ATM withdrawal", _transfer(_CASH, _CHECKING, 120.0)))
    if dom == 15:
        out.append(("Transfer to savings", _transfer(_SAVINGS, _CHECKING, 400.0)))
    if dom == 28 and r.random() < 0.6:
        amt = round(r.uniform(400, 900), 2)
        out.append(("Freelance — side project", _income("income:freelance", amt)))
    if forecast:
        # Monthly budget lumps only exist in the forecast (hledger periodic
        # rules), giving a realistic projected net without the granular history.
        if dom == 2:
            out.append(("Groceries (budget)", _expense("expenses:groceries", 450.0)))
        if dom == 12:
            out.append(("Dining out (budget)", _expense("expenses:dining", 220.0)))
        if dom == 14:
            out.append(("Transport (budget)", _expense("expenses:transport", 130.0)))
        if dom == 18:
            out.append(("Leisure (budget)", _expense("expenses:entertainment", 90.0)))
        if dom == 20:
            out.append(("Shopping (budget)", _expense("expenses:shopping", 200.0)))
    return [(iso(d), desc, ps) for desc, ps in out]


def _daily(d):
    """Granular, actual day-to-day spending for date `d` (history only)."""
    r = rng("findaily", iso(d))
    wd = d.weekday()
    out = []

    def maybe(p, cat, lo, hi, asset=_CHECKING, cur="EUR"):
        if r.random() < p:
            amt = round(r.uniform(lo, hi), 2)
            merch = _pick(r, _MERCHANTS.get(cat, [cat.split(":")[-1].title()]))
            out.append((iso(d), merch, _expense(cat, amt, asset, cur)))

    maybe(0.35, "expenses:groceries", 12, 74)
    maybe(0.22 + (0.15 if wd >= 4 else 0), "expenses:dining", 11, 46)
    maybe(0.30 if wd < 5 else 0.12, "expenses:transport", 3, 28)
    maybe(0.45 if wd < 5 else 0.25, "expenses:coffee", 2.5, 6.5, asset=_CASH)
    maybe(0.08, "expenses:shopping", 20, 180)
    maybe(0.05, "expenses:health", 8, 60)
    maybe(0.06 if wd >= 5 else 0.03, "expenses:entertainment", 9, 55)
    # Occasional IRT (Toman) spending — showcases multi-currency.
    if r.random() < 0.05:
        amt = round(r.uniform(150000, 1800000), -3)
        out.append((iso(d), _pick(r, _IRT_MERCHANTS),
                    _expense("expenses:travel:iran", amt, asset=_RIAL, cur="IRT")))
    if r.random() < 0.012:
        amt = round(r.uniform(2000000, 9000000), -3)
        out.append((iso(d), "Family gift",
                    _income("income:gift", amt, asset=_RIAL, cur="IRT")))
    return out


def _actual_txns(a, b):
    """All real (historical) transactions with date in [a, b] inclusive.
    Recurring + daily, never beyond today. Includes opening balances if in range."""
    lo = datetime.date.fromisoformat(a)
    hi = min(datetime.date.fromisoformat(b), today())
    out = []
    start = _ledger_start()
    for d, desc, ps in _opening_txns():
        od = datetime.date.fromisoformat(d)
        if lo <= od <= hi:
            out.append((d, desc, ps))
    for d in days_between(max(lo, start), hi):
        out.extend(_recurring(d, forecast=False))
        out.extend(_daily(d))
    out.sort(key=lambda t: t[0])
    return out


def _forecast_txns(a, b):
    """Forecast (periodic) occurrences strictly after today, in [a, b]."""
    lo = max(datetime.date.fromisoformat(a),
             today() + datetime.timedelta(days=1))
    hi = datetime.date.fromisoformat(b)
    out = []
    for d in days_between(lo, hi):
        out.extend(_recurring(d, forecast=True))
    out.sort(key=lambda t: t[0])
    return out


# ---- row shaping (mirrors hledgerbridge.txn_row / valuation) ---------------

def _value_postings(ps, cur):
    if cur not in ("EUR", "IRT"):
        return ps
    return [_mk(p["account"], round(_conv(p["value"], p["currency"], cur), 2), cur)
            for p in ps]


def _classify(ps):
    exp = [p for p in ps if p["account"].startswith("expenses")]
    inc = [p for p in ps if p["account"].startswith("income")]
    if exp:
        cur = exp[0]["currency"]
        return "expense", cur, sum(p["value"] for p in exp if p["currency"] == cur)
    if inc:
        cur = inc[0]["currency"]
        return "income", cur, abs(sum(p["value"] for p in inc if p["currency"] == cur))
    cur = ps[0]["currency"] if ps else ""
    return "transfer", cur, abs(ps[0]["value"]) if ps else 0


def _row(txn, cur="native"):
    date, desc, ps = txn
    vps = _value_postings(ps, cur)
    kind, c, amt = _classify(vps)
    return {"date": date, "description": desc, "kind": kind,
            "amount": amt, "currency": c, "postings": vps}


def _forecast_row(txn, cur="native"):
    row = _row(txn, cur)
    cat, asset = "", ""
    for p in row["postings"]:
        a = p["account"]
        if not cat and a.startswith(("expenses", "income")):
            cat = a
        elif not asset and a.startswith(("assets", "liabilities")):
            asset = a
    row["account"] = cat
    row["asset"] = asset or "assets:cash"
    return row


# ---- finance commands ------------------------------------------------------

def fin_day(key, cur="native"):
    lo = datetime.date.fromisoformat(key)
    if lo > today():
        return []  # future actuals don't exist — the forecast list covers them
    return [_row(t, cur) for t in _actual_txns(key, key)]


def fin_range(a, b):
    counts = {}
    for d, _, _ in _actual_txns(a, b):
        counts[d] = counts.get(d, 0) + 1
    return [{"date": d, "count": n} for d, n in sorted(counts.items())]


def fin_frange(a, b):
    counts = {}
    for d, _, _ in _forecast_txns(a, b):
        counts[d] = counts.get(d, 0) + 1
    return [{"date": d, "count": n} for d, n in sorted(counts.items())]


def fin_fentries(a, b):
    return [_forecast_row(t) for t in _forecast_txns(a, b)]


def fin_register(query, limit, cur="native"):
    rows = []
    for t in _actual_txns(iso(_ledger_start()), iso(today())):
        if query and not any(p["account"].startswith(query) for p in t[2]):
            continue
        rows.append(_row(t, cur))
    return list(reversed(rows))[:limit]


def _asset_liab_sums(cur):
    """{account: {currency: value}} over all history up to today, valued in cur."""
    sums = {}
    for _, _, ps in _actual_txns(iso(_ledger_start()), iso(today())):
        for p in ps:
            top = p["account"].split(":")[0]
            if top not in ("assets", "liabilities"):
                continue
            v = _conv(p["value"], p["currency"], cur) if cur in ("EUR", "IRT") \
                else p["value"]
            c = cur if cur in ("EUR", "IRT") else p["currency"]
            sums.setdefault(p["account"], {})
            sums[p["account"]][c] = sums[p["account"]].get(c, 0.0) + v
    return sums


def _amounts_list(curmap):
    order = ["EUR", "IRT"]
    keys = [c for c in order if c in curmap] + \
           [c for c in curmap if c not in order]
    return [{"currency": c, "value": round(curmap[c], 2)}
            for c in keys if abs(curmap[c]) > 0.005]


def fin_balances(cur="native"):
    leaves = _asset_liab_sums(cur)
    tree = {}
    for acct, curs in leaves.items():
        parts = acct.split(":")
        for i in range(1, len(parts) + 1):
            pre = ":".join(parts[:i])
            node = tree.setdefault(pre, {})
            for c, v in curs.items():
                node[c] = node.get(c, 0.0) + v
    rows = []
    for acct in sorted(tree):
        amounts = _amounts_list(tree[acct])
        if amounts:
            rows.append({"account": acct, "indent": acct.count(":"),
                         "amounts": amounts})
    totals = {}
    for top in ("assets", "liabilities"):
        for c, v in tree.get(top, {}).items():
            totals[c] = totals.get(c, 0.0) + v
    return {"rows": rows, "totals": _amounts_list(totals)}


def fin_accounts():
    groups = {"expenses": set(), "income": set(), "assets": set(),
              "liabilities": set(), "other": set()}
    # every account the ledger can mention
    seeds = [_CHECKING, _SAVINGS, _CASH, _RIAL, _CARD, "income:salary",
             "income:freelance", "income:gift", "expenses:rent",
             "expenses:utilities", "expenses:subscriptions",
             "expenses:travel:iran"]
    seeds += list(_MERCHANTS.keys())
    for a in seeds:
        top = a.split(":")[0]
        groups[top if top in groups else "other"].add(a)
    return {k: sorted(v) for k, v in groups.items()}


def fin_catsum(a, b, cur="native"):
    sums = {}
    for _, _, ps in _actual_txns(a, b):
        for p in ps:
            top = p["account"].split(":")[0]
            if top not in ("expenses", "income"):
                continue
            v = _conv(p["value"], p["currency"], cur) if cur in ("EUR", "IRT") \
                else p["value"]
            c = cur if cur in ("EUR", "IRT") else p["currency"]
            sums.setdefault(p["account"], {})
            sums[p["account"]][c] = sums[p["account"]].get(c, 0.0) + v
    rows = [{"account": acct, "amounts": _amounts_list(curs)}
            for acct, curs in sorted(sums.items())]
    rows = [r for r in rows if r["amounts"]]
    totals = {}
    for _, curs in sums.items():
        for c, v in curs.items():
            totals[c] = totals.get(c, 0.0) + v
    return {"rows": rows, "totals": _amounts_list(totals)}


def _net_asset_delta_eur(ps):
    """Signed change in total (EUR-valued) assets for a transaction."""
    net = 0.0
    for p in ps:
        if p["account"].split(":")[0] == "assets":
            net += _conv(p["value"], p["currency"], "EUR")
    return net


def fin_timeline(cur="native", months=12):
    disp = cur if cur in ("EUR", "IRT") else "EUR"
    start_eur = sum(_conv(a["value"], a["currency"], "EUR")
                    for a in fin_balances("native")["totals"]
                    if a["currency"] in ("EUR", "IRT"))
    running = start_eur
    horizon = add_months(today(), months)
    rows = []
    for t in _forecast_txns(iso(today()), iso(horizon)):
        net = _net_asset_delta_eur(t[2])
        if abs(net) < 0.005:
            continue  # e.g. savings transfers don't move total assets
        running += net
        bal = _conv(running, "EUR", disp) if disp != "EUR" else running
        amt = abs(_conv(net, "EUR", disp) if disp != "EUR" else net)
        rows.append({"date": t[0], "description": t[1],
                     "amount": round(amt, 2), "currency": disp,
                     "kind": "income" if net > 0 else "expense",
                     "balance": [{"currency": disp, "value": round(bal, 2)}]})
    return rows


# ---- wishlist + plan -------------------------------------------------------

# Buy priority = file order. Prices in EUR; converted to the display currency.
_WISHLIST = [
    ("Mechanical keyboard", 160.0),
    ("Noise-cancelling headphones", 320.0),
    ("Standing desk", 480.0),
    ("4K monitor", 540.0),
    ("Weekend trip to Lisbon", 650.0),
    ("Camera lens", 900.0),
    ("Used car", 9000.0),
    ("Sabbatical fund", 18000.0),
]

_PLAN_BUFFER_EUR = 4000.0
_PLAN_GOAL_EUR = 30000.0


def _wishlist_valued(pc):
    return [{"description": name, "price": round(_conv(price, "EUR", pc), 2)}
            for name, price in _WISHLIST]


def fin_wishlist(cur=None):
    pc = cur if cur in ("EUR", "IRT") else "EUR"
    liquid = sum(a["value"] for a in fin_balances(pc)["totals"]
                 if a["currency"] == pc)
    if not liquid:  # native fallback: value assets in pc explicitly
        liquid = sum(_conv(a["value"], a["currency"], pc)
                     for a in fin_balances("native")["totals"])
    buffer = _conv(_PLAN_BUFFER_EUR, "EUR", pc)
    spendable = liquid - buffer
    items = []
    for it in _wishlist_valued(pc):
        price = it["price"]
        items.append({"description": it["description"], "amount": price,
                      "currency": pc, "affordable": spendable >= price})
    return {"liquid": round(liquid, 2), "buffer": round(buffer, 2),
            "spendable": round(spendable, 2), "currency": pc, "items": items}


def _month_trajectory(pc, horizon):
    """[{month, end_date, balance}] projected month-end balances, valued in pc."""
    start_eur = sum(_conv(a["value"], a["currency"], "EUR")
                    for a in fin_balances("native")["totals"])
    t = today()
    months = []
    running = start_eur
    m = first_of_month(t)
    end_month = first_of_month(horizon)
    while m <= end_month:
        nxt = add_months(m, 1)
        # sum forecast net-asset deltas for future days in this month
        for txn in _forecast_txns(iso(max(m, t + datetime.timedelta(days=1))),
                                  iso(nxt - datetime.timedelta(days=1))):
            running += _net_asset_delta_eur(txn[2])
        end_date = iso(nxt - datetime.timedelta(days=1))
        months.append({"month": m.strftime("%Y-%m"), "end_date": end_date,
                       "balance": _conv(running, "EUR", pc) if pc != "EUR" else running})
        m = nxt
    return months


def fin_plan(cur=None):
    pc = cur if cur in ("EUR", "IRT") else "EUR"
    buffer = _conv(_PLAN_BUFFER_EUR, "EUR", pc)
    goal = _conv(_PLAN_GOAL_EUR, "EUR", pc)
    gdate = iso(first_of_month(add_months(today(), 8)))
    t = today()
    horizon = add_months(t, 12)
    if datetime.date.fromisoformat(gdate) > horizon:
        horizon = datetime.date.fromisoformat(gdate)
    months = _month_trajectory(pc, horizon)
    base = {"currency": pc, "buffer": round(buffer, 2),
            "goal": round(goal, 2), "goal_date": gdate}
    start = sum(_conv(a["value"], a["currency"], pc)
                for a in fin_balances("native")["totals"])
    if not months:
        return dict(base, start=round(start, 2), months=[], items=[])
    prev = start
    for m in months:
        m["net"] = m["balance"] - prev
        prev = m["balance"]

    def floor_at(i):
        if goal is not None and months[i]["end_date"] >= gdate:
            return max(buffer, goal)
        return buffer

    floors = [floor_at(i) for i in range(len(months))]
    bal = [m["balance"] for m in months]
    items = _wishlist_valued(pc)
    plan_items, min_i = [], 0
    for it in items:
        price = it["price"]
        rec = {"description": it["description"], "price": price, "currency": pc}
        placed = None
        for i in range(min_i, len(months)):
            if all(bal[k] - price >= floors[k] for k in range(i, len(months))):
                placed = i
                for k in range(i, len(months)):
                    bal[k] -= price
                min_i = i
                break
        if placed is not None:
            rec["month"] = months[placed]["month"]
            rec["month_index"] = placed
        else:
            rec["month"] = None
            best = None
            for i in range(min_i, len(months)):
                head = min(bal[k] - floors[k] for k in range(i, len(months)))
                best = head if best is None else max(best, head)
            rec["shortfall"] = round(price - (best or 0.0), 2)
        plan_items.append(rec)
    month_out = []
    for i, m in enumerate(months):
        buys = [p["description"] for p in plan_items if p.get("month_index") == i]
        month_out.append({"month": m["month"], "end_date": m["end_date"],
                          "net": round(m["net"], 2), "projected": round(bal[i], 2),
                          "floor": round(floors[i], 2),
                          "cushion": round(bal[i] - floors[i], 2),
                          "purchases": buys})
    return dict(base, start=round(start, 2), months=month_out, items=plan_items)


def fin_today_has_entry():
    n = len(fin_day(iso(today())))
    return {"has": n > 0, "count": n}


def fin_entities():
    return [{"name": "personal", "default": True}]


def fin_git_status():
    return {"repo": True, "branch": "main", "dirty": 0, "ahead": 0, "behind": 0,
            "last": "a1b2c3d pill: finance entries " + iso(today())}


# =========================================================================== #
#  Dispatch — one entry point per bridge namespace
# =========================================================================== #

def _write(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))


def _strip_leading(argv, flags_with_arg):
    """Drop leading `--dir X` / `--entity X` / `-E X` the real bridges parse."""
    argv = list(argv)
    while len(argv) >= 2 and argv[0] in flags_with_arg:
        argv = argv[2:]
    return argv


def _run_org(argv):
    argv = _strip_leading(argv, ("--dir",))
    cmd = argv[0] if argv else ""
    if cmd == "day" and len(argv) > 1:
        _write(org_day(argv[1]))
    elif cmd == "range" and len(argv) > 2:
        _write(org_range(argv[1], argv[2]))
    elif cmd == "deadlines":
        try:
            ahead = int(argv[1]) if len(argv) > 1 else 30
        except ValueError:
            ahead = 30
        _write(org_deadlines(ahead))
    elif cmd == "done" and len(argv) > 2:
        _write(org_done(argv[1], argv[2], argv[3] if len(argv) > 3 else ""))
    else:
        # toggle / goto / open — actions; nothing to do, empty result.
        _write([])


def _run_gcal(argv):
    cmd = argv[0] if argv else "read"
    if cmd == "fetch":
        a, b = (argv[1], argv[2]) if len(argv) > 2 else gcal_default_window()
        _write(gcal_fetch(a, b))
    elif cmd == "accounts":
        _write(gcal_accounts())
    elif cmd in ("add-google", "add-proton"):
        _write({"ok": True, "label": "demo account"})
    elif cmd == "remove":
        _write({"ok": True})
    else:  # read
        a, b = gcal_default_window()
        _write(gcal_fetch(a, b))


def _run_finance(argv):
    argv = _strip_leading(argv, ("--dir",))
    argv = _strip_leading(argv, ("--entity", "-E"))
    cmd = argv[0] if argv else ""
    if cmd == "range" and len(argv) > 2:
        _write(fin_range(argv[1], argv[2]))
    elif cmd == "frange" and len(argv) > 2:
        _write(fin_frange(argv[1], argv[2]))
    elif cmd == "fentries" and len(argv) > 2:
        _write(fin_fentries(argv[1], argv[2]))
    elif cmd == "day" and len(argv) > 1:
        _write(fin_day(argv[1], argv[2] if len(argv) > 2 else "native"))
    elif cmd == "add":
        _write({"ok": True})  # demo: accept but don't persist
    elif cmd == "accounts":
        _write(fin_accounts())
    elif cmd == "balances":
        _write(fin_balances(argv[1] if len(argv) > 1 else "native"))
    elif cmd == "timeline":
        cur = argv[1] if len(argv) > 1 else "native"
        _write(fin_timeline(cur, int(argv[2]) if len(argv) > 2 else 12))
    elif cmd == "register":
        query = argv[1] if len(argv) > 1 else ""
        limit = int(argv[2]) if len(argv) > 2 else 50
        _write(fin_register(query, limit, argv[3] if len(argv) > 3 else "native"))
    elif cmd == "catsum" and len(argv) > 2:
        _write(fin_catsum(argv[1], argv[2], argv[3] if len(argv) > 3 else "native"))
    elif cmd == "wishlist":
        _write(fin_wishlist(argv[1] if len(argv) > 1 else None))
    elif cmd == "plan":
        _write(fin_plan(argv[1] if len(argv) > 1 else None))
    elif cmd == "entities":
        _write(fin_entities())
    elif cmd == "today-has-entry":
        _write(fin_today_has_entry())
    elif cmd == "git-status":
        _write(fin_git_status())
    elif cmd == "git-sync":
        _write({"ok": True, "changed": False})
    elif cmd == "git-push":
        _write({"ok": True, "committed": False, "pushed": True})
    else:
        _write([])


def _run_git(argv):
    cmd = argv[0] if argv else ""
    if cmd == "summary" and len(argv) >= 4:
        period = argv[4] if len(argv) > 4 else ""
        _write(git_summary(argv[1], argv[2], argv[3], period))
    elif cmd == "prs" and len(argv) >= 3:
        period = argv[3] if len(argv) > 3 else ""
        _write(git_prs(argv[1], argv[2], period))
    else:
        _write({"period": ""})


def _run_clip(argv):
    cmd = argv[0] if argv else ""
    if cmd == "list":
        _write(clip_list())
    elif cmd == "watch":
        # keep the process alive (init.qml holds it running) without touching
        # the real clipboard.
        import signal
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            pass
    # copy / delete / wipe — no-ops in demo mode.


_DISPATCH = {
    "org": _run_org,
    "gcal": _run_gcal,
    "finance": _run_finance,
    "git": _run_git,
    "clip": _run_clip,
}


def run(kind, argv):
    """Entry point used by every bridge's DEMO gate. Writes the command's JSON to
    stdout (or blocks, for `clip watch`)."""
    _DISPATCH[kind](list(argv))


def enabled():
    return bool(os.environ.get("DEMO"))


if __name__ == "__main__":
    # Manual testing: `DEMO=1 python demodata.py finance balances EUR`
    run(sys.argv[1], sys.argv[2:])
    sys.stdout.write("\n")
