pragma ComponentBehavior: Bound
// MockFinance.qml — stand-in for FinanceState.qml (screenshot harness). Static
// finance data for the selected day + every report view; nag is forced on so the
// dismiss card renders; hasItems lights deterministic day-of-month dots.
import QtQuick

QtObject {
    id: root
    property string dayKey: ""
    property var dayItems: [
        { date: "2026-07-22", description: "Groceries — supermarket", kind: "expense", amount: 1450000, currency: "IRT", postings: [] },
        { date: "2026-07-22", description: "Lunch with the team", kind: "expense", amount: 18.50, currency: "EUR", postings: [] },
        { date: "2026-07-22", description: "Freelance invoice", kind: "income", amount: 350.00, currency: "EUR", postings: [] }
    ]
    property var rangeMap: ({})
    property var rangeDays: []
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
        liquid: [{ currency: "EUR", value: 8187.50 }, { currency: "IRT", value: 84000000 }],
        items: [
            { description: "camera", amount: 200000000, currency: "IRT", affordable: false },
            { description: "headphones", amount: 150.00, currency: "EUR", affordable: true },
            { description: "standing desk", amount: 700.00, currency: "USD", affordable: null }
        ]
    })
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
    // real formatter (copied from FinanceState) so the shots match production
    function fmtAmount(v, cur) {
        if (root.privacy) return "•••";
        var n = cur === "IRT"
            ? Number(Math.round(v)).toLocaleString(Qt.locale("en_US"), 'f', 0)
            : Number(v).toLocaleString(Qt.locale("en_US"), 'f', 2);
        return n + " " + cur;
    }
}
