#!/usr/bin/env python3
# gcalbridge.py — calendar backend for the pill's calendar menu + account manager.
#
#   fetch [A B]     refresh the event cache for window [A,B] from every account —
#                   KDE Google + pill-added Google + pill-added Proton (ICS) — then
#                   dedupe and print the cached JSON (hourly Timer + refetch button).
#   read            print the cached JSON with no network I/O (menu open).
#   accounts        print JSON of all accounts for the settings page:
#                   {"accounts":[{id, provider, label, source, removable}], "errors":[]}
#   add-google      run a loopback OAuth flow (opens the browser), store the refresh
#                   token in the keyring, register the account; print {ok, label, error}
#   add-proton URL [LABEL]
#                   register a Proton / iCal share-URL calendar (URL kept in the
#                   keyring); print {ok, label, error}
#   remove ID       remove a pill-added account and its keyring secret; print {ok}
#
# KDE Google accounts come from KDE Online Accounts (libaccounts) with tokens from
# signond (the refresh token stays in KWallet). Pill-added Google accounts use our
# own loopback OAuth — reusing the KDE OAuth client, whose registered localhost
# redirect lets the loopback flow use any port — with the refresh token in the
# keyring (secret-tool). Proton has no calendar API and is end-to-end encrypted, so
# a "Proton" account is that calendar's ICS share link, fetched + parsed here.
# Everything is best-effort: failures are recorded in "errors" and the rest render.
import sys, os, json, re, tempfile, subprocess, hashlib
from datetime import date, datetime, timedelta

CACHE_DIR = os.path.expanduser("~/.cache/quickshell-pill")
CACHE = os.path.join(CACHE_DIR, "gcal-events.json")
DATA_DIR = os.path.expanduser("~/.local/share/quickshell-pill")
ACCOUNTS_FILE = os.path.join(DATA_DIR, "accounts.json")
KEYRING_SERVICE = "quickshell-pill-cal"
PROVIDER = "/usr/share/accounts/providers/kde/google.provider"
SSO = "com.google.code.AccountsSSO.SingleSignOn"
SSO_PATH = "/com/google/code/AccountsSSO/SingleSignOn"
API = "https://www.googleapis.com/calendar/v3"
TOKEN_URL = "https://oauth2.googleapis.com/token"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
USERINFO = "https://www.googleapis.com/oauth2/v3/userinfo"
CAL_SCOPE = "https://www.googleapis.com/auth/calendar.readonly"
PROTON_COLOR = "#8a6fdf"  # default bar/dot colour for Proton events (ICS has none)
NO_UI = 3  # signon SessionData UiPolicy: NO_USER_INTERACTION_POLICY

# hard-coded fallbacks (also present in the provider file) so a missing/renamed
# provider file doesn't break auth.
FALLBACK = {
    "Host": "accounts.google.com",
    "AuthPath": "o/oauth2/auth?access_type=offline&approval_prompt=force",
    "TokenPath": "o/oauth2/token",
    "RedirectUri": "http://localhost/oauth2callback",
    "ResponseType": "code",
    "ClientId": "317066460457-pkpkedrvt2ldq6g2hj1egfka2n7vpuoo.apps.googleusercontent.com",
    "ClientSecret": "Y8eFAaWfcanV3amZdDvtbYUq",
    "Scope": ["https://www.googleapis.com/auth/calendar"],
}


def _empty(errors=None):
    return {"events": [], "window": None, "fetched": None,
            "errors": errors or [], "accounts": []}


# ---------------------------------------------------------------- pill accounts
def _load_accounts():
    try:
        with open(ACCOUNTS_FILE, encoding="utf-8") as fh:
            return (json.load(fh) or {}).get("accounts", [])
    except Exception:
        return []


