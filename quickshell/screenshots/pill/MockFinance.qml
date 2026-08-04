pragma ComponentBehavior: Bound
// MockFinance.qml — stand-in for FinanceState.qml (screenshot harness). Static
// finance data for the selected day + every report view; nag is forced on so the
// dismiss card renders; hasItems lights deterministic day-of-month dots.
import QtQuick

QtObject {
    id: root
    property bool enabled: true            // feature gate (mock: always on for the shot)
    property string dayKey: ""
    property var dayItems: [
        { date: "2026-07-22", description: "Groceries — supermarket", kind: "expense", amount: 1450000, currency: "IRT", postings: [] },
        { date: "2026-07-22", description: "Lunch with the team", kind: "expense", amount: 18.50, currency: "EUR", postings: [] },
        { date: "2026-07-22", description: "Freelance invoice", kind: "income", amount: 350.00, currency: "EUR", postings: [] }
    ]
    property var rangeMap: ({})
    property var rangeDays: []
    // forecast (periodic) occurrences over the loaded range — the calendar's
    // hollow dots + per-day "Upcoming" section (native amounts, category + asset)
    property var forecastRangeItems: []
    // hand-off to the finance menu's add form (see FinanceState.pendingPrefill)
    property var pendingPrefill: null
    property var accounts: ({
        expenses: ["expenses:rent", "expenses:food:groceries", "expenses:food:restaurants",
                   "expenses:transport", "expenses:utilities", "expenses:entertainment",
                   "expenses:shopping", "expenses:misc"],
        income: ["income:salary", "income:other"],
        assets: ["assets:bank:checking", "assets:bank:savings", "assets:cash"],
        liabilities: ["liabilities:debts"],
        other: ["equity:opening"]
    })
    property var balances: ({
        rows: [
            { account: "assets:bank:checking", indent: 2, amounts: [{ currency: "EUR", value: 3187.50 }] },
            { account: "assets:bank:savings", indent: 2, amounts: [{ currency: "EUR", value: 5000.00 }] },
            { account: "assets:cash", indent: 1, amounts: [{ currency: "IRT", value: 84000000 }] }
        ],
        totals: [{ currency: "EUR", value: 8187.50 }, { currency: "IRT", value: 84000000 }]
    })
    property var timelineItems: [
        { date: "2026-08-01", description: "rent", kind: "expense", amount: 300000000, currency: "IRT", balance: [{ currency: "IRT", value: -216000000 }, { currency: "EUR", value: 8187.50 }] },
        { date: "2026-08-07", description: "salary", kind: "income", amount: 2000.00, currency: "EUR", balance: [{ currency: "IRT", value: -216000000 }, { currency: "EUR", value: 10187.50 }] },
        { date: "2026-08-21", description: "salary", kind: "income", amount: 2000.00, currency: "EUR", balance: [{ currency: "IRT", value: -216000000 }, { currency: "EUR", value: 12187.50 }] },
        { date: "2026-09-04", description: "salary", kind: "income", amount: 2000.00, currency: "EUR", balance: [{ currency: "IRT", value: -216000000 }, { currency: "EUR", value: 14187.50 }] }
    ]
    property var registerItems: [
        { date: "2026-07-22", description: "Freelance invoice", kind: "income", amount: 350.00, currency: "EUR", postings: [] },
        { date: "2026-07-22", description: "Lunch with the team", kind: "expense", amount: 18.50, currency: "EUR", postings: [] },
        { date: "2026-07-21", description: "Metro card top-up", kind: "expense", amount: 900000, currency: "IRT", postings: [] },
        { date: "2026-07-20", description: "Savings transfer", kind: "transfer", amount: 500.00, currency: "EUR", postings: [] },
        { date: "2026-07-18", description: "Groceries", kind: "expense", amount: 2100000, currency: "IRT", postings: [] }
    ]
    property var wishlist: ({
        liquid: 8187.50, buffer: 1000, spendable: 7187.50, currency: "EUR",
        items: [
            { description: "camera", amount: 920.00, currency: "EUR", affordable: true },
            { description: "headphones", amount: 150.00, currency: "EUR", affordable: true },
            { description: "standing desk", amount: 700.00, currency: "EUR", affordable: false }
        ]
    })
    // savings + wishlist-purchase plan (see FinanceState.planData)
    property var planData: ({
        currency: "EUR", buffer: 1000, goal: 5000, goal_date: "2026-12-31", start: 8187.50,
        months: [
            { month: "2026-07", end_date: "2026-07-31", net: 1250.00, projected: 8437.50, floor: 1000, cushion: 7437.50, purchases: ["headphones"] },
            { month: "2026-08", end_date: "2026-08-31", net: 1900.00, projected: 9417.50, floor: 1000, cushion: 8417.50, purchases: ["camera"] },
            { month: "2026-09", end_date: "2026-09-30", net: 2000.00, projected: 11417.50, floor: 1000, cushion: 10417.50, purchases: [] },
            { month: "2026-10", end_date: "2026-10-31", net: 2000.00, projected: 13417.50, floor: 1000, cushion: 12417.50, purchases: [] },
            { month: "2026-11", end_date: "2026-11-30", net: 1400.00, projected: 14817.50, floor: 1000, cushion: 13817.50, purchases: [] },
            { month: "2026-12", end_date: "2026-12-31", net: 2000.00, projected: 16817.50, floor: 5000, cushion: 11817.50, purchases: [] }
        ],
        items: [
            { description: "headphones", price: 150.00, currency: "EUR", month: "2026-07", month_index: 0 },
            { description: "camera", price: 920.00, currency: "EUR", month: "2026-08", month_index: 1 },
            { description: "standing desk", price: 700.00, currency: "EUR", month: null, shortfall: 220.00 }
        ]
    })
    // books (entities) — a second one so the header chip shows
    property string entity: "personal"
    property var entities: [{ name: "personal", default: true }, { name: "company", default: false }]
    // git strip — unsaved entries + one unpushed commit so both cues show
    property var gitInfo: ({ repo: true, branch: "main", dirty: 2, ahead: 1, behind: 0,
                             last: "a1b2c3d groceries" })
    property bool gitBusy: false
    property string gitError: ""
    function loadGit() {}
    function gitSync() {}
    function gitPush() {}
    function loadEntities() {}
    function loadPlan() {}
    function switchEntity(name) { if (name) root.entity = name; }
    function cycleEntity() {
        var names = root.entities.map(function (e) { return e.name; });
        var i = names.indexOf(root.entity);
        root.switchEntity(names[(i + 1) % names.length]);
    }
    property bool todayHasEntry: false
    property bool adding: false
    property bool privacy: false
    property bool screenShare: false
    property bool nag: true               // force the dismiss card into the shot
    readonly property bool nagIcon: nag && !privacy

    // display currency (native | EUR | IRT) — cycled by the header/day-list chips
    property string displayCurrency: "native"
    readonly property var currencyCycle: ["native", "EUR", "IRT"]
    readonly property string currencyLabel: displayCurrency === "native" ? "As-is" : displayCurrency
    function cycleCurrency() {
        var i = root.currencyCycle.indexOf(root.displayCurrency);
        root.displayCurrency = root.currencyCycle[(i + 1) % root.currencyCycle.length];
    }

    signal addFinished(bool ok, string error)
    signal entryAdded()

    function loadDay(key) { root.dayKey = key; }
    function loadRange(a, b) {}
    function loadForecastRange(a, b) {}
    function loadAccounts() {}
    function loadBalances() {}
    function loadTimeline(months) {}
    function loadRegister(query, limit) {}
    function loadWishlist() {}
    function checkToday() {}
    function addEntry(payload) {}
    function togglePrivacy() { root.privacy = !root.privacy; }
    function dismissNag(minutes) {}
    function dismissNagUntilTomorrow() {}
    // deterministic dots: light fixed days of whatever month is shown
    function hasItems(key) {
        var d = ("" + key).slice(-2);
        return ["03", "08", "12", "17", "22", "26"].indexOf(d) !== -1;
    }
    // forecast (hollow) dots on a different set of days
    function hasForecast(key) {
        var d = ("" + key).slice(-2);
        return ["01", "07", "15", "21", "28"].indexOf(d) !== -1;
    }
    // the selected day's forecast rows — non-empty on a hasForecast day, so the
    // calendar's "Upcoming" section renders whenever a hollow dot is selected.
    function forecastForDay(key) {
        if (!root.hasForecast(key)) return [];
        return [
            { date: key, description: "Rent", kind: "expense", amount: 300000000, currency: "IRT", account: "expenses:rent", asset: "assets:bank:checking", postings: [] },
            { date: key, description: "Netflix subscription", kind: "expense", amount: 12.99, currency: "EUR", account: "expenses:entertainment", asset: "assets:bank:checking", postings: [] }
        ];
    }
    // real formatter (copied from FinanceState) so the shots match production
    function fmtAmount(v, cur) {
        if (root.privacy) return "•••";
        var n = cur === "IRT"
            ? Number(Math.round(v)).toLocaleString(Qt.locale("en_US"), 'f', 0)
            : Number(v).toLocaleString(Qt.locale("en_US"), 'f', 2);
        return n + " " + cur;
    }
}
