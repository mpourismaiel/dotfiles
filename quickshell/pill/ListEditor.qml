pragma ComponentBehavior: Bound
// ListEditor.qml — a labelled multi-item string list for the Settings pages:
// an add control (a folder picker in "folder" mode, a text field in "text"
// mode) plus the current items, each with a delete button that asks for inline
// confirmation before removing. Purely a view over `items`; every mutation is
// emitted whole via changed(list) so the host can reassign the JsonAdapter
// array (reassign, not mutate, so it flushes).
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var theme
    property string label: ""
    property string blurb: ""
    property string mode: "text"               // "text" | "folder"
    property string placeholder: ""
    property string addLabel: "Add"
    property var picker: null                    // pickFolder(cb) — injected native picker
    property var items: []                      // source list (strings)
    signal changed(var list)                    // full new list after add/remove

    property var _list: []
    property int _confirm: -1                   // index awaiting delete confirmation
    function _seed() { root._list = (root.items || []).slice(); root._confirm = -1; }
    Component.onCompleted: _seed()
    onItemsChanged: if (!addInput.activeFocus) _seed()

    function _add(v) {
        var s = ("" + v).trim();
        if (!s) return;
        var l = root._list.slice();
        if (l.indexOf(s) !== -1) return;        // no duplicates
        l.push(s);
        root._list = l;
        root.changed(l);
    }
    function _remove(i) {
        var l = root._list.slice();
        l.splice(i, 1);
        root._list = l;
        root._confirm = -1;
        root.changed(l);
    }

    // folder picker: prefer the injected root picker (which hides the Overlay
    // surface so the dialog isn't eaten — see init.qml pickFolder); fall back to a
    // local kdialog/zenity Process for standalone use. Runs only on click, so the
    // headless screenshot harness never triggers it.
    property Process pickProc: Process {
        stdout: StdioCollector {
            onStreamFinished: { var p = ("" + this.text).trim(); if (p) root._add(p); }
        }
    }
    function pickFolder() {
        if (root.picker) {
            root.picker(function (p) { root._add(p); });
            return;
        }
        pickProc.command = ["sh", "-c",
            "kdialog --getexistingdirectory \"$HOME\" 2>/dev/null || "
            + "zenity --file-selection --directory 2>/dev/null"];
        if (!pickProc.running) pickProc.running = true;
    }

    implicitHeight: col.implicitHeight
    height: implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 8

        Text {
            text: root.label
            color: root.theme.faint
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
            font.letterSpacing: root.theme.labelSpacing
            font.capitalization: Font.AllUppercase
        }
        Text {
            visible: root.blurb.length > 0
            width: col.width
            wrapMode: Text.WordWrap
            text: root.blurb
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: root.theme.fsSmall
        }

        // ---- add control ----
        Item {
            width: col.width
            height: 36

            // folder mode: a single "Add folder…" button
            Rectangle {
                visible: root.mode === "folder"
                anchors.fill: parent
                radius: root.theme.radiusBtn
                color: addFolderMa.containsMouse ? root.theme.accentSoft : root.theme.bgElevated
                border.width: 1
                border.color: addFolderMa.containsMouse ? root.theme.accent : root.theme.border
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "create_new_folder"; size: 18
                        color: addFolderMa.containsMouse ? root.theme.accent : root.theme.textDim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.addLabel
                        color: addFolderMa.containsMouse ? root.theme.text : root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                }
                MouseArea {
                    id: addFolderMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickFolder()
                }
                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }

            // text mode: a field + an add button
            Row {
                visible: root.mode === "text"
                anchors.fill: parent
                spacing: 8
                Rectangle {
                    width: parent.width - addBtn.width - 8
                    height: parent.height
                    radius: root.theme.radiusBtn
                    color: root.theme.bgElevated
                    border.width: 1
                    border.color: addInput.activeFocus ? root.theme.accent : root.theme.border
                    TextInput {
                        id: addInput
                        objectName: "pillKbInput"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        clip: true
                        selectByMouse: true
                        selectionColor: root.theme.accentDim
                        onAccepted: { root._add(text); text = ""; }
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: addInput.text.length === 0
                            text: root.placeholder
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            elide: Text.ElideRight
                        }
                    }
                }
                Rectangle {
                    id: addBtn
                    width: 64
                    height: parent.height
                    radius: root.theme.radiusBtn
                    color: addTextMa.containsMouse ? root.theme.accentSoft : root.theme.bgElevated
                    border.width: 1
                    border.color: addTextMa.containsMouse ? root.theme.accent : root.theme.border
                    Text {
                        anchors.centerIn: parent
                        text: "Add"
                        color: addTextMa.containsMouse ? root.theme.accent : root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                    MouseArea {
                        id: addTextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root._add(addInput.text); addInput.text = ""; }
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }

        // ---- current items ----
        Text {
            visible: root._list.length === 0
            text: root.mode === "folder" ? "No directories added yet."
                                         : "No emails added yet."
            color: root.theme.faint
            font.family: root.theme.family
            font.italic: true
            font.pixelSize: root.theme.fsSmall
        }

        Repeater {
            model: root._list
            delegate: Rectangle {
                id: rowItem
                required property int index
                required property var modelData
                readonly property bool confirming: root._confirm === index
                width: col.width
                height: 40
                radius: root.theme.radiusBtn
                color: root.theme.row

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: actions.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.modelData
                    color: root.theme.text
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    elide: Text.ElideMiddle
                }

                // trailing: a trash button, or the inline confirm pair
                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    // idle: delete icon
                    Rectangle {
                        visible: !rowItem.confirming
                        width: 26; height: 26
                        radius: root.theme.radiusSmall
                        color: delMa.containsMouse ? root.theme.accentSoft : "transparent"
                        MSym {
                            anchors.centerIn: parent
                            icon: "delete"; size: 16
                            color: delMa.containsMouse ? root.theme.danger : root.theme.faint
                        }
                        MouseArea {
                            id: delMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._confirm = rowItem.index
                        }
                    }

                    // confirming: Remove? · Cancel
                    Text {
                        visible: rowItem.confirming
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Remove?"
                        color: root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsSmall
                    }
                    Rectangle {
                        visible: rowItem.confirming
                        width: yesLabel.implicitWidth + 18; height: 26
                        radius: root.theme.radiusSmall
                        color: yesMa.containsMouse ? root.theme.danger : root.theme.accentSoft
                        Text {
                            id: yesLabel
                            anchors.centerIn: parent
                            text: "Remove"
                            color: yesMa.containsMouse ? root.theme.text : root.theme.danger
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            id: yesMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._remove(rowItem.index)
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                    Rectangle {
                        visible: rowItem.confirming
                        width: noLabel.implicitWidth + 18; height: 26
                        radius: root.theme.radiusSmall
                        color: noMa.containsMouse ? root.theme.bgHover : "transparent"
                        border.width: 1
                        border.color: root.theme.border
                        Text {
                            id: noLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            id: noMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._confirm = -1
                        }
                    }
                }
            }
        }
    }
}