def _save_accounts(accs):
    os.makedirs(DATA_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=DATA_DIR, prefix=".accts-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump({"accounts": accs}, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, ACCOUNTS_FILE)


def _secret_store(acc_id, value):
    try:
        p = subprocess.run(
            ["secret-tool", "store", "--label", "pill calendar " + acc_id,
             "service", KEYRING_SERVICE, "account", acc_id],
            input=value.encode(), capture_output=True, timeout=20)
        return p.returncode == 0
    except Exception:
        return False


def _secret_lookup(acc_id):
    try:
        p = subprocess.run(
            ["secret-tool", "lookup", "service", KEYRING_SERVICE, "account", acc_id],
            capture_output=True, timeout=20)
        return p.stdout.decode("utf-8", "replace").strip() if p.returncode == 0 else ""
    except Exception:
        return ""


def _secret_clear(acc_id):
    try:
        subprocess.run(["secret-tool", "clear", "service", KEYRING_SERVICE,
                        "account", acc_id], capture_output=True, timeout=20)
    except Exception:
        pass


# ------------------------------------------------------------ google OAuth creds
def provider_creds():
    # Parse the (world-readable) KDE provider file for the OAuth client + endpoints.
    # Falls back to the constants above if it can't be read/parsed.
    creds = dict(FALLBACK)
    try:
        import xml.etree.ElementTree as ET

        root = ET.parse(PROVIDER).getroot()
        for s in root.iter("setting"):
            name = s.get("name")
            if name in ("Host", "AuthPath", "TokenPath", "RedirectUri",
                        "ResponseType", "ClientId", "ClientSecret") and s.text:
                creds[name] = s.text.strip()
            elif name == "Scope" and s.text:
                sc = re.findall(r"'([^']+)'", s.text)
                if sc:
                    creds["Scope"] = sc
    except Exception:
        pass
    if "https://www.googleapis.com/auth/calendar" in creds["Scope"]:
        creds["Scope"] = ["https://www.googleapis.com/auth/calendar"]
    return creds


def list_accounts(errors):
    # Enumerate enabled KDE Google accounts + their signond credentials id via
    # libaccounts-glib. Returns [{name, cred_id}].
    out = []
    try:
        import gi

        gi.require_version("Accounts", "1.0")
        from gi.repository import Accounts

        mgr = Accounts.Manager.new()
        for aid in mgr.list():
            acc = mgr.get_account(aid)
            if not acc or acc.get_provider_name() != "google" or not acc.get_enabled():
                continue
            name = acc.get_display_name() or ("account %d" % aid)
            cred_id = 0
            try:
                asvc = Accounts.AccountService.new(acc, None)  # None -> global service
                cred_id = int(asvc.get_auth_data().get_credentials_id())
            except Exception:
                cred_id = 0
            if cred_id:
                out.append({"name": name, "cred_id": cred_id})
            else:
                errors.append("%s: no credentials id" % name)
    except Exception as e:
        errors.append("accounts: %s" % e)
    return out


def access_token(cred_id, creds):
    # Ask signond for a fresh access token for this credentials id, no UI. The
    # refresh token lives in KWallet; signond refreshes and hands us only the
    # access token. Returns "" on any failure.
    import dbus

    bus = dbus.SessionBus()
    auth = dbus.Interface(bus.get_object(SSO, SSO_PATH), SSO + ".AuthService")
    path = auth.getAuthSessionObjectPath(dbus.UInt32(cred_id), "", "oauth2")
    sess = dbus.Interface(bus.get_object(SSO, path), SSO + ".AuthSession")
    sd = dbus.Dictionary(
        {
            "Host": creds["Host"], "AuthPath": creds["AuthPath"],
            "TokenPath": creds["TokenPath"], "RedirectUri": creds["RedirectUri"],
            "ResponseType": creds["ResponseType"], "ClientId": creds["ClientId"],
            "ClientSecret": creds["ClientSecret"], "ForceClientAuthViaRequestBody": True,
            "Scope": dbus.Array(creds["Scope"], signature="s"),
            "UiPolicy": dbus.UInt32(NO_UI),
        },
        signature="sv",
    )
    reply = sess.process(sd, "web_server", timeout=30)
    return str(reply.get("AccessToken", "") or "")


def _pill_google_token(acc, creds, errors):
    # Refresh a pill-added Google account's access token from its keyring refresh token.
    import requests

    rt = _secret_lookup(acc["id"])
    if not rt:
        errors.append("%s: not signed in (re-add the account)" % acc.get("label", acc["id"]))
        return ""
    try:
        r = requests.post(TOKEN_URL, data={
            "client_id": creds["ClientId"], "client_secret": creds["ClientSecret"],
            "refresh_token": rt, "grant_type": "refresh_token"}, timeout=25)
    except Exception as e:
        errors.append("%s: token refresh failed (%s)" % (acc.get("label", ""), str(e)[:100]))
        return ""
    if r.status_code != 200:
        errors.append("%s: token refresh rejected (re-add the account)" % acc.get("label", ""))
        return ""
    return r.json().get("access_token", "") or ""


# ----------------------------------------------------------- google event fetch
def _get(session, url, params, token):
    r = session.get(url, headers={"Authorization": "Bearer " + token},
                    params=params, timeout=25)
    r.raise_for_status()
    return r.json()


_URL_RE = re.compile(r"https?://\S+")
_JOIN_RE = re.compile(r"https?://\S*(?:meet\.google|zoom\.us|teams\.microsoft|"
                      r"webex\.com|whereby\.com|meet\.jit\.si)\S*", re.I)


def _join_from_text(*fields):
    for field in fields:
        m = _JOIN_RE.search(field or "")
        if m:
            return m.group(0).rstrip(").,>")
    m = _URL_RE.search(fields[0] or "" if fields else "")
    return m.group(0).rstrip(").,>") if m else ""


def _join_link(ev):
    if ev.get("hangoutLink"):
        return ev["hangoutLink"]
    conf = ev.get("conferenceData") or {}
    for ep in conf.get("entryPoints", []) or []:
        if ep.get("entryPointType") == "video" and ep.get("uri"):
            return ep["uri"]
    return _join_from_text(ev.get("location", ""), ev.get("description", ""))


def _local(dtstr):
    s = dtstr.replace("Z", "+00:00")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is not None:
        dt = dt.astimezone()
    return dt.strftime("%Y-%m-%d"), dt.strftime("%H:%M")


def _day_span(start_key, end_key, all_day):
    d0 = date(*map(int, start_key.split("-")))
    d1 = date(*map(int, end_key.split("-")))
    if all_day:
        d1 -= timedelta(days=1)
    if d1 < d0:
        d1 = d0
    out, d = [], d0
    while d <= d1 and len(out) < 60:
        out.append(d.isoformat())
        d += timedelta(days=1)
    return out


def normalize(ev, account, cal, color, access, source):
    start, end = ev.get("start", {}), ev.get("end", {})
    all_day = "date" in start
    if all_day:
        start_key = start.get("date", "")
        end_key = end.get("date", start_key)
        start_time = end_time = ""
    else:
        sd = start.get("dateTime", "")
        ed = end.get("dateTime", sd)
        start_key, start_time = _local(sd) if sd else ("", "")
        end_key, end_time = _local(ed) if ed else (start_key, "")
    if not start_key:
        return None
    atts = []
    for a in ev.get("attendees", []) or []:
        if a.get("resource"):
            continue
        atts.append({"name": a.get("displayName") or a.get("email") or "",
                     "response": a.get("responseStatus", ""), "self": bool(a.get("self"))})
    org = ev.get("organizer", {}) or {}
    return {
        "id": ev.get("id", ""),
        "uid": ev.get("iCalUID", "") or ev.get("id", ""),
        "access": access or "",
        "source": source,
        "provider": "google",
        "account": account,
        "calendar": cal,
        "color": color or "",
        "summary": ev.get("summary", "") or "(no title)",
        "allDay": all_day,
        "days": _day_span(start_key, end_key, all_day),
        "startKey": start_key, "endKey": end_key,
        "startTime": start_time, "endTime": end_time,
        "location": ev.get("location", "") or "",
        "description": (ev.get("description", "") or "").strip(),
        "attendees": atts,
        "organizer": org.get("displayName") or org.get("email") or "",
        "joinLink": _join_link(ev),
        "htmlLink": ev.get("htmlLink", "") or "",
        "status": ev.get("status", ""),
    }


def _fetch_google_events(token, account, source, time_min, time_max, errors):
    import requests

    out = []
    session = requests.Session()
    try:
        cal_list = _get(session, API + "/users/me/calendarList", {"maxResults": 250}, token)
    except Exception as e:
        errors.append("%s: calendar list failed (%s)" % (account, str(e)[:120]))
        return []
    for cal in cal_list.get("items", []):
        if cal.get("hidden") or not (cal.get("selected") or cal.get("primary")):
            continue
        cal_id = cal.get("id")
        cal_name = cal.get("summaryOverride") or cal.get("summary") or cal_id
        color = cal.get("backgroundColor", "")
        access = cal.get("accessRole", "")
        page = None
        for _ in range(20):
            params = {"timeMin": time_min, "timeMax": time_max, "singleEvents": "true",
                      "orderBy": "startTime", "maxResults": 250}
            if page:
                params["pageToken"] = page
            try:
                data = _get(session, API + "/calendars/%s/events"
                            % requests.utils.quote(cal_id, safe=""), params, token)
            except Exception as e:
                errors.append("%s / %s: events failed (%s)" % (account, cal_name, str(e)[:100]))
                break
            for ev in data.get("items", []):
                if ev.get("status") == "cancelled":
                    continue
                n = normalize(ev, account, cal_name, color, access, source)
                if n:
                    out.append(n)
            page = data.get("nextPageToken")
            if not page:
                break
    return out


def fetch_account(acct, creds, time_min, time_max, errors):
    # KDE Google account: token via signond, then the shared event fetch.
    try:
        token = access_token(acct["cred_id"], creds)
    except Exception as e:
        errors.append("%s: sign-in failed (%s)" % (acct["name"], str(e)[:120]))
        return []
    if not token:
        errors.append("%s: no access token (re-add the account in System Settings?)" % acct["name"])
        return []
    return _fetch_google_events(token, acct["name"], "kde", time_min, time_max, errors)


def fetch_pill_google(acc, creds, time_min, time_max, errors):
    token = _pill_google_token(acc, creds, errors)
    if not token:
        return []
    return _fetch_google_events(token, acc.get("label", acc["id"]), "pill",
                                time_min, time_max, errors)


# ------------------------------------------------------------- Proton / ICS feed
def _ics_unfold(text):
    # RFC5545 line unfolding: a line beginning with space/tab continues the prior.
    out = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and out:
            out[-1] += raw[1:]
        else:
            out.append(raw)
    return out


def _ics_unescape(v):
    return (v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
             .replace("\\;", ";").replace("\\\\", "\\"))


def _ics_prop(line):
    # "NAME;PARAM=x;PARAM2=y:VALUE" -> (NAME, {params}, VALUE)
    if ":" not in line:
        return None
    head, value = line.split(":", 1)
    parts = head.split(";")
    name = parts[0].upper()
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.upper()] = v.strip('"')
    return name, params, value


