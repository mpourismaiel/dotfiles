#!/usr/bin/env python3
# hledgerbridge.py — hledger backend for the pill's finance menu + calendar dots.
#
#   range A B          print JSON [{date, count}, …] for days in [A,B] with entries
#   frange A B         print JSON [{date, count}, …] for days in [A,B] with a
#                      *forecast* (periodic) entry — drives the hollow calendar dot
#   fentries A B       print JSON [forecast_row, …] the forecast (periodic)
#                      occurrences across [A,B], native amounts, each carrying the
#                      category + asset account so the pill can list them per day
#                      (calendar "Upcoming") and prefill an add form. Same query as
#                      frange, so it lines up exactly with the hollow dots.
#   day KEY [CUR]      print JSON [txn_row, …] for that day, valued in CUR
#   add JSON           append a transaction (see payload below), check, print {ok}
#   accounts           print JSON {expenses, income, assets, liabilities, other}
#   balances [CUR]     print JSON {rows: [{account, indent, amounts}], totals}
#   timeline CUR [mo]  print JSON [{date, description, amount, currency, kind,
#                      balance:[{currency,value}]}] — a running assets projection
#                      from today over the next `mo` months, real + forecast events
#                      (--historical: balance starts from the current asset total)
#   register [q][n][CUR] print JSON [txn_row, …] newest first, at most n (default 50)
#   wishlist [CUR]     print JSON {liquid, buffer, spendable, currency,
#                      items: [{description, amount, currency, affordable}]} — a
#                      wish is affordable when (liquid − buffer) ≥ its price
#   plan [CUR]         print JSON {currency, buffer, goal, goal_date, start,
#                      months: [{month, end_date, net, projected, floor, cushion,
#                      purchases}], items: [{description, price, currency, month,
#                      month_index?, shortfall?}]} — a month-by-month savings +
#                      wishlist-purchase schedule (see cmd_plan)
#   entities           print JSON [{name, default}] — the available books
#   today-has-entry    print JSON {has, count}
#   git-status         print JSON {repo, branch, dirty, ahead, behind, last}
#   git-sync           fetch + ff-only pull, print {ok, changed} or {ok, error}
#   git-push           commit-if-dirty + push, print {ok, committed, pushed}
#
# A LEADING `--entity NAME` (or `-E NAME`) selects the book; default "personal".
#   python hledgerbridge.py --entity company balances EUR
#
# CUR is one of: native (no conversion — the amount as entered), EUR, IRT. EUR/IRT
# value every amount at market price (`-X CUR --infer-market-prices`), so rates
# come from your real conversions (the `@@` costs) plus prices.journal.
#
# txn_row = {date, description, kind: expense|income|transfer, amount, currency,
#            postings: [{account, value, currency}]}
#
# add payload = {date, description, amount, currency: EUR|IRT,
#                kind: expense|income, account, asset}
#   account = the category (expenses:… / income:…), asset = the money account.
#
# Journals live in ~/Documents/finance (override: PILL_FINANCE_DIR). Best-effort:
# if hledger fails, data commands print empty shapes and the UI shows nothing.
import sys, os, json, subprocess, datetime

# A "book" (entity) is a self-contained set of journals. The DEFAULT book,
# "personal", is the journals sitting at the base dir. Any subfolder that holds
# its own main.journal is another book (e.g. company/). BASE_DIR is the parent
# of all books (override: PILL_FINANCE_DIR).
BASE_DIR = os.path.expanduser(os.environ.get("PILL_FINANCE_DIR",
                                             "~/Documents/finance"))


def entity_dir(entity):
    """Folder for a book. 'personal'/''/None → the base dir when it holds the
    root journals, else base/personal; any other name → base/<name>."""
    if entity in ("", "personal", None):
        if os.path.exists(os.path.join(BASE_DIR, "main.journal")):
            return BASE_DIR
        return os.path.join(BASE_DIR, "personal")
    return os.path.join(BASE_DIR, entity)


# Rebound per-invocation in main() once --entity is parsed; default = personal.
FINANCE_DIR = entity_dir("personal")
MAIN = os.path.join(FINANCE_DIR, "main.journal")
WISHLIST = os.path.join(FINANCE_DIR, "wishlist.journal")

