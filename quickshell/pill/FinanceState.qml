pragma ComponentBehavior: Bound
// FinanceState.qml — hledger finance state over hledgerbridge.py, plus the
// privacy and evening-nag state machines. Instantiated once in init.qml as
// `FinanceState { id: finance; settings: settings; screenShare: root.screenRecording;
// now: sysclock.date }` and shared with the finance/calendar menus, launcher and
// status icons. Best-effort — empty data if hledger is unreachable.
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var settings: null           // JsonAdapter (persisted privacy/nag fields)
    property bool screenShare: false      // bound to root.screenRecording
    property date now: new Date()         // bound to sysclock.date (reactive, minutes)
    // ---- feature gate (launcher Settings → Finance) ----
    // enabled=false → no hledger calls, no evening nag, empty views. financeDir, when
    // set, is the repo every command targets (`--dir`, overriding the ~/Documents/finance
    // default) so nothing is hard-coded and the project is shareable.
    property bool enabled: false
    property string financeDir: ""

    // ---- book (entity): which set of journals every command targets ----
    //   "personal" = the journals at the base dir; any other name = a subfolder
    //   with its own main.journal (e.g. "company"). Every bridge call is scoped
    //   to it; switching reloads whatever views are live.
    property string entity: "personal"
    property var entities: [{ name: "personal", default: true }]
    function loadEntities() {
        if (!root.enabled) return;
        entitiesProc.command = root.bridge(["entities"]);
        if (!entitiesProc.running) entitiesProc.running = true;
    }
    function switchEntity(name) {
        if (name && name !== root.entity) root.entity = name;
    }
    function cycleEntity() {                 // header chip: hop to the next book
        var names = (root.entities || []).map(function (e) { return e.name; });
        if (names.length < 2) return;
        var i = names.indexOf(root.entity);
        root.switchEntity(names[(i + 1) % names.length]);
    }

    // ---- display currency: how every amount the pill shows is valued ----
    //   "native" = as entered (mixed EUR/IRT) · "EUR"/"IRT" = market-valued.
    //   Shared by calendar + finance menu; cycling it reloads the live views.
    property string displayCurrency: "native"
    readonly property var currencyCycle: ["native", "EUR", "IRT"]
    readonly property string currencyLabel: displayCurrency === "native" ? "As-is" : displayCurrency
    function cycleCurrency() {
        var i = root.currencyCycle.indexOf(root.displayCurrency);
        root.displayCurrency = root.currencyCycle[(i + 1) % root.currencyCycle.length];
    }

    // ---- day / range data (calendar + finance menu grid) ----
    property string dayKey: ""            // day currently loaded ("YYYY-MM-DD")
    property var dayItems: []             // [{ date, description, kind, amount, currency, postings }]
    property var rangeMap: ({})           // date -> actual-entry count in the loaded range
    property var rangeDays: []            // [{ date, count }, …]
    property var forecastMap: ({})        // date -> forecast-entry count (hollow dot)
    property var forecastRangeItems: []   // [{ date, description, kind, amount, currency, account, asset, postings }]
                                          //   every forecast occurrence in the loaded range; both the hollow
                                          //   dots (forecastMap) and the calendar's per-day "Upcoming" list
                                          //   (forecastForDay) derive from this one query, so they always agree.
    // the selected day's forecast occurrences — filtered from forecastRangeItems.
    function forecastForDay(key) {
        var out = [];
        var arr = root.forecastRangeItems || [];
        for (var i = 0; i < arr.length; i++)
            if (arr[i].date === key) out.push(arr[i]);
        return out;
    }

    // Hand-off from the calendar's forecast section to the finance menu's add
    // form: the calendar sets this to a forecast row, flips to the finance menu,
    // and the menu prefills + clears it. Null when nothing is pending.
    property var pendingPrefill: null

    // ---- finance-menu view data ----
    property var accounts: ({ expenses: [], income: [], assets: [], liabilities: [], other: [] })
    property var balances: ({ rows: [], totals: [] })
    property var timelineItems: []        // [{ date, description, amount, currency, kind, balance }]
    property var registerItems: []
    readonly property bool registerLoading: registerProc.running
    // per-category totals over a date range (same shape as `balances`)
    property var categoryItems: ({ rows: [], totals: [] })
    property var wishlist: ({ liquid: 0, buffer: 0, spendable: 0, currency: "EUR", items: [] })
    // savings + wishlist-purchase plan: { currency, buffer, goal, goal_date,
    // start, months:[{month,end_date,net,projected,floor,cushion,purchases}],
    // items:[{description,price,currency,month,month_index?,shortfall?}] }
    property var planData: ({ currency: "EUR", buffer: 0, goal: null, months: [], items: [] })

    // optimistic default so the nag never flashes before the first check lands
    property bool todayHasEntry: true

    readonly property bool adding: addProc.running
    signal addFinished(bool ok, string error)
    signal entryAdded()                   // fired after a successful add (reload hook)

    function bridge(args) {
        // optional --dir picks the repo; every command is then scoped to the
        // current book via --entity.
        var base = ["python", Quickshell.shellPath("hledgerbridge.py")];
        if (root.financeDir) base = base.concat(["--dir", root.financeDir]);
        return base.concat(["--entity", root.entity]).concat(args);
    }
    // remembered so an entity switch can re-fire the same-span calendar loads
    property string lastRangeA: ""
    property string lastRangeB: ""
    function loadDay(key) {
        root.dayKey = key;
        if (!root.enabled) { root.dayItems = []; return; }
        dayProc.command = root.bridge(["day", key, root.displayCurrency]);
        if (!dayProc.running) dayProc.running = true;
    }
    function loadRange(a, b) {
        root.lastRangeA = a; root.lastRangeB = b;
        if (!root.enabled) { root.rangeMap = ({}); root.rangeDays = []; return; }
        rangeProc.command = root.bridge(["range", a, b]);
        if (!rangeProc.running) rangeProc.running = true;
    }
    function loadForecastRange(a, b) {
        if (!root.enabled) { root.forecastMap = ({}); root.forecastRangeItems = []; return; }
        forecastRangeProc.command = root.bridge(["fentries", a, b]);
        if (!forecastRangeProc.running) forecastRangeProc.running = true;
    }
    function loadPlan() {
        planProc.command = root.bridge(["plan", root.displayCurrency]);
        if (!planProc.running) planProc.running = true;
    }
    function loadAccounts() {
        accountsProc.command = root.bridge(["accounts"]);
        if (!accountsProc.running) accountsProc.running = true;
    }
    function loadBalances() {
        balancesProc.command = root.bridge(["balances", root.displayCurrency]);
        if (!balancesProc.running) balancesProc.running = true;
    }
    function loadTimeline(months) {
        timelineProc.command = root.bridge(["timeline", root.displayCurrency,
                                            "" + (months || 12)]);
        if (!timelineProc.running) timelineProc.running = true;
    }
    function loadRegister(query, limit) {
        registerProc.command = root.bridge(["register", query || "",
                                            "" + (limit || 50), root.displayCurrency]);
        if (!registerProc.running) registerProc.running = true;
    }
    function loadWishlist() {
        wishlistProc.command = root.bridge(["wishlist", root.displayCurrency]);
        if (!wishlistProc.running) wishlistProc.running = true;
    }
    function loadCategorySums(a, b) {
        if (!root.enabled || !a || !b) { root.categoryItems = { rows: [], totals: [] }; return; }
        catSumProc.command = root.bridge(["catsum", a, b, root.displayCurrency]);
        if (!catSumProc.running) catSumProc.running = true;
    }
    function checkToday() {
        if (!root.enabled) { root.todayHasEntry = true; return; }
        todayProc.command = root.bridge(["today-has-entry"]);
        if (!todayProc.running) todayProc.running = true;
    }
    function addEntry(payload) {
        if (addProc.running) return;
        addProc.command = root.bridge(["add", JSON.stringify(payload)]);
        addProc.running = true;
    }
    function hasItems(key) { return root.rangeMap.hasOwnProperty(key); }
    function hasForecast(key) { return root.forecastMap.hasOwnProperty(key); }

    // Cycling the display currency reloads the day list in place; the finance
    // menu reloads whichever report is open (it watches displayCurrency too).
    onDisplayCurrencyChanged: if (root.dayKey) root.loadDay(root.dayKey)

    // Switching books re-fires every live load against the new journals; the
    // menus watch `entity` too and re-open their current view.
    onEntityChanged: {
        root.checkToday();
        if (root.dayKey) root.loadDay(root.dayKey);
        if (root.lastRangeA) {
            root.loadRange(root.lastRangeA, root.lastRangeB);
            root.loadForecastRange(root.lastRangeA, root.lastRangeB);
        }
    }

    // ---- one formatter for every amount the pill renders: EUR two decimals,
    //      IRT whole Toman, en-US separators; privacy masks the number ----
    function fmtAmount(v, cur) {
        if (root.privacy) return "•••";
        var n = cur === "IRT"
            ? Number(Math.round(v)).toLocaleString(Qt.locale("en_US"), 'f', 0)
            : Number(v).toLocaleString(Qt.locale("en_US"), 'f', 2);
        return n + " " + cur;
    }

    // ---- privacy machine ----
    // While sharing, `privacyShare` is the effective value (reset to ON at every
    // share start; the toggle overrides it for that share only). Otherwise the
    // persisted manual choice applies — so share end "restores" by construction.
    property bool privacyShare: true
    onScreenShareChanged: if (screenShare) privacyShare = true
    readonly property bool privacy: screenShare
        ? privacyShare
        : (settings ? settings.financePrivacy === true : false)
    function togglePrivacy() {
        if (root.screenShare) root.privacyShare = !root.privacyShare;
        else if (root.settings) root.settings.financePrivacy = !root.settings.financePrivacy;
    }

    // ---- nag machine (all derived from the reactive `now`) ----
    readonly property string todayKey: Qt.formatDateTime(now, "yyyy-MM-dd")
    readonly property int hour: now.getHours()
    readonly property bool nagDismissed: {
        var s = settings ? settings.financeNagDismissedUntil : "";
        if (!s) return false;
        var t = Date.parse(s);
        return !isNaN(t) && now.getTime() < t;
    }
    readonly property bool nag: enabled && hour >= 20 && !todayHasEntry && !nagDismissed
    readonly property bool nagIcon: nag && !privacy
    // one-shot per day, deferred while sharing (fires when the share ends)
    readonly property bool notifyDue: hour >= 23 && nag && !screenShare
        && settings !== null && settings.financeNagNotifiedOn !== todayKey
    onNotifyDueChanged: if (notifyDue) {
        settings.financeNagNotifiedOn = todayKey;
        nagProc.command = ["notify-send", "-a", "Finance", "-u", "critical",
            "-i", "wallet", "No finance entries today",
            "Nothing recorded for " + todayKey + " yet — add it from the pill or Emacs."];
        nagProc.running = true;
    }
    function dismissNag(minutes) {
        if (root.settings)
            root.settings.financeNagDismissedUntil =
                new Date(root.now.getTime() + minutes * 60000).toISOString();
    }
    function dismissNagUntilTomorrow() {   // caller runs the confirm step
        if (!root.settings) return;
        var d = new Date(root.now);
        d.setHours(24, 0, 0, 0);           // next midnight
        root.settings.financeNagDismissedUntil = d.toISOString();
    }
    onTodayKeyChanged: checkToday()        // midnight rollover: fresh day, fresh check
    Component.onCompleted: if (root.enabled) { checkToday(); loadEntities(); loadGit(); }
    // turning the feature on/off: warm or reset the derived state.
    onEnabledChanged: {
        if (root.enabled) { checkToday(); loadEntities(); loadGit(); }
        else {
            root.todayHasEntry = true;   // nag off
            root.gitInfo = ({ repo: false });
            root.dayItems = []; root.rangeMap = ({}); root.rangeDays = [];
            root.forecastMap = ({}); root.forecastRangeItems = [];
        }
    }

    // catch entries added outside the pill (Emacs) during the nag window
    property Timer freshTimer: Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: root.enabled && root.hour >= 19 && !root.todayHasEntry
        onTriggered: root.checkToday()
    }

    // ---- processes (one per command, orgbridge pattern) ----
    property Process dayProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dayItems = JSON.parse(this.text) || []; }
                catch (e) { root.dayItems = []; }
            }
        }
    }
    property Process rangeProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var arr = [];
                try { arr = JSON.parse(this.text) || []; } catch (e) { arr = []; }
                var m = {};
                for (var i = 0; i < arr.length; i++) m[arr[i].date] = arr[i].count;
                root.rangeMap = m;
                root.rangeDays = arr;
            }
        }
    }
    property Process accountsProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.accounts = JSON.parse(this.text) || root.accounts; }
                catch (e) { /* keep last */ }
            }
        }
    }
    property Process balancesProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.balances = JSON.parse(this.text) || { rows: [], totals: [] }; }
                catch (e) { root.balances = { rows: [], totals: [] }; }
            }
        }
    }
    property Process forecastRangeProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                // full forecast rows over the range; the hollow-dot map is the
                // per-day count of these, so dots and the "Upcoming" list agree.
                var arr = [];
                try { arr = JSON.parse(this.text) || []; } catch (e) { arr = []; }
                var m = {};
                for (var i = 0; i < arr.length; i++)
                    m[arr[i].date] = (m[arr[i].date] || 0) + 1;
                root.forecastMap = m;
                root.forecastRangeItems = arr;
            }
        }
    }
    property Process timelineProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.timelineItems = JSON.parse(this.text) || []; }
                catch (e) { root.timelineItems = []; }
            }
        }
    }
    property Process registerProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.registerItems = JSON.parse(this.text) || []; }
                catch (e) { root.registerItems = []; }
            }
        }
    }
    property Process catSumProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.categoryItems = JSON.parse(this.text) || { rows: [], totals: [] }; }
                catch (e) { root.categoryItems = { rows: [], totals: [] }; }
            }
        }
    }
    property Process wishlistProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var empty = { liquid: 0, buffer: 0, spendable: 0, currency: "EUR", items: [] };
                try { root.wishlist = JSON.parse(this.text) || empty; }
                catch (e) { root.wishlist = empty; }
            }
        }
    }
    property Process planProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var empty = { currency: "EUR", buffer: 0, goal: null, months: [], items: [] };
                try { root.planData = JSON.parse(this.text) || empty; }
                catch (e) { root.planData = empty; }
            }
        }
    }
    property Process entitiesProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(this.text);
                    if (arr && arr.length) root.entities = arr;
                } catch (e) { /* keep last */ }
            }
        }
    }
    property Process todayProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r = JSON.parse(this.text);
                    root.todayHasEntry = r && r.has === true;
                } catch (e) { /* keep last */ }
            }
        }
    }
    property Process addProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var ok = false, err = "";
                try {
                    var r = JSON.parse(this.text);
                    ok = r && r.ok === true;
                    err = (r && r.error) ? r.error : "";
                } catch (e) { err = "finance bridge failed"; }
                if (ok) {
                    if (root.dayKey) root.loadDay(root.dayKey);
                    if (root.lastRangeA) root.loadForecastRange(root.lastRangeA, root.lastRangeB);
                    root.checkToday();
                    root.loadGit();   // the new entry shows up as unsaved
                    root.entryAdded();
                }
                root.addFinished(ok, err);
            }
        }
    }
    // --- git: the finance dir is one git repo (shared with shledger/web).
    // The pill offers status + ff-pull + commit&push; anything messier
    // (diverged branches, conflicts) is fixed in a terminal. ----------------
    property var gitInfo: ({ repo: false })
    property bool gitBusy: false
    property string gitError: ""
    function loadGit() {
        if (!root.enabled) { root.gitInfo = ({ repo: false }); return; }
        gitStatusProc.command = root.bridge(["git-status"]);
        if (!gitStatusProc.running) gitStatusProc.running = true;
    }
    function gitSync() {
        if (root.gitBusy) return;
        root.gitBusy = true;
        root.gitError = "";
        gitSyncProc.command = root.bridge(["git-sync"]);
        if (!gitSyncProc.running) gitSyncProc.running = true;
    }
    function gitPush() {
        if (root.gitBusy) return;
        root.gitBusy = true;
        root.gitError = "";
        gitPushProc.command = root.bridge(["git-push"]);
        if (!gitPushProc.running) gitPushProc.running = true;
    }
    property Process gitStatusProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.gitInfo = JSON.parse(this.text) || { repo: false }; }
                catch (e) { root.gitInfo = { repo: false }; }
            }
        }
    }
    property Process gitSyncProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.gitBusy = false;
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                if (r && r.ok) {
                    if (r.changed) {   // remote had new entries — reload views
                        if (root.dayKey) root.loadDay(root.dayKey);
                        if (root.lastRangeA) {
                            root.loadRange(root.lastRangeA, root.lastRangeB);
                            root.loadForecastRange(root.lastRangeA, root.lastRangeB);
                        }
                        root.checkToday();
                    }
                } else {
                    root.gitError = (r && r.error) ? r.error : "sync failed";
                }
                root.loadGit();
            }
        }
    }
    property Process gitPushProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.gitBusy = false;
                var r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = null; }
                if (!(r && r.ok))
                    root.gitError = (r && r.error) ? r.error : "push failed";
                root.loadGit();
            }
        }
    }
    property Process nagProc: Process {}
}