def _ics_dt(value, params):
    # returns (datetime|date, is_date)
    from dateutil import tz as _tz

    if params.get("VALUE") == "DATE" or (len(value) == 8 and "T" not in value):
        return date(int(value[0:4]), int(value[4:6]), int(value[6:8])), True
    v = value
    utc = v.endswith("Z")
    if utc:
        v = v[:-1]
    dt = datetime.strptime(v, "%Y%m%dT%H%M%S")
    if utc:
        dt = dt.replace(tzinfo=_tz.UTC)
    elif params.get("TZID"):
        dt = dt.replace(tzinfo=_tz.gettz(params["TZID"]) or _tz.tzlocal())
    else:
        dt = dt.replace(tzinfo=_tz.tzlocal())  # floating -> local
    return dt, False


def _local_keys(dt, is_date):
    from dateutil import tz as _tz

    if is_date:
        return dt.isoformat(), ""
    lo = dt.astimezone(_tz.tzlocal())
    return lo.strftime("%Y-%m-%d"), lo.strftime("%H:%M")


def _ics_person(value, params):
    name = params.get("CN") or value.replace("mailto:", "").replace("MAILTO:", "")
    return name, (params.get("PARTSTAT", "") or "").lower()


def _parse_vevents(lines):
    events, cur = [], None
    for line in lines:
        u = line.upper()
        if u == "BEGIN:VEVENT":
            cur = {"attendees": []}
        elif u == "END:VEVENT":
            if cur is not None:
                events.append(cur)
            cur = None
        elif cur is not None:
            p = _ics_prop(line)
            if not p:
                continue
            name, params, value = p
            if name == "UID":
                cur["uid"] = value
            elif name == "SUMMARY":
                cur["summary"] = _ics_unescape(value)
            elif name == "LOCATION":
                cur["location"] = _ics_unescape(value)
            elif name == "DESCRIPTION":
                cur["description"] = _ics_unescape(value)
            elif name == "DTSTART":
                cur["start"], cur["all_day"] = _ics_dt(value, params)
            elif name == "DTEND":
                cur["end"], _ = _ics_dt(value, params)
            elif name == "RRULE":
                cur["rrule"] = value
            elif name == "EXDATE":
                cur.setdefault("exdate", []).append((value, params))
            elif name == "ORGANIZER":
                cur["organizer"] = _ics_person(value, params)[0]
            elif name == "ATTENDEE":
                nm, st = _ics_person(value, params)
                cur["attendees"].append({"name": nm, "response": st, "self": False})
            elif name in ("COLOR", "X-APPLE-CALENDAR-COLOR") and value:
                cur["color"] = value.strip()
    return events


