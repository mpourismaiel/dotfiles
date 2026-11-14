pragma ComponentBehavior: Bound
// DiskOverview.qml — the first page of the Disk window: where the space went (one
// ledger line per category, click to open its page), the best things to remove
// according to the scan, and — while a scan runs — what each scanner is doing.
// A fresh install shows a single "Scan" call instead.
import QtQuick

Item {
    id: root
    required property var theme
    required property var disk
    signal go(string page)

    readonly property var ov: root.disk.overview
    readonly property var main: root.disk.disk ? root.disk.disk.main : null
    readonly property var names: ({ home: "Home folder", projects: "Projects", caches: "Caches", packages: "Packages", docker: "Docker",
                                    games: "Games", thumbnails: "Thumbnails", downloads: "Downloads", bins: "Programs", system: "System" })

    // ---- never scanned ---------------------------------------------------------
    Column {
        visible: root.disk.ready && root.disk.empty && !root.disk.scanning
        anchors.centerIn: parent
        spacing: 12
        width: 460
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Nothing has been measured yet"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 26
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "A scan walks your home folder, projects, caches, packages, Docker and games. It only reads — it takes a few minutes the first time and nothing is removed, ever, without a review."
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: 13
        }
        DiskBtn {
            anchors.horizontalCenter: parent.horizontalCenter
            theme: root.theme
            primary: true
            text: "Scan this computer"
            onClicked: root.disk.scan("")
        }
    }

    // ---- ledger ----------------------------------------------------------------
    Column {
        id: ledger
        visible: !!root.ov
        anchors.left: parent.left
        anchors.top: parent.top
        width: Math.round(parent.width * 0.44)
        spacing: 2

        Text {
            text: "Where it went"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 26
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            bottomPadding: 10
            text: root.main ? root.disk.fmtBytes(root.main.used) + " used of " + root.disk.fmtBytes(root.main.total) + " on " + root.main.mount
                              + " (" + root.main.fstype + "). Sizes are what files really occupy on disk." : ""
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: 13
        }
        Repeater {
            model: root.ov ? root.ov.categories : []
            Rectangle {
                id: cat
                required property var modelData
                width: ledger.width
                height: 34
                radius: root.theme.radiusBtn
                color: cma.containsMouse ? root.theme.row : "transparent"
                MouseArea {
                    id: cma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(cat.modelData.page)
                }
                Rectangle {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 3
                    color: root.disk.catColor(root.theme, cat.modelData.key)
                }
                Text {
                    x: 28
                    anchors.verticalCenter: parent.verticalCenter
                    text: cat.modelData.label
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: 13
                }
                DiskSeg {
                    theme: root.theme
                    anchors.right: bytesT.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(60, ledger.width - 300)
                    implicitHeight: 6
                    total: root.main ? root.main.used : 1
                    parts: [{ color: root.disk.catColor(root.theme, cat.modelData.key), value: cat.modelData.bytes }]
                }
                Text {
                    id: bytesT
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 70
                    horizontalAlignment: Text.AlignRight
                    text: root.disk.fmtBytes(cat.modelData.bytes)
                    color: root.theme.money
                    font.family: root.theme.mono
                    font.pixelSize: 12
                }
            }
        }
        Text {
            topPadding: 8
            width: parent.width
            wrapMode: Text.Wrap
            visible: !!root.ov
            text: "“Everything else” is what no scanner claimed: documents, pictures, application data — and anything only root can read."
            color: root.theme.faint
            font.family: root.theme.family
            font.pixelSize: 11
        }
    }

    // ---- suggestions -------------------------------------------------------------
    Item {
        id: best
        visible: !!root.ov
        anchors.left: ledger.right
        anchors.leftMargin: 28
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Text {
            id: bTitle
            text: "Worth removing first"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 26
        }
        Text {
            id: bLead
            anchors.top: bTitle.bottom
            anchors.topMargin: 2
            width: parent.width
            wrapMode: Text.Wrap
            text: root.ov ? "The scan suggests " + root.disk.fmtBytes(root.ov.offered_bytes) + " that comes back by itself or with a download. Suggestions are never your own files, never state, and never from a project you touched this month."
                          : ""
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: 13
        }
        Row {
            id: bBtns
            anchors.top: bLead.bottom
            anchors.topMargin: 10
            spacing: 8
            DiskBtn {
                theme: root.theme
                primary: true
                text: "Plan every suggestion"
                onClicked: root.disk.addPlan(root.disk.offeredIds(""))
            }
            DiskBtn {
                theme: root.theme
                text: "Only what costs nothing"
                onClicked: {
                    var ids = root.disk.offeredIds("").filter(function (i) { return root.disk.items[i].tier === "free"; });
                    root.disk.addPlan(ids);
                }
            }
        }
        ListView {
            id: bl
            anchors.top: bBtns.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.ov ? root.ov.best : []
            delegate: Rectangle {
                id: b
                required property string modelData
                readonly property var it: root.disk.items[modelData] || null
                visible: !!it
                width: bl.width
                height: it ? 40 : 0
                radius: root.theme.radiusBtn
                color: bma.containsMouse ? root.theme.row : "transparent"
                MouseArea {
                    id: bma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (b.it) root.go(b.it.section)
                }
                PillCheckbox {
                    theme: root.theme
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.disk.inPlan(b.modelData)
                    onToggled: root.disk.togglePlan(b.modelData)
                }
                Column {
                    x: 34
                    width: parent.width - 34 - 230
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: b.it ? (b.it.section === "projects" ? "" : root.disk.sectionLabel[b.it.section] + " · ") + root.disk.itemTitle(b.it) : ""
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: b.it ? b.it.why : ""
                        color: root.theme.faint
                        font.family: root.theme.family
                        font.pixelSize: 11
                    }
                }
                DiskChip {
                    theme: root.theme
                    anchors.right: bb.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    tier: b.it ? b.it.tier : ""
                    text: b.it ? root.disk.tierShort[b.it.tier] : ""
                }
                Text {
                    id: bb
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66
                    horizontalAlignment: Text.AlignRight
                    text: b.it ? root.disk.fmtBytes(b.it.reclaim) : ""
                    color: root.theme.money
                    font.family: root.theme.mono
                    font.pixelSize: 12
                }
            }
        }
    }

    // ---- scan progress (first scan: centre stage; rescans: the header shows it) ----
    Column {
        visible: root.disk.scanning && !root.ov
        anchors.centerIn: parent
        width: 520
        spacing: 6
        Text {
            text: "Measuring…"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 26
        }
        Repeater {
            model: ["home", "projects", "caches", "docker", "thumbnails", "system", "packages", "games", "downloads", "bins"]
            Row {
                id: pr
                required property string modelData
                readonly property var p: root.disk.progress[modelData] || null
                spacing: 10
                Text {
                    width: 110
                    text: root.names[pr.modelData]
                    color: pr.p ? root.theme.text : root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: 13
                }
                Text {
                    width: 400
                    elide: Text.ElideMiddle
                    text: !pr.p ? "waiting" : pr.p.state === "done" ? "done in " + pr.p.took + " s"
                          : (pr.p.total ? pr.p.done + " of " + pr.p.total + "  " : "") + (pr.p.at || (pr.p.files ? pr.p.files + " files" : "working"))
                    color: pr.p && pr.p.state === "done" ? root.theme.success : root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: 11
                }
            }
        }
    }
}
