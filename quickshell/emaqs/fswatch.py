#!/usr/bin/env python
# fswatch.py — reports whether the focused window is fullscreen, for emaqs.
#
# KWin (Wayland) exposes no active-window / fullscreen state over DBus to clients,
# so we load a tiny KWin script that calls back into our own org.kde.emaqs service
# on activation and fullScreen changes. Prints one JSON line {"fullscreen": bool}
# per change on stdout; emaqs reads it and hides the resting tab while fullscreen.
# Own DBus/script names so it never clashes with the pill's winbridge.
import sys, os, json, atexit, tempfile
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
state = {"fullscreen": None}
PLUGIN = "quickshell-emaqs-active"

NODE = (
    '<node><interface name="org.kde.emaqs">'
    '<method name="Set"><arg type="s" direction="in"/></method>'
    "</interface></node>"
)
IFACE = Gio.DBusNodeInfo.new_for_xml(NODE).interfaces[0]


def emit():
    sys.stdout.write(json.dumps({"fullscreen": bool(state["fullscreen"])}) + "\n")
    sys.stdout.flush()


def on_call(conn, sender, path, ifc, method, params, inv):
    if method == "Set":
        (fs,) = params.unpack()
        val = fs == "1"
        if val != state["fullscreen"]:
            state["fullscreen"] = val
            emit()
    inv.return_value(None)


def on_bus_acquired(conn, name):
    conn.register_object("/Active", IFACE, on_call, None, None)
    load_kwin_script()


# report the active window's fullScreen on activation, and when *its* fullScreen
# toggles (e.g. a video going fullscreen without re-activating the window).
KWIN_JS = (
    'function setActive(w){ callDBus("org.kde.emaqs","/Active","org.kde.emaqs","Set",'
    ' (w && w.fullScreen) ? "1" : "0"); }\n'
    "function watch(w){ if (!w || !w.fullScreenChanged) return;\n"
    "  w.fullScreenChanged.connect(function(){\n"
    "    if (w === workspace.activeWindow) setActive(w); }); }\n"
    "workspace.windowActivated.connect(setActive);\n"
    "workspace.windowAdded.connect(function(w){ watch(w); });\n"
    "var all=workspace.windowList(); for (var i=0;i<all.length;i++) watch(all[i]);\n"
    "setActive(workspace.activeWindow);\n"
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
        sys.stderr.write("fswatch: %s failed: %s\n" % (method, e))


def load_kwin_script():
    path = os.path.join(tempfile.gettempdir(), "quickshell_emaqs_active.js")
    with open(path, "w") as f:
        f.write(KWIN_JS)
    kwin("unloadScript", GLib.Variant("(s)", (PLUGIN,)))  # clear a stale copy
    kwin("loadScript", GLib.Variant("(ss)", (path, PLUGIN)))
    kwin("start", None)


@atexit.register
def _cleanup():
    kwin("unloadScript", GLib.Variant("(s)", (PLUGIN,)))


Gio.bus_own_name(
    Gio.BusType.SESSION,
    "org.kde.emaqs",
    Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
    on_bus_acquired,
    None,
    None,
)
emit()  # initial line so emaqs has a value before the first change
GLib.MainLoop().run()
