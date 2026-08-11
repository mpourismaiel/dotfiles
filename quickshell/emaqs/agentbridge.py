#!/usr/bin/env python
# agentbridge.py — agent-shell push channel for emaqs, over DBus.
#
# Owns org.kde.emaqs.agent (its own name so it never clashes with the pill's
# org.kde.pill or emaqs's own org.kde.emaqs). Emacs pushes agent-shell turns here
# instead of to the freedesktop daemon, so they are absent from the pill entirely.
# Each method call becomes one JSON line on stdout, which AgentBridge.qml reads:
#
#   Notify(id, kind, buffer, workspace, title, body, actions_json)
#                 -> {"op":"notify", ...}   kind = "permission" | "finished"
#   Meta(id, meta_json)  -> stashed, then folded into the next Notify(id). Optional
#                 and additive: carries the operation type (permission), elapsed
#                 prompt time (finished) and model/session-mode options for the card.
#                 Kept a SEPARATE method (not extra Notify args) so an Emacs and a
#                 bridge at different versions never break each other — a skew just
#                 means "no meta", never a rejected Notify.
#   Close(id)     -> {"op":"close", "id":id}
#   Working(buffer, workspace, active)  -> {"op":"working", ...}  active = "1"|"0"
#
# One-way (Emacs -> emaqs); Allow/Deny/switch go back via emaqsbridge.py.
import sys, json
from gi.repository import Gio, GLib

PLUGIN = "org.kde.emaqs.agent"

NODE = (
    '<node><interface name="org.kde.emaqs.agent">'
    '<method name="Notify">'
    + '<arg type="s" direction="in"/>' * 7 +
    '</method>'
    '<method name="Meta">'
    '<arg type="s" direction="in"/>'
    '<arg type="s" direction="in"/>'
    '</method>'
    '<method name="Close"><arg type="s" direction="in"/></method>'
    '<method name="Working">'
    '<arg type="s" direction="in"/>'
    '<arg type="s" direction="in"/>'
    '<arg type="s" direction="in"/>'
    '</method>'
    '</interface></node>'
)
IFACE = Gio.DBusNodeInfo.new_for_xml(NODE).interfaces[0]

# meta stashed by notification id, awaiting its Notify (Emacs sends Meta first).
PENDING_META = {}


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def on_call(conn, sender, path, ifc, method, params, inv):
    args = list(params.unpack())
    if method == "Notify":
        idv, kind, buf, ws, title, body, actions = args
        try:
            acts = json.loads(actions) if actions else []
        except Exception:
            acts = []
        # fold in any meta Emacs sent just before this Notify (may be absent).
        meta = PENDING_META.pop(idv, {})
        emit({"op": "notify", "id": idv, "kind": kind, "buffer": buf,
              "workspace": ws, "title": title, "body": body, "actions": acts,
              "meta": meta})
    elif method == "Meta":
        idv, meta_json = args
        try:
            meta = json.loads(meta_json) if meta_json else {}
        except Exception:
            meta = {}
        if not isinstance(meta, dict):
            meta = {}
        # stash for the imminent Notify(id); also emit so an already-shown card
        # (a re-issued/updated meta) refreshes.
        PENDING_META[idv] = meta
        emit({"op": "meta", "id": idv, "meta": meta})
    elif method == "Close":
        emit({"op": "close", "id": args[0]})
    elif method == "Working":
        buf, ws, active = args
        emit({"op": "working", "buffer": buf, "workspace": ws,
              "active": active == "1"})
    inv.return_value(None)


def on_bus_acquired(conn, name):
    conn.register_object("/Agent", IFACE, on_call, None, None)


Gio.bus_own_name(
    Gio.BusType.SESSION,
    PLUGIN,
    Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT | Gio.BusNameOwnerFlags.REPLACE,
    on_bus_acquired,
    None,
    None,
)
GLib.MainLoop().run()
