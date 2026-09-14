pragma ComponentBehavior: Bound
// HabitDialog.qml — per-habit dialog (opened from a habit card or a jungle
// tree): log a new entry for any date (default today), flip it to an explicit
// miss with a reason, and review/edit/delete the full history. Grouped rows
// (e.g. books = reading + listening) get a member switcher — entries always
// belong to one member habit. All writes go through HabitState → habiqbridge
// → the habiq CLI, which rewrites journal lines in place (hledger-style).
import QtQuick

Rectangle {
    id: root
    required property var theme
    property var habits: null
    property var row: null                 // report row {id, name, members, ...}
    property string today: ""
    signal dismissed()
    signal editHabitRequested(string id)   // header "edit habit" → definition form

    // scrim covers the pill's padding ring (not just the inset content box)
    // and matches the pill surface's rounding — no sharp box behind the dialog
    anchors.fill: parent
    anchors.margins: -theme.pad
    radius: theme.radiusPanel
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

    readonly property var members: row && row.members ? row.members : []
    property string member: members.length > 0 ? members[0] : ""
    function memberDef(id) {
        var hs = habits && habits.habits ? habits.habits : [];
        for (var i = 0; i < hs.length; i++)
            if (hs[i].id === id) return hs[i];
        return null;
    }
    readonly property var def: memberDef(member)
    readonly property bool isBool: def ? (def.typeRaw || def.type) === "bool" : false
    readonly property string valueHint: {
        if (!def) return "";
        if (def.type === "bool") return "done";
        if (def.type === "hours") return "h:mm";
        if (def.type === "hh:mm:ss") return "h:mm:ss";
        return def.type; // count unit (pages, …)
    }

    // form state — editing != null targets an existing entry (date+index locked)
    property var editing: null             // { date, index }
    property string error: ""
    property bool missed: false
    property bool doneChecked: true        // bool habits: the "done" tick

    Connections {
        target: root.habits
        function onWriteDone(ok, err) {
            root.error = ok ? "" : err;
            if (ok) {
                root.editing = null;
                root.missed = false;
                root.doneChecked = true;
                fValue.text = "";
                fReason.text = "";
            }
        }
    }

    function submit() {
        var d = fDate.text.trim() || root.today;
        if (root.isBool && !root.missed && !root.doneChecked) {
            root.error = "tick done or missed";
            return;
        }
        var value = root.isBool ? "done" : fValue.text.trim();
        if (root.editing) {
            root.habits.editEntry(root.member, root.editing.date, root.editing.index,
                                  root.missed ? "miss" : value, fReason.text.trim());
        } else if (root.missed) {
            root.habits.missEntry(root.member, d, fReason.text.trim());
        } else {
            root.habits.logEntry(root.member, d, value, fReason.text.trim());
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 540
        height: Math.min(root.height - 24, 470)
        radius: root.theme.radiusPanel
        color: root.theme.bgElevated
        border.width: 1
        border.color: root.theme.borderStrong
        MouseArea { anchors.fill: parent }  // swallow clicks

        Column {
            id: body
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.row ? root.row.name : ""
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: 19
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {                // edit the definition (schedule/target/…)
                        anchors.verticalCenter: parent.verticalCenter
                        width: editHabRow.implicitWidth + 18
                        height: 22
                        radius: root.theme.radiusBtn
                        color: editHabMa.containsMouse ? root.theme.rowHi : root.theme.row
                        Row {
                            id: editHabRow
                            anchors.centerIn: parent
                            spacing: 5
                            MSym {
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "edit"
                                size: 12
                                color: root.theme.textDim
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Edit habit"
                                color: root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: root.theme.labelSpacing
                            }
                        }
                        MouseArea { id: editHabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.editHabitRequested(root.member) }
                    }
                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "close"
                        size: 16
                        color: closeMa.containsMouse ? root.theme.text : root.theme.faint
                        MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                    }
                }
            }

            // member switcher (groups only)
            Row {
                visible: root.members.length > 1
                spacing: 6
                Repeater {
                    model: root.members
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: modelData === root.member
                        width: memTxt.implicitWidth + 18
                        height: 22
                        radius: root.theme.radiusBtn
                        color: active ? root.theme.accentSoft : root.theme.row
                        border.width: 1
                        border.color: active ? root.theme.accent : root.theme.border
                        Text {
                            id: memTxt
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.active ? root.theme.accent : root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.member = parent.modelData;
                                root.editing = null;
                                root.habits.loadHistory(parent.modelData);
                            }
                        }
                    }
                }
            }

            // ---- log / edit form ----
            Row {
                spacing: 8
                DateField {
                    id: fDate
                    theme: root.theme
                    overlay: root
                    label: root.editing ? "date (editing)" : "date"
                    fieldWidth: 138
                    placeholder: root.today
                    editable: root.editing === null
                }
                HabitField {
                    id: fValue
                    visible: !root.isBool
                    theme: root.theme
                    label: "value"
                    fieldWidth: 96
                    placeholder: root.valueHint
                    input.enabled: !root.missed
                }
                Column {
                    visible: root.isBool
                    spacing: 4
                    Text {
                        text: "done"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    Item {
                        width: 20
                        height: 28
                        PillCheckbox {
                            anchors.verticalCenter: parent.verticalCenter
                            theme: root.theme
                            checked: root.doneChecked && !root.missed
                            onToggled: (on) => {
                                root.doneChecked = on;
                                if (on) root.missed = false;
                            }
                        }
                    }
                }
                Column {
                    spacing: 4
                    Text {
                        text: "missed"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    Item {
                        width: 20
                        height: 28
                        PillCheckbox {
                            anchors.verticalCenter: parent.verticalCenter
                            theme: root.theme
                            checked: root.missed
                            onToggled: (on) => {
                                root.missed = on;
                                if (on && root.isBool) root.doneChecked = false;
                                else if (!on && root.isBool) root.doneChecked = true;
                            }
                        }
                    }
                }
                HabitField {
                    id: fReason
                    theme: root.theme
                    label: "reason / note"
                    fieldWidth: 130
                    placeholder: "optional"
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    width: saveTxt.implicitWidth + 24
                    height: 26
                    radius: root.theme.radiusBtn
                    color: saveMa.containsMouse ? root.theme.accent : root.theme.accentSoft
                    Text {
                        id: saveTxt
                        anchors.centerIn: parent
                        text: root.editing ? "Save edit" : "Log"
                        color: saveMa.containsMouse ? "#ffffff" : root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    MouseArea { id: saveMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.submit() }
                }
                Rectangle {
                    visible: root.editing !== null
                    width: cancTxt.implicitWidth + 20
                    height: 26
                    radius: root.theme.radiusBtn
                    color: cancMa.containsMouse ? root.theme.rowHi : root.theme.row
                    Text {
                        id: cancTxt
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    MouseArea {
                        id: cancMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.editing = null; fValue.text = ""; fReason.text = ""; root.missed = false; root.doneChecked = true; }
                    }
                }
                Text {
                    visible: root.error !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.error
                    color: root.theme.danger
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    width: 230
                    elide: Text.ElideRight
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.theme.divider }

            Text {
                text: "history — " + root.member
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.capitalization: Font.AllUppercase
                font.letterSpacing: root.theme.labelSpacing
            }

            // ---- full history, newest first ----
            ListView {
                width: parent.width
                height: body.height - y
                clip: true
                spacing: 2
                model: {
                    var h = root.habits && root.habits.historyHabit === root.member
                          ? (root.habits.history || []) : [];
                    var out = h.slice();
                    out.reverse();
                    return out;
                }
                delegate: Rectangle {
                    id: hRow
                    required property var modelData
                    width: ListView.view.width
                    height: 26
                    radius: root.theme.radiusBtn
                    color: hMa.containsMouse ? root.theme.row : "transparent"
                    Text {
                        id: hDate
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: hRow.modelData.date
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                    }
                    Text {
                        anchors.left: hDate.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: (hRow.modelData.kind === "miss" ? "miss" : hRow.modelData.value)
                              + (hRow.modelData.reason ? "  · " + hRow.modelData.reason : "")
                        color: hRow.modelData.kind === "miss" ? "#d9a441" : root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        width: parent.width - 200
                        elide: Text.ElideRight
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        visible: hMa.containsMouse
                        Rectangle {
                            width: 24; height: 20; radius: 6
                            color: editMa.containsMouse ? root.theme.rowHi : root.theme.row
                            MSym {
                                anchors.centerIn: parent
                                icon: "edit"
                                size: 13
                                color: editMa.containsMouse ? root.theme.text : root.theme.textDim
                            }
                            MouseArea {
                                id: editMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.editing = { date: hRow.modelData.date, index: hRow.modelData.index };
                                    fDate.text = hRow.modelData.date;
                                    fValue.text = hRow.modelData.kind === "miss" ? "" : hRow.modelData.value;
                                    root.missed = hRow.modelData.kind === "miss";
                                    root.doneChecked = hRow.modelData.kind === "log";
                                    fReason.text = hRow.modelData.reason || "";
                                }
                            }
                        }
                        Rectangle {
                            width: 24; height: 20; radius: 6
                            color: delMa.containsMouse ? root.theme.danger : root.theme.row
                            MSym {
                                anchors.centerIn: parent
                                icon: "delete"
                                size: 13
                                color: delMa.containsMouse ? "#ffffff" : root.theme.textDim
                            }
                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.habits.deleteEntry(root.member, hRow.modelData.date, hRow.modelData.index)
                            }
                        }
                    }
                    MouseArea {
                        id: hMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }
        }
    }
}
