pragma ComponentBehavior: Bound
// DoneState.qml — state for the "Done" work-history page. Two independent
// chapters, never joined: CODE (git activity across the configured project
// directories, via gitbridge.py) and AGENDA (org DONE closures + clocked hours
// via orgbridge.py, merged with attended calendar meetings from CalendarEvents).
// Instantiated once in init.qml and shared with DoneMenu. Best-effort — an
// unreachable source leaves its chapter empty, never in an error state.
//
// The window is always [periodStart … today]: nothing here is ever in the
// future, so a meeting only ever appears as attended, never as upcoming.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var settings: null            // JsonAdapter (productivityDirs / productivityEmails / org*)
    property var cal: null                 // CalendarEvents (attended meetings)
    property date now: new Date()

    // ---- period selector ----------------------------------------------------
    property string period: "all"          // week · month · quarter · year · all
    readonly property var periods: [
        { key: "week",    label: "WEEK" },
        { key: "month",   label: "MONTH" },
        { key: "quarter", label: "QUARTER" },
        { key: "year",    label: "YEAR" },
        { key: "all",     label: "ALL TIME" }
    ]
    readonly property string periodPhrase: period === "all" ? "all-time"
        : ("this " + period)
    function setPeriod(k) { if (k && k !== root.period) { root.period = k; root.reload(); } }

    // ---- configuration gates ------------------------------------------------
    readonly property var dirs:   (settings && settings.productivityDirs)   ? settings.productivityDirs   : []
    readonly property var emails: (settings && settings.productivityEmails) ? settings.productivityEmails : []
    readonly property bool codeConfigured: dirs.length > 0 && emails.length > 0

    // ---- CODE chapter (git) -------------------------------------------------
    // ready=false → skeleton; configured=false → empty-state prompt.
    property var code: ({ ready: false, configured: false, empty: true,
        commits: 0, branches: 0, projects: 0, merges: 0, prs: 0, prsStale: false,
        repos: 0, biggest: [] })
    property var _gitSummary: null
    property var _prs: null

    // ---- AGENDA chapter (org + calendar) ------------------------------------
    property var agenda: ({ ready: false, configured: false, empty: true,
        done: 0, cancelled: 0, meetings: 0, hours: 0, items: [] })
    property var _orgDone: ({ done: 0, cancelled: 0, hours: 0, items: [] })

    // ---- per-period cache (stale-while-revalidate) --------------------------
    // Switching timeframe reuses the last result for that period instantly, so
    // the page never lags behind the chips; the bridges are only re-run when the
    // cached copy is older than ttlMs. `refreshing` is true while a live refresh
    // is in flight (the view dims the body until it lands).
    property var _cache: ({})
    property int ttlMs: 5 * 60 * 1000
    property bool refreshing: false
    property bool _codeDone: false          // a valid CODE result for the current period
    property bool _agendaDone: false        // a valid AGENDA result for the current period
    function _tryCache() {
        if (!root._codeDone || !root._agendaDone) return;
        var nc = root._cache;
        nc[root.period] = { code: root.code, agenda: root.agenda, at: Date.now() };
        root._cache = nc;
        root.refreshing = false;
    }
    // (re)start a per-command Process, cancelling any in-flight run so a switch to
    // a new period doesn't get stuck behind a slow query for the old one. Every
    // response is period-stamped and dropped on mismatch (see the handlers), so a
    // cancelled run's late output can never corrupt the current period.
    function _restart(p) { if (p.running) p.running = false; p.running = true; }

    // ---- date helpers -------------------------------------------------------
    function _fmt(d) { return Qt.formatDateTime(d, "yyyy-MM-dd"); }
    readonly property string todayKey: _fmt(now)
    function periodStart(p) {                       // "" for all-time
        if (p === "all") return "";
        var d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        if (p === "week") {
            var dow = (d.getDay() + 6) % 7;         // Monday = 0
            d.setDate(d.getDate() - dow);
        } else if (p === "month") {
            d = new Date(now.getFullYear(), now.getMonth(), 1);
        } else if (p === "quarter") {
            d = new Date(now.getFullYear(), Math.floor(now.getMonth() / 3) * 3, 1);
        } else if (p === "year") {
            d = new Date(now.getFullYear(), 0, 1);
        }
        return _fmt(d);
    }

    // ---- loaders ------------------------------------------------------------
    // Apply the cached copy for the period at once (no lag), then revalidate
    // from the bridges only if it is missing or past its TTL.
    readonly property bool agendaConfigured:
        (root.settings && root.settings.orgAgendaEnabled)
        || (root.cal && root.cal.events && root.cal.events.length > 0)

    function reload() {
        var c = root._cache[root.period];
        if (c) {
            root.code = c.code; root.agenda = c.agenda;
        } else {
            // never seen this period — show a loading skeleton rather than the
            // previous period's figures (ready:false → the chapters read "Gathering…")
            root.code = { ready: false, configured: root.codeConfigured, empty: false,
                commits: 0, branches: 0, projects: 0, merges: 0, prs: 0,
                prsStale: false, repos: 0, biggest: [] };
            root.agenda = { ready: false, configured: root.agendaConfigured, empty: false,
                done: 0, cancelled: 0, meetings: 0, hours: 0, items: [] };
        }
        if (c && (Date.now() - c.at) < root.ttlMs) { root.refreshing = false; return; }
        root.refreshing = true;
        root._codeDone = false;
        root._agendaDone = false;
        root.loadGit();
        root.loadAgenda();
    }

    function loadGit() {
        if (!root.codeConfigured) {
            root._gitSummary = null; root._prs = null;
            root.code = { ready: true, configured: false, empty: true,
                commits: 0, branches: 0, projects: 0, merges: 0, prs: 0,
                prsStale: false, repos: 0, biggest: [] };
            root._codeDone = true;
            root._tryCache();
            return;
        }
        root._gitSummary = null; root._prs = null;   // clear stale before the fetch
        var per = root.period;
        var since = root.periodStart(per);
        var dj = JSON.stringify(root.dirs), ej = JSON.stringify(root.emails);
        gitSummaryProc.command = ["python", Quickshell.shellPath("gitbridge.py"),
                                  "summary", since, dj, ej, per];
        root._restart(gitSummaryProc);
        gitPrsProc.command = ["python", Quickshell.shellPath("gitbridge.py"),
                              "prs", since, dj, per];
        root._restart(gitPrsProc);
    }

    function loadAgenda() {
        if (root.settings && root.settings.orgAgendaEnabled) {
            var per = root.period;
            var a = root.periodStart(per) || "1970-01-01";
            var cmd = ["python", Quickshell.shellPath("orgbridge.py")];
            if (root.settings.orgAgendaDir)
                cmd = cmd.concat(["--dir", root.settings.orgAgendaDir]);
            cmd = cmd.concat(["done", a, root.todayKey, per]);
            orgDoneProc.command = cmd;
            root._restart(orgDoneProc);
        } else {
            root._orgDone = { done: 0, cancelled: 0, hours: 0, items: [] };
            root._applyAgenda();
            root._agendaDone = true;
            root._tryCache();
        }
    }

    function _applyCode() {
        var s = root._gitSummary;
        var p = root._prs;
        if (!s) return;
        root.code = {
            ready: true, configured: true,
            empty: (s.commits + s.merges + s.branches + (p ? p.prs : 0)) === 0,
            commits: s.commits || 0, branches: s.branches || 0,
            projects: s.projects || 0, merges: s.merges || 0, repos: s.repos || 0,
            prs: p ? (p.prs || 0) : 0, prsStale: p ? !!p.stale : false,
            biggest: s.biggest || []
        };
    }

    // meeting duration in minutes, from the normalized event's start/end keys
    function _durMins(e) {
        if (!e.startTime || !e.endKey) return 0;
        var s = ("" + e.startKey).split("-"), st = ("" + e.startTime).split(":");
        var en = ("" + e.endKey).split("-"), et = ("" + (e.endTime || e.startTime)).split(":");
        var a = new Date(+s[0], +s[1] - 1, +s[2], +st[0], +st[1]);
        var b = new Date(+en[0], +en[1] - 1, +en[2], +et[0], +et[1]);
        var m = (b - a) / 60000;
        return m > 0 ? m : 0;
    }

    function _applyAgenda() {
        var o = root._orgDone || { done: 0, cancelled: 0, hours: 0, items: [] };
        var mA = root.periodStart(root.period) || "0000-01-01";
        var mB = root.todayKey;
        var mCount = 0, mHours = 0, mItems = [];
        var evs = (root.cal && root.cal.events) ? root.cal.events : [];
        for (var i = 0; i < evs.length; i++) {
            var e = evs[i];
            if (e.allDay || e.status === "cancelled" || !e.startKey) continue;
            var atts = e.attendees || [];
            var attending = atts.length === 0;     // own event with no invitees
            for (var k = 0; k < atts.length; k++) {
                var at = atts[k];
                if (at.self && (at.response === "accepted" || at.response === "tentative"))
                    attending = true;
            }
            if (!attending) continue;
            if (e.startKey < mA || e.startKey > mB) continue;   // window: past only
            var dur = root._durMins(e);
            mCount++; mHours += dur / 60;
            mItems.push({ text: e.summary || "(untitled)", hours: dur / 60, kind: "meeting" });
        }
        // group by title (recurring meetings/tasks collapse into one row whose
        // hours are the sum — e.g. five "Refinement" hours show as one 5.0h row),
        // keyed by kind+title so a task and a meeting of the same name stay apart.
        var raw = (o.items || []).map(function (x) {
            return { text: x.text, hours: x.hours, kind: "task" };
        }).concat(mItems);
        var byTitle = {};
        var order = [];
        for (var g = 0; g < raw.length; g++) {
            var it = raw[g];
            var key = it.kind + "|" + it.text;
            if (!byTitle[key]) { byTitle[key] = { text: it.text, hours: 0, kind: it.kind }; order.push(key); }
            byTitle[key].hours += it.hours;
        }
        var items = order.map(function (key) { return byTitle[key]; });
        items.sort(function (x, y) { return y.hours - x.hours; });
        items = items.slice(0, 6);
        root.agenda = {
            ready: true,
            configured: (root.settings && root.settings.orgAgendaEnabled) || evs.length > 0,
            empty: (o.done + o.cancelled + mCount) === 0,
            done: o.done || 0, cancelled: o.cancelled || 0, meetings: mCount,
            hours: (o.hours || 0) + mHours, items: items
        };
    }

    // recompute meetings when the calendar cache changes underneath us
    property Connections _calConn: Connections {
        target: root.cal
        function onEventsChanged() { root._applyAgenda(); }
    }

    property Process gitSummaryProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                if (!r || r.period !== root.period) return;   // stale period — drop
                root._gitSummary = r;
                root._applyCode();
                root._codeDone = true;
                root._tryCache();
            }
        }
    }
    property Process gitPrsProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                if (!r || r.period !== root.period) return;   // stale period — drop
                root._prs = r;
                root._applyCode();
            }
        }
    }
    property Process orgDoneProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                if (!r || r.period !== root.period) return;   // stale period — drop
                root._orgDone = r;
                root._applyAgenda();
                root._agendaDone = true;
                root._tryCache();
            }
        }
    }

    onPeriodChanged: { }          // reload() is driven by setPeriod / openDone
    Component.onCompleted: root.reload()
}
