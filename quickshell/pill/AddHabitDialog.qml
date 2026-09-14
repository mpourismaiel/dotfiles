pragma ComponentBehavior: Bound
// AddHabitDialog.qml — the header's "+ Add habit", and (with `editId` set, via
// the habit dialog's "Edit habit" button) the definition editor: appends or
// rewrites a `habit` directive via `habiq habit add` / `habiq habit edit`
// (config-as-data — same thing as editing habits.journal by hand, which stays
// the canonical path; this is the convenience form). Schedule/type/reward are
// cycle chips; target uses the chosen type's own value syntax (6:00, 20,
// 0:30:00). New habits start scoring today — no retroactive misses, no trees
// for prior weeks.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property var habits: null
    property string editId: ""             // "" = add mode; else edit this habit
    readonly property bool editMode: editId !== ""
    signal dismissed()

    // Prefill in edit mode. The definition comes from HabitState.habits, which
    // the bridge loads asynchronously — so this may run before the data lands.
    // We fill once (guarded by _filled) from Component.onCompleted AND whenever
    // the habit list changes, so the form populates as soon as the data is
    // there without ever clobbering the user's own edits afterwards.
    property bool _filled: false
    function _prefill() {
        if (!editMode || _filled) return;
        var hs = habits && habits.habits ? habits.habits : [];
        for (var i = 0; i < hs.length; i++) {
            if (hs[i].id !== editId) continue;
            var d = hs[i];
            fId.text = d.id;
            fName.text = (d.name && d.name !== d.id) ? d.name : "";
            fGroup.text = d.group || "";
            var spec = d.scheduleSpec || "";
            var fixed = ["daily", "weekdays", "freeform"];
            if (fixed.indexOf(spec) >= 0) {
                schedI = fixed.indexOf(spec);
            } else if (spec !== "") {
                schedI = 3; // custom day list
                var days = {};
                var toks = spec.split(" ");
                for (var t = 0; t < toks.length; t++)
                    if (toks[t]) days[toks[t]] = true;
                customDays = days;
            }
            typeI = Math.max(0, types.indexOf(d.typeRaw || d.type || "bool"));
            rewardI = Math.min(3, Math.max(0, Math.round(d.reward || 1) - 1));
            fTarget.text = d.target || "";
            fUnit.text = d.unit || "";
            fPenalty.text = (d.penalty !== undefined && d.penalty !== d.reward) ? String(d.penalty) : "";
            fOffday.text = d.offdayPenalty ? String(d.offdayPenalty) : "";
            noStreak = !!d.noStreak;
            _filled = true;
            return;
        }
    }
    Component.onCompleted: {
        _prefill();
        // if the list hasn't arrived yet, ask for a fresh load so it will
        if (editMode && !_filled && habits) habits.reload();
    }
    Connections {
        target: root.habits
        function onHabitsChanged() { root._prefill(); }
    }

    // scrim covers the pill's padding ring and rounds to match the surface
    anchors.fill: parent
    anchors.margins: -theme.pad
    radius: theme.radiusPanel
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
        var spec = {
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
        };
        if (root.editMode)
            root.habits.editHabit(spec);
        else
            root.habits.addHabit(spec);
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
        width: 540
        height: Math.min(root.height - 24, 430)
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
                    text: root.editMode ? "Edit habit — " + root.editId : "Add habit"
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: 19
                }
                MSym {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    size: 16
                    color: acloseMa.containsMouse ? root.theme.text : root.theme.faint
                    MouseArea { id: acloseMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            Row {
                spacing: 8
                HabitField { id: fId; theme: root.theme; label: "id (one word)"; fieldWidth: 140; placeholder: "stretching"; input.enabled: !root.editMode }
                HabitField { id: fName; theme: root.theme; label: "display name"; fieldWidth: 210; placeholder: "optional" }
                HabitField { id: fGroup; theme: root.theme; label: "group"; fieldWidth: 130; placeholder: "optional" }
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
                        text: root.editMode ? "Save habit" : "Create habit"
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
                text: root.editMode
                    ? "Saving rewrites this habit's directive block in habits.journal in place. "
                      + "Edit the file for anything the form doesn't cover (presence-weight, start date …)."
                    : "Habits are directives in habits.journal — this form just appends one. "
                      + "Edit the file for anything the form doesn't cover (presence-weight, start date …)."
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
                wrapMode: Text.Wrap
            }
        }
    }
}