def _expand_occurrences(ve, win_start, win_end):
    # yields (start_dt_or_date, is_date) occurrences within [win_start, win_end]
    from dateutil import tz as _tz
    from dateutil.rrule import rrulestr

    start = ve.get("start")
    if start is None:
        return []
    is_date = ve.get("all_day", False)
    base = (datetime(start.year, start.month, start.day, tzinfo=_tz.tzlocal())
            if is_date else start)
    if not ve.get("rrule"):
        if win_start <= base <= win_end:
            return [(start, is_date)]
        return []
    text = "DTSTART:" + base.astimezone(_tz.UTC).strftime("%Y%m%dT%H%M%SZ") + \
           "\nRRULE:" + ve["rrule"]
    for val, params in ve.get("exdate", []):
        for piece in val.split(","):
            try:
                edt, ed_date = _ics_dt(piece, params)
                eb = (datetime(edt.year, edt.month, edt.day, tzinfo=_tz.tzlocal())
                      if ed_date else edt)
                text += "\nEXDATE:" + eb.astimezone(_tz.UTC).strftime("%Y%m%dT%H%M%SZ")
            except Exception:
                pass
    try:
        rs = rrulestr(text, forceset=True)
        occ = rs.between(win_start, win_end, inc=True)
    except Exception:
        return []
    out = []
    for o in occ[:366]:
        if is_date:
            out.append((o.date(), True))
        else:
            out.append((o, False))
    return out


