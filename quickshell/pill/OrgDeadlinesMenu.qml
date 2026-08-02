pragma ComponentBehavior: Bound
// OrgDeadlinesMenu.qml — the floating "Org deadlines" list, opened by
// right-clicking the resting pill or clicking its deadline under-line. Like
// AppMenu it is a full-overlay Item (anchors.fill your host) with an outside-click
// backdrop; the panel drops from (px,py) just below the pill and is clamped to
// stay on screen. It reads OrgAgenda's deadline buckets and shows them in the
// spec order — overdue ("LATE") first, then due-today ("TODAY"), then upcoming
// ("AHEAD") — with a checkbox to tick an item done and a click to open it in
// Emacs. Keyboard: ↑/↓ move, Space ticks done, Enter opens, Esc closes (the pill
// grabs the keyboard while `open`, wired via win.deadlines in init.qml).
import QtQuick
import Quickshell

Item {
    id: root
    required property var theme
    required property var org             // OrgAgenda instance (deadline buckets + actions)
    property bool open: false
    property real px: 0                   // requested top-left, in this overlay's coords
    property real py: 0
    property int  aheadMax: 4             // AHEAD rows shown before a "+N more" line
    signal dismissed()                    // backdrop / Esc / after opening an item

    anchors.fill: parent
    visible: open
    focus: open
    z: 1000

    // ---- data: the three buckets, with AHEAD capped for display ----
    readonly property var lateItems:  org ? org.lateItems  : []
    readonly property var todayItems: org ? org.todayItems : []
    readonly property var aheadAll:   org ? org.aheadItems : []
    readonly property var aheadItems: aheadAll.slice(0, aheadMax)
    readonly property int aheadMore:  Math.max(0, aheadAll.length - aheadItems.length)
    // flat, in display order — the keyboard cursor walks this; each section's rows
    // offset into it by the lengths before them.
    readonly property var flat: lateItems.concat(todayItems, aheadItems)
    readonly property bool nothingDue: (lateItems.length + todayItems.length) === 0
    property int sel: 0

    // entrance driver: 0 hidden -> 1 fully in. The panel drops down from just under
    // the pill (slides + fades + scales up from its top edge) each time it opens, so
    // the list reads as spilling out of the pill rather than snapping into place.
    property real appear: 0
    NumberAnimation {
        id: appearAnim
        target: root; property: "appear"; from: 0; to: 1
        duration: root.theme.anim; easing.type: Easing.OutCubic
    }

    onOpenChanged: {
        if (open) {
            sel = 0;
            if (org && org.loadDeadlines) org.loadDeadlines();   // freshen on open
            appear = 0;
            appearAnim.restart();
            forceActiveFocus();
        } else {
            appear = 0;
        }
    }
    // keep the cursor in range as items tick away underneath it
    onFlatChanged: if (sel >= flat.length) sel = Math.max(0, flat.length - 1)

    // NB: never assign root.open here — it is *bound* to win.deadlines in init.qml,
    // and a direct assignment would destroy that binding (leaving open stuck false
    // while win.deadlines still flips true → an invisible full-screen mask that eats
    // every click). Just signal; init clears win.deadlines, which flows back to open.
    function close() { root.dismissed(); }
    function toggleAt(i) {
        const it = root.flat[i];
        if (it && it.file) root.org.toggleDone(it.file, it.pos);
    }
    function openAt(i) {
        const it = root.flat[i];
        if (it && it.file) { root.org.gotoItem(it.file, it.pos); root.close(); }
    }
    // ddd d — e.g. "Sat 1" — from an item's ISO deadline date
    function fmtDate(iso) {
        if (!iso) return "";
        const p = ("" + iso).split("-");
        if (p.length !== 3) return iso;
        const d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
        return Qt.formatDate(d, "ddd d");
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
        else if (e.key === Qt.Key_Down) { if (root.sel < root.flat.length - 1) root.sel++; e.accepted = true; }
        else if (e.key === Qt.Key_Up)   { if (root.sel > 0) root.sel--; e.accepted = true; }
        else if (e.key === Qt.Key_Space) { root.toggleAt(root.sel); e.accepted = true; }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.openAt(root.sel); e.accepted = true; }
    }

    // backdrop: any outside click (either button) dismisses
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.close()
    }

    // ---- one deadline row: checkbox · heading · trailing date/overdue label ----
    component DlRow: Rectangle {
        id: dr
        required property var item
        required property int idx        // global index into root.flat
        property bool late: false        // overdue styling (accent tint + border)
        width: panelCol.width
        height: 30
        radius: root.theme.radiusBtn
        // selected row wins; else a faint accent wash for overdue rows, flat otherwise
        color: root.sel === idx ? root.theme.rowHi
             : late ? root.theme.accentSoft : "transparent"

        Rectangle {                       // checkbox
            id: box
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 15; radius: 4
            color: "transparent"
            border.width: 1.5
            border.color: boxMa.containsMouse ? root.theme.accent
                        : dr.late ? root.theme.accent : root.theme.faint
            MouseArea {
                id: boxMa
                anchors.fill: parent; anchors.margins: -3
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleAt(dr.idx)
            }
        }
        Text {
            id: head
            anchors.left: box.right; anchors.leftMargin: 10
            anchors.right: lbl.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: dr.item ? dr.item.text : ""
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }
        Text {
            id: lbl
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            // overdue → "-9d" (days late); dated → weekday+day ("Sat 1")
            text: dr.late ? (dr.item.delta + "d") : root.fmtDate(dr.item ? dr.item.date : "")
            color: dr.late ? root.theme.accent : root.theme.faint
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
            font.letterSpacing: root.theme.labelSpacing
        }
        MouseArea {                       // click the body → open in Emacs
            anchors.left: head.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.bottom: parent.bottom
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onEntered: root.sel = dr.idx
            onClicked: root.openAt(dr.idx)
        }
    }

    // a section header: "LATE · 3" etc.
    component SectionHead: Item {
        id: sh
        property string label: ""
        property int count: 0
        property color tint: root.theme.textDim
        width: panelCol.width
        height: 24
        Text {
            anchors.left: parent.left; anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: sh.label + " · " + sh.count
            color: sh.tint
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
            font.letterSpacing: root.theme.labelSpacing
            font.capitalization: Font.AllUppercase
        }
    }

    // ---- the panel ----
    Rectangle {
        id: panel
        x: Math.max(8, Math.min(root.px, root.width - width - 8))
        y: Math.max(8, Math.min(root.py, root.height - height - 8))
        width: 400
        height: panelCol.implicitHeight + root.theme.pad * 2
        radius: root.theme.radiusCard
        color: root.theme.bgElevated
        border.color: root.theme.border
        border.width: 1

        // drop-in entrance: fade + slide down from ~12px above the rest position +
        // a small scale-up anchored to the top edge (the pill it drops out of).
        opacity: root.appear
        transformOrigin: Item.Top
        transform: [
            Translate { y: (1 - root.appear) * -12 },
            Scale {
                origin.x: panel.width / 2; origin.y: 0
                xScale: 0.96 + 0.04 * root.appear
                yScale: 0.96 + 0.04 * root.appear
            }
        ]

        Column {
            id: panelCol
            x: root.theme.pad; y: root.theme.pad
            width: parent.width - root.theme.pad * 2
            spacing: 2

            // header: title + keyboard hints
            Item {
                width: parent.width
                height: 22
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ORG DEADLINES"
                    color: root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SPACE DONE · ENTER OPEN · ESC"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: 0.8
                }
            }
            Rectangle { width: parent.width; height: 1; color: root.theme.divider }
            Item { width: 1; height: 4 }   // spacer

            // ---- LATE (overdue) ----
            SectionHead {
                visible: root.lateItems.length > 0
                label: "Late"; count: root.lateItems.length; tint: root.theme.accent
            }
            Repeater {
                model: root.lateItems
                delegate: DlRow {
                    required property var modelData
                    required property int index
                    item: modelData
                    idx: index
                    late: true
                }
            }

            // ---- TODAY (due today) ----
            SectionHead {
                visible: root.todayItems.length > 0
                label: "Today"; count: root.todayItems.length; tint: root.theme.textDim
            }
            Repeater {
                model: root.todayItems
                delegate: DlRow {
                    required property var modelData
                    required property int index
                    item: modelData
                    idx: root.lateItems.length + index
                }
            }

            // ---- AHEAD (upcoming, capped) ----
            SectionHead {
                visible: root.aheadItems.length > 0
                label: "Ahead"; count: root.aheadAll.length; tint: root.theme.faint
            }
            Repeater {
                model: root.aheadItems
                delegate: DlRow {
                    required property var modelData
                    required property int index
                    item: modelData
                    idx: root.lateItems.length + root.todayItems.length + index
                }
            }
            Text {
                visible: root.aheadMore > 0
                leftPadding: 4; topPadding: 4
                text: "+" + root.aheadMore + " more"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
            }

            // ---- empty state: nothing due/overdue (ahead may still list above) ----
            Item { visible: root.nothingDue; width: 1; height: 4 }
            Rectangle {
                visible: root.nothingDue
                width: parent.width
                height: emptyCol.implicitHeight + 16
                radius: root.theme.radiusBtn
                color: root.theme.row
                Column {
                    id: emptyCol
                    anchors.left: parent.left; anchors.leftMargin: 12
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        text: "EMPTY STATE"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: root.aheadAll.length > 0
                            ? ("Nothing due. Next deadline " + root.fmtDate(root.aheadAll[0].date) + ".")
                            : "Nothing due."
                        color: root.theme.textDim
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                }
            }
        }
    }
}
