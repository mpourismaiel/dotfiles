pragma ComponentBehavior: Bound
// DiskState.qml — state of the Disk window (diskbridge.py), instantiated once in
// init.qml and handed to DiskWindow / DiskView by required property.
//
// The bridge is one-shot: `scan` streams {"event":"progress"|"section"|"done"}
// lines while it walks, everything else (snapshot, ls, item, verify, apply,
// reports …) is a queued command whose answer arrives as a single event line.
// The last scan is cached by the bridge, so opening the window shows it at once
// and a rescan only replaces sections as they finish.
//
// The cleanup plan is just a list of item ids (persisted in settings.diskPlan).
// Nothing here removes anything: `review()` asks the bridge to re-check the plan
// against the disk and returns a token; `apply()` hands that token back together
// with the tiers the user acknowledged. The bridge refuses anything else.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    required property var settings

    property bool shown: false             // the window is open
    property string page: "overview"       // sidebar selection
    // ---- last scan ------------------------------------------------------------
    property bool ready: false             // a snapshot/scan has been read
    property bool empty: false             // never scanned
    property var disk: null                // {mounts, main{total,used,free,…}, home}
    property var overview: null            // {categories[], best[], offered{}, …}
    property var sections: ({})            // name → section data (see diskscan.py)
    property var items: ({})               // id → removable item
    property double scannedAt: 0           // seconds since epoch
    property real took: 0
    // ---- scan in progress -------------------------------------------------------
    property bool scanning: false
    property var progress: ({})            // section → {state, at, done, total, took}
    // ---- cleanup plan -----------------------------------------------------------
    property var plan: []                  // item ids
    property var review: null              // the bridge's `verified` answer
    property bool reviewing: false
    property bool applying: false
    property var applyStep: null           // {index,total,title}
    property var result: null              // the bridge's `applied` answer
    // ---- files browser ----------------------------------------------------------
    property var listing: null             // {path,parent,rows[],bytes,error}
    property bool listingBusy: false
    property var flagged: []               // paths flagged with d
    property var reports: []
    property string reportsDir: ""
    property string toast: ""
    // hide file and game names until asked (media libraries are private)
    property bool discreet: settings ? settings.diskDiscreet : true
    function setDiscreet(on) { if (root.settings) root.settings.diskDiscreet = on; else root.discreet = on; }
    // items the bridge made on demand for plain paths (Files, video rows …)
    property var pathIds: ({})             // path → item id
    property var _pendingPaths: []         // paths waiting for their item, then planned
    property bool _reviewAfter: false      // open the review once they arrive

    signal itemsMade(var items)

    readonly property var planItems: {
        var out = [];
        for (var i = 0; i < plan.length; i++) {
            var it = items[plan[i]];
            if (it) out.push(it);
        }
        return out;
    }
    readonly property double planBytes: {
        var b = 0;
        for (var i = 0; i < planItems.length; i++) b += planItems[i].reclaim || 0;
        return b;
    }
    readonly property var planTiers: {
        var t = { free: 0, cost: 0, state: 0, data: 0 };
        for (var i = 0; i < planItems.length; i++) t[planItems[i].tier] = (t[planItems[i].tier] || 0) + 1;
        return t;
    }

    // ---- formatting -------------------------------------------------------------
    function fmtBytes(b) {
        if (b === undefined || b === null || b < 0) return "—";
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB";
        if (b >= 10737418240) return Math.round(b / 1073741824) + " GB";
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576) return Math.round(b / 1048576) + " MB";
        if (b >= 1024) return Math.round(b / 1024) + " KB";
        return Math.round(b) + " B";
    }
    function fmtAge(ts) {
        if (!ts) return "—";
        var d = (Date.now() / 1000 - ts) / 86400;
        if (d < 1) return "today";
        if (d < 2) return "yesterday";
        if (d < 30) return Math.round(d) + " d ago";
        if (d < 365) return Math.round(d / 30.4) + " mo ago";
        var y = d / 365;
        return (y < 10 ? y.toFixed(1).replace(".0", "") : Math.round(y)) + " yr ago";
    }
    function fmtDate(ts) {
        return ts ? Qt.formatDateTime(new Date(ts * 1000), "yyyy-MM-dd") : "";
    }
    function tilde(p) {
        var h = disk && disk.home ? disk.home : "";
        return (h && p && (p === h || p.indexOf(h + "/") === 0)) ? "~" + p.substring(h.length) : (p || "");
    }
    // a name, or dots when discreet — the size and place stay readable
    function veil(name) {
        if (!discreet || !name) return name || "";
        var cut = name.lastIndexOf("/");
        if (cut >= 0 && cut < name.length - 1) return name.substring(0, cut + 1) + veil(name.substring(cut + 1));
        return name.substring(0, 1) + "•••••" + (name.length > 6 ? name.substring(name.length - 1) : "");
    }
    readonly property var tierLabel: ({ free: "comes back by itself", cost: "costs time to get back", state: "holds state", data: "cannot be recovered" })
    readonly property var sectionLabel: ({ projects: "Projects", caches: "Caches", packages: "Packages", docker: "Docker", games: "Games",
                                           thumbnails: "Thumbnails", downloads: "Downloads", bins: "Programs", files: "Files" })
    // names that may be private: games, downloads, loose files, hand-installed programs
    function private_(it) { return !!it && ["game", "steam-game", "download", "duplicate", "file", "binary"].indexOf(it.kind) >= 0; }
    function itemTitle(it) {
        if (!it) return "";
        if (it.section === "projects") return it.sub + " / " + it.title;
        return private_(it) ? veil(it.title) : it.title;
    }
    readonly property var tierShort: ({ free: "regenerates", cost: "re-download", state: "has state", data: "your file" })

    // ---- plan -------------------------------------------------------------------
    function inPlan(id) { return plan.indexOf(id) >= 0; }
    function setPlan(p) {
        root.plan = p;
        root.review = null;
        if (root.settings) root.settings.diskPlan = p;
    }
    function togglePlan(id) {
        if (!id) return;
        var p = plan.slice(), i = p.indexOf(id);
        if (i >= 0) p.splice(i, 1); else p.push(id);
        setPlan(p);
    }
    function addPlan(ids) {
        var p = plan.slice();
        for (var i = 0; i < ids.length; i++)
            if (ids[i] && p.indexOf(ids[i]) < 0) p.push(ids[i]);
        setPlan(p);
    }
    function dropPlan(ids) {
        setPlan(plan.filter(function (x) { return ids.indexOf(x) < 0; }));
    }
    function clearPlan() { setPlan([]); }
    // tick a row that is only a path: make its item first, then plan it
    function planPath(path) {
        var id = root.pathIds[path];
        if (id) { root.togglePlan(id); return; }
        root._pendingPaths = root._pendingPaths.concat([path]);
        root.makeItems([path]);
    }
    // Files: everything flagged becomes plan items, then straight to the review
    function reviewFlagged() {
        if (root.flagged.length === 0) return;
        root._pendingPaths = root._pendingPaths.concat(root.flagged);
        root._reviewAfter = true;
        root.makeItems(root.flagged);
    }
    function catColor(theme, key) {
        switch (key) {
        case "src": return theme.text;
        case "dep": return theme.accent;
        case "bld": return theme.money;
        case "dock": return theme.event;
        case "vid": return theme.success;
        case "game": return theme.plum;
        case "dl": return theme.good;
        case "cache": return theme.umber;
        case "pkg": return Qt.darker(theme.money, 1.5);
        case "sys": return theme.slate;
        }
        return theme.faint;
    }
    // every item the scan itself suggests, optionally for one section
    function offeredIds(section) {
        var out = [];
        for (var k in items)
            if (items[k].offer && (!section || items[k].section === section)) out.push(k);
        return out;
    }

    // ---- bridge plumbing ----------------------------------------------------------
    function _config() {
        var s = root.settings;
        return JSON.stringify({
            projectDirs: s ? (s.diskProjectDirs || []) : [],
            gameDirs: s ? (s.diskGameDirs || []) : [],
            staleDays: s ? (s.diskStaleDays || 180) : 180
        });
    }
    function _base() { return ["python", Quickshell.shellPath("diskbridge.py"), "--config", root._config()]; }
    property var _queue: []
    function _send(args) {
        var q = root._queue.slice(); q.push(root._base().concat(args)); root._queue = q;
        root._pump();
    }
    function _pump() {
        if (cmdProc.running || root._queue.length === 0) return;
        var q = root._queue.slice();
        cmdProc.command = q.shift();
        root._queue = q;
        cmdProc.running = true;
    }

    function open(pageName) {
        if (pageName) root.page = pageName;
        root.shown = true;
        if (!root.ready) root._send(["snapshot"]);
        if (root.settings && root.plan.length === 0 && root.settings.diskPlan) root.plan = root.settings.diskPlan;
    }
    function scan(only) {
        if (root.scanning) return;
        root.progress = ({});
        root.scanning = true;
        scanProc.command = root._base().concat(only ? ["scan", "--only", only] : ["scan"]);
        scanProc.running = true;
    }
    function stopScan() { scanProc.running = false; root.scanning = false; }
    function ls(path) { root.listingBusy = true; root._send(["ls", path]); }
    function makeItems(paths) { root._send(["item"].concat(paths)); }
    function startReview() {
        if (root.plan.length === 0) return;
        root.reviewing = true; root.result = null;
        root._send(["verify"].concat(root.plan));
    }
    // acks: the tiers the user acknowledged, e.g. ["free","cost"]
    function apply(acks) {
        if (!root.review || root.applying) return;
        root.applying = true; root.applyStep = null;
        root._send(["apply", root.review.token, "--ack", acks.join(",")]);
    }
    // Stop a removal run: the bridge finishes the item in hand (stopping a tool's
    // cleaner if one is running), leaves the rest on disk and still writes its report.
    function stopApply() { if (root.applying && cmdProc.running) cmdProc.signal(15); }
    function terminal(id) { root._send(["terminal", id]); }
    function reveal(path) { root._send(["reveal", path]); }
    function loadReports() { root._send(["reports"]); }
    function copy(text) {
        copyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", text];
        copyProc.running = true;
        root.toast = "Copied";
        toastTimer.restart();
    }
    function openFile(path) { Quickshell.execDetached(["xdg-open", path]); }

    function _loadScan(s) {
        root.disk = s.disk || null;
        root.overview = s.overview || null;
        root.sections = s.sections || ({});
        root.items = s.items || ({});
        root.scannedAt = s.at || 0;
        root.took = s.took || 0;
        root.ready = true;
        root.empty = false;
        root._prunePlan();
    }
    function _prunePlan() {
        var p = root.plan.filter(function (x) { return !!root.items[x]; });
        if (p.length !== root.plan.length) root.setPlan(p);
    }
    function _event(d) {
        var e = d.event;
        if (e === "snapshot") { root._loadScan(d.scan); }
        else if (e === "empty") { root.ready = true; root.empty = true; }
        else if (e === "ls") { root.listing = d; root.listingBusy = false; }
        else if (e === "items") {
            var m = Object.assign({}, root.items), pi = Object.assign({}, root.pathIds), add = [];
            for (var i = 0; i < d.items.length; i++) {
                var it = d.items[i];
                m[it.id] = it;
                pi[it.paths[0]] = it.id;
                if (root._pendingPaths.indexOf(it.paths[0]) >= 0) add.push(it.id);
            }
            root.items = m;
            root.pathIds = pi;
            root._pendingPaths = [];
            if (add.length) root.addPlan(add);
            if (root._reviewAfter) { root._reviewAfter = false; root.flagged = []; root.page = "plan"; }
            root.itemsMade(d.items);
        }
        else if (e === "verified") { root.review = d; root.reviewing = false; }
        else if (e === "applying") { root.applyStep = d; }
        else if (e === "applied") {
            root.applying = false; root.applyStep = null; root.result = d;
            if (d.ok) {
                // what went is no longer in the plan; what was skipped stays for another look
                var gone = [];
                for (var j = 0; j < d.results.length; j++)
                    if (["removed", "trashed", "ran"].indexOf(d.results[j].status) >= 0) gone.push(d.results[j].id);
                root.dropPlan(gone);
                root.review = null;
                root._send(["snapshot"]);
                root.loadReports();
            }
        }
        else if (e === "reports") { root.reports = d.reports || []; root.reportsDir = d.dir || ""; }
        else if (e === "terminal" && !d.ok) { root.toast = d.error || "Could not open a terminal"; toastTimer.restart(); }
    }

    property Process scanProc: Process {
        stdout: SplitParser {
            onRead: line => {
                var d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (!d) return;
                if (d.event === "progress") {
                    var p = Object.assign({}, root.progress);
                    p[d.section] = d;
                    root.progress = p;
                } else if (d.event === "disk") {
                    root.disk = d.disk;
                } else if (d.event === "section") {
                    var s = Object.assign({}, root.sections);
                    s[d.name] = d.data;
                    root.sections = s;
                    // this section's items replace the old ones
                    var m = ({});
                    for (var k in root.items)
                        if (root.items[k].section !== d.name) m[k] = root.items[k];
                    for (var k2 in d.items) m[k2] = d.items[k2];
                    root.items = m;
                    root.ready = true; root.empty = false;
                } else if (d.event === "done") {
                    root.disk = d.disk; root.overview = d.overview;
                    root.scannedAt = d.at; root.took = d.took;
                    root._prunePlan();
                }
            }
        }
        onExited: root.scanning = false
    }
    property Process cmdProc: Process {
        stdout: SplitParser {
            onRead: line => {
                var d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d) root._event(d);
            }
        }
        onExited: {
            // a command that died without answering must not leave a spinner behind
            root.listingBusy = false; root.reviewing = false;
            if (root.applying && !root.result) root.applying = false;
            root._pump();
        }
    }
    property Process copyProc: Process {}
    property Timer toastTimer: Timer { interval: 1600; onTriggered: root.toast = "" }
}
