pragma ComponentBehavior: Bound
// MockCal.qml — stand-in for CalendarEvents.qml (screenshot harness). Static Google
// Calendar events; hasEvents returns false so no per-cell dots appear without real
// keys. No Process / DBus / network — pure data. `nowMs` is pinned to 09:00 on the
// mock day so one event reads as "Starting now" for the imminent banner.
import QtQuick

QtObject {
    id: root
    property var accounts: ["mpourismaiel", "root-sustainability"]
    property bool loading: false
    property string lastError: ""
    property var events: root.baseEvents
    // pinned wall-clock: 09:00 on the mock day, so the standup is "Starting now".
    property double nowMs: new Date(2026, 7, 3, 9, 0, 0).getTime()
    function read() {}
    function ensureCovers(a, b) {}
    function fetch(a, b) {}
    function hasEvents(key) { return false; }

    // shared event list (with start/end keys so EventCard can compute times / state)
    readonly property var baseEvents: [
        // already ended before nowMs (09:00) → renders struck-through
        { color: "#c98e8e", summary: "Early gym slot", allDay: false,
          startKey: "2026-08-03", endKey: "2026-08-03",
          startTime: "07:00", endTime: "08:00", location: "", description: "",
          attendees: [], joinLink: "", htmlLink: "",
          calendar: "Personal", account: "mpourismaiel", days: ["2026-08-03"] },
        { color: "#6ea8d8", summary: "Daily standup", allDay: false,
          startKey: "2026-08-03", endKey: "2026-08-03",
          startTime: "09:00", endTime: "09:30", location: "Google Meet",
          description: "Quick sync on the week's goals and current blockers.",
          attendees: [{ name: "Sam Rivera", response: "accepted", self: false },
                      { name: "You", response: "needsAction", self: true }],
          joinLink: "https://meet.google.com/abc-defg-hij",
          htmlLink: "https://calendar.google.com/event?eid=1",
          calendar: "Work", account: "mpourismaiel", days: ["2026-08-03"] },
        { color: "#8ec98e", summary: "Design review", allDay: false,
          startKey: "2026-08-03", endKey: "2026-08-03",
          startTime: "14:00", endTime: "15:00", location: "",
          description: "Walk through the agenda popup redesign.",
          attendees: [], joinLink: "https://meet.google.com/xyz-1234-abc",
          htmlLink: "https://calendar.google.com/event?eid=3",
          calendar: "Work", account: "mpourismaiel", days: ["2026-08-03"] },
        { color: "#d9a441", summary: "Team offsite", allDay: true,
          startKey: "2026-08-04", endKey: "2026-08-05",
          startTime: "", endTime: "", location: "", description: "",
          attendees: [], joinLink: "", htmlLink: "",
          calendar: "Personal", account: "root-sustainability", days: ["2026-08-04"] }
    ]
    function dayEvents(key) {
        return root.baseEvents.filter(function (e) { return (e.days || []).indexOf(key) !== -1; });
    }
}