MONTHS = ["january", "february", "march", "april", "may", "june", "july",
          "august", "september", "october", "november", "december"]


def cmd_entities():
    """List books: [{name, default}]. 'personal' (the root journals) first when
    they exist, then every subfolder of BASE_DIR carrying its own main.journal."""
    out = []
    if os.path.exists(os.path.join(BASE_DIR, "main.journal")):
        out.append({"name": "personal", "default": True})
    try:
        for name in sorted(os.listdir(BASE_DIR)):
            d = os.path.join(BASE_DIR, name)
            if os.path.isdir(d) and os.path.exists(os.path.join(d, "main.journal")):
                out.append({"name": name, "default": not out})
    except Exception:
        pass
    return out or [{"name": "personal", "default": True}]


def _num(s):
    """Parse a plan.conf number: strips thousands separators / stray text."""
    try:
        return float(str(s).replace(",", "").replace("_", "").strip())
    except Exception:
        return 0.0


def read_plan_conf():
    """The current book's plan.conf → {currency, buffer, goal, goal_date}.
    Missing file or keys degrade to no floor / no goal."""
    conf = {"currency": "EUR", "buffer": 0.0, "goal": None, "goal_date": None}
    try:
        with open(os.path.join(FINANCE_DIR, "plan.conf")) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split(None, 1)
                if len(parts) < 2:
                    continue
                k, v = parts[0].lower(), parts[1].strip()
                if k == "currency":
                    conf["currency"] = v
                elif k == "buffer":
                    conf["buffer"] = _num(v)
                elif k == "goal":
                    conf["goal"] = _num(v) if v else None
                elif k in ("goal-date", "goal_date"):
                    conf["goal_date"] = v or None
    except Exception:
        pass
    return conf


def market_rate(frm, to):
    """Market value of 1 `frm` in `to` at today's rate, using the book's prices
    (prices.journal + inferred @@ costs). 1.0 if same commodity, None if no rate
    connects them. A one-line synthetic txn is fed on stdin alongside the real
    journal (`-f MAIN -f -`) so its own prices apply."""
    if frm == to:
        return 1.0
    try:
        today = datetime.date.today().isoformat()
        synth = "%s rate\n    a  1.00 %s\n    b\n" % (today, frm)
        r = subprocess.run(["hledger", "-f", MAIN, "-f", "-", "balance", "a",
                            "-X", to, "--infer-market-prices", "-O", "json"],
                           input=synth, capture_output=True, text=True, timeout=15)
        if r.returncode != 0:
            return None
        rows, _ = json.loads(r.stdout)
        for row in rows:
            for amt in row[3]:
                if amt.get("acommodity") == to:
                    return amt.get("aquantity", {}).get("floatingPoint")
    except Exception:
        return None
    return None


def plan_targets(cur):
    """Resolve the display currency + buffer/goal for the plan and wishlist.
    Returns (pc, buffer_in_pc, goal_in_pc, goal_date, conf). buffer/goal are
    stored in conf['currency']; when the requested display currency differs they
    are converted at market rate so the floor stays meaningful. If no rate is
    available we fall back to showing everything in the plan currency."""
    conf = read_plan_conf()
    pc = cur if cur in ("EUR", "IRT") else conf["currency"]
    rate = 1.0
    if pc != conf["currency"]:
        rate = market_rate(conf["currency"], pc)
        if not rate:                       # no rate → don't fake it; stay native
            pc, rate = conf["currency"], 1.0
    buf = (conf["buffer"] or 0.0) * rate
    goal = conf["goal"] * rate if conf["goal"] is not None else None
    return pc, buf, goal, conf["goal_date"], conf


def run_hledger(args, file=None):
    """hledger stdout, or None on any failure (missing binary/journal, bad rc).
    `file` defaults to the current book's main.journal (resolved at call time so
    an --entity switch in main() is honoured)."""
    try:
        r = subprocess.run(["hledger", "-f", file or MAIN] + args,
                           capture_output=True, text=True, timeout=15)
        return r.stdout if r.returncode == 0 else None
    except Exception:
        return None


def val(cur):
    """Valuation flags for a currency: native → none, EUR/IRT → market value."""
    return ["-X", cur, "--infer-market-prices"] if cur in ("EUR", "IRT") else []


