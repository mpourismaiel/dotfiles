pragma ComponentBehavior: Bound
// FreezeDialog.qml — vacation mode. Opened by both the Freeze and Unfreeze
// header buttons: lists every freeze range in the journal (global or
// per-habit) with delete, adds a new range (start/end/habit/note), and
// "Unfreeze from today" truncates any active range so tomorrow counts again.
// Frozen days are excluded from scoring entirely and render snow in the
// jungle (habiq's report drives that; this dialog just edits the entries).
import QtQuick

Rectangle {
    id: root
    required property var theme
    property var habits: null
    property string today: ""
    signal dismissed()

    // the scrim covers the pill's padding ring too (the menu content box is
    // inset theme.pad inside the pill surface — filling only the parent left
    // an un-dimmed frame that read as a sharp box) and rounds its corners to
    // match the pill surface
    anchors.fill: parent
    anchors.margins: -theme.pad
    radius: theme.radiusPanel
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea { anchors.fill: parent; onClicked: root.dismissed() }

    property string error: ""
    property string scopeHabit: ""      // "" = all habits
    Connections {
        target: root.habits
        function onWriteDone(ok, err) {
            root.error = ok ? "" : err;
            if (ok) { fStart.text = ""; fEnd.text = ""; fNote.text = ""; }
        }
    }
    function cycleScope() {
        var ids = [""];
        var hs = root.habits && root.habits.habits ? root.habits.habits : [];
        for (var i = 0; i < hs.length; i++) ids.push(hs[i].id);
        root.scopeHabit = ids[(ids.indexOf(root.scopeHabit) + 1) % ids.length];
    }

    Rectangle {
        anchors.centerIn: parent
        width: 540
        height: Math.min(root.height - 24, 420)
        radius: root.theme.radiusPanel
        color: root.theme.bgElevated
        border.width: 1
        border.color: root.theme.borderStrong
        MouseArea { anchors.fill: parent }

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
                    text: "Freeze / vacation"
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: 19
                }
                MSym {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    size: 16
                    color: fcloseMa.containsMouse ? root.theme.text : root.theme.faint
                    MouseArea { id: fcloseMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.dismissed() }
                }
            }

            Row {
                spacing: 8
                DateField { id: fStart; theme: root.theme; overlay: root; label: "from"; fieldWidth: 128; placeholder: root.today }
                DateField { id: fEnd; theme: root.theme; overlay: root; label: "to"; fieldWidth: 128; placeholder: "YYYY-MM-DD" }
                Column {
                    spacing: 4
                    Text {
                        text: "scope"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    Rectangle {
                        width: 88
                        height: 28
                        radius: root.theme.radiusBtn
                        color: root.theme.row
                        border.width: 1
                        border.color: root.theme.border
                        Text {
                            anchors.centerIn: parent
                            text: root.scopeHabit === "" ? "all" : root.scopeHabit
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            elide: Text.ElideRight
                            width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cycleScope() }
                    }
                }
                HabitField { id: fNote; theme: root.theme; label: "note"; fieldWidth: 128; placeholder: "vacation" }
            }

            Row {
                spacing: 8
                Rectangle {
                    width: addTxt.implicitWidth + 24
                    height: 26
                    radius: root.theme.radiusBtn
                    color: addMa.containsMouse ? root.theme.accent : root.theme.accentSoft
                    Text {
                        id: addTxt
                        anchors.centerIn: parent
                        text: "Freeze range"
                        color: addMa.containsMouse ? "#ffffff" : root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var s = fStart.text.trim() || root.today;
                            var e = fEnd.text.trim() || s;
                            root.habits.addFreeze(s, e, root.scopeHabit, fNote.text.trim());
                        }
                    }
                }
                Rectangle {
                    width: unfTxt.implicitWidth + 24
                    height: 26
                    radius: root.theme.radiusBtn
                    color: unfMa.containsMouse ? root.theme.rowHi : root.theme.row
                    Text {
                        id: unfTxt
                        anchors.centerIn: parent
                        text: "Unfreeze from today"
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    MouseArea { id: unfMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.habits.unfreeze() }
                }
                Text {
                    visible: root.error !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.error
                    color: root.theme.danger
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    width: 130
                    elide: Text.ElideRight
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.theme.divider }

            ListView {
                width: parent.width
                height: body.height - y
                clip: true
                spacing: 2
                model: root.habits ? root.habits.freezes : []
                delegate: Rectangle {
                    id: fRow
                    required property var modelData
                    width: ListView.view.width
                    height: 26
                    radius: root.theme.radiusBtn
                    color: rowMa.containsMouse ? root.theme.row : "transparent"
                    readonly property bool active: root.today >= modelData.start && root.today <= modelData.end
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: (fRow.active ? "❄ " : "") + fRow.modelData.start + " .. " + fRow.modelData.end
                              + "  " + (fRow.modelData.habit || "all")
                              + (fRow.modelData.note ? "  · " + fRow.modelData.note : "")
                        color: fRow.active ? "#dfe6ec" : root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        width: parent.width - 60
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: rowMa.containsMouse
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 20; radius: 6
                        color: fdelMa.containsMouse ? root.theme.danger : root.theme.row
                        MSym {
                            anchors.centerIn: parent
                            icon: "delete"
                            size: 13
                            color: fdelMa.containsMouse ? "#ffffff" : root.theme.textDim
                        }
                        MouseArea {
                            id: fdelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.habits.removeFreeze(fRow.modelData.index)
                        }
                    }
                    MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
        }
    }
}
