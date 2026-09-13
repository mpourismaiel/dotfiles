// DateField.qml — labeled date input: a masked YYYY-MM-DD text field plus a
// calendar button that drops a month-grid popover (the same picker pattern as
// the finance category range, generalized into a reusable component). Typing is
// validated to digits+dashes; picking a day fills the field.
//
// The popover is created imperatively and parented to `overlay` (pass the
// dialog's fill-parent root) from birth. It must NEVER be a child of this
// Column: a child popup participates in the Column's flow and wrecks the
// dialog layout the moment it opens (and reparenting a Loader's item
// mid-flight is just as bad) — the popup lives entirely outside this item's
// geometry, positioned by mapping the field's coordinates into the overlay.
import QtQuick

Column {
    id: root
    required property var theme
    property var overlay: null             // Item to host the floating calendar in
    property string label: ""
    property string text: ""               // "YYYY-MM-DD" (the value)
    property string placeholder: "YYYY-MM-DD"
    property int fieldWidth: 140
    property bool editable: true           // false = locked (e.g. editing an entry)
    property bool open: false
    onEditableChanged: if (!editable) open = false
    // keep the input in sync when `text` is set from outside (prefill / picker),
    // without a plain binding — a plain binding breaks the moment the user types
    onTextChanged: if (input.text !== text) input.text = text

    spacing: 4

    function _pad(n) { return (n < 10 ? "0" : "") + n; }
    function _today() {
        var d = new Date();
        return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate());
    }
    // 42-cell Sunday-first month grid
    function monthGrid(y, m) {
        var first = new Date(y, m - 1, 1);
        var start = new Date(y, m - 1, 1 - first.getDay());
        var cells = [];
        for (var i = 0; i < 42; i++) {
            var dt = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            var gy = dt.getFullYear(), gm = dt.getMonth() + 1, gd = dt.getDate();
            cells.push({ y: gy, m: gm, d: gd,
                         key: gy + "-" + _pad(gm) + "-" + _pad(gd),
                         inMonth: (gm === m && gy === y) });
        }
        return cells;
    }
    readonly property var _months: ["January", "February", "March", "April", "May", "June",
                                    "July", "August", "September", "October", "November", "December"]

    Text {
        text: root.label
        visible: root.label !== ""
        color: root.theme.faint
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.theme.labelSpacing
    }

    Rectangle {
        id: field
        width: root.fieldWidth
        height: 28
        radius: root.theme.radiusBtn
        color: root.theme.row
        border.width: 1
        border.color: (input.activeFocus || root.open) ? root.theme.accent : root.theme.border
        Behavior on border.color { ColorAnimation { duration: root.theme.animFast } }

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.right: calBtn.visible ? calBtn.left : parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            color: root.editable ? root.theme.text : root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsNormal
            clip: true
            selectByMouse: true
            enabled: root.editable
            Component.onCompleted: text = root.text
            // digits + dashes only, capped at YYYY-MM-DD length; source of truth
            // flows both ways via equality-guarded assignment (no binding to break)
            onTextChanged: {
                var clean = text.replace(/[^0-9-]/g, "").slice(0, 10);
                if (clean !== text) { text = clean; return; }
                if (text !== root.text) root.text = text;
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === "" && !input.activeFocus
                text: root.placeholder
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsNormal
            }
        }
        Rectangle {
            id: calBtn
            visible: root.editable
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: root.theme.radiusBtn - 2
            color: (calMa.containsMouse || root.open) ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "calendar_month"
                size: 15
                color: root.open ? root.theme.accent : root.theme.textDim
            }
            MouseArea {
                id: calMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.open = !root.open
            }
        }
    }

    // ---- popup lifecycle: create into the overlay, destroy on close ----
    property var _pop: null
    onOpenChanged: {
        if (open) {
            if (!overlay) { open = false; return; }
            if (!_pop) _pop = popComponent.createObject(overlay);
        } else if (_pop) {
            _pop.destroy();
            _pop = null;
        }
    }
    Component.onDestruction: if (_pop) _pop.destroy()

    Component {
        id: popComponent
        Item {
            id: pop
            anchors.fill: parent   // = the overlay it was created into
            z: 5000
            // dismiss on outside click
            MouseArea { anchors.fill: parent; onClicked: root.open = false }

            readonly property point anchorPt: field.mapToItem(root.overlay, 0, 0)
            readonly property real cellW: (box.width - 12) / 7
            readonly property real cellH: 26
            readonly property real boxH: 32 + 20 + 6 * cellH + 12

            Rectangle {
                id: box
                width: 236
                height: pop.boxH
                x: Math.max(6, Math.min(pop.anchorPt.x, pop.width - width - 6))
                // flip above the field if it would spill past the overlay bottom
                readonly property bool up: pop.anchorPt.y + field.height + 4 + pop.boxH > pop.height
                y: box.up ? (pop.anchorPt.y - 4 - pop.boxH)
                          : (pop.anchorPt.y + field.height + 4)
                radius: root.theme.radiusRow
                color: root.theme.bgElevated
                border.width: 1
                border.color: root.theme.borderStrong
                clip: true
                MouseArea { anchors.fill: parent }   // swallow clicks inside

                property int pickY: 2026
                property int pickM: 1
                Component.onCompleted: {
                    var p = ("" + root.text).split("-");
                    var y = +p[0], m = +p[1];
                    var t = new Date();
                    box.pickY = y || t.getFullYear();
                    box.pickM = m || (t.getMonth() + 1);
                }

                // month nav
                Item {
                    id: head
                    x: 6; y: 6
                    width: parent.width - 12
                    height: 26
                    Rectangle {
                        width: 24; height: 24
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        radius: root.theme.radiusBtn
                        color: prevMa.containsMouse ? root.theme.rowHi : "transparent"
                        MSym { anchors.centerIn: parent; icon: "chevron_left"; size: 16; color: root.theme.textDim }
                        MouseArea {
                            id: prevMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var m = box.pickM - 1, y = box.pickY;
                                if (m < 1) { m = 12; y -= 1; }
                                box.pickM = m; box.pickY = y;
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root._months[box.pickM - 1] + " " + box.pickY
                        color: root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                    }
                    Rectangle {
                        width: 24; height: 24
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: root.theme.radiusBtn
                        color: nextMa.containsMouse ? root.theme.rowHi : "transparent"
                        MSym { anchors.centerIn: parent; icon: "chevron_right"; size: 16; color: root.theme.textDim }
                        MouseArea {
                            id: nextMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var m = box.pickM + 1, y = box.pickY;
                                if (m > 12) { m = 1; y += 1; }
                                box.pickM = m; box.pickY = y;
                            }
                        }
                    }
                }

                // weekday header
                Row {
                    id: wd
                    x: 6
                    anchors.top: head.bottom
                    width: parent.width - 12
                    height: 20
                    Repeater {
                        model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                        delegate: Item {
                            required property var modelData
                            width: pop.cellW
                            height: 20
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall - 2
                                font.capitalization: Font.AllUppercase
                            }
                        }
                    }
                }

                // day grid
                Grid {
                    x: 6
                    anchors.top: wd.bottom
                    width: parent.width - 12
                    columns: 7
                    Repeater {
                        model: root.monthGrid(box.pickY, box.pickM)
                        delegate: Item {
                            id: cell
                            required property var modelData
                            width: pop.cellW
                            height: pop.cellH
                            readonly property bool selected: cell.modelData.key === root.text
                            readonly property bool isToday: cell.modelData.key === root._today()
                            Rectangle {
                                anchors.centerIn: parent
                                width: pop.cellW - 4
                                height: pop.cellH - 4
                                radius: root.theme.radiusSmall
                                color: cell.selected ? root.theme.accentSoft
                                     : (cellMa.containsMouse ? root.theme.rowHi : "transparent")
                                border.color: cell.selected ? root.theme.accent
                                     : (cell.isToday ? root.theme.borderStrong : "transparent")
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: cell.modelData.d
                                    color: cell.selected ? root.theme.accent
                                         : (cell.modelData.inMonth ? root.theme.text : root.theme.faint)
                                    font.family: root.theme.mono
                                    font.pixelSize: root.theme.fsSmall
                                }
                            }
                            MouseArea {
                                id: cellMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.text = cell.modelData.key;
                                    root.open = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
