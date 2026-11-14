pragma ComponentBehavior: Bound
// DiskProjects.qml — the Projects page of the Disk window: every project the scan
// found, what it is made of (source · dependencies · build output · git), when it
// was last touched, what can go and why the project itself may still matter
// (uncommitted / unpushed / stashed work, no remote, not in git at all).
//
// The tick on a project row puts its *suggested* dependency and build folders in
// the cleanup plan — never the project itself. Selecting a row opens the panel
// at the bottom listing each removable folder (and, for projects that are not
// being worked on, the whole project) with its own tick, risk and command.
import QtQuick

Item {
    id: root
    required property var theme
    required property var disk
    signal browse(string path)

    readonly property var sec: root.disk.sections.projects || null
    property string sort: "reclaim"      // reclaim | size | age
    property string filter: "all"        // all | stale | look
    property var sel: null               // selected project row
    property var selItem: null           // selected item inside the panel

    readonly property var rows: {
        if (!root.sec) return [];
        var r = root.sec.projects.slice();
        if (root.filter === "stale") r = r.filter(function (p) { return p.status === "stale" || p.status === "dormant"; });
        else if (root.filter === "look") r = r.filter(function (p) { return p.keep.length > 0 || p.tone === "warn" || p.tone === "stop"; });
        if (root.sort === "size") r.sort(function (a, b) { return b.bytes - a.bytes; });
        else if (root.sort === "age") r.sort(function (a, b) { return a.last - b.last; });
        else r.sort(function (a, b) { return b.reclaim - a.reclaim; });
        return r;
    }
    function offered(p) {
        var out = [];
        for (var i = 0; i < p.items.length; i++) {
            var it = root.disk.items[p.items[i]];
            if (it && (it.tier === "free" || it.tier === "cost")) out.push(it.id);
        }
        return out;
    }
    function allIn(p) {
        var o = root.offered(p);
        if (o.length === 0) return false;
        for (var i = 0; i < o.length; i++) if (!root.disk.inPlan(o[i])) return false;
        return true;
    }
    function staleIds() {
        var out = [];
        if (!root.sec) return out;
        for (var i = 0; i < root.sec.projects.length; i++) {
            var p = root.sec.projects[i];
            if (p.status === "stale" || p.status === "dormant") out = out.concat(root.offered(p));
        }
        return out;
    }
    function touchNote(p) {
        if (p.nogit) return "not in git";
        var bits = [];
        if (p.dirty) bits.push(p.dirty < 0 ? "uncommitted" : p.dirty + " uncommitted");
        if (p.unpushed) bits.push(p.unpushed + " unpushed");
        if (p.stash) bits.push(p.stash + " stashed");
        if (bits.length) return bits.join(" · ");
        return p.remote ? "clean · pushed" : "clean · no remote";
    }

    Text {
        anchors.centerIn: parent
        visible: !root.sec
        text: root.disk.scanning ? "Walking your projects…" : "Nothing measured yet — run a scan."
        color: root.theme.faint
        font.family: root.theme.family
        font.pixelSize: 14
    }

    // ---- headline ------------------------------------------------------------
    Row {
        id: head
        visible: !!root.sec
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: 24
        Repeater {
            model: root.sec ? [
                { label: root.sec.totals.count + " projects", value: root.disk.fmtBytes(root.sec.totals.bytes), tone: "" },
                { label: "dependencies", value: root.disk.fmtBytes(root.sec.totals.deps), tone: "dep" },
                { label: "build output", value: root.disk.fmtBytes(root.sec.totals.build), tone: "bld" },
                { label: "can go", value: root.disk.fmtBytes(root.sec.totals.reclaim), tone: "safe" },
                { label: "stale > " + Math.round(root.sec.staleDays / 30) + " mo", value: root.sec.totals.stale + "", tone: "", tail: "projects · " + root.disk.fmtBytes(root.sec.totals.stale_reclaim) }
            ] : []
            Column {
                id: st
                required property var modelData
                Text {
                    text: st.modelData.label.toUpperCase()
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: 10
                    font.letterSpacing: root.theme.labelSpacing
                }
                Row {
                    spacing: 6
                    Text {
                        text: st.modelData.value
                        color: st.modelData.tone === "dep" ? root.theme.accent : st.modelData.tone === "bld" ? root.theme.money : st.modelData.tone === "safe" ? root.theme.success : root.theme.text
                        font.family: root.theme.serif
                        font.pixelSize: 26
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: st.modelData.tail || ""
                        color: root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
    Row {
        id: tools
        visible: !!root.sec
        anchors.right: parent.right
        anchors.verticalCenter: head.verticalCenter
        spacing: 8
        DiskBtn {
            theme: root.theme
            text: "Sort: " + (root.sort === "reclaim" ? "can go" : root.sort === "size" ? "size" : "oldest")
            onClicked: root.sort = root.sort === "reclaim" ? "size" : root.sort === "size" ? "age" : "reclaim"
        }
        DiskBtn {
            theme: root.theme
            text: root.filter === "all" ? "All" : root.filter === "stale" ? "Stale only" : "Needs a look"
            onClicked: root.filter = root.filter === "all" ? "stale" : root.filter === "stale" ? "look" : "all"
        }
        DiskBtn {
            theme: root.theme
            text: "Plan all stale"
            on: root.staleIds().length > 0
            onClicked: root.disk.addPlan(root.staleIds())
        }
    }

    // ---- column heads ----------------------------------------------------------
    Item {
        id: cols
        visible: !!root.sec
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.topMargin: 14
        height: 24
        Repeater {
            model: [{ t: "Project", x: 34, w: 0 }, { t: "Last touch", x: -640, w: 0 }, { t: "What it is made of", x: -500, w: 0 },
                    { t: "Total", x: -262, w: 60 }, { t: "Can go", x: -192, w: 60 }, { t: "Verdict", x: -120, w: 0 }]
            Text {
                required property var modelData
                x: modelData.x >= 0 ? modelData.x : cols.width + modelData.x
                width: modelData.w > 0 ? modelData.w : implicitWidth
                horizontalAlignment: modelData.w > 0 ? Text.AlignRight : Text.AlignLeft
                text: modelData.t.toUpperCase()
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
            }
        }
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.theme.border }
    }
    ListView {
        id: list
        visible: !!root.sec
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: cols.bottom
        anchors.bottom: panel.visible ? panel.top : parent.bottom
        anchors.bottomMargin: panel.visible ? 10 : 0
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var p: modelData
            width: list.width
            height: 44
            radius: root.theme.radiusBtn
            color: root.sel && root.sel.path === row.p.path ? root.theme.rowHi : (ma.containsMouse ? root.theme.row : "transparent")

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { root.sel = row.p; root.selItem = null; }
            }
            PillCheckbox {
                theme: root.theme
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: root.offered(row.p).length > 0
                checked: root.allIn(row.p)
                onToggled: on => {
                    if (on) root.disk.addPlan(root.offered(row.p));
                    else root.disk.dropPlan(root.offered(row.p));
                }
            }
            Column {
                x: 34
                width: row.width - 640 - 34 - 12
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: row.p.rel
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: (row.p.eco.length ? row.p.eco.join(" · ") : "no manifest") + (row.p.worktree_of ? " · worktree" : "") + (row.p.docker ? " · docker" : "")
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: 11
                }
            }
            Column {
                x: row.width - 640
                width: 130
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: root.disk.fmtAge(row.p.last)
                    color: row.p.status === "active" ? root.theme.success : root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: 13
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.touchNote(row.p)
                    color: row.p.keep.length ? root.theme.accent : root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: 11
                }
            }
            DiskSeg {
                theme: root.theme
                x: row.width - 500
                width: 220
                anchors.verticalCenter: parent.verticalCenter
                parts: [{ color: root.theme.text, value: row.p.src }, { color: root.theme.accent, value: row.p.deps },
                        { color: root.theme.money, value: row.p.build }, { color: root.theme.faint, value: row.p.git }]
            }
            Text {
                x: row.width - 262
                width: 60
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: root.disk.fmtBytes(row.p.bytes)
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: 12
            }
            Text {
                x: row.width - 192
                width: 60
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: row.p.reclaim > 1048576 ? root.disk.fmtBytes(row.p.reclaim) : "—"
                color: row.p.reclaim > 1048576 ? root.theme.money : root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 12
            }
            DiskChip {
                theme: root.theme
                x: row.width - 120
                anchors.verticalCenter: parent.verticalCenter
                tone: row.p.tone === "safe" ? "safe" : row.p.tone === "warn" ? "warn" : row.p.tone === "stop" ? "stop" : "plain"
                text: row.p.tone === "safe" ? "can go" : row.p.tone === "warn" ? "look first" : row.p.tone === "stop" ? "look first" : row.p.tone === "leave" ? "active" : "nothing"
            }
        }
    }

    // ---- selected project ------------------------------------------------------
    Rectangle {
        id: panel
        visible: !!root.sel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 232
        radius: theme.radiusTile
        color: theme.bgElevated
        border.width: 1
        border.color: theme.border

        Column {
            id: facts
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 14
            width: 300
            spacing: 5
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: root.sel ? root.sel.rel : ""
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: 19
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.sel ? root.sel.verdict.charAt(0).toUpperCase() + root.sel.verdict.substring(1) + "." : ""
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: 12
            }
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                visible: !!root.sel && !!root.sel.remote
                text: root.sel ? (root.sel.branch ? root.sel.branch + "  →  " : "") + root.sel.remote : ""
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
            }
            Text {
                visible: !!root.sel && root.sel.keep.length > 0
                text: "WHY THE PROJECT ITSELF MATTERS"
                topPadding: 4
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
            }
            Repeater {
                model: root.sel ? root.sel.keep : []
                Text {
                    required property string modelData
                    width: facts.width
                    wrapMode: Text.Wrap
                    text: "·  " + modelData
                    color: root.theme.accent
                    font.family: root.theme.family
                    font.pixelSize: 12
                }
            }
            Text {
                visible: !!root.sel && root.sel.keep.length === 0 && !root.sel.nogit
                width: parent.width
                wrapMode: Text.Wrap
                text: "Nothing here exists only on this disk: the tree is clean and everything is pushed."
                color: root.theme.success
                font.family: root.theme.family
                font.pixelSize: 12
            }
            Row {
                spacing: 8
                topPadding: 4
                DiskBtn { theme: root.theme; text: "Show in Files"; onClicked: if (root.sel) root.browse(root.sel.path) }
                DiskBtn { theme: root.theme; text: "Copy path"; onClicked: if (root.sel) root.disk.copy(root.sel.path) }
            }
        }
        Rectangle { x: 328; y: 12; width: 1; height: parent.height - 24; color: root.theme.border }

        ListView {
            id: parts
            anchors.left: facts.right
            anchors.leftMargin: 28
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.sel ? root.sel.items.concat(root.sel.whole ? [root.sel.whole] : []) : []
            header: Text {
                height: 20
                text: "WHAT CAN GO — TICK TO PLAN, CLICK FOR THE COMMAND"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
            }
            delegate: Rectangle {
                id: part
                required property string modelData
                readonly property var it: root.disk.items[modelData] || null
                width: parts.width
                height: open ? 30 + extra.implicitHeight + 8 : 30
                readonly property bool open: root.selItem === modelData
                radius: 8
                color: open ? root.theme.rowHi : (pma.containsMouse ? root.theme.row : "transparent")
                MouseArea {
                    id: pma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.selItem = part.open ? null : part.modelData
                }
                PillCheckbox {
                    theme: root.theme
                    x: 8
                    y: 5
                    checked: root.disk.inPlan(part.modelData)
                    onToggled: root.disk.togglePlan(part.modelData)
                }
                Text {
                    x: 32
                    y: 6
                    width: parent.width - 32 - 300
                    elide: Text.ElideMiddle
                    text: part.it ? part.it.title : ""
                    color: part.it && part.it.kind === "project" ? root.theme.accent : root.theme.text
                    font.family: root.theme.mono
                    font.pixelSize: 12
                }
                DiskChip {
                    theme: root.theme
                    anchors.right: sizeT.left
                    anchors.rightMargin: 12
                    y: 6
                    tier: part.it ? part.it.tier : ""
                    text: part.it ? root.disk.tierLabel[part.it.tier] : ""
                }
                Text {
                    id: sizeT
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    y: 7
                    width: 64
                    horizontalAlignment: Text.AlignRight
                    text: part.it ? root.disk.fmtBytes(part.it.bytes) : ""
                    color: root.theme.money
                    font.family: root.theme.mono
                    font.pixelSize: 12
                }
                Column {
                    id: extra
                    visible: part.open
                    x: 32
                    y: 30
                    width: parent.width - 44
                    spacing: 3
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: part.it ? part.it.why + (part.it.restore ? "  Comes back with: " + part.it.restore : "")
                                        + (part.it.reclaim < part.it.bytes * 0.95 ? "  Only " + root.disk.fmtBytes(part.it.reclaim) + " frees up now — the rest is hardlinked from a package store." : "") : ""
                        color: root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: part.it ? (part.it.warn || []) : []
                        Text {
                            required property string modelData
                            width: extra.width
                            wrapMode: Text.Wrap
                            text: "!  " + modelData
                            color: root.theme.accent
                            font.family: root.theme.family
                            font.pixelSize: 12
                        }
                    }
                    Row {
                        spacing: 10
                        Text {
                            width: Math.min(implicitWidth, extra.width - 60)
                            elide: Text.ElideMiddle
                            text: part.it ? part.it.cmd : ""
                            color: root.theme.text
                            font.family: root.theme.mono
                            font.pixelSize: 11
                        }
                        Text {
                            text: "COPY"
                            color: cma.containsMouse ? root.theme.text : root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            MouseArea {
                                id: cma
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (part.it) root.disk.copy(part.it.cmd)
                            }
                        }
                    }
                }
            }
        }
    }
}
