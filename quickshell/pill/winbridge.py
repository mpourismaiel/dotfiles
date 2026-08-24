#!/usr/bin/env python
# winbridge.py — feeds the pill its open-window list + the active window.
#
# Why this exists: KWin (Wayland) exposes NO window-list protocol to clients and
# NO active-window over DBus. So we use two KDE APIs and glue them:
#   * the KRunner "windows" runner (org.kde.KWin /WindowsRunner) lists windows
#     (id, title, app-icon name) and is polled here;
#   * a 3-line KWin script (loaded below via /Scripting) reports the active
#     window's id whenever it changes, by calling our own org.kde.pill service.
# We print one JSON line {"active": "{uuid}", "windows": [...]} per update; the
# pill reads it on stdout. Launched by init.qml as `python <shellDir>/winbridge.py`.
import sys, os, json, atexit, tempfile
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
# "taskbar" maps each taskbar-eligible window id (normal, not skip-taskbar, as
# reported by KWin) to its { seq, cls, dfile } metadata; None until the first
# report arrives.
state = {"active": "", "taskbar": None, "fullscreen": False, "screen": ""}
PLUGIN = "quickshell-pill-active"
ACTION_PLUGIN = "quickshell-pill-action"

# --- our DBus service ---
#   Set(uuid,fs,scr) — KWin script reports the active window (+ "1"/"0" fullscreen
#                    + its output/monitor name, for the per-monitor brightness key)
#   List(json)     — KWin script reports the taskbar-eligible window ids (JSON array)
#   Launcher(scr)  — KWin global shortcut asks the pill to toggle the launcher on
#                    the screen named `scr` (empty = whichever pill is on it)
#   Action(ids,vb) — the taskbar right-click menu asks KWin to run window action
#                    `vb` against every window whose internalId is in the JSON
#                    array `ids` (see run_action / ACTION_JS).
NODE = (
    '<node><interface name="org.kde.pill">'
    '<method name="Set"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/></method>'
    '<method name="List"><arg type="s" direction="in"/></method>'
    '<method name="Launcher"><arg type="s" direction="in"/></method>'
    '<method name="Action"><arg type="s" direction="in"/><arg type="s" direction="in"/></method>'
    "</interface></node>"
)
IFACE = Gio.DBusNodeInfo.new_for_xml(NODE).interfaces[0]


def on_call(conn, sender, path, ifc, method, params, inv):
    if method == "Set":
        (u, fs, scr) = params.unpack()
        state["active"] = u
        state["fullscreen"] = fs == "1"
        state["screen"] = scr
        emit()
    elif method == "List":
        (j,) = params.unpack()
        try:
            # map uuid -> { seq, cls, dfile } for the taskbar-eligible windows
            state["taskbar"] = {m["id"]: m for m in json.loads(j)}
        except Exception:
            state["taskbar"] = None
        emit()
    elif method == "Launcher":
        (scr,) = params.unpack()
        # one-off event line (not the regular state snapshot) the pill reacts to
        sys.stdout.write(json.dumps({"event": "launcher", "screen": scr}) + "\n")
        sys.stdout.flush()
    elif method == "Action":
        (ids_json, verb) = params.unpack()
        run_action(ids_json, verb)
    inv.return_value(None)


def on_bus_acquired(conn, name):
    conn.register_object("/Active", IFACE, on_call, None, None)
    load_kwin_script()