def fetch_proton(acc, a, b, errors):
    import requests
    from dateutil import tz as _tz

    url = _secret_lookup(acc["id"])
    if not url:
        errors.append("%s: missing iCal URL (re-add)" % acc.get("label", ""))
        return []
    try:
        r = requests.get(url, timeout=25)
        r.raise_for_status()
        text = r.text
    except Exception as e:
        errors.append("%s: iCal fetch failed (%s)" % (acc.get("label", ""), str(e)[:100]))
        return []
    if "BEGIN:VCALENDAR" not in text[:4000]:
        errors.append("%s: not an iCal feed" % acc.get("label", ""))
        return []

    win_start = datetime(*map(int, a.split("-")), 0, 0, tzinfo=_tz.tzlocal())
    win_end = datetime(*map(int, b.split("-")), 23, 59, 59, tzinfo=_tz.tzlocal())
    label = acc.get("label", "Proton")
    out = []
    for ve in _parse_vevents(_ics_unfold(text)):
        start = ve.get("start")
        if start is None:
            continue
        is_date = ve.get("all_day", False)
        end = ve.get("end") or start
        # duration between the (original) start and end
        if is_date:
            dur = timedelta(days=1)
            try:
                dur = date(end.year, end.month, end.day) - date(start.year, start.month, start.day)
                if dur.days < 1:
                    dur = timedelta(days=1)
            except Exception:
                dur = timedelta(days=1)
        else:
            try:
                dur = end - start
            except Exception:
                dur = timedelta(hours=1)
        for occ_start, occ_is_date in _expand_occurrences(ve, win_start, win_end):
            if occ_is_date:
                s_key = occ_start.isoformat()
                e_key = (occ_start + dur).isoformat()
                s_time = e_time = ""
            else:
                occ_end = occ_start + dur
                s_key, s_time = _local_keys(occ_start, False)
                e_key, e_time = _local_keys(occ_end, False)
            uid = ve.get("uid", "")
            out.append({
                "id": (uid + "|" + s_key + s_time) if uid else (s_key + s_time + (ve.get("summary", ""))),
                "uid": uid,
                "access": "owner", "source": "proton", "provider": "proton",
                "account": label, "calendar": label,
                "color": ve.get("color", "") or PROTON_COLOR,
                "summary": ve.get("summary", "") or "(no title)",
                "allDay": occ_is_date,
                "days": _day_span(s_key, e_key, occ_is_date),
                "startKey": s_key, "endKey": e_key,
                "startTime": s_time, "endTime": e_time,
                "location": ve.get("location", ""),
                "description": ve.get("description", ""),
                "attendees": ve.get("attendees", []),
                "organizer": ve.get("organizer", ""),
                "joinLink": _join_from_text(ve.get("location", ""), ve.get("description", "")),
                "htmlLink": "", "status": "",
            })
    return out


