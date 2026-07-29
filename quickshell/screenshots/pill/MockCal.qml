pragma ComponentBehavior: Bound
// MockCal.qml — stand-in for CalendarEvents.qml (screenshot harness). Static Google
// Calendar events for the selected day; hasEvents returns false so no per-cell dots
// appear without real keys. No Process / DBus / network — pure data.
import QtQuick

QtObject {
    id: root
    property var accounts: ["mpourismaiel", "root-sustainability"]
    property bool loading: false
    property string lastError: ""
    property var events: []
    function ensureCovers(a, b) {}
    function fetch(a, b) {}
    function hasEvents(key) { return false; }
    function dayEvents(key) {
        return [
            { color: "#6ea8d8", summary: "Daily standup", allDay: false,
              startTime: "09:00", endTime: "09:30", location: "Google Meet",
              description: "Quick sync on the week's goals and current blockers.",
              attendees: [{ name: "Sam Rivera", response: "accepted", self: false },
                          { name: "You", response: "needsAction", self: true }],
              joinLink: "https://meet.google.com/abc-defg-hij",
              htmlLink: "https://calendar.google.com/event?eid=1",
              calendar: "Work", account: "mpourismaiel", days: [key] },
            { color: "#d9a441", summary: "Team offsite", allDay: true,
              startTime: "", endTime: "", location: "", description: "",
              attendees: [], joinLink: "", htmlLink: "",
              calendar: "Personal", account: "root-sustainability", days: [key] }
        ];
    }
}