# --- the KWin script: reports the active window (+ its fullscreen flag) AND the
#     taskbar-eligible window ids (normal windows that don't ask to skip the
#     taskbar). KWin is the only place skipTaskbar / fullScreen are exposed;
#     KRunner (used for icon names) is not. We re-push the list on add/remove and
#     on skipTaskbar changes, and re-push the active window when *its* fullScreen
#     toggles (e.g. a video going fullscreen without re-activating the window). ---
KWIN_JS = (
    # each taskbar window is reported as { id, seq, cls, dfile, desk }: seq is a
    # stable open-order index (assigned the first time a window is seen, so newly
    # opened windows sort after older ones), cls is the app's resourceClass and
    # dfile its desktopFileName — both used by the pill to group by app and resolve
    # a proper icon (the KRunner icon name alone often misses) — and desk is the
    # window's virtual desktop (for the right-click Move-to-Desktop marker).
    "var seqN=0, seq={};\n"
    "function meta(w){ var id=String(w.internalId);\n"
    "  if (seq[id]===undefined) seq[id]=seqN++;\n"
    "  return { id:id, seq:seq[id],\n"
    "    cls:(w.resourceClass?String(w.resourceClass):''),\n"
    "    dfile:(w.desktopFileName?String(w.desktopFileName):''),\n"
    # desk = which virtual desktop the window is on ('all', a desktop id, or '');
    # the pill marks it in the right-click Move-to-Desktop list.
    "    desk:(w.onAllDesktops ? 'all' : (w.desktops && w.desktops.length ? String(w.desktops[0].id) : '')) }; }\n"
    "function ids(){ var ws=workspace.windowList(), o=[];\n"
    "  for (var i=0;i<ws.length;i++){ var w=ws[i];\n"
    "    if (w.normalWindow && !w.skipTaskbar) o.push(meta(w)); }\n"
    "  return o; }\n"
    'function pushList(){ callDBus("org.kde.pill","/Active","org.kde.pill","List",'
    " JSON.stringify(ids())); }\n"
    # Ignore activation of our OWN overlay surfaces (the pill / emaqs). KWin reports
    # the Quickshell layer surface as a NORMAL window with resourceClass "quickshell",
    # so when the pill grabs the keyboard it fires windowActivated for itself; without
    # this guard `active` (and so the pill's lastActiveWindow) gets overwritten with
    # the pill, and "restore focus" then re-activates the pill => focus stuck on it.
    # Skipping it keeps `active` pointing at the real app the user came from, which is
    # the correct restore target. (A plain `!normalWindow` test does NOT catch the
    # pill — it *is* normalWindow here — which is exactly what bit us.)
    'function setActive(w){ if (w && String(w.resourceClass)==="quickshell") return;\n'
    ' callDBus("org.kde.pill","/Active","org.kde.pill","Set",'
    ' w ? String(w.internalId) : "", (w && w.fullScreen) ? "1" : "0",'
    ' (w && w.output) ? String(w.output.name) : ""); }\n'
    "function watch(w){ if (!w) return;\n"
    "  if (w.skipTaskbarChanged) w.skipTaskbarChanged.connect(pushList);\n"
    "  if (w.desktopsChanged) w.desktopsChanged.connect(pushList);\n"
    "  if (w.fullScreenChanged) w.fullScreenChanged.connect(function(){\n"
    "    if (w === workspace.activeWindow) setActive(w); }); }\n"
    "workspace.windowActivated.connect(setActive);\n"
    "workspace.windowAdded.connect(function(w){ watch(w); pushList(); });\n"
    "workspace.windowRemoved.connect(pushList);\n"
    "var all=workspace.windowList(); for (var i=0;i<all.length;i++) watch(all[i]);\n"
    "setActive(workspace.activeWindow);\n"
    "pushList();\n"
    # global shortcut (Meta+D) to toggle the launcher; passes the focused window's
    # screen so the right monitor's pill opens. Configurable in System Settings ->
    # Shortcuts -> KWin once registered.
    "function scr(){ var w=workspace.activeWindow; return (w && w.output) ? w.output.name : ''; }\n"
    'registerShortcut("PillLauncher","Pill: open launcher","Meta+D",function(){\n'
    '  callDBus("org.kde.pill","/Active","org.kde.pill","Launcher", scr()); });\n'
)


def kwin(method, variant):
    try:
        bus.call_sync(
            "org.kde.KWin",
            "/Scripting",
            "org.kde.kwin.Scripting",
            method,
            variant,
            None,
            Gio.DBusCallFlags.NONE,
            2000,
            None,
        )
    except Exception as e:
        sys.stderr.write("winbridge: %s failed: %s\n" % (method, e))


def load_kwin_script():
    path = os.path.join(tempfile.gettempdir(), "quickshell_pill_active.js")
    with open(path, "w") as f:
        f.write(KWIN_JS)
    kwin("unloadScript", GLib.Variant("(s)", (PLUGIN,)))  # clear a stale copy
    kwin("loadScript", GLib.Variant("(ss)", (path, PLUGIN)))
    kwin("start", None)


# --- the taskbar right-click window actions ---
# A one-shot KWin script (there is no per-window DBus): it looks up every window
# whose internalId is in TARGETS and applies VERB. Toggle verbs act on the group's
# AGGREGATE state so a grouped app stays in sync — e.g. minimize hides them all
# unless they're already all hidden (then it restores all). maximizeMode 3 = full.
# The `activate` verb (single window) focuses+raises it — used to restore focus to
# the app that was active before a keyboard-grabbing pill pane opened.
ACTION_JS = (
    "(function(){\n"
    "  var wl = workspace.windowList ? workspace.windowList() : workspace.clientList();\n"
    "  var wins = [];\n"
    "  for (var i=0;i<wl.length;i++){ var id=String(wl[i].internalId);\n"
    "    for (var j=0;j<TARGETS.length;j++) if (TARGETS[j]===id){ wins.push(wl[i]); break; } }\n"
    "  if (!wins.length) return;\n"
    "  function every(f){ for (var i=0;i<wins.length;i++) if (!f(wins[i])) return false; return true; }\n"
    # activate: give the (single) window keyboard focus + raise it. Used to hand
    # focus BACK to the app that was active before a keyboard-grabbing pill pane
    # opened — KWin/Wayland won't do it on its own when our layer surface lets go
    # of the keyboard. Done in-compositor (workspace.activeWindow = w), so it's
    # not subject to focus-stealing prevention the way an external request is.
    '  if (VERB === "activate"){ var a=wins[0];\n'
    "    a.minimized=false; workspace.raiseWindow(a); workspace.activeWindow=a; }\n"
    '  else if (VERB === "close"){ for (var i=0;i<wins.length;i++) wins[i].closeWindow(); }\n'
    '  else if (VERB === "minimize"){ var on = !every(function(w){return w.minimized;});\n'
    "    for (var i=0;i<wins.length;i++) wins[i].minimized = on; }\n"
    '  else if (VERB === "maximize"){ var on = !every(function(w){return w.maximizeMode === 3;});\n'
    "    for (var i=0;i<wins.length;i++) wins[i].setMaximize(on, on); }\n"
    '  else if (VERB === "above"){ var on = !every(function(w){return w.keepAbove;});\n'
    "    for (var i=0;i<wins.length;i++){ wins[i].keepAbove = on; if (on) wins[i].keepBelow = false; } }\n"
    '  else if (VERB === "below"){ var on = !every(function(w){return w.keepBelow;});\n'
    "    for (var i=0;i<wins.length;i++){ wins[i].keepBelow = on; if (on) wins[i].keepAbove = false; } }\n"
    '  else if (VERB === "desktop:all"){ for (var i=0;i<wins.length;i++) wins[i].onAllDesktops = true; }\n'
    '  else if (VERB.indexOf("desktop:") === 0){ var did = VERB.substring(8);\n'
    "    var ds = workspace.desktops, vd = null;\n"
    "    for (var i=0;i<ds.length;i++) if (String(ds[i].id) === did) vd = ds[i];\n"
    "    if (vd) for (var i=0;i<wins.length;i++){ wins[i].onAllDesktops = false; wins[i].desktops = [vd]; } }\n"
    "})();\n"
)