def print_json(args, file=None):
    """Parsed `hledger print -x -O json` transactions, [] on failure.

    -x makes elided amounts explicit so every posting carries a value."""
    out = run_hledger(["print", "-x", "-O", "json"] + args, file)
    if out is None:
        return []
    try:
        return json.loads(out)
    except Exception:
        return []


def postings(t):
    """Flatten a raw transaction's postings to [{account, value, currency}]."""
    rows = []
    for p in t.get("tpostings", []):
        for a in p.get("pamount", []):
            rows.append({"account": p.get("paccount", ""),
                         "value": a.get("aquantity", {}).get("floatingPoint", 0),
                         "currency": a.get("acommodity", "")})
    return rows


def txn_row(t):
    """Normalize one raw transaction into the row shape the pill renders."""
    ps = postings(t)
    exp = [p for p in ps if p["account"].startswith("expenses")]
    inc = [p for p in ps if p["account"].startswith("income")]
    if exp:
        kind, cur = "expense", exp[0]["currency"]
        amount = sum(p["value"] for p in exp if p["currency"] == cur)
    elif inc:
        kind, cur = "income", inc[0]["currency"]
        amount = abs(sum(p["value"] for p in inc if p["currency"] == cur))
    else:
        kind = "transfer"
        cur = ps[0]["currency"] if ps else ""
        amount = abs(ps[0]["value"]) if ps else 0
    return {"date": t.get("tdate", ""), "description": t.get("tdescription", ""),
            "kind": kind, "amount": amount, "currency": cur, "postings": ps}


def day_after(datestr):
    """datestr + 1 day — hledger date: queries are end-exclusive."""
    d = datetime.date.fromisoformat(datestr)
    return (d + datetime.timedelta(days=1)).isoformat()


def cmd_range(a, b):
    counts = {}
    for t in print_json(["date:%s..%s" % (a, day_after(b))]):
        d = t.get("tdate", "")
        counts[d] = counts.get(d, 0) + 1
    return [{"date": d, "count": n} for d, n in sorted(counts.items())]


def cmd_frange(a, b):
    """Days in [a,b] carrying a forecast (periodic) occurrence — for the hollow
    dot. Only generated transactions count (tag _generated-transaction)."""
    span = "%s..%s" % (a, day_after(b))
    counts = {}
    for t in print_json(["--forecast=" + span, "date:" + span,
                         "tag:_generated-transaction"]):
        d = t.get("tdate", "")
        counts[d] = counts.get(d, 0) + 1
    return [{"date": d, "count": n} for d, n in sorted(counts.items())]


def cmd_day(key, cur="native"):
    return [txn_row(t) for t in
            print_json(["date:%s..%s" % (key, day_after(key))] + val(cur))]


def forecast_row(t):
    """A forecast occurrence, extended with the category + money account so the
    pill can prefill an add form. Amounts stay native (as the periodic rule
    defines them) — confirming a forecast writes the real figure, not a
    market-valued one."""
    row = txn_row(t)
    ps = row["postings"]
    cat, asset = "", ""
    for p in ps:
        a = p["account"]
        if not cat and a.startswith(("expenses", "income")):
            cat = a
        elif not asset and a.startswith(("assets", "liabilities")):
            asset = a
    row["account"] = cat
    row["asset"] = asset or "assets:cash"
    return row


def cmd_fentries(a, b):
    """Forecast occurrences across [a,b] (native amounts), each carrying its
    category + money account. The SAME query as cmd_frange (only generated
    transactions, tag _generated-transaction), so the per-day list the calendar
    shows lines up exactly with the hollow dots — grouping/counting is done in
    the pill from these rows."""
    span = "%s..%s" % (a, day_after(b))
    return [forecast_row(t) for t in
            print_json(["--forecast=" + span, "date:" + span,
                        "tag:_generated-transaction"])]


def fmt_amount(value, currency):
    """Journal-file formatting: EUR two decimals, IRT whole Toman — both with
    thousands separators, matching main.journal's commodity styles."""
    if currency == "IRT":
        return "{:,} IRT".format(int(round(value)))
    return "{:,.2f} {}".format(value, currency)


