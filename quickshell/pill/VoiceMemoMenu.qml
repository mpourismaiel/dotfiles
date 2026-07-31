pragma ComponentBehavior: Bound
// VoiceMemoMenu.qml — pre-record config panel (menu 7), opened by voicePolishToggle.
// Choose memo type (meeting/task/prompt/note; Note preselected), toggle Polish (on
// by default) and Add-to-org (off; shows a TODO/NOTE override), then Start records.
import QtQuick

Item {
    id: root
    required property var theme
    property var settings: null      // shared JsonAdapter (polish model ids)
    property var setup: null         // VoiceSetup (keys + local download)
    signal closeRequested()
    // committed on Start: the chosen type, whether to polish, whether to add to
    // the org agenda, and the resolved org category ("todo"/"note").
    signal startRequested(string memoType, bool polish, bool org, string orgCategory)

    property string sel: "note"      // selected type (defaults to Note; "" = none -> no Start)
    property bool polishOn: true     // default to polishing the transcript
    property bool orgOn: false
    property string orgOverride: ""  // "" = derive from type; else "todo"/"note"

    readonly property var types: [
        { key: "meeting", icon: "groups",         label: "Meeting" },
        { key: "task",    icon: "task_alt",        label: "Task" },
        { key: "prompt",  icon: "smart_toy",       label: "Prompt" },
        { key: "note",    icon: "sticky_note_2",   label: "Note" }
    ]
    // task -> a TODO, everything else -> a plain note
    function defaultCat(t) { return t === "task" ? "todo" : "note"; }
    readonly property string effectiveCat: root.orgOverride !== "" ? root.orgOverride : root.defaultCat(root.sel)

    // one settings row: label (left) + a PillToggle (right)
    component SwitchRow: Item {
        id: sw
        property string label: ""
        property bool checked: false
        signal toggled(bool value)
        width: parent ? parent.width : 0
        height: 26
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: sw.label
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }
        PillToggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            checked: sw.checked
            onToggled: v => sw.toggled(v)
        }
    }

    // scrolls when Polish is on (the shared PolishConfig adds a model + key rows)
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

    Column {
        id: col
        width: parent.width
        spacing: root.theme.gap

        MenuHeader { theme: root.theme; title: "Voice Memo"; onBack: root.closeRequested() }

        // ---- type tiles (2×2 grid) ----
        Grid {
            width: parent.width
            columns: 2
            columnSpacing: root.theme.gap
            rowSpacing: root.theme.gap
            Repeater {
                model: root.types
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool on: root.sel === modelData.key
                    readonly property bool kbFocusable: true
                    property bool kbFocused: false
                    function keyClick() { root.sel = tile.modelData.key; }
                    width: (parent.width - root.theme.gap) / 2
                    height: 60
                    radius: root.theme.radiusRow
                    color: on ? root.theme.accentSoft : ((tileMa.containsMouse || tile.kbFocused) ? root.theme.rowHi : root.theme.row)
                    border.width: 1
                    border.color: on ? root.theme.accent : root.theme.border
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        MSym {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: tile.modelData.icon
                            size: 22
                            fill: tile.on ? 1 : 0
                            color: tile.on ? root.theme.accent : root.theme.textDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.modelData.label
                            color: tile.on ? root.theme.text : root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                    }
                    MouseArea {
                        id: tileMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sel = tile.modelData.key
                    }
                }
            }
        }

        SwitchRow {
            label: "Polish transcript"
            checked: root.polishOn
            onToggled: v => root.polishOn = v
        }
        // polish backend picker (model + cloud key / local download), shared with
        // the Transcribe tab — only while Polish is enabled
        PolishConfig {
            visible: root.polishOn
            width: parent.width
            theme: root.theme
            settings: root.settings
            setup: root.setup
        }
        SwitchRow {
            label: "Add to org agenda"
            checked: root.orgOn
            onToggled: v => { root.orgOn = v; if (!v) root.orgOverride = ""; }
        }

        // ---- org category override (only while Add-to-org is on) ----
        Row {
            width: parent.width
            height: root.orgOn ? 26 : 0
            visible: root.orgOn
            spacing: root.theme.gap
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "As"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Repeater {
                model: ["todo", "note"]
                delegate: Rectangle {
                    id: catChip
                    required property string modelData
                    readonly property bool on: root.effectiveCat === modelData
                    readonly property bool kbFocusable: true
                    property bool kbFocused: false
                    function keyClick() { root.orgOverride = catChip.modelData; }
                    anchors.verticalCenter: parent.verticalCenter
                    width: catTxt.implicitWidth + 22
                    height: 22
                    radius: root.theme.radiusBtn
                    color: on ? root.theme.accent : ((catMa.containsMouse || catChip.kbFocused) ? root.theme.rowHi : root.theme.row)
                    border.width: 1
                    border.color: on ? root.theme.accent : root.theme.border
                    Text {
                        id: catTxt
                        anchors.centerIn: parent
                        text: catChip.modelData
                        color: catChip.on ? "#ffffff" : root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: catMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.orgOverride = catChip.modelData
                    }
                }
            }
        }

        // ---- Start (only once a type is chosen) ----
        Rectangle {
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.startRequested(root.sel, root.polishOn, root.orgOn, root.effectiveCat); }
            width: parent.width
            height: root.sel !== "" ? 42 : 0
            visible: root.sel !== ""
            radius: root.theme.radiusRow
            color: (startMa.containsMouse || kbFocused) ? root.theme.danger : root.theme.accent
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            Row {
                anchors.centerIn: parent
                spacing: 8
                MSym { anchors.verticalCenter: parent.verticalCenter; icon: "mic"; fill: 1; size: 18; color: "#ffffff" }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Start"
                    color: "#ffffff"
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsNormal
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
            }
            MouseArea {
                id: startMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startRequested(root.sel, root.polishOn, root.orgOn, root.effectiveCat)
            }
        }
    }
    }
}
