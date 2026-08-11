pragma ComponentBehavior: Bound
// AgentBridge.qml — agent-shell notification / working state for emaqs, fed by
// agentbridge.py (DBus). Push-driven; dispatches Allow/Deny/switch back to Emacs
// through emaqsbridge.py. See qs-emaqs-docs.org.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var notifs: []          // [{id,kind,buffer,workspace,title,body,actions,meta}]
    property var workingList: []     // [{buffer, workspace}]
    property bool dnd: false          // emaqs-local do-not-disturb

    readonly property int workingCount: workingList.length

    // newest of each kind, for the collapsed morph
    readonly property var permissionNotif: {
        for (var i = notifs.length - 1; i >= 0; i--)
            if (notifs[i].kind === "permission") return notifs[i];
        return null;
    }
    readonly property var finishedNotif: {
        for (var i = notifs.length - 1; i >= 0; i--)
            if (notifs[i].kind === "finished") return notifs[i];
        return null;
    }

    function workspaceWorking(ws) {
        for (var i = 0; i < workingList.length; i++)
            if (workingList[i].workspace === ws) return true;
        return false;
    }

    // ---- dispatch to Emacs ------------------------------------------------
    function action(id, key) {
        actProc.command = ["python", Quickshell.shellPath("emaqsbridge.py"),
                           "agent-action", id, key];
        if (!actProc.running) actProc.running = true;
    }
    function dismiss(id) { removeNotif(id); }   // local hide only

    // change the model / session mode of a permission's shell buffer. Optimistically
    // reflect the pick locally (the daemon won't re-Notify for the same request), then
    // dispatch to Emacs. KIND is "model" or "mode" — also the meta key it updates.
    function setSession(id, buffer, kind, value) {
        updateMeta(id, kind, value);
        sessProc.command = ["python", Quickshell.shellPath("emaqsbridge.py"),
                            "agent-session", buffer, kind, value];
        if (!sessProc.running) sessProc.running = true;
    }
    // fold a bridge "meta" op into an already-shown card. If the card isn't here
    // yet, ignore it — the paired Notify carries the same meta (the bridge stashes
    // it), so nothing is lost.
    function mergeMeta(id, meta) {
        var out = [], found = false;
        for (var i = 0; i < notifs.length; i++) {
            var n = notifs[i];
            if (n.id === id) {
                found = true;
                out.push({ id: n.id, kind: n.kind, buffer: n.buffer,
                           workspace: n.workspace, title: n.title, body: n.body,
                           actions: n.actions, meta: meta });
            } else out.push(n);
        }
        if (found) notifs = out;
    }
    function updateMeta(id, key, value) {
        var out = [];
        for (var i = 0; i < notifs.length; i++) {
            var n = notifs[i];
            if (n.id === id) {
                var m = {};
                for (var k in n.meta) m[k] = n.meta[k];
                m[key] = value;
                out.push({ id: n.id, kind: n.kind, buffer: n.buffer,
                           workspace: n.workspace, title: n.title, body: n.body,
                           actions: n.actions, meta: m });
            } else out.push(n);
        }
        notifs = out;
    }

    // ---- state mutation (reassign wholesale so bindings re-evaluate) -------
    function removeNotif(id) {
        var out = [];
        for (var i = 0; i < notifs.length; i++)
            if (notifs[i].id !== id) out.push(notifs[i]);
        notifs = out;
    }
    function upsertNotif(o) {
        var out = [], found = false;
        for (var i = 0; i < notifs.length; i++) {
            if (notifs[i].id === o.id) { out.push(o); found = true; }
            else out.push(notifs[i]);
        }
        if (!found) out.push(o);
        notifs = out;
    }
    function setWorking(buffer, ws, active) {
        var out = [];
        for (var i = 0; i < workingList.length; i++)
            if (workingList[i].buffer !== buffer) out.push(workingList[i]);
        if (active) out.push({ buffer: buffer, workspace: ws });
        workingList = out;
    }

    function handle(line) {
        var o;
        try { o = JSON.parse(line); } catch (e) { return; }
        if (!o || !o.op) return;
        if (o.op === "notify")
            upsertNotif({ id: o.id, kind: o.kind, buffer: o.buffer,
                          workspace: o.workspace, title: o.title, body: o.body,
                          actions: o.actions || [], meta: o.meta || ({}) });
        else if (o.op === "meta") mergeMeta(o.id, o.meta || ({}));
        else if (o.op === "close") removeNotif(o.id);
        else if (o.op === "working") setWorking(o.buffer, o.workspace, o.active);
    }

    property Process actProc: Process {}
    property Process sessProc: Process {}
    property Process feed: Process {
        running: true
        command: ["python", Quickshell.shellPath("agentbridge.py")]
        stdout: SplitParser { onRead: line => root.handle(line) }
    }
}