def cmd_add(payload):
    try:
        p = json.loads(payload)
        date = p["date"]
        desc = p["description"]
        amount = float(p["amount"])
        currency = p["currency"]
        kind = p.get("kind", "expense")
        account = p["account"]
        asset = p.get("asset", "assets:cash")
    except Exception as e:
        return {"ok": False, "error": "bad payload: %s" % e}
    d = datetime.date.fromisoformat(date)
    month_file = os.path.join(FINANCE_DIR,
                              "%d-%s.journal" % (d.year, MONTHS[d.month - 1]))
    try:
        if not os.path.exists(month_file):
            # main.journal's `include ????-*.journal` glob picks this up.
            with open(month_file, "w") as f:
                f.write("; %s\n" % os.path.basename(month_file))
        # expense: category carries the amount; income: the asset does.
        first = account if kind == "expense" else asset
        second = asset if kind == "expense" else account
        with open(month_file, "a") as f:
            f.write("\n%s %s\n    %-28s  %s\n    %s\n"
                    % (date, desc, first, fmt_amount(amount, currency), second))
    except Exception as e:
        return {"ok": False, "error": str(e)}
    try:
        r = subprocess.run(["hledger", "-f", MAIN, "check"],
                           capture_output=True, text=True, timeout=15)
        if r.returncode != 0:
            # keep the entry for fixing in Emacs; surface the tail of the error
            return {"ok": False, "error": r.stderr.strip()[-400:]}
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True}


def cmd_accounts():
    groups = {"expenses": [], "income": [], "assets": [],
              "liabilities": [], "other": []}
    out = run_hledger(["accounts"])
    for name in (out or "").split("\n"):
        name = name.strip()
        if not name:
            continue
        top = name.split(":", 1)[0]
        groups[top if top in groups else "other"].append(name)
    return groups


def amounts_of(raw):
    """[{currency, value}] summed per commodity. Valuation (-X) can leave a
    market-valued amount and a native amount of the SAME commodity unmerged
    (e.g. bank-EUR-as-IRT plus cash-IRT); coalescing gives one figure per
    currency, which is what every report here wants to show."""
    order, sums = [], {}
    for a in raw:
        cur = a.get("acommodity", "")
        if cur not in sums:
            sums[cur] = 0
            order.append(cur)
        sums[cur] += a.get("aquantity", {}).get("floatingPoint", 0)
    return [{"currency": c, "value": sums[c]} for c in order]


def balance_data(query, cur="native"):
    out = run_hledger(["balance", "-O", "json"] + val(cur)
                      + (query or ["assets", "liabilities"]))
    if out is None:
        return {"rows": [], "totals": []}
    try:
        rows_raw, totals_raw = json.loads(out)
    except Exception:
        return {"rows": [], "totals": []}
    rows = [{"account": r[0],
             "indent": r[0].count(":"),
             "amounts": amounts_of(r[3])} for r in rows_raw]
    return {"rows": rows, "totals": amounts_of(totals_raw)}


def cmd_balances(cur="native"):
    return balance_data(["assets", "liabilities"], cur)


def add_months(d, n):
    m = d.month - 1 + n
    y = d.year + m // 12
    m = m % 12 + 1
    day = min(d.day, [31, 29 if y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
                      else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1])
    return datetime.date(y, m, day)


def kind_of(account, amount):
    """Coarse expense/income/transfer classification for a single posting."""
    if account.startswith("income"):
        return "income"
    if account.startswith("expenses"):
        return "expense"
    return "income" if amount >= 0 else "expense"


def cmd_timeline(cur="native", months=12):
    """A running projection of liquid assets from today over the next `months`.
    One row per real-or-forecast event that moves an asset account, each with the
    event amount and the projected running balance after it (register semantics).
    `-H` (--historical) seeds the running balance with the actual current asset
    balance, so the projection continues from today's real total rather than 0."""
    today = datetime.date.today()
    span = "%s..%s" % (today.isoformat(),
                       add_months(today, months).isoformat())
    out = run_hledger(["register", "assets", "--forecast=" + span,
                       "date:" + span, "-H", "-O", "json"] + val(cur))
    if out is None:
        return []
    try:
        raw = json.loads(out)
    except Exception:
        return []
    rows = []
    for r in raw:
        # register row = [date, _, description, posting, running_balance[]]
        date, _, desc, posting, bal = r[0], r[1], r[2], r[3], r[4]
        pa = posting.get("pamount", [])
        amount = pa[0].get("aquantity", {}).get("floatingPoint", 0) if pa else 0
        currency = pa[0].get("acommodity", "") if pa else ""
        rows.append({"date": date, "description": desc,
                     "amount": abs(amount), "currency": currency,
                     "kind": kind_of(posting.get("paccount", ""), amount),
                     "balance": amounts_of(bal)})
    return rows


