pragma ComponentBehavior: Bound
// DiskBuckets.qml — the generic page of the Disk window: a title, one honest
// sentence, a few headline figures, then groups of rows (see diskpages.js for the
// shape). Videos, Games, Downloads, Caches, Packages, Docker, Thumbnails,
// Programs, System and Reports are all this component with a different model.
//
// A row's tick box puts it in / takes it out of the cleanup plan — nothing more.
// Clicking a row selects it; the card at the bottom then explains it and shows
// the exact command. Names on rows marked `veil` are dotted out while the
// window is in discreet mode.
import QtQuick

Item {
    id: root
    required property var theme
    required property var disk
    property var model: null          // page object from diskpages.js (null → still scanning)
    property var sel: null            // the selected row
    signal browse(string path)

    function rowId(r) { return r ? (r.id || (r.path ? (root.disk.pathIds[r.path] || "") : "")) : ""; }
    readonly property var selItem: root.sel ? (root.disk.items[root.rowId(root.sel)] || null) : null
    onModelChanged: { root.sel = null; list.positionViewAtBeginning(); }

    readonly property var entries: {
        var out = [];
        if (!root.model) return out;
        var gs = root.model.groups || [];
        for (var i = 0; i < gs.length; i++) {
            var g = gs[i];
            if (!g.rows || g.rows.length === 0) continue;
            var mx = 1, offer = [];
            for (var j = 0; j < g.rows.length; j++) {
                if ((g.rows[j].bytes || 0) > mx) mx = g.rows[j].bytes;
                var it = g.rows[j].id ? root.disk.items[g.rows[j].id] : null;
                if (it && it.offer) offer.push(it.id);
            }
            out.push({ t: "g", g: g, offer: offer });
            for (var k = 0; k < g.rows.length; k++) out.push({ t: "r", r: g.rows[k], max: mx });
        }
        return out;
    }

    Text {
        anchors.centerIn: parent
        visible: !root.model
        text: root.disk.scanning ? "Still measuring this part…" : "Nothing measured yet — run a scan."
        color: root.theme.faint
        font.family: root.theme.family
        font.pixelSize: 14
    }

    ListView {
        id: list
        visible: !!root.model
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: detail.visible ? detail.top : parent.bottom
        anchors.bottomMargin: detail.visible ? 10 : 0
        clip: true
        model: root.entries
        boundsBehavior: Flickable.StopAtBounds

        header: Column {
            width: list.width
            spacing: 10
            bottomPadding: 6
            Text {
                text: root.model ? root.model.title : ""
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: 26
            }
            Text {
                width: Math.min(parent.width, 760)
                wrapMode: Text.Wrap
                text: root.model ? root.model.lead : ""
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: 13
            }
            Row {
                spacing: 30
                Repeater {
                    model: root.model ? root.model.stats : []
                    Column {
                        id: stat
                        required property var modelData
                        spacing: 0
                        Text {
                            text: stat.modelData.label.toUpperCase()
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: root.theme.labelSpacing
                        }
                        Text {
                            text: stat.modelData.value
                            visible: stat.modelData.value !== ""
                            color: stat.modelData.tone === "safe" ? root.theme.success : stat.modelData.tone === "warn" ? root.theme.money : root.theme.text
                            font.family: root.theme.serif
                            font.pixelSize: 24
                        }
                    }
                }
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isGroup: modelData.t === "g"
            readonly property var r: modelData.r || null
            readonly property string iid: root.rowId(row.r)
            readonly property bool tickable: !!row.r && (!!row.r.id || (!!row.r.path && row.r.tier !== undefined && !row.r.file))
            width: list.width
            height: isGroup ? 44 : 40

            // ---- group header --------------------------------------------------
            Item {
                visible: row.isGroup
                anchors.fill: parent
                Text {
                    id: gTitle
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 7
                    text: row.isGroup ? row.modelData.g.title.toUpperCase() : ""
                    color: root.theme.text
                    font.family: root.theme.mono
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.letterSpacing: root.theme.labelSpacing
                }
                Text {
                    anchors.left: gTitle.right
                    anchors.leftMargin: 12
                    anchors.right: gRight.left
                    anchors.rightMargin: 12
                    anchors.baseline: gTitle.baseline
                    elide: Text.ElideRight
                    text: row.isGroup ? (row.modelData.g.note || "") : ""
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: 11
                }
                Row {
                    id: gRight
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.isGroup && row.modelData.g.bytes !== undefined
                        text: row.isGroup && row.modelData.g.bytes !== undefined ? root.disk.fmtBytes(row.modelData.g.bytes) : ""
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: 11
                    }
                    DiskBtn {
                        theme: root.theme
                        visible: row.isGroup && row.modelData.offer.length > 0
                        implicitHeight: 22
                        text: "Add the " + (row.isGroup ? row.modelData.offer.length : 0) + " suggested"
                        onClicked: root.disk.addPlan(row.modelData.offer)
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.theme.border
                }
            }

            // ---- row -------------------------------------------------------------
            Rectangle {
                visible: !row.isGroup
                anchors.fill: parent
                radius: root.theme.radiusBtn
                color: root.sel === row.r ? root.theme.rowHi : (rowMa.containsMouse ? root.theme.row : "transparent")

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.sel = row.r;
                        if (row.r.file) root.disk.openFile(row.r.file);
                        else if (!row.iid && row.tickable) root.disk.makeItems([row.r.path]);
                    }
                }
                PillCheckbox {
                    id: tick
                    theme: root.theme
                    visible: row.tickable
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    checked: row.iid !== "" && root.disk.inPlan(row.iid)
                    onToggled: {
                        if (row.iid) root.disk.togglePlan(row.iid);
                        else root.disk.planPath(row.r.path);
                    }
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.right: rightSide.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Row {
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, row.width - 420)
                            elide: Text.ElideMiddle
                            text: row.r ? (row.r.veil ? root.disk.veil(row.r.label) : row.r.label) : ""
                            color: root.theme.text
                            font.family: row.r && row.r.mono ? root.theme.mono : root.theme.family
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Repeater {
                            model: row.r ? (row.r.chips || []) : []
                            DiskChip {
                                required property var modelData
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                theme: root.theme
                                text: modelData.text
                                tone: modelData.tone
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        visible: text !== ""
                        text: row.r ? (row.r.sub || "") : ""
                        color: root.theme.faint
                        font.family: row.r && row.r.mono ? root.theme.mono : root.theme.family
                        font.pixelSize: 11
                    }
                }
                Row {
                    id: rightSide
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 62
                        horizontalAlignment: Text.AlignRight
                        text: row.r && row.r.when ? root.disk.fmtAge(row.r.when) : ""
                        color: root.theme.faint
                        font.family: root.theme.family
                        font.pixelSize: 11
                    }
                    DiskSeg {
                        anchors.verticalCenter: parent.verticalCenter
                        theme: root.theme
                        width: 70
                        implicitHeight: 6
                        visible: !!row.r && row.r.bytes !== undefined
                        total: row.modelData.max || 1
                        parts: [{ color: row.r && row.r.tier === "free" ? root.theme.success : row.r && row.r.tier === "cost" ? root.theme.money : root.theme.textDim,
                                  value: row.r ? (row.r.bytes || 0) : 0 }]
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 62
                        horizontalAlignment: Text.AlignRight
                        text: row.r && row.r.bytes !== undefined ? root.disk.fmtBytes(row.r.bytes) : ""
                        color: root.theme.money
                        font.family: root.theme.mono
                        font.pixelSize: 12
                    }
                    Item {
                        width: 20
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        MSym {
                            anchors.centerIn: parent
                            visible: !!row.r && !!row.r.open
                            icon: "folder_open"
                            size: 15
                            color: openMa.containsMouse ? root.theme.text : root.theme.faint
                        }
                        MouseArea {
                            id: openMa
                            anchors.fill: parent
                            enabled: !!row.r && !!row.r.open
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.browse(row.r.open)
                        }
                    }
                }
            }
        }
    }

    DiskDetail {
        id: detail
        theme: root.theme
        disk: root.disk
        item: root.selItem
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onBrowse: path => root.browse(path)
    }
}