def run_action(ids_json, verb):
    # validate the ids JSON so a bad payload can't inject into the script body
    try:
        ids = json.loads(ids_json)
        if not isinstance(ids, list):
            return
    except Exception:
        return
    js = "var TARGETS = %s;\nvar VERB = %s;\n%s" % (
        json.dumps(ids),
        json.dumps(verb),
        ACTION_JS,
    )
    path = os.path.join(tempfile.gettempdir(), "quickshell_pill_action.js")
    with open(path, "w") as f:
        f.write(js)
    # reuse one plugin slot: the previous action script already ran, so unloading
    # it is safe; load+start runs the fresh one exactly once.
    kwin("unloadScript", GLib.Variant("(s)", (ACTION_PLUGIN,)))
    kwin("loadScript", GLib.Variant("(ss)", (path, ACTION_PLUGIN)))
    kwin("start", None)


@atexit.register
def _cleanup():
    kwin("unloadScript", GLib.Variant("(s)", (PLUGIN,)))
    kwin("unloadScript", GLib.Variant("(s)", (ACTION_PLUGIN,)))


# --- poll the KRunner windows runner for the window list ---
def windows():
    try:
        res = bus.call_sync(
            "org.kde.KWin",
            "/WindowsRunner",
            "org.kde.krunner1",
            "Match",
            GLib.Variant("(s)", ("",)),
            GLib.VariantType("(a(sssida{sv}))"),
            Gio.DBusCallFlags.NONE,
            3000,
            None,
        )
    except Exception:
        return []
    tb = state["taskbar"]
    seen = {}
    for m in res.unpack()[0]:
        mid, text, icon = m[0], m[1], m[2]  # id, title, icon name
        if not mid.startswith("0_") or mid in seen:
            continue
        # KWin briefly lists an internal placeholder window (icon "kwin", no title)
        # while a window is being activated; it would flash a phantom app tile in
        # the taskbar for a frame, so drop it — no real app uses the "kwin" icon.
        if icon == "kwin":
            continue
        uuid = mid[2:]
        # once KWin has reported the eligible set, drop skip-taskbar windows;
        # before the first report, show everything (previous behaviour)
        if tb is not None and uuid not in tb:
            continue
        meta = tb.get(uuid) if isinstance(tb, dict) else None
        seen[mid] = {
            "id": mid,
            "uuid": uuid,
            "title": text,
            "icon": icon,
            # class + desktop file (from the KWin script) let the pill group by
            # app and resolve a proper icon; seq is the open-order index.
            "cls": (meta or {}).get("cls", ""),
            "dfile": (meta or {}).get("dfile", ""),
            "seq": (meta or {}).get("seq", 0),
            # which virtual desktop the window is on ('all' / a desktop id / '')
            "desk": (meta or {}).get("desk", ""),
        }
    # order by open time (seq); before the first List report seq is 0 for all, so
    # fall back to id for a stable order.
    return sorted(seen.values(), key=lambda d: (d["seq"], d["id"]))


def emit():
    line = json.dumps(
        {
            "active": state["active"],
            "fullscreen": state["fullscreen"],
            "screen": state["screen"],
            "windows": windows(),
        },
        ensure_ascii=False,
    )
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def tick():
    emit()
    return True


Gio.bus_own_name(
    Gio.BusType.SESSION,
    "org.kde.pill",
    Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
    on_bus_acquired,
    None,
    None,
)
GLib.timeout_add_seconds(1, tick)
GLib.MainLoop().run()