# ------------------------------------------------------------------------ dedup
_ACCESS_RANK = {"owner": 3, "writer": 2, "reader": 1, "freeBusyReader": 0}
# source preference: a Proton original beats a Google-imported copy; a pill-added
# Google account beats the same account read from KDE ("ignore the KDE one").
_SOURCE_BONUS = {"proton": 3, "pill": 2, "kde": 1}


def _score(e):
    return _ACCESS_RANK.get(e.get("access", ""), 0) * 10 + _SOURCE_BONUS.get(e.get("source", ""), 0)


def _dedup(events):
    # Collapse copies of the same instance that show up on more than one calendar,
    # account or provider. Key = normalized iCalUID/UID (domain stripped, so a
    # Google-imported Proton event folds with the Proton original) + the instance
    # start — so distinct recurring instances (same UID, different start) survive.
    # The higher-scoring copy wins (access role, then source preference).
    best, order = {}, []
    for e in events:
        uid = e.get("uid", "") or e.get("id", "")
        if "@" in uid:
            uid = uid.rsplit("@", 1)[0]
        base = uid or e.get("id", "") or ("obj%d" % id(e))
        key = base + "|" + e.get("startKey", "") + "|" + e.get("startTime", "")
        if key not in best:
            best[key] = e
            order.append(key)
        elif _score(e) > _score(best[key]):
            best[key] = e
    return [best[k] for k in order]


