pragma ComponentBehavior: Bound
// DiskFiles.qml — the Files page of the Disk window: a dired-style listing where
// every folder shows its real size, largest first, driven from the keyboard.
//
//   j/k ↑/↓ move · Enter/l open · h/^/Backspace up · d flag · u unflag · U unflag all
//   x review the flagged · y copy path · s sort · / filter · g re-read · o open
//   r show in the file manager · ~ home
//
// Flagging only marks. `x` turns the flagged paths into cleanup-plan items and
// opens the review, which is the one place anything is removed (your files go to
// the Trash; dependency / build / cache folders are recognised and say so).
import QtQuick

Item {
    id: root
    required property var theme
    required property var disk
    property string startPath: ""        // set by "Show in Files" from another page

    readonly property var sec: root.disk.listing
    property string sort: "size"         // size | name | date
    property string filter: ""
    property bool filtering: false
    property int cur: 0
    property string cameFrom: ""         // the folder we just left: re-select it in the parent

    readonly property var rows: {
        if (!root.sec || !root.sec.rows) return [];
        var r = root.sec.rows;
        if (root.filter !== "") {
            var f = root.filter.toLowerCase();
            r = r.filter(function (x) { return x.name.toLowerCase().indexOf(f) >= 0; });
        } else r = r.slice();
        if (root.sort === "name") r.sort(function (a, b) { return a.name.localeCompare(b.name); });
        else if (root.sort === "date") r.sort(function (a, b) { return b.mtime - a.mtime; });
        else r.sort(function (a, b) { return b.bytes - a.bytes; });
        return r;
    }
    readonly property double maxBytes: {
        var m = 1;
        for (var i = 0; i < rows.length; i++) if (rows[i].bytes > m) m = rows[i].bytes;
        return m;
    }
    readonly property double flaggedBytes: {
        var b = 0, fl = root.disk.flagged;
        if (!root.sec) return 0;
        for (var i = 0; i < root.sec.rows.length; i++)
            if (fl.indexOf(root.sec.rows[i].path) >= 0) b += root.sec.rows[i].bytes;
        return b;
    }

    function go(path) {
        if (!path) return;
        root.filter = ""; root.filtering = false;
        root.disk.ls(path);
    }
    function up() {
        if (!root.sec || !root.sec.parent) return;
        root.cameFrom = root.sec.path;
        root.go(root.sec.parent);
    }
    function enter() {
        var r = root.rows[root.cur];
        if (r && r.dir) { root.cameFrom = ""; root.go(r.path); }
    }
    function flag(on) {
        var r = root.rows[root.cur];
        if (!r) return;
        var fl = root.disk.flagged.slice(), i = fl.indexOf(r.path);
        if (on && i < 0) fl.push(r.path);
        if (!on && i >= 0) fl.splice(i, 1);
        root.disk.flagged = fl;
        root.cur = Math.min(root.rows.length - 1, root.cur + 1);
    }
    onSecChanged: {
        var idx = 0;
        if (root.cameFrom !== "")
            for (var i = 0; i < root.rows.length; i++) if (root.rows[i].path === root.cameFrom) { idx = i; break; }
        root.cur = idx;
        list.positionViewAtIndex(idx, ListView.Contain);
    }
    onCurChanged: list.positionViewAtIndex(root.cur, ListView.Contain)
    onStartPathChanged: if (root.startPath !== "") root.go(root.startPath)
    Component.onCompleted: {
        if (root.startPath !== "") root.go(root.startPath);
        else if (!root.sec) root.go(root.disk.disk && root.disk.disk.home ? root.disk.disk.home : "/");
        keys.forceActiveFocus();
    }
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => {
            if (root.filtering) return;
            var k = ev.key, t = ev.text;
            ev.accepted = true;
            if (k === Qt.Key_Down || t === "j") root.cur = Math.min(root.rows.length - 1, root.cur + 1);
            else if (k === Qt.Key_Up || t === "k") root.cur = Math.max(0, root.cur - 1);
            else if (k === Qt.Key_PageDown) root.cur = Math.min(root.rows.length - 1, root.cur + 15);
            else if (k === Qt.Key_PageUp) root.cur = Math.max(0, root.cur - 15);
            else if (k === Qt.Key_Home) root.cur = 0;
            else if (k === Qt.Key_End || t === "G") root.cur = Math.max(0, root.rows.length - 1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right || t === "l") root.enter();
            else if (k === Qt.Key_Backspace || k === Qt.Key_Left || t === "h" || t === "^") root.up();
            else if (t === "d") root.flag(true);
            else if (t === "u") root.flag(false);
            else if (t === "U") root.disk.flagged = [];
            else if (t === "x") root.disk.reviewFlagged();
            else if (t === "y") { if (root.rows[root.cur]) root.disk.copy(root.rows[root.cur].path); }
            else if (t === "s") root.sort = root.sort === "size" ? "name" : root.sort === "name" ? "date" : "size";
            else if (t === "/") { root.filtering = true; filterIn.forceActiveFocus(); }
            else if (t === "g") root.go(root.sec ? root.sec.path : "/");
            else if (t === "o") { if (root.rows[root.cur]) root.disk.openFile(root.rows[root.cur].path); }
            else if (t === "r") { if (root.rows[root.cur]) root.disk.reveal(root.rows[root.cur].path); }
            else if (t === "~") root.go(root.disk.disk ? root.disk.disk.home : "/");
            else if (k === Qt.Key_Escape && root.filter !== "") root.filter = "";
            else ev.accepted = false;
        }
    }

    // ---- path line -----------------------------------------------------------
    Row {
        id: pathLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 26
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - 420)
            elide: Text.ElideLeft
            text: root.sec ? root.disk.tilde(root.sec.path) : ""
            color: root.theme.text
            font.family: root.theme.mono
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.sec ? root.rows.length + " entries · " + root.disk.fmtBytes(root.sec.bytes) + " · sorted by " + root.sort
                              + (root.disk.listingBusy ? " · reading…" : "") : (root.disk.listingBusy ? "reading…" : "")
            color: root.theme.faint
            font.family: root.theme.mono
            font.pixelSize: 11
        }
        Rectangle {
            visible: root.filtering || root.filter !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: 200
            height: 22
            radius: 7
            color: root.theme.desk
            border.width: 1
            border.color: root.theme.borderStrong
            Text {
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                text: "/"
                color: root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: 12
            }
            TextInput {
                id: filterIn
                x: 18
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: 12
                clip: true
                onTextChanged: { root.filter = text; root.cur = 0; }
                Keys.onReturnPressed: { root.filtering = false; keys.forceActiveFocus(); }
                Keys.onEscapePressed: { text = ""; root.filtering = false; keys.forceActiveFocus(); }
            }
        }
    }
    Text {
        anchors.top: pathLine.bottom
        anchors.topMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !!root.sec && root.sec.error !== ""
        text: root.sec ? "Cannot read this folder: " + root.sec.error : ""
        color: root.theme.accent
        font.family: root.theme.family
        font.pixelSize: 13
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: pathLine.bottom
        anchors.topMargin: 6
        anchors.bottom: modeline.top
        anchors.bottomMargin: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool flagged: root.disk.flagged.indexOf(modelData.path) >= 0
            readonly property bool planned: !!root.disk.pathIds[modelData.path] && root.disk.inPlan(root.disk.pathIds[modelData.path])
            width: list.width
            height: 24
            radius: 6
            color: index === root.cur ? root.theme.rowHi : "transparent"
            MouseArea {
                anchors.fill: parent
                onClicked: { root.cur = row.index; keys.forceActiveFocus(); }
                onDoubleClicked: { root.cur = row.index; root.enter(); }
            }
            Text {
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.flagged ? "D" : row.planned ? "P" : ""
                color: root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            Text {
                x: 26
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.mode
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 12
            }
            Text {
                x: 116
                width: 64
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.fmtBytes(row.modelData.bytes) + (row.modelData.partial ? "+" : "")
                color: root.theme.money
                font.family: root.theme.mono
                font.pixelSize: 12
            }
            DiskSeg {
                theme: root.theme
                x: 192
                width: 110
                implicitHeight: 6
                anchors.verticalCenter: parent.verticalCenter
                total: root.maxBytes
                parts: [{ color: row.modelData.kind === "deps" ? root.theme.accent : row.modelData.kind === "build" ? root.theme.money
                                 : row.modelData.kind === "git" ? root.theme.faint : row.modelData.kind === "video" ? root.theme.success : root.theme.textDim,
                          value: row.modelData.bytes }]
            }
            Text {
                x: 314
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.fmtDate(row.modelData.mtime)
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 12
            }
            Text {
                x: 408
                width: row.width - 408 - 150
                elide: Text.ElideMiddle
                anchors.verticalCenter: parent.verticalCenter
                text: (row.modelData.dir || root.disk.discreet === false ? row.modelData.name : root.disk.veil(row.modelData.name))
                      + (row.modelData.dir ? "/" : "") + (row.modelData.link ? "  →  " + row.modelData.link : "")
                color: row.flagged ? root.theme.accent : row.modelData.dir ? root.theme.text : root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: 12
                font.strikeout: row.flagged
            }
            DiskChip {
                theme: root.theme
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: ["deps", "build", "git"].indexOf(row.modelData.kind) >= 0
                tone: row.modelData.kind === "git" ? "stop" : "safe"
                text: row.modelData.kind === "deps" ? "dependencies" : row.modelData.kind === "build" ? "build output" : "git history"
            }
        }
    }

    // ---- modeline ----------------------------------------------------------------
    Rectangle {
        id: modeline
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 30
        radius: theme.radiusBtn
        color: theme.desk
        border.width: 1
        border.color: theme.border
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Repeater {
                model: [["j k", "move"], ["RET", "open"], ["^", "up"], ["d", "flag"], ["u", "unflag"], ["x", "review flagged"], ["y", "copy path"], ["s", "sort"], ["/", "filter"], ["r", "file manager"]]
                Row {
                    id: hint
                    required property var modelData
                    spacing: 5
                    Text {
                        text: hint.modelData[0]
                        color: root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Text {
                        text: hint.modelData[1]
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.disk.flagged.length > 0
                text: root.disk.flagged.length + " flagged · " + root.disk.fmtBytes(root.flaggedBytes)
                color: root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: 11
            }
            DiskBtn {
                theme: root.theme
                visible: root.disk.flagged.length > 0
                implicitHeight: 22
                primary: true
                text: "Review"
                onClicked: root.disk.reviewFlagged()
            }
        }
    }
}
