pragma ComponentBehavior: Bound
// AddHabitDialog.qml — the header's "+ Add habit": appends a `habit` directive
// to the root journal via `habiq habit add` (config-as-data — same thing as
// editing habits.journal by hand, which stays the canonical path; this is the
// convenience form). Schedule/type/reward are cycle chips; target uses the
// chosen type's own value syntax (6:00, 20, 0:30:00). New habits start
// scoring today — no retroactive misses, no trees for prior weeks.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property var habits: null
    signal dismissed()

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

    readonly property var schedules: ["daily", "weekdays", "freeform", "custom"]
    readonly property var types: ["bool", "hours", "count", "duration"]
    readonly property var rewards: ["small", "medium", "big", "huge"]
    property int schedI: 0
    property int typeI: 0
    property int rewardI: 0
    property var customDays: ({})       // "mon" → true
    property bool noStreak: false
    property string error: ""

    Connections {
        target: root.habits
        function onWriteDone(ok, err) {
            root.error = ok ? "" : err;
            if (ok) root.dismissed();
        }
    }

    function submit() {
        var id = fId.text.trim();
        if (!id) { root.error = "habit id is required"; return; }
        var sched = root.schedules[root.schedI];
        if (sched === "custom") {
            var days = [];
            var order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
            for (var i = 0; i < order.length; i++)
                if (root.customDays[order[i]]) days.push(order[i]);
            if (days.length === 0) { root.error = "pick at least one day"; return; }
            sched = days.join(" ");
        }
        root.habits.addHabit({
            id: id,
            name: fName.text.trim(),
            schedule: sched,
            type: root.types[root.typeI],
            unit: fUnit.text.trim(),
            target: fTarget.text.trim(),
            reward: root.rewards[root.rewardI],
            penalty: fPenalty.text.trim(),
            offdayPenalty: fOffday.text.trim(),
            group: fGroup.text.trim(),
            noStreak: root.noStreak
        });
    }

    component Chip: Rectangle {
        property string label: ""
        property string value: ""
        signal tapped()
        width: chipCol.implicitWidth + 18
        height: 44
        radius: root.theme.radiusBtn
        color: chipMa.containsMouse ? root.theme.rowHi : root.theme.row
        border.width: 1
        border.color: root.theme.border
        Column {
            id: chipCol
            anchors.centerIn: parent
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.parent.label
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 9
                font.capitalization: Font.AllUppercase
                font.letterSpacing: root.theme.labelSpacing
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.parent.value
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
            }
        }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.tapped() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 470
        height: Math.min(root.height - 24, 400)
        radius: root.theme.radiusPanel
        color: root.theme.bgElevated
        border.width: 1
        border.color: root.theme.borderStrong
        MouseArea { anchors.fill: parent }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add habit"
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: 19
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: acloseMa.containsMouse ? root.theme.text : root.theme.faint
                    font.pixelSize: 14
                    MouseArea { id: acloseMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            Row {
                spacing: 8
                HabitField { id: fId; theme: root.theme; label: "id (one word)"; fieldWidth: 130; placeholder: "stretching" }
                HabitField { id: fName; theme: root.theme; label: "display name"; fieldWidth: 170; placeholder: "optional" }
                HabitField { id: fGroup; theme: root.theme; label: "group"; fieldWidth: 110; placeholder: "optional" }
            }

            Row {
                spacing: 8
                Chip {
                    label: "schedule"
                    value: root.schedules[root.schedI]
                    onTapped: root.schedI = (root.schedI + 1) % root.schedules.length
                }
                Chip {
                    label: "type"
                    value: root.types[root.typeI]
                    onTapped: root.typeI = (root.typeI + 1) % root.types.length
                }
                Chip {
                    label: "reward"
                    value: root.rewards[root.rewardI] + " (" + (root.rewardI + 1) + ")"
                    onTapped: root.rewardI = (root.rewardI + 1) % root.rewards.length
                }
                Chip {
                    label: "streak"
                    value: root.noStreak ? "off" : "on"
                    onTapped: root.noStreak = !root.noStreak
                }
            }

            // custom day picker
            Row {
                visible: root.schedules[root.schedI] === "custom"
                spacing: 5
                Repeater {
                    model: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: !!root.customDays[modelData]
                        width: 40
                        height: 22
                        radius: root.theme.radiusBtn
                        color: on ? root.theme.accentSoft : root.theme.row
                        border.width: 1
                        border.color: on ? root.theme.accent : root.theme.border
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.on ? root.theme.accent : root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var d = {};
                                for (var k in root.customDays) d[k] = root.customDays[k];
                                d[parent.modelData] = !d[parent.modelData];
                                root.customDays = d;
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 8
                HabitField { id: fTarget; theme: root.theme; label: "daily target"; fieldWidth: 100; placeholder: "6:00 / 20" }
                HabitField { id: fUnit; theme: root.theme; label: "unit"; fieldWidth: 84; placeholder: "pages" }
                HabitField { id: fPenalty; theme: root.theme; label: "penalty"; fieldWidth: 84; placeholder: "= reward" }
                HabitField { id: fOffday; theme: root.theme; label: "offday pen."; fieldWidth: 84; placeholder: "none" }
            }

            Row {
                spacing: 8
                Rectangle {
                    width: createTxt.implicitWidth + 24
                    height: 26
                    radius: root.theme.radiusBtn
                    color: createMa.containsMouse ? root.theme.accent : root.theme.accentSoft
                    Text {
                        id: createTxt
                        anchors.centerIn: parent
                        text: "Create habit"
                        color: createMa.containsMouse ? "#ffffff" : root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    MouseArea { id: createMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submit() }
                }
                Text {
                    visible: root.error !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.error
                    color: root.theme.danger
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    width: 280
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                text: "Habits are directives in habits.journal — this form just appends one. "
                      + "Edit the file for anything the form doesn't cover (presence-weight, start date …)."
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
                wrapMode: Text.Wrap
            }
        }
    }
}