def cmd_register(query, limit, cur="native"):
    rows = [txn_row(t) for t in print_json(([query] if query else []) + val(cur))]
    return list(reversed(rows))[:limit]


def valued_total(query, cur):
    """Single float: the total of `query` valued in `cur`. (After valuation the
    totals coalesce to one commodity, so summing is safe.)"""
    return sum(t["value"] for t in balance_data(query, cur)["totals"])


def wishlist_ordered_valued(cur):
    """Wishlist items in FILE ORDER (the buy priority), each with its price
    valued in `cur`. Prices come from the book's prices.journal, so valuation
    runs against MAIN *and* the wishlist file together (`-f MAIN -f WISHLIST`);
    the wishlist file alone carries no exchange rates. `price` is None when no
    rate connects the item's commodity to `cur`."""
    ordered = []
    for t in print_json([], WISHLIST):
        row = txn_row(t)
        wish = [p for p in row["postings"] if p["account"].startswith("wishlist")]
        if not wish:
            continue
        ncur = wish[0]["currency"]
        namt = sum(p["value"] for p in wish if p["currency"] == ncur)
        ordered.append({"description": row["description"],
                        "account": wish[0]["account"],
                        "native_amount": namt, "native_currency": ncur})
    valmap = {}
    out = run_hledger(["-f", WISHLIST, "balance", "^wishlist", "--flat",
                       "--no-total", "-O", "json"] + val(cur))
    if out:
        try:
            rows, _ = json.loads(out)
            for r in rows:
                valmap[r[0]] = sum(a.get("aquantity", {}).get("floatingPoint", 0)
                                   for a in r[3])
        except Exception:
            pass
    for it in ordered:
        it["price"] = valmap.get(
            it["account"],
            it["native_amount"] if it["native_currency"] == cur else None)
    return ordered


def cmd_wishlist(cur=None):
    """Wishlist with buffer-aware affordability. A wish is affordable when
    liquid assets MINUS the plan buffer still cover its price — so a purchase is
    never called affordable if it would eat into your base needed money. Honours
    the display currency (EUR/IRT re-value everything, buffer included)."""
    pc, buffer, _goal, _gd, _conf = plan_targets(cur)
    liquid = valued_total(["assets"], pc)
    spendable = liquid - buffer
    items = []
    for it in wishlist_ordered_valued(pc):
        price = it["price"]
        items.append({"description": it["description"],
                      "amount": price if price is not None else it["native_amount"],
                      "currency": pc if price is not None else it["native_currency"],
                      "affordable": (spendable >= price) if price is not None else None})
    return {"liquid": liquid, "buffer": buffer, "spendable": spendable,
            "currency": pc, "items": items}


def first_of_month(d):
    return datetime.date(d.year, d.month, 1)


def month_trajectory(cur, until):
    """[{month:'YYYY-MM', end_date, balance}] — projected month-end liquid-asset
    balances from this month through the month containing `until`, forecast +
    historical (running from today's real total), valued in `cur`."""
    today = datetime.date.today()
    end = add_months(first_of_month(until), 1)   # exclusive: include until's month
    out = run_hledger(["balance", "assets", "--forecast", "-H", "-M",
                       "--depth", "1", "-b", first_of_month(today).isoformat(),
                       "-e", end.isoformat(), "-O", "json"] + val(cur))
    if not out:
        return []
    try:
        d = json.loads(out)
    except Exception:
        return []
    totals = d.get("prTotals", {}).get("prrAmounts", [])
    months = []
    for i, per in enumerate(d.get("prDates", [])):
        start = per[0].get("contents", "")
        endbound = per[1].get("contents", "")
        try:
            end_date = (datetime.date.fromisoformat(endbound)
                        - datetime.timedelta(days=1)).isoformat()
        except Exception:
            end_date = endbound
        amts = totals[i] if i < len(totals) else []
        bal = sum(a.get("aquantity", {}).get("floatingPoint", 0) for a in amts)
        months.append({"month": start[:7], "end_date": end_date, "balance": bal})
    return months


