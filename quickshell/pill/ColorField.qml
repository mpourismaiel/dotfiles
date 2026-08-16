pragma ComponentBehavior: Bound
// ColorField.qml — one editable colour row on the Appearance page: a swatch, the
// colour's label, a text input (in the currently-selected unit) and a reset dot
// (shown only when the colour is a user override). Clicking the swatch expands an
// inline ColorPicker beneath the row.
//
// Purely a view: it reads `valueStr` (the css string currently in effect) + `unit`
// in, and emits edited(cssString) / cleared() so the host persists to theme.json.
import QtQuick

Item {
    id: root
    required property var theme
    property string label: ""
    property string valueStr: "#000000"     // css string currently in effect
    property string unit: "hex"             // hex | rgb | hsl
    property bool overridden: false         // this key is a user override (→ show reset)
    signal edited(string value)
    signal cleared()

    readonly property color eff: root.theme.parseColor(root.valueStr)
    property bool expanded: false

    readonly property int rowH: 34
    implicitHeight: rowH + (expanded ? picker.implicitHeight + 12 : 0)
    height: implicitHeight
    Behavior on implicitHeight { NumberAnimation { duration: root.theme.animFast } }

    // re-seed the text input from the effective colour whenever it (or the unit)
    // changes and the user isn't mid-edit — same guard-against-fighting-input trick
    // as FeaturePage.
    function _seed() { if (!inp.activeFocus) inp.text = root.theme.formatColor(root.eff, root.unit); }
    Component.onCompleted: _seed()
    onValueStrChanged: _seed()
    onUnitChanged: _seed()

    // ---- the row ----
    Item {
        id: rowItem
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.rowH

        // swatch (checkerboard backing so alpha reads as transparent)
        Rectangle {
            id: swatch
            width: 26
            height: 26
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: root.theme.radiusSmall
            clip: true
            border.width: 1
            border.color: root.expanded ? root.theme.accent : root.theme.border
            Grid {
                anchors.fill: parent
                columns: 4
                Repeater {
                    model: 16
                    delegate: Rectangle {
                        required property int index
                        width: 7
                        height: 7
                        color: ((Math.floor(index / 4) + index) % 2 === 0) ? "#3a3a3a" : "#5a5a5a"
                    }
                }
            }
            Rectangle { anchors.fill: parent; radius: parent.radius; color: root.eff }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.expanded = !root.expanded;
                    if (root.expanded)
                        picker.seedFrom(root.eff);
                }
            }
        }

        // label
        Text {
            anchors.left: swatch.right
            anchors.leftMargin: 10
            anchors.right: inputBox.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.label
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }

        // reset-to-default dot (only when this colour is a user override)
        Rectangle {
            id: resetDot
            visible: root.overridden
            anchors.right: inputBox.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: resetMa.containsMouse ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "restart_alt"
                size: 13
                color: resetMa.containsMouse ? root.theme.accent : root.theme.faint
            }
            MouseArea {
                id: resetMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.cleared();
                    if (root.expanded)
                        picker.seedFrom(root.eff);
                }
            }
        }

        // text input (value in the selected unit)
        Rectangle {
            id: inputBox
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 150
            height: 28
            radius: root.theme.radiusBtn
            color: root.theme.bgElevated
            border.width: 1
            border.color: inp.activeFocus ? root.theme.accent : root.theme.border
            TextInput {
                id: inp
                objectName: "pillKbInput"
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                clip: true
                selectByMouse: true
                selectionColor: root.theme.accentDim
                function commit() {
                    var t = inp.text.trim();
                    if (t === "") { root.cleared(); return; }
                    root.edited(root.theme.formatColor(root.theme.parseColor(t), root.unit));
                }
                onEditingFinished: commit()
                onActiveFocusChanged: if (!activeFocus) root._seed()
            }
        }
    }

    // ---- inline picker ----
    ColorPicker {
        id: picker
        visible: root.expanded
        anchors.top: rowItem.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 2
        theme: root.theme
        onPicked: (value) => root.edited(root.theme.formatColor(value, root.unit))
    }
}