# ------------------------------------------------------------------ commands
def fetch(a, b):
    errors = []
    creds = provider_creds()
    time_min = a + "T00:00:00Z"
    time_max = b + "T23:59:59Z"
    events, names = [], []

    for acc in _load_accounts():
        names.append(acc.get("label", acc["id"]))
        if acc.get("provider") == "google":
            events += fetch_pill_google(acc, creds, time_min, time_max, errors)
        elif acc.get("provider") == "proton":
            events += fetch_proton(acc, a, b, errors)

    for acct in list_accounts(errors):
        names.append(acct["name"])
        events += fetch_account(acct, creds, time_min, time_max, errors)

    events = _dedup(events)
    events.sort(key=lambda e: (e["startKey"], 0 if e["allDay"] else 1,
                               e["startTime"], e["summary"]))
    env = {"events": events, "window": [a, b],
           "fetched": datetime.now().strftime("%Y-%m-%d %H:%M"),
           "errors": errors, "accounts": names}
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, prefix=".gcal-", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(env, fh, ensure_ascii=False)
        os.replace(tmp, CACHE)
    except Exception as e:
        env["errors"].append("cache write: %s" % e)
    return env


def read():
    try:
        with open(CACHE, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return _empty()


def cmd_accounts():
    errors, out = [], []
    for a in list_accounts(errors):
        out.append({"id": "kde-%s" % a["cred_id"], "provider": "google",
                    "label": a["name"], "source": "kde", "removable": False})
    for a in _load_accounts():
        out.append({"id": a["id"], "provider": a.get("provider", "google"),
                    "label": a.get("label", a["id"]), "source": "pill", "removable": True})
    return {"accounts": out, "errors": errors}


def _oauth_google(creds, errors):
    # Loopback OAuth: spin a localhost listener, open the browser, wait for the
    # redirect with the code, exchange it for a refresh token, resolve the email.
    import http.server
    import urllib.parse
    import secrets
    import time as _t
    import requests

    holder = {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.urlparse(self.path)
            if not q.path.startswith("/oauth2callback"):
                self.send_response(404)
                self.end_headers()
                return
            qs = urllib.parse.parse_qs(q.query)
            holder["code"] = qs.get("code", [""])[0]
            holder["error"] = qs.get("error", [""])[0]
            holder["state"] = qs.get("state", [""])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<html><body style='font-family:sans-serif;padding:3em'>"
                             b"<h2>Signed in.</h2><p>You can close this tab and return "
                             b"to the pill.</p></body></html>")

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    srv.timeout = 1
    port = srv.server_port
    redirect = "http://localhost:%d/oauth2callback" % port
    state = secrets.token_urlsafe(16)
    auth = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": creds["ClientId"], "redirect_uri": redirect,
        "response_type": "code", "scope": "openid email profile " + CAL_SCOPE,
        "access_type": "offline", "prompt": "consent", "state": state})
    try:
        subprocess.Popen(["xdg-open", auth], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
    except Exception:
        errors.append("could not open the browser; visit: " + auth)

    deadline = _t.time() + 180
    while "code" not in holder and "error" not in holder and _t.time() < deadline:
        srv.handle_request()
    srv.server_close()

    if holder.get("error"):
        errors.append("google auth: " + holder["error"])
        return None
    if holder.get("state") != state:
        errors.append("google auth: state mismatch")
        return None
    code = holder.get("code")
    if not code:
        errors.append("google auth: timed out")
        return None
    try:
        r = requests.post(TOKEN_URL, data={
            "client_id": creds["ClientId"], "client_secret": creds["ClientSecret"],
            "code": code, "redirect_uri": redirect,
            "grant_type": "authorization_code"}, timeout=30)
    except Exception as e:
        errors.append("google token: %s" % str(e)[:120])
        return None
    if r.status_code != 200:
        errors.append("google token: %s" % r.text[:150])
        return None
    tok = r.json()
    refresh = tok.get("refresh_token", "")
    access = tok.get("access_token", "")
    if not refresh:
        errors.append("google: no refresh token returned (revoke the app's prior "
                      "access at myaccount.google.com and retry)")
        return None
    email = ""
    try:
        ui = requests.get(USERINFO, headers={"Authorization": "Bearer " + access}, timeout=15)
        if ui.status_code == 200:
            email = ui.json().get("email", "")
    except Exception:
        pass
    return {"refresh": refresh, "email": email or "Google account"}


def cmd_add_google():
    errors = []
    res = _oauth_google(provider_creds(), errors)
    if not res:
        return {"ok": False, "error": errors[0] if errors else "sign-in failed"}
    acc_id = "g-" + hashlib.sha1(res["email"].encode()).hexdigest()[:10]
    if not _secret_store(acc_id, res["refresh"]):
        return {"ok": False, "error": "keyring store failed (is a keyring running?)"}
    accs = [a for a in _load_accounts() if a.get("id") != acc_id]
    accs.append({"id": acc_id, "provider": "google", "label": res["email"]})
    _save_accounts(accs)
    return {"ok": True, "label": res["email"]}


def cmd_add_proton(url, label):
    import requests

    url = (url or "").strip()
    if not url:
        return {"ok": False, "error": "empty URL"}
    if url.startswith("webcal://"):
        url = "https://" + url[len("webcal://"):]
    try:
        r = requests.get(url, timeout=25)
    except Exception as e:
        return {"ok": False, "error": "fetch failed: %s" % str(e)[:100]}
    if r.status_code != 200 or "BEGIN:VCALENDAR" not in r.text[:4000]:
        return {"ok": False, "error": "not an iCal feed (HTTP %s)" % r.status_code}
    acc_id = "p-" + hashlib.sha1(url.encode()).hexdigest()[:10]
    if not _secret_store(acc_id, url):
        return {"ok": False, "error": "keyring store failed (is a keyring running?)"}
    accs = [a for a in _load_accounts() if a.get("id") != acc_id]
    accs.append({"id": acc_id, "provider": "proton", "label": label or "Proton"})
    _save_accounts(accs)
    return {"ok": True, "label": label or "Proton"}


def cmd_remove(acc_id):
    accs = [a for a in _load_accounts() if a.get("id") != acc_id]
    _save_accounts(accs)
    _secret_clear(acc_id)
    return {"ok": True}


def _default_window():
    t = date.today()
    return (t - timedelta(days=14)).isoformat(), (t + timedelta(days=60)).isoformat()


def main():
    # DEMO mode: serve deterministic fake calendar/account data (demodata.py)
    # instead of hitting Google / KDE accounts, so the pill is safe to record.
    if os.environ.get("DEMO"):
        import demodata
        demodata.run("gcal", sys.argv[1:])
        return
    cmd = sys.argv[1] if len(sys.argv) > 1 else "read"
    if cmd == "fetch":
        a, b = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else _default_window()
        try:
            out = fetch(a, b)
        except Exception as e:
            out = _empty(["fetch: %s" % e])
        sys.stdout.write(json.dumps(out, ensure_ascii=False))
    elif cmd == "accounts":
        sys.stdout.write(json.dumps(cmd_accounts(), ensure_ascii=False))
    elif cmd == "add-google":
        try:
            out = cmd_add_google()
        except Exception as e:
            out = {"ok": False, "error": str(e)[:150]}
        sys.stdout.write(json.dumps(out, ensure_ascii=False))
    elif cmd == "add-proton" and len(sys.argv) > 2:
        label = sys.argv[3] if len(sys.argv) > 3 else ""
        try:
            out = cmd_add_proton(sys.argv[2], label)
        except Exception as e:
            out = {"ok": False, "error": str(e)[:150]}
        sys.stdout.write(json.dumps(out, ensure_ascii=False))
    elif cmd == "remove" and len(sys.argv) > 2:
        sys.stdout.write(json.dumps(cmd_remove(sys.argv[2]), ensure_ascii=False))
    else:  # read
        sys.stdout.write(json.dumps(read(), ensure_ascii=False))


if __name__ == "__main__":
    main()
