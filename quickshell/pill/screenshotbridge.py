#!/usr/bin/env python3
"""screenshotbridge.py — ALTERNATE grabber (NOT the default). Grabs the whole
screen via the freedesktop Screenshot portal and writes it to argv[1].

NOTE: on THIS machine the portal refuses non-interactive grabs (Response code 2),
so the working default is Spectacle (`CaptureState.grabCmd`). Keep this for a
machine where the portal works — point grabCmd at it: `python3 <dir>/screenshotbridge.py %o`.

This is the SWAPPABLE grab seam (see ../capture/PLAN.md). CaptureState calls it
through `grabCmd`; if the portal ever misbehaves on your machine, replace the
command with any tool that writes a PNG to argv[1] and prints its path — do NOT
sink time into debugging the portal (per the project brief). Candidates:
  - a KWin ScreenShot2 helper (grabs an exact rect, needs an os.pipe() reader)
  - `spectacle -b -n -f -o <path>` (unreliable here, but may work on your box)

The portal is async (Request -> Response signal), so we run a GLib mainloop and
exit when the Response arrives. Full screen only; CaptureState crops to the
selected region in QML.
"""
import os
import sys
import shutil
import urllib.parse

try:
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
except Exception as e:  # pragma: no cover - dependency hint
    sys.stderr.write(
        "screenshotbridge: missing python-dbus / PyGObject (%s).\n"
        "Install: sudo pacman -S python-dbus python-gobject\n" % e)
    sys.exit(3)

PORTAL = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.portal.Screenshot"
REQ_IFACE = "org.freedesktop.portal.Request"


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "qs-capture-grab.png")

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    # unique token so we can predict the Request object path and subscribe to its
    # Response BEFORE issuing the call (avoids the signal-before-listen race).
    token = "qscap%d" % os.getpid()
    sender = bus.get_unique_name().lstrip(":").replace(".", "_")
    req_path = "%s/request/%s/%s" % (PATH, sender, token)

    loop = GLib.MainLoop()
    result = {"uri": None, "code": None}

    def on_response(code, results):
        result["code"] = int(code)
        if code == 0 and "uri" in results:
            result["uri"] = str(results["uri"])
        loop.quit()

    bus.add_signal_receiver(
        on_response, signal_name="Response", dbus_interface=REQ_IFACE,
        bus_name=PORTAL, path=req_path)

    portal = dbus.Interface(bus.get_object(PORTAL, PATH), IFACE)
    portal.Screenshot("", {
        "handle_token": token,
        "interactive": dbus.Boolean(False),
        "modal": dbus.Boolean(False),
    })

    # safety timeout so we never hang the pill forever
    GLib.timeout_add_seconds(20, loop.quit)
    loop.run()

    if not result["uri"]:
        sys.stderr.write("screenshotbridge: portal returned no image (code=%s)\n"
                         % result["code"])
        return 1

    src = urllib.parse.unquote(result["uri"].replace("file://", "", 1))
    try:
        # portal writes to its own temp dir; move it to the requested path.
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        shutil.move(src, out)
    except Exception:
        shutil.copyfile(src, out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