def cmd_plan(cur=None):
    """A month-by-month savings + wishlist-purchase schedule for the current
    book. It starts from the projected month-end balance trajectory (forecast,
    valued in the plan currency), then walks the wishlist IN FILE ORDER and
    places each item in the EARLIEST month where buying it keeps every later
    month-end balance at or above the floor. The floor is `buffer` before
    goal-date and max(buffer, goal) on/after it — so a purchase can never drop a
    projected balance below your base needed money (or your saved-by goal).
    Purchases never move earlier than a higher-priority item's month, so entry
    order is respected; they need not land in the same month. Honours the display
    currency (EUR/IRT re-value the whole plan, buffer + goal included)."""
    pc, buffer, goal, gdate, conf = plan_targets(cur)
    today = datetime.date.today()
    horizon = add_months(today, 12)
    if gdate:
        try:
            gd = datetime.date.fromisoformat(gdate)
            if gd > horizon:
                horizon = gd
        except Exception:
            gdate = None
    months = month_trajectory(pc, horizon)
    base = {"currency": pc, "buffer": buffer, "goal": goal, "goal_date": gdate}
    if not months:
        return dict(base, start=0.0, months=[], items=[])
    start = valued_total(["assets"], pc)
    # baseline monthly net (before any purchase) = Δ of month-end balances
    prev = start
    for m in months:
        m["net"] = m["balance"] - prev
        prev = m["balance"]
    # per-month floor
    def floor_at(i):
        if goal is not None and gdate and months[i]["end_date"] >= gdate:
            return max(buffer, goal)
        return buffer
    floors = [floor_at(i) for i in range(len(months))]
    bal = [m["balance"] for m in months]        # mutated as purchases are placed
    items = wishlist_ordered_valued(pc)
    plan_items = []
    min_i = 0
    for it in items:
        price = it["price"]
        rec = {"description": it["description"], "price": price, "currency": pc}
        placed = None
        if price is not None:
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
            if price is not None:
                # best headroom any allowed month offers; shortfall = how much
                # more you'd need for it to ever fit within the horizon.
                best = None
                for i in range(min_i, len(months)):
                    head = min(bal[k] - floors[k] for k in range(i, len(months)))
                    best = head if best is None else max(best, head)
                rec["shortfall"] = price - (best or 0.0)
        plan_items.append(rec)
    month_out = []
    for i, m in enumerate(months):
        buys = [p["description"] for p in plan_items if p.get("month_index") == i]
        month_out.append({"month": m["month"], "end_date": m["end_date"],
                          "net": m["net"], "projected": bal[i],
                          "floor": floors[i], "cushion": bal[i] - floors[i],
                          "purchases": buys})
    return dict(base, start=start, months=month_out, items=plan_items)


def cmd_today_has_entry():
    today = datetime.date.today().isoformat()
    n = len(print_json(["date:%s..%s" % (today, day_after(today))]))
    return {"has": n > 0, "count": n}


