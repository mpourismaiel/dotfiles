// HabitDots.qml — the GitHub-commit-style 7-day dot matrix for one habit-week
// (Monday first). Each day's outcome gets its own read: done = seasonal green
// (orange in fall/winter), missed = red, missed-with-reason = hollow amber
// (distinct from an unexplained gap, per the reserve/reason mechanic), frozen
// = icy white, off-schedule activity = hollow orange, pending = dim well,
// unscheduled/pre-start = near-invisible. Used by the habit cards, the tree
// tooltip and the habit dialog.
import QtQuick

Row {
    id: root
    required property var theme
    property var days: []          // week.days from habiq (7 entries)
    property string season: "summer"
    property int cell: 12
    spacing: 4

    readonly property bool warm: season === "fall" || season === "winter"

    Repeater {
        model: root.days
        delegate: Rectangle {
            required property var modelData
            readonly property string st: modelData.state || "unscheduled"
            width: root.cell
            height: root.cell
            radius: 3
            color: st === "done" ? (root.warm ? "#d78f3c" : "#74b06a")
                 : st === "missed" ? "#b4513e"
                 : st === "frozen" ? "#dfe6ec"
                 : "transparent"
            border.width: (st === "missed-reason" || st === "offday" || st === "pending" || st === "unscheduled") ? 1 : 0
            border.color: st === "missed-reason" ? "#d9a441"
                        : st === "offday" ? "#c06a35"
                        : st === "pending" ? root.theme.track
                        : Qt.rgba(root.theme.track.r, root.theme.track.g, root.theme.track.b, 0.35)
        }
    }
}
