pragma ComponentBehavior: Bound
// DiskReview.qml — the cleanup plan and the only screen of the Disk window from
// which anything is removed.
//
// Opening it asks the bridge to re-check every planned item against the disk
// (`verify`): sizes are re-measured, git state re-read, vanished or changed
// things are set aside with the reason. What survives is grouped by what losing
// it costs, and each group must be acknowledged in a way that fits the cost:
//
//   comes back by itself        one tick for the group
//   costs time to get back      one tick for the group
//   holds state                 every item ticked, one by one
//   cannot be recovered         every item ticked, and — for a gigabyte or more,
//                               or anything carrying a warning — the amount typed
//
// The right column shows the exact script (copy it, edit it, run it yourself
// instead) and the Remove button, which stays off until every group present is
// acknowledged. The bridge enforces the same thing and re-checks every path
// once more right before touching it. After a run: what went, what was skipped
// and why, and the report file.
import QtQuick

Item {
    id: root
    required property var theme
    required property var disk

    readonly property var rev: root.disk.review
    readonly property var res: root.disk.result
    readonly property var tiers: ["free", "cost", "state", "data"]
    readonly property var tierTitle: ({ free: "Caches and build output", cost: "Dependencies, images and downloads", state: "Things holding state", data: "Your files" })
    readonly property var tierAsk: ({
        free: "I understand these are rebuilt or re-downloaded when needed.",
        cost: "I accept the downloads and build time it takes to get these back.",
        state: "Tick each one: it holds something no lockfile or registry can restore.",
        data: "Tick each one. These are your files — once gone (or once the Trash is emptied) nothing brings them back."
    })
    property var ack: ({ free: false, cost: false })
    property var seen: ({})              // id → ticked (state / data items)
    property string typed: ""

    function group(tier) {
        var out = [];
        if (!root.rev) return out;
        for (var i = 0; i < root.rev.items.length; i++)
            if (root.rev.items[i].status === "ok" && root.rev.items[i].tier === tier) out.push(root.rev.items[i]);
        return out;
    }
    readonly property var leftOut: {
        var out = [];
        if (!root.rev) return out;
        for (var i = 0; i < root.rev.items.length; i++) if (root.rev.items[i].status !== "ok") out.push(root.rev.items[i]);
        return out;
    }
    function groupBytes(tier) {
        var g = root.group(tier), b = 0;
        for (var i = 0; i < g.length; i++) b += g[i].bytes_now;
        return b;
    }
    function allSeen(tier) {
        var g = root.group(tier);
        for (var i = 0; i < g.length; i++) if (!root.seen[g[i].id]) return false;
        return g.length > 0;
    }
    function needsTyping() {
        var g = root.group("data");
        if (root.groupBytes("data") >= 1073741824) return true;
        for (var i = 0; i < g.length; i++) if (g[i].warn && g[i].warn.length) return true;
        return false;
    }
    function norm(s) { return ("" + s).toLowerCase().replace(/\s+/g, ""); }
    function acked(tier) {
        if (root.group(tier).length === 0) return true;
        if (tier === "free" || tier === "cost") return !!root.ack[tier];
        if (!root.allSeen(tier)) return false;
        if (tier === "data" && root.needsTyping()) return root.norm(root.typed) === root.norm(root.disk.fmtBytes(root.groupBytes("data")));
        return true;
    }
    readonly property bool ready: !!root.rev && root.rev.items.length > root.leftOut.length
        && root.acked("free") && root.acked("cost") && root.acked("state") && root.acked("data")
    readonly property int okCount: root.rev ? root.rev.items.length - root.leftOut.length : 0
    function veiled(v) {
        return root.disk.itemTitle(v);
    }
    function resetAcks() { root.ack = ({ free: false, cost: false }); root.seen = ({}); root.typed = ""; }
    onRevChanged: root.resetAcks()
    function refresh() {
        if (root.disk.plan.length > 0 && !root.disk.review && !root.disk.reviewing && !root.disk.applying && !root.disk.result) root.disk.startReview();
    }
    Component.onCompleted: root.refresh()
    Connections {
        target: root.disk
        function onPlanChanged() { root.refresh(); }
    }

    // ---- nothing planned ---------------------------------------------------------
    Column {
        visible: root.disk.plan.length === 0 && !root.res && !root.disk.applying
        anchors.centerIn: parent
        width: 480
        spacing: 8
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "The cleanup plan is empty"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 26
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Tick things on any page — or flag them in Files — and they collect here. Nothing is removed until you have read this page and acknowledged each group."
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: 13
        }
    }

    // ---- working -------------------------------------------------------------------
    Column {
        visible: (root.disk.reviewing && !root.rev) || root.disk.applying
        anchors.centerIn: parent
        spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.disk.applying ? "Removing…" : "Checking the plan against the disk…"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: 26
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.disk.applying && root.disk.applyStep ? (root.disk.applyStep.index + 1) + " of " + root.disk.applyStep.total + " — " + root.disk.applyStep.title
                  : "sizes re-measured, git state re-read, every path re-checked"
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: 12
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.disk.applying
            text: "Large caches and tools' own cleaners can take minutes. A cleaner that asks a question is stopped and reported."
            color: root.theme.faint
            font.family: root.theme.family
            font.pixelSize: 11
        }
        DiskBtn {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.disk.applying
            theme: root.theme
            text: "Stop after this item"
            icon: "stop"
            onClicked: root.disk.stopApply()
        }
    }

    // ---- result of a run -------------------------------------------------------------
    Flickable {
        visible: !!root.res && !root.disk.applying
        anchors.fill: parent
        contentHeight: resCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: resCol
            width: parent.width
            spacing: 8
            Text {
                text: root.res && root.res.ok ? "Done" : "Nothing was removed"
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: 26
            }
            Text {
                width: Math.min(parent.width, 760)
                wrapMode: Text.Wrap
                text: !root.res ? "" : !root.res.ok ? root.res.error
                      : root.disk.fmtBytes(Math.max(0, root.res.freed)) + " more free space now (" + root.disk.fmtBytes(root.res.free) + " free). "
                        + "Things sent to the Trash keep their space until the Trash is emptied."
                color: root.res && !root.res.ok ? root.theme.accent : root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: 13
            }
            Row {
                spacing: 8
                DiskBtn { theme: root.theme; visible: !!root.res && !!root.res.report; text: "Open the report"; onClicked: root.disk.openFile(root.res.report) }
                DiskBtn { theme: root.theme; primary: true; text: "Back to the plan"; onClicked: root.disk.result = null }
            }
            Repeater {
                model: root.res && root.res.results ? root.res.results : []
                Rectangle {
                    id: rr
                    required property var modelData
                    readonly property bool good: ["removed", "trashed", "ran"].indexOf(modelData.status) >= 0
                    width: resCol.width
                    height: 38
                    radius: root.theme.radiusBtn
                    color: root.theme.row
                    MSym {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        icon: rr.good ? "check_circle" : rr.modelData.status === "manual" ? "terminal" : "do_not_disturb_on"
                        size: 16
                        color: rr.good ? root.theme.success : rr.modelData.status === "manual" ? root.theme.money : root.theme.accent
                    }
                    Column {
                        x: 36
                        width: parent.width - 36 - 260
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: rr.modelData.title
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: 13
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: rr.modelData.status + (rr.modelData.detail ? " — " + rr.modelData.detail.replace(/\n/g, " ") : "")
                            color: rr.good ? root.theme.faint : root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: 11
                        }
                    }
                    DiskBtn {
                        theme: root.theme
                        visible: rr.modelData.status === "manual"
                        anchors.right: rb.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 22
                        text: "Open in terminal"
                        onClicked: root.disk.terminal(rr.modelData.id)
                    }
                    Text {
                        id: rb
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.disk.fmtBytes(rr.modelData.bytes)
                        color: root.theme.money
                        font.family: root.theme.mono
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // ---- the review --------------------------------------------------------------------
    Item {
        visible: !!root.rev && !root.res && !root.disk.applying && root.disk.plan.length > 0
        anchors.fill: parent

        Flickable {
            id: flick
            anchors.left: parent.left
            anchors.right: side.left
            anchors.rightMargin: 20
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            contentHeight: revCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: revCol
                width: flick.width
                spacing: 12
                Text {
                    text: "Review the cleanup plan"
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: 26
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.rev ? root.okCount + " items, " + root.disk.fmtBytes(root.rev.bytes) + ", checked against the disk just now. Read each group and acknowledge it. Take anything out with ✕ — it stays on disk."
                          : ""
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: 13
                }

                Repeater {
                    model: root.tiers
                    Rectangle {
                        id: grp
                        required property string modelData
                        readonly property var rows: root.group(modelData)
                        readonly property bool each: modelData === "state" || modelData === "data"
                        visible: rows.length > 0
                        width: revCol.width
                        height: visible ? gcol.implicitHeight + 24 : 0
                        radius: root.theme.radiusTile
                        color: root.theme.bgElevated
                        border.width: 1
                        border.color: modelData === "data" ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.5) : root.theme.border

                        Column {
                            id: gcol
                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 6
                            Item {
                                width: parent.width
                                height: 22
                                DiskChip { id: gchip; theme: root.theme; tier: grp.modelData; text: root.disk.tierLabel[grp.modelData]; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    anchors.left: gchip.right
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.tierTitle[grp.modelData] + "  ·  " + grp.rows.length + (grp.rows.length === 1 ? " item" : " items")
                                    color: root.theme.text
                                    font.family: root.theme.family
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.disk.fmtBytes(root.groupBytes(grp.modelData))
                                    color: root.theme.money
                                    font.family: root.theme.mono
                                    font.pixelSize: 13
                                }
                            }
                            Repeater {
                                model: grp.rows
                                Item {
                                    id: it
                                    required property var modelData
                                    width: gcol.width
                                    height: Math.max(30, itCol.implicitHeight + 8)
                                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: root.theme.border }
                                    PillCheckbox {
                                        theme: root.theme
                                        visible: grp.each
                                        y: 8
                                        checked: !!root.seen[it.modelData.id]
                                        onToggled: on => { var s = Object.assign({}, root.seen); s[it.modelData.id] = on; root.seen = s; }
                                    }
                                    Column {
                                        id: itCol
                                        x: grp.each ? 26 : 0
                                        y: 6
                                        width: parent.width - x - 120
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideMiddle
                                            text: root.veiled(it.modelData)
                                            color: root.theme.text
                                            font.family: root.theme.mono
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            width: parent.width
                                            wrapMode: Text.Wrap
                                            text: it.modelData.why + (it.modelData.restore ? "  Back with: " + it.modelData.restore : "")
                                                  + (it.modelData.method === "trash" ? "  → goes to the Trash" : it.modelData.method === "terminal" ? "  → you run this in a terminal" : "")
                                            color: root.theme.textDim
                                            font.family: root.theme.family
                                            font.pixelSize: 11
                                        }
                                        Repeater {
                                            model: it.modelData.warn || []
                                            Text {
                                                required property string modelData
                                                width: itCol.width
                                                wrapMode: Text.Wrap
                                                text: "!  " + modelData
                                                color: root.theme.accent
                                                font.family: root.theme.family
                                                font.pixelSize: 11
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.right: xBtn.left
                                        anchors.rightMargin: 12
                                        y: 7
                                        text: root.disk.fmtBytes(it.modelData.bytes_now)
                                        color: root.theme.money
                                        font.family: root.theme.mono
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        id: xBtn
                                        anchors.right: parent.right
                                        y: 5
                                        text: "✕"
                                        color: xma.containsMouse ? root.theme.text : root.theme.faint
                                        font.pixelSize: 13
                                        MouseArea {
                                            id: xma
                                            anchors.fill: parent
                                            anchors.margins: -5
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.disk.togglePlan(it.modelData.id)
                                        }
                                    }
                                }
                            }
                            // ---- the acknowledgment for this group ----
                            Rectangle { width: parent.width; height: 1; color: root.theme.border }
                            PillCheckbox {
                                theme: root.theme
                                visible: !grp.each
                                checked: !!root.ack[grp.modelData]
                                label: root.tierAsk[grp.modelData]
                                onToggled: on => { var a = Object.assign({}, root.ack); a[grp.modelData] = on; root.ack = a; }
                            }
                            Text {
                                visible: grp.each
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: root.tierAsk[grp.modelData]
                                color: root.allSeen(grp.modelData) ? root.theme.success : root.theme.textDim
                                font.family: root.theme.family
                                font.pixelSize: 12
                            }
                            Row {
                                visible: grp.modelData === "data" && root.needsTyping()
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Type the amount in this group (" + root.disk.fmtBytes(root.groupBytes("data")) + ") to acknowledge:"
                                    color: root.theme.textDim
                                    font.family: root.theme.family
                                    font.pixelSize: 12
                                }
                                Rectangle {
                                    width: 120
                                    height: 24
                                    radius: 7
                                    color: root.theme.desk
                                    border.width: 1
                                    border.color: typeIn.activeFocus ? root.theme.accent : root.theme.borderStrong
                                    TextInput {
                                        id: typeIn
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: root.theme.text
                                        font.family: root.theme.mono
                                        font.pixelSize: 12
                                        clip: true
                                        text: root.typed
                                        onTextEdited: root.typed = text
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.typed !== ""
                                    text: root.acked("data") ? "✓ matches" : root.allSeen("data") ? "does not match" : "tick each item too"
                                    color: root.acked("data") ? root.theme.success : root.theme.faint
                                    font.family: root.theme.mono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                // ---- set aside ----
                Column {
                    visible: root.leftOut.length > 0
                    width: parent.width
                    spacing: 4
                    Text {
                        text: "LEFT OUT — NOT TOUCHED"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: 10
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    Repeater {
                        model: root.leftOut
                        Text {
                            required property var modelData
                            width: revCol.width
                            wrapMode: Text.Wrap
                            text: root.veiled(modelData) + " — " + modelData.reason
                            color: root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: 12
                        }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }

        // ---- right column: script, safety, the button ----
        Column {
            id: side
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 340
            spacing: 10
            Text {
                text: "WHAT WILL RUN"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
            }
            Rectangle {
                width: parent.width
                height: Math.max(120, side.height - 330)
                radius: root.theme.radiusBtn
                color: root.theme.desk
                border.width: 1
                border.color: root.theme.border
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 9
                    contentHeight: scriptT.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Text {
                        id: scriptT
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: root.rev ? root.rev.script : ""
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: 10
                    }
                }
            }
            Row {
                spacing: 8
                DiskBtn { theme: root.theme; text: "Copy as script"; onClicked: if (root.rev) root.disk.copy(root.rev.script) }
                DiskBtn { theme: root.theme; text: "Check again"; onClicked: root.disk.startReview() }
                DiskBtn { theme: root.theme; text: "Empty plan"; onClicked: root.disk.clearPlan() }
            }
            Text {
                topPadding: 4
                text: "SAFETY"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: 10
                font.letterSpacing: root.theme.labelSpacing
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                lineHeight: 1.25
                text: "· Every path is checked once more right before it is removed; anything that changed is skipped.\n"
                    + "· Your own files go to the Trash. Caches and dependencies are removed for real — the Trash would not free the space.\n"
                    + "· Commands that need administrator rights are not run here: they open in a terminal and wait for Enter.\n"
                    + "· A report of what went, with sizes, is kept under Reports."
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: 11
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.ready ? "Every group is acknowledged." : "Acknowledge every group on the left to enable the button."
                color: root.ready ? root.theme.success : root.theme.faint
                font.family: root.theme.family
                font.pixelSize: 12
            }
            DiskBtn {
                theme: root.theme
                width: parent.width
                implicitHeight: 38
                primary: true
                on: root.ready
                text: root.rev ? "Remove " + root.okCount + (root.okCount === 1 ? " item · " : " items · ") + root.disk.fmtBytes(root.rev.bytes) : "Remove"
                onClicked: {
                    var a = [];
                    for (var i = 0; i < root.tiers.length; i++) if (root.group(root.tiers[i]).length > 0) a.push(root.tiers[i]);
                    root.disk.apply(a);
                }
            }
        }
    }
}