def run_git(args, timeout=30):
    """(rc, stdout, stderr) of git run at BASE_DIR — the whole finance dir is
    one repo; books are folders inside it. Never raises."""
    try:
        r = subprocess.run(["git", "-C", BASE_DIR] + args,
                           capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def cmd_git_status():
    """Offline snapshot for the pill's git row: branch, dirty file count,
    ahead/behind origin (as of the last fetch), last commit subject."""
    rc, _, _ = run_git(["rev-parse", "--git-dir"])
    if rc != 0:
        return {"repo": False}
    _, branch, _ = run_git(["rev-parse", "--abbrev-ref", "HEAD"])
    _, porcelain, _ = run_git(["status", "--porcelain"])
    dirty = len([l for l in porcelain.splitlines() if l.strip()])
    ahead = behind = 0
    rc, counts, _ = run_git(["rev-list", "--left-right", "--count",
                             "HEAD...@{upstream}"])
    if rc == 0 and counts:
        parts = counts.split()
        if len(parts) == 2:
            ahead, behind = int(parts[0]), int(parts[1])
    _, last, _ = run_git(["log", "-1", "--format=%h %s"])
    return {"repo": True, "branch": branch, "dirty": dirty,
            "ahead": ahead, "behind": behind, "last": last}


def cmd_git_sync():
    """Fetch + fast-forward pull. Refuses to merge: a diverged branch is
    reported for fixing in a terminal."""
    rc, _, err = run_git(["fetch", "--quiet"], timeout=60)
    if rc != 0:
        return {"ok": False, "error": err[-200:] or "fetch failed"}
    before_rc, before, _ = run_git(["rev-parse", "HEAD"])
    rc, _, err = run_git(["merge", "--ff-only", "@{upstream}"], timeout=60)
    if rc != 0:
        return {"ok": False, "error": "diverged — merge in a terminal"}
    _, after, _ = run_git(["rev-parse", "HEAD"])
    return {"ok": True, "changed": before != after}


def cmd_git_push():
    """Commit everything (if dirty) and push. A rejected push is reported, not
    resolved — pull or branch in a terminal."""
    _, porcelain, _ = run_git(["status", "--porcelain"])
    committed = False
    if porcelain.strip():
        run_git(["add", "-A"])
        today = datetime.date.today().isoformat()
        rc, _, err = run_git(["commit", "-m", "pill: finance entries %s" % today])
        if rc != 0:
            return {"ok": False, "error": err[-200:] or "commit failed"}
        committed = True
    rc, _, err = run_git(["push", "--quiet"], timeout=60)
    if rc != 0:
        tail = err[-200:]
        if "rejected" in err or "non-fast-forward" in err or "fetch first" in err:
            tail = "push rejected — pull first (sync), or fix in a terminal"
        return {"ok": False, "committed": committed, "error": tail}
    return {"ok": True, "committed": committed, "pushed": True}


def main():
    global FINANCE_DIR, MAIN, WISHLIST
    argv = sys.argv[1:]
    # optional leading `--entity NAME` / `-E NAME` selects the book
    if len(argv) >= 2 and argv[0] in ("--entity", "-E"):
        FINANCE_DIR = entity_dir(argv[1])
        MAIN = os.path.join(FINANCE_DIR, "main.journal")
        WISHLIST = os.path.join(FINANCE_DIR, "wishlist.journal")
        argv = argv[2:]
    cmd = argv[0] if argv else ""
    if cmd == "range" and len(argv) > 2:
        out = cmd_range(argv[1], argv[2])
    elif cmd == "frange" and len(argv) > 2:
        out = cmd_frange(argv[1], argv[2])
    elif cmd == "fentries" and len(argv) > 2:
        out = cmd_fentries(argv[1], argv[2])
    elif cmd == "day" and len(argv) > 1:
        out = cmd_day(argv[1], argv[2] if len(argv) > 2 else "native")
    elif cmd == "add" and len(argv) > 1:
        out = cmd_add(argv[1])
    elif cmd == "accounts":
        out = cmd_accounts()
    elif cmd == "balances":
        out = cmd_balances(argv[1] if len(argv) > 1 else "native")
    elif cmd == "timeline":
        cur = argv[1] if len(argv) > 1 else "native"
        out = cmd_timeline(cur, int(argv[2]) if len(argv) > 2 else 12)
    elif cmd == "register":
        query = argv[1] if len(argv) > 1 else ""
        limit = int(argv[2]) if len(argv) > 2 else 50
        out = cmd_register(query, limit, argv[3] if len(argv) > 3 else "native")
    elif cmd == "wishlist":
        out = cmd_wishlist(argv[1] if len(argv) > 1 else None)
    elif cmd == "plan":
        out = cmd_plan(argv[1] if len(argv) > 1 else None)
    elif cmd == "entities":
        out = cmd_entities()
    elif cmd == "today-has-entry":
        out = cmd_today_has_entry()
    elif cmd == "git-status":
        out = cmd_git_status()
    elif cmd == "git-sync":
        out = cmd_git_sync()
    elif cmd == "git-push":
        out = cmd_git_push()
    else:
        out = []
    sys.stdout.write(json.dumps(out))


if __name__ == "__main__":
    main()
