pragma ComponentBehavior: Bound
// DiskView.qml — the whole content of the Disk window (DiskWindow.qml wraps it in
// a real, decorated toplevel; the screenshot harness wraps it in its own).
//
//   header   the disk as one bar (categories, free space left empty), free
//            figure, when it was scanned, Rescan, and the discreet-names toggle
//   sidebar  "where it went" pages + the tools (Files, Cleanup plan, Reports)
//   page     DiskOverview / DiskProjects / DiskBuckets (generic) / DiskFiles /
//            DiskReview, chosen by disk.page
//   tray     the cleanup plan in one line and the way into its review
//
// All state lives in DiskState (`disk`); this file only lays things out.
import QtQuick
import "diskpages.js" as Pages

Rectangle {
    id: root
    required property var theme
    required property var disk
    property string filesPath: ""
    readonly property alias pageItem: pageLoader.item   // the page shown (the screenshot harness pokes at it)

    color: theme.bg
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.lighter(root.theme.bg, 1.12) }
        GradientStop { position: 1; color: root.theme.desk }
    }

    readonly property var main: root.disk.disk ? root.disk.disk.main : null
    readonly property var nav: [
        { head: "Where it went" },
        { key: "overview", label: "Overview" }, { key: "projects", label: "Projects" }, { key: "videos", label: "Videos" },
        { key: "games", label: "Games" }, { key: "downloads", label: "Downloads" }, { key: "caches", label: "Caches" },
        { key: "thumbnails", label: "Thumbnails" }, { key: "packages", label: "Packages" }, { key: "docker", label: "Docker" },
        { key: "bins", label: "Programs" }, { key: "system", label: "System" },
        { head: "Tools" },
        { key: "files", label: "Files" }, { key: "plan", label: "Cleanup plan" }, { key: "reports", label: "Reports" }
    ]
    function browse(path) { root.filesPath = path; root.disk.page = "files"; root.disk.ls(path); }
    function scanLine() {
        var p = root.disk.progress, run = [], done = 0;
        for (var k in p) { if (p[k].state === "done") done++; else run.push(k); }
        return "scanning · " + done + " of 10 done" + (run.length ? " · " + run.slice(0, 3).join(", ") : "");
    }

    // ---- header ------------------------------------------------------------------
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 66

        Text {
            id: title
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            text: "Disk"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 24
        }
        Column {
            anchors.left: title.right
            anchors.leftMargin: 20
            anchors.right: headRight.left
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            DiskSeg {
                theme: root.theme
                width: parent.width
                implicitHeight: 12
                total: root.main ? root.main.total : 1
                parts: {
                    var out = [], c = root.disk.overview ? root.disk.overview.categories : [];
                    for (var i = 0; i < c.length; i++) out.push({ color: root.disk.catColor(root.theme, c[i].key), value: c[i].bytes });
                    if (c.length === 0 && root.main) out.push({ color: root.theme.textDim, value: root.main.used });
                    return out;
                }
            }
            Row {
                width: parent.width
                height: 14
                clip: true
                spacing: 12
                Repeater {
                    model: root.disk.overview ? root.disk.overview.categories : []
                    Row {
                        id: leg
                        required property var modelData
                        spacing: 5
                        Rectangle { width: 8; height: 8; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: root.disk.catColor(root.theme, leg.modelData.key) }
                        Text {
                            text: leg.modelData.label.toLowerCase()
                            color: root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
        Row {
            id: headRight
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    anchors.right: parent.right
                    spacing: 6
                    Text {
                        text: root.main ? root.disk.fmtBytes(root.main.free) : "—"
                        color: root.theme.money
                        font.family: root.theme.serif
                        font.pixelSize: 24
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: root.main ? "free of " + root.disk.fmtBytes(root.main.total) : ""
                        color: root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: 13
                    }
                }
                Text {
                    anchors.right: parent.right
                    text: (root.disk.scanning ? root.scanLine() : root.disk.scannedAt ? "scanned " + root.disk.fmtAge(root.disk.scannedAt) + " · took " + Math.round(root.disk.took) + " s" : "never scanned").toUpperCase()
                    color: root.disk.scanning ? root.theme.money : root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                }
            }
            DiskBtn {
                theme: root.theme
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.scanning ? "Stop" : "Rescan"
                icon: root.disk.scanning ? "stop" : "refresh"
                onClicked: root.disk.scanning ? root.disk.stopScan() : root.disk.scan("")
            }
            DiskBtn {
                theme: root.theme
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.discreet ? "Names hidden" : "Names shown"
                icon: root.disk.discreet ? "visibility_off" : "visibility"
                onClicked: root.disk.setDiscreet(!root.disk.discreet)
            }
        }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.theme.border }
    }

    // ---- sidebar -------------------------------------------------------------------
    Item {
        id: sidebar
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.bottom: tray.top
        width: 196
        Column {
            x: 10
            y: 8
            width: parent.width - 20
            spacing: 1
            Repeater {
                model: root.nav
                Rectangle {
                    id: nv
                    required property var modelData
                    readonly property bool isHead: !!modelData.head
                    readonly property bool on: !isHead && root.disk.page === modelData.key
                    readonly property double bytes: isHead ? -1 : Pages.pageBytes(modelData.key, root.disk)
                    width: parent.width
                    height: isHead ? 30 : 30
                    radius: root.theme.radiusBtn
                    color: on ? root.theme.rowHi : (nma.containsMouse && !isHead ? root.theme.row : "transparent")
                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: nv.isHead ? 4 : 0
                        text: nv.isHead ? nv.modelData.head.toUpperCase() : nv.modelData.label
                        color: nv.isHead ? root.theme.faint : nv.on ? root.theme.text : root.theme.textDim
                        font.family: nv.isHead ? root.theme.mono : root.theme.family
                        font.pixelSize: nv.isHead ? 10 : 13
                        font.letterSpacing: nv.isHead ? root.theme.labelSpacing : 0
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !nv.isHead
                        text: nv.modelData.key === "plan" ? (root.disk.plan.length > 0 ? "" + root.disk.plan.length : "")
                              : nv.modelData.key === "reports" ? (root.disk.reports.length > 0 ? "" + root.disk.reports.length : "")
                              : nv.bytes >= 0 ? root.disk.fmtBytes(nv.bytes) : ""
                        color: nv.modelData.key === "plan" ? root.theme.accent : root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: nma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !nv.isHead
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.disk.page = nv.modelData.key;
                            if (nv.modelData.key === "reports") root.disk.loadReports();
                        }
                    }
                }
            }
        }
        Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: root.theme.border }
    }

    // ---- page ------------------------------------------------------------------------
    Loader {
        id: pageLoader
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: tray.top
        anchors.margins: 20
        anchors.topMargin: 16
        anchors.bottomMargin: 14
        sourceComponent: root.disk.page === "overview" ? cOverview : root.disk.page === "projects" ? cProjects
                         : root.disk.page === "files" ? cFiles : root.disk.page === "plan" ? cPlan : cBuckets
    }
    Component { id: cOverview; DiskOverview { theme: root.theme; disk: root.disk; onGo: page => { root.disk.page = (page === "home" ? "videos" : page === "files" ? "files" : page); } } }
    Component { id: cProjects; DiskProjects { theme: root.theme; disk: root.disk; onBrowse: path => root.browse(path) } }
    Component { id: cBuckets; DiskBuckets { theme: root.theme; disk: root.disk; model: Pages.build(root.disk.page, root.disk); onBrowse: path => root.browse(path) } }
    Component { id: cFiles; DiskFiles { theme: root.theme; disk: root.disk; startPath: root.filesPath } }
    Component { id: cPlan; DiskReview { theme: root.theme; disk: root.disk } }

    // ---- tray ------------------------------------------------------------------------
    Rectangle {
        id: tray
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 50
        color: root.theme.desk
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: root.theme.border }
        Row {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "CLEANUP PLAN"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.plan.length > 0 ? root.disk.fmtBytes(root.disk.planBytes) : "empty"
                color: root.disk.plan.length > 0 ? root.theme.money : root.theme.faint
                font.family: root.theme.serif
                font.pixelSize: 20
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.disk.plan.length > 0
                text: {
                    var t = root.disk.planTiers, n = root.disk.planItems.length;
                    var care = (t.state || 0) + (t.data || 0);
                    return n + (n === 1 ? " item" : " items") + " · " + ((t.free || 0) + (t.cost || 0)) + " regenerable" + (care ? " · " + care + " need your eyes" : "");
                }
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: 13
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.toast !== "" ? root.disk.toast : "Nothing is removed until you review it."
                color: root.disk.toast !== "" ? root.theme.success : root.theme.faint
                font.family: root.theme.family
                font.pixelSize: 11
            }
            DiskBtn {
                theme: root.theme
                visible: root.disk.plan.length > 0 && root.disk.page !== "plan"
                text: "Empty"
                onClicked: root.disk.clearPlan()
            }
            DiskBtn {
                theme: root.theme
                visible: root.disk.page !== "plan"
                primary: true
                on: root.disk.plan.length > 0
                text: "Review plan →"
                onClicked: root.disk.page = "plan"
            }
        }
    }
}
