pragma ComponentBehavior: Bound
// MockDone.qml — deterministic stand-in for DoneState so the Done page renders a
// full CODE + AGENDA picture off-screen, with no git/org/calendar calls. Shape
// matches what DoneMenu reads (period/periods/periodPhrase/setPeriod + code/agenda).
import QtQuick

QtObject {
    id: root
    property string period: "quarter"
    readonly property var periods: [
        { key: "week",    label: "WEEK" },
        { key: "month",   label: "MONTH" },
        { key: "quarter", label: "QUARTER" },
        { key: "year",    label: "YEAR" },
        { key: "all",     label: "ALL TIME" }
    ]
    readonly property string periodPhrase: period === "all" ? "all-time" : ("this " + period)
    function setPeriod(k) { if (k) root.period = k; }

    // loading toggle for the skeleton/busy screenshot stage
    property bool loading: false
    readonly property bool refreshing: loading

    property var code: loading ? ({ ready: false, configured: true, empty: false,
            commits: 0, branches: 0, projects: 0, merges: 0, prs: 0,
            prsStale: false, repos: 0, biggest: [] }) : ({
        ready: true, configured: true, empty: false,
        commits: 402, branches: 38, projects: 11, merges: 27, prs: 19,
        prsStale: false, repos: 11,
        biggest: [
            { subject: "Pill dashboard + paged states", add: 6412, del: 172, hash: "f796cf1", repo: "awesome" },
            { subject: "Remove legacy CSV importer", add: 40, del: 9920, hash: "3966435", repo: "shledger" },
            { subject: "Forecast & plan projections", add: 4180, del: 78, hash: "8a564de", repo: "shledger" },
            { subject: "Fix hotplug monitor scaling", add: 902, del: 22, hash: "92cd1c7", repo: "pill" },
            { subject: "Combo scoring engine", add: 2841, del: 31, hash: "80fe963", repo: "pill" },
            { subject: "Clipboard history panel", add: 1904, del: 0, hash: "69a0534", repo: "pill" }
        ]
    })
    property var agenda: loading ? ({ ready: false, configured: true, empty: false,
            done: 0, cancelled: 0, meetings: 0, hours: 0, items: [] }) : ({
        ready: true, configured: true, empty: false,
        done: 342, cancelled: 12, meetings: 96, hours: 118,
        items: [
            { text: "Ship the 0.3 release checklist", hours: 9.2, kind: "task" },
            { text: "Refinement", hours: 5.0, kind: "meeting" },
            { text: "Rewrite the onboarding docs", hours: 6.1, kind: "task" },
            { text: "Standup", hours: 4.5, kind: "meeting" },
            { text: "Migrate the CI pipeline to the new runners", hours: 5.0, kind: "task" },
            { text: "Retrospective", hours: 2.0, kind: "meeting" }
        ]
    })

    function reload() { }
}
