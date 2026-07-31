pragma ComponentBehavior: Bound
// Notifications.qml — the freedesktop notification server + popup/history state.
// Instantiated once in init.qml as `Notifications { id: notifs; theme: theme }`
// and shared with every monitor's views (no singletons). It:
//   * owns a NotificationServer advertising body/markup/images/actions/action-
//     icons/inline-reply/persistence, so apps send us the rich payload;
//   * keeps every notification `tracked` so it survives as *history*
//     (server.trackedNotifications), grouped by app in the history view;
//   * maintains an `active` stack (newest first) of un-closed popups that drive
//     the collapsed-pill morph; each notification has its own countdown (kept in
//     `remaining`, keyed by id), and `held` (set while a deck is hovered) pauses
//     and resets them all. Closing a popup or letting it time out only removes it
//     from `active` and keeps the (tracked) history copy — we never call
//     Notification.dismiss()/expire(), which would *destroy* it. Forget/clear set
//     tracked=false to actually drop a notification from history.
//
// The spec carries no timestamp, so we stamp arrival time ourselves (`stamps`);
// on a Quickshell reload restored notifications are re-stamped to "now".
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

QtObject {
    id: root
    required property var theme

    // ---- the server: the capabilities we advertise to apps ----
    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true
        inlineReplySupported: true
        onNotification: n => root.onArrived(n)
    }

    // ---- arrival timestamps (id -> ms since epoch); the spec carries none ----
    property var stamps: ({})

    // ---- active popup stack (newest first) drives the pill morph ----
    // Per-notification countdowns live HERE (keyed by id), not in the cards: the
    // deck's Repeater recreates its delegates whenever `active` changes, which
    // would otherwise reset every timer on each arrival. `held` (set while a deck
    // is hovered) pauses every countdown and resets them all to full.
    property var active: []
    readonly property var current: active.length ? active[0] : null   // newest
    property bool held: false
    // do-not-disturb: when on, arrivals are still kept for history but never
    // popped (no morph, no floating card). Toggled from the launcher's toggle row.
    property bool dnd: false

    // ---- screen-share auto-DND -----------------------------------------------
    // While a screencast is live (init binds `screenShare` to root.screenRecording)
    // the pill auto-enters DND so notifications don't pop over whatever is being
    // shared. It counts what it silenced and — when sharing ends — restores the DND
    // state from before the share and posts a single "you missed N" summary. The
    // prior state is remembered so a manually-set DND survives a share untouched.
    // (Agent-shell turns live on emaqs, not here, so nothing important is swallowed.)
    property bool screenShare: false
    property int  missedDuringShare: 0
    property bool dndBeforeShare: false
    onScreenShareChanged: {
        if (root.screenShare) {
            root.dndBeforeShare = root.dnd;
            root.missedDuringShare = 0;
            root.dnd = true;
        } else {
            const n = root.missedDuringShare;
            root.missedDuringShare = 0;
            root.dnd = root.dndBeforeShare;
            if (n > 0) root.postMissedSummary(n);
        }
    }
    // post a single freedesktop notification summarising what was silenced during a
    // share. Routed through notify-send to our OWN server (we own the name), so it
    // arrives via onArrived like any other app's — and pops now that DND is lifted.
    readonly property Process missedProc: Process { }
    function postMissedSummary(n) {
        const body = (n === 1)
            ? "You missed 1 notification while sharing your screen."
            : ("You missed " + n + " notifications while sharing your screen.");
        root.missedProc.command = ["notify-send", "-a", "Screen Share",
            "-i", "notifications", "Screen sharing ended", body];
        root.missedProc.running = true;
    }

    property var remaining: ({})              // id -> ms left
    property int tick: 0                       // bumped each step to refresh progress bindings
    readonly property bool anyReply: {
        for (const n of active) if (n && n.hasInlineReply) return true;
        return false;
    }

    function progressFor(n) {
        root.tick;                            // dependency: re-eval each countdown step
        if (!n) return 0;
        const t = root.timeoutFor(n);
        if (t <= 0) return 0;
        const r = root.remaining[n.id];
        return r === undefined ? 1 : Math.max(0, Math.min(1, r / t));
    }

    readonly property Timer ticker: Timer {
        interval: 50; repeat: true
        running: root.active.length > 0 && !root.held
        onTriggered: {
            const dead = [];
            for (const n of root.active) {
                const t = root.timeoutFor(n);
                if (t <= 0) continue;          // no countdown (critical stays until dismissed)
                let r = root.remaining[n.id];
                r = (r === undefined ? t : r) - interval;
                root.remaining[n.id] = r;
                if (r <= 0) dead.push(n);
            }
            root.tick++;                       // refresh progress bars
            for (const n of dead) root.expireOne(n);
        }
    }

    // a 1-second clock so "x min ago" stays fresh in the cards / history
    readonly property var clock: SystemClock { precision: SystemClock.Seconds }
    readonly property double nowMs: clock.date.getTime()

    function onArrived(n) {
        if (!root.stamps[n.id])
            root.stamps[n.id] = (new Date()).getTime();
        n.tracked = true;                     // keep it for history
        // rebuild the grouped history now, splicing in `n` explicitly: setting
        // tracked=true neither fires trackedNotificationsChanged nor lands `n` in
        // the server's `values` on this tick, so a plain rebuild would omit it and
        // the resting app-icon strip / bell badge / history wouldn't update until
        // something later forced another rebuild (e.g. opening the history pane).
        root.rebuild(n);
        if (n.lastGeneration)                 // restored on reload: history only, don't re-pop
            return;
        if (root.dnd) {                       // do-not-disturb: history only, no popup
            if (root.screenShare) root.missedDuringShare++;   // tally for the end-of-share summary
            return;
        }
        // de-dupe (apps reuse ids to replace): drop any copy, push to the front
        const a = root.active.filter(x => x.id !== n.id);
        a.unshift(n);
        root.active = a;
        root.remaining[n.id] = root.timeoutFor(n);   // start (or restart) its countdown
        root.tick++;
    }

    readonly property int defaultTimeoutMs: 5000   // hard ceiling for non-critical popups
    function timeoutFor(n) {
        if (!n) return 0;
        // Critical popups never auto-expire (freedesktop: critical notifications
        // "should not automatically expire") — they stay until dismissed. The
        // 23:00 finance nag relies on this. 0 = no countdown: the ticker skips
        // t <= 0 entries and progressFor shows no bar.
        if (n.urgency === NotificationUrgency.Critical) return 0;
        // Everything else is capped at 5s — including an app's "persistent" (0)
        // / "default" (-1) request: honour a *shorter* app-requested timeout,
        // but ignore anything longer or indefinite, so nothing lingers past
        // defaultTimeoutMs. (Transcribe cards get the copy button for when 5s
        // isn't enough — the transcript is on the clipboard.)
        const want = n.expireTimeout;
        return (want > 0 && want < root.defaultTimeoutMs) ? want : root.defaultTimeoutMs;
    }

    // remove from the active stack only (the history copy is untouched)
    function drop(n) {
        if (!n) return;
        root.active = root.active.filter(x => x.id !== n.id);
        delete root.remaining[n.id];
        // deck just emptied — clear any stuck hover-hold. The morph deck's
        // HoverHandler is destroyed when the last popup goes (notifMorph turns
        // false); if it was hovered at that moment it never fires hovered=false,
        // leaving `held` true and freezing every *future* popup's countdown.
        if (root.active.length === 0)
            root.held = false;
    }
    // close a popup: stop showing it but ALWAYS KEEP it in history (even the X and
    // even transient notifications — only `forget`/`clearAll` remove from history).
    // We deliberately do NOT call Notification.dismiss()/expire() here — in
    // Quickshell those *destroy* the notification (untracking it), which would wipe
    // the history copy too; the trade-off is the sending app isn't told it closed.
    function closePopup(n) {
        if (!n) return;
        root.drop(n);   // remove from the popup stack; the tracked history copy stays
    }
    function dismiss(n)   { root.closePopup(n); }   // X on a popup
    function expireOne(n) { root.closePopup(n); }   // a countdown elapsed
    // dismiss the whole active popup deck at once (history is kept, like the X)
    function dismissAll() { for (const n of root.active.slice()) root.closePopup(n); }
    function hold(v) {                                // hover: pause + reset every countdown
        root.held = v;
        if (v) {
            for (const n of root.active) root.remaining[n.id] = root.timeoutFor(n);
            root.tick++;
        }
    }

    // remove from history entirely (tracked=false == dismiss(): destroys it).
    // Rebuild *now* rather than waiting for trackedNotificationsChanged: the dying
    // notification can linger in `values` for a cycle with its content already
    // cleared, which would flash an empty card in the history (rebuild filters it).
    function forget(n) { if (n) { root.drop(n); n.tracked = false; root.rebuild(); } }
    function clearAll() {
        const all = root.server.trackedNotifications ? root.server.trackedNotifications.values.slice() : [];
        for (const n of all) n.tracked = false;
        root.active = [];
        root.rebuild();
    }
    // clear one history group (an app's notifications) at once — like clearAll,
    // scoped to the group's items (the "Clear" button on a group header).
    function clearGroup(g) {
        if (!g || !g.items) return;
        for (const n of g.items.slice()) { root.drop(n); n.tracked = false; }
        root.rebuild();
    }

    // ---- watch each tracked notification's `closed` (e.g. the sender closed or
    //      replaced it) so it leaves the active stack too ----
    readonly property Instantiator watcher: Instantiator {
        model: root.server.trackedNotifications
        delegate: Connections {
            required property var modelData
            target: modelData
            // CloseRequested == the *sending app* withdrew the notification via
            // CloseNotification — e.g. you opened the app and it cleared the alert.
            // Treat that as "handled": forget it from history too (not just the
            // active stack) so the resting app-icon strip / unread badge update
            // immediately. Expired / user-Dismissed only leave the active stack —
            // their history copy is kept until the user forgets/clears it.
            function onClosed(reason) {
                if (reason === NotificationCloseReason.CloseRequested)
                    root.forget(modelData);
                else
                    root.drop(modelData);
            }
        }
    }

    // ---- grouped history: by app, newest-first within a group, group ordered by
    //      its newest item, so a fresh notification floats its app to the top ----
    property var grouped: []
    // `extra` is an optional just-arrived notification: setting `tracked=true` adds
    // it to the server model *without* emitting trackedNotificationsChanged AND its
    // `values` list may not include it yet on the same tick, so a plain rebuild at
    // arrival would omit it and the resting strip / badge / history would go stale
    // until something later forced another rebuild (e.g. opening the history pane).
    // Splicing `extra` in makes the arrival reflect immediately and deterministically
    // (deduped by id; a later rebuild from a settled `values` yields the same set).
    function rebuild(extra) {
        const vals = root.server.trackedNotifications ? root.server.trackedNotifications.values : [];
        const list = vals.slice();
        if (extra && extra.tracked && !list.some(x => x && x.id === extra.id))
            list.push(extra);
        const ts = id => root.stamps[id] || 0;
        const by = {}, order = [];
        for (const n of list) {
            // a just-forgotten notification can still appear in `values` for one
            // cycle (emptied of content) while it is being destroyed — skip it so
            // history never shows a contentless card.
            if (!n || !n.tracked) continue;
            const k = n.appName || "Unknown";
            if (!by[k]) { by[k] = { app: k, items: [] }; order.push(k); }
            by[k].items.push(n);
        }
        for (const k of order) by[k].items.sort((x, y) => ts(y.id) - ts(x.id));
        const gs = order.map(k => by[k]);
        gs.sort((g1, g2) => ts(g2.items[0].id) - ts(g1.items[0].id));
        root.grouped = gs;
    }
    // total un-cleared notifications in history (sum across app groups); drives the
    // collapsed-pill unread dot and the status-switcher notifications badge.
    readonly property int unreadCount: {
        let c = 0;
        for (const g of root.grouped) c += g.items.length;
        return c;
    }
    readonly property Connections rebuilder: Connections {
        target: root.server
        function onTrackedNotificationsChanged() { root.rebuild(); }
    }
    Component.onCompleted: root.rebuild()

    function relTime(id) {
        const t = root.stamps[id]; if (!t) return "";
        let s = Math.floor((root.nowMs - t) / 1000); if (s < 0) s = 0;
        if (s < 60) return "now";
        const m = Math.floor(s / 60); if (m < 60) return m + "m ago";
        const h = Math.floor(m / 60); if (h < 24) return h + "h ago";
        return Math.floor(h / 24) + "d ago";
    }
}
