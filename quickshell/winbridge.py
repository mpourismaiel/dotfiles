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
# pill reads it on stdout. Launched by pill.qml as `python <shellDir>/winbridge.py`.
import sys, os, json, atexit, tempfile
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
# "taskbar" is the set of window ids that belong in a taskbar (normal, not
# skip-taskbar) as reported by KWin; None until the first report arrives.
state = {"active": "", "taskbar": None}
PLUGIN = "quickshell-pill-active"

# --- our DBus service ---
#   Set(uuid)   — KWin script reports the active window on change
#   List(json)  — KWin script reports the taskbar-eligible window ids (JSON array)
NODE = ('<node><interface name="org.kde.pill">'
        '<method name="Set"><arg type="s" direction="in"/></method>'
        '<method name="List"><arg type="s" direction="in"/></method>'
        '</interface></node>')
IFACE = Gio.DBusNodeInfo.new_for_xml(NODE).interfaces[0]

def on_call(conn, sender, path, ifc, method, params, inv):
    if method == "Set":
        (u,) = params.unpack()
        state["active"] = u
        emit()
    elif method == "List":
        (j,) = params.unpack()
        try:
            state["taskbar"] = set(json.loads(j))
        except Exception:
            state["taskbar"] = None
        emit()
    inv.return_value(None)

def on_bus_acquired(conn, name):
    conn.register_object("/Active", IFACE, on_call, None, None)
    load_kwin_script()

# --- the KWin script: reports the active window AND the taskbar-eligible
#     window ids (normal windows that don't ask to skip the taskbar). KWin is
#     the only place skipTaskbar is exposed; KRunner (used for icon names) is
#     not. We re-push the list on add/remove and on skipTaskbar changes. ---
KWIN_JS = (
    'function ids(){ var ws=workspace.windowList(), o=[];\n'
    '  for (var i=0;i<ws.length;i++){ var w=ws[i];\n'
    '    if (w.normalWindow && !w.skipTaskbar) o.push(String(w.internalId)); }\n'
    '  return o; }\n'
    'function pushList(){ callDBus("org.kde.pill","/Active","org.kde.pill","List",'
    ' JSON.stringify(ids())); }\n'
    'function watch(w){ if (w && w.skipTaskbarChanged) w.skipTaskbarChanged.connect(pushList); }\n'
    'function setActive(w){ callDBus("org.kde.pill","/Active","org.kde.pill","Set",'
    ' w ? String(w.internalId) : ""); }\n'
    'workspace.windowActivated.connect(setActive);\n'
    'workspace.windowAdded.connect(function(w){ watch(w); pushList(); });\n'
    'workspace.windowRemoved.connect(pushList);\n'
    'var all=workspace.windowList(); for (var i=0;i<all.length;i++) watch(all[i]);\n'
    'setActive(workspace.activeWindow);\n'
    'pushList();\n'
)

def kwin(method, variant):
    try:
        bus.call_sync("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
                      method, variant, None, Gio.DBusCallFlags.NONE, 2000, None)
    except Exception as e:
        sys.stderr.write("winbridge: %s failed: %s\n" % (method, e))

def load_kwin_script():
    path = os.path.join(tempfile.gettempdir(), "quickshell_pill_active.js")
    with open(path, "w") as f:
        f.write(KWIN_JS)
    kwin("unloadScript", GLib.Variant("(s)", (PLUGIN,)))   # clear a stale copy
    kwin("loadScript", GLib.Variant("(ss)", (path, PLUGIN)))
    kwin("start", None)

@atexit.register
def _cleanup():
    kwin("unloadScript", GLib.Variant("(s)", (PLUGIN,)))

# --- poll the KRunner windows runner for the window list ---
def windows():
    try:
        res = bus.call_sync("org.kde.KWin", "/WindowsRunner", "org.kde.krunner1",
                            "Match", GLib.Variant("(s)", ("",)),
                            GLib.VariantType("(a(sssida{sv}))"),
                            Gio.DBusCallFlags.NONE, 3000, None)
    except Exception:
        return []
    tb = state["taskbar"]
    seen = {}
    for m in res.unpack()[0]:
        mid, text, icon = m[0], m[1], m[2]      # id, title, icon name
        if not mid.startswith("0_") or mid in seen:
            continue
        uuid = mid[2:]
        # once KWin has reported the eligible set, drop skip-taskbar windows;
        # before the first report, show everything (previous behaviour)
        if tb is not None and uuid not in tb:
            continue
        seen[mid] = {"id": mid, "uuid": uuid, "title": text, "icon": icon}
    return sorted(seen.values(), key=lambda d: d["id"])

def emit():
    line = json.dumps({"active": state["active"], "windows": windows()}, ensure_ascii=False)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()

def tick():
    emit()
    return True

Gio.bus_own_name(Gio.BusType.SESSION, "org.kde.pill",
                 Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
                 on_bus_acquired, None, None)
GLib.timeout_add_seconds(1, tick)
GLib.MainLoop().run()
