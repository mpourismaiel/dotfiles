pragma ComponentBehavior: Bound
// DiskDetail.qml — the "why it can go" card at the bottom of a Disk page: for the
// selected removable item it says what it is, what losing it costs, how it comes
// back, every warning, and the exact command — copyable, never run from here.
// The only actions are putting it in / taking it out of the cleanup plan, opening
// a terminal on commands that need one, and showing it in Files.
import QtQuick

Rectangle {
    id: root
    required property var theme
    required property var disk
    property var item: null
    signal browse(string path)

    visible: !!item
    implicitHeight: visible ? Math.max(col.implicitHeight, side.implicitHeight) + 24 : 0
    radius: theme.radiusTile
    color: theme.bgElevated
    border.width: 1
    border.color: theme.border

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: side.left
        anchors.top: parent.top
        anchors.margins: 12
        anchors.rightMargin: 16
        spacing: 5

        Row {
            spacing: 8
            Text {
                text: root.item ? ((root.item.sub && root.item.section === "projects" ? root.item.sub + " / " : "") + root.item.title).toUpperCase() : ""
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
                anchors.verticalCenter: parent.verticalCenter
            }
            DiskChip {
                theme: root.theme
                tier: root.item ? root.item.tier : ""
                text: root.item ? root.disk.tierLabel[root.item.tier] : ""
            }
            Text {
                text: root.item ? root.disk.fmtBytes(root.item.bytes) + (root.item.reclaim < root.item.bytes * 0.95 ? "  (" + root.disk.fmtBytes(root.item.reclaim) + " frees up)" : "") : ""
                color: root.theme.money
                font.family: root.theme.mono
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.item ? root.item.why + (root.item.restore ? "  Comes back with: " + root.item.restore : "") : ""
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: 13
        }
        Repeater {
            model: root.item ? (root.item.warn || []) : []
            Text {
                required property string modelData
                width: col.width
                wrapMode: Text.Wrap
                text: "!  " + modelData
                color: root.theme.accent
                font.family: root.theme.family
                font.pixelSize: 12
            }
        }
        Text {
            visible: !!root.item && !!root.item.detail
            width: parent.width
            wrapMode: Text.Wrap
            text: root.item && root.item.detail ? root.item.detail.join("   ") : ""
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: 10
        }
    }

    Column {
        id: side
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        width: 360
        spacing: 8

        Rectangle {
            width: parent.width
            height: Math.min(64, cmdText.implicitHeight + 14)
            radius: theme.radiusBtn
            color: theme.desk
            border.width: 1
            border.color: theme.border
            clip: true
            Text {
                id: cmdText
                anchors.left: parent.left
                anchors.right: copyLab.left
                anchors.top: parent.top
                anchors.margins: 7
                text: root.item ? root.item.cmd : ""
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: 11
            }
            Text {
                id: copyLab
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                text: "COPY"
                color: copyMa.containsMouse ? root.theme.text : root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 9
                font.letterSpacing: 1
                MouseArea {
                    id: copyMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.item) root.disk.copy(root.item.cmd)
                }
            }
        }
        Row {
            spacing: 8
            DiskBtn {
                theme: root.theme
                primary: !!root.item && !root.disk.inPlan(root.item.id)
                text: root.item && root.disk.inPlan(root.item.id) ? "Take out of plan" : "Add to plan"
                onClicked: if (root.item) root.disk.togglePlan(root.item.id)
            }
            DiskBtn {
                theme: root.theme
                visible: !!root.item && root.item.method === "terminal"
                text: "Open in terminal"
                icon: "terminal"
                onClicked: if (root.item) root.disk.terminal(root.item.id)
            }
            DiskBtn {
                theme: root.theme
                visible: !!root.item && root.item.paths.length > 0 && root.item.method !== "terminal"
                text: "Show in Files"
                onClicked: if (root.item) root.browse(root.item.paths[0])
            }
        }
    }
}
