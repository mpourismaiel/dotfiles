pragma ComponentBehavior: Bound
// AgendaMenu.qml — the floating "Agenda" list, opened by right-clicking the resting
// pill or clicking its under-line. Like AppMenu it is a full-overlay Item
// (anchors.fill your host) with an outside-click backdrop; the panel drops from
// (px,py) just below the pill and is clamped to stay on screen. It shows two things:
// the org deadline buckets from OrgAgenda — overdue ("LATE") first, then due-today
// ("TODAY"), then upcoming ("AHEAD"), each with a checkbox to tick done and a click
// to open it in Emacs — and, below them, the calendar events from CalendarEvents that
// have not yet ended (each a full EventCard, same as the calendar menu). Keyboard:
// ↑/↓ move, Space ticks done, Enter opens, Esc closes (the pill grabs the keyboard
// while `open`, wired via win.deadlines in init.qml); keys drive the deadline rows,
// while events are mouse-driven (expand / Join) like in the calendar.
import QtQuick
import Quickshell

Item {
    id: root
    required property var theme
    required property var org             // OrgAgenda instance (deadline buckets + actions)
    property var cal: null                // CalendarEvents instance (upcoming events); may be null
    property bool open: false
    property real px: 0                   // requested top-left, in this overlay's coords
    property real py: 0
    property int  bodyMax: 460            // scroll the sections past this height
    property real dimAlpha: 0.55          // how much the AHEAD section is faded back
    signal dismissed()                    // backdrop / Esc / after opening an item

    anchors.fill: parent
    visible: open
    focus: open
    z: 1000

    // ---- deadline buckets (from OrgAgenda), by delta (days from today) ----
    readonly property var lateItems:  org ? org.lateItems  : []   // < 0  (due before today)
    readonly property var todayItems: org ? org.todayItems : []   // = 0  (due today)
    readonly property var aheadAll:   org ? org.aheadItems : []   // > 0  (due later)
    // The AHEAD section leads with EVERY #A-priority upcoming task (tomorrow or any
    // day after) so high-priority work is unmissable, then lists what's due *tomorrow*
    // (excluding those #A ones, so they aren't shown twice). aheadAll is already sorted
    // nearest-first, so the filters keep that order.
    readonly property var aheadPriority: aheadAll.filter(function (d) { return d.priority === "A"; })
    readonly property var tomorrowTasks: aheadAll.filter(function (d) { return d.delta === 1 && d.priority !== "A"; })
    // flat, in keyboard display order — the cursor walks this; each section's rows
    // offset into it by the lengths before them. (Events are mouse-only, not here.)
    readonly property var flat: lateItems.concat(todayItems, aheadPriority, tomorrowTasks)
    property int sel: 0

    // ---- events for today / tomorrow (interleaved into those sections) ----
    // reactive day keys (follow cal.nowMs so they roll over on their own)
    readonly property var _now: (cal && cal.nowMs > 0) ? new Date(cal.nowMs) : new Date()
    readonly property string todayKey: Qt.formatDate(root._now, "yyyy-MM-dd")
    readonly property string tomorrowKey: {
        var d = new Date(root._now.getTime()); d.setDate(d.getDate() + 1);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }
    readonly property var todayEvents:    (cal && cal.dayEvents) ? cal.dayEvents(root.todayKey)    : []
    readonly property var tomorrowEvents: (cal && cal.dayEvents) ? cal.dayEvents(root.tomorrowKey) : []
    readonly property bool showAccount: !!(cal && cal.accounts && cal.accounts.length > 1)
    // section presence
    readonly property bool hasToday: todayEvents.length > 0 || todayItems.length > 0
    readonly property bool hasAhead: aheadPriority.length > 0 || tomorrowEvents.length > 0 || tomorrowTasks.length > 0
    // nothing at all across every section
    readonly property bool whollyEmpty: lateItems.length === 0 && !hasToday && !hasAhead

    // entrance: a water droplet wells out of the pill's bottom lip and *expands into*
    // the panel footprint (the same effect notifications use), then the panel content
    // fades in over the expanded rect on `landed()`. `contentIn` gates that fade; a
    // fallback timer reveals it even if the droplet is skipped.
    property int dropGap: 8               // pill-to-panel offset (matches py in init)
    property bool contentIn: false
    Timer { id: cardFallback; interval: 640; onTriggered: root.contentIn = true }

    onOpenChanged: {
        if (open) {
            sel = 0;
            if (org && org.loadDeadlines) org.loadDeadlines();   // freshen on open
            if (cal && cal.read) cal.read();                     // freshen events (cache, no net)
            contentIn = false;
            cardFallback.restart();
            drop.play();
            forceActiveFocus();
        } else {
            contentIn = false;
            cardFallback.stop();
            drop.reset();
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

    // ---- one deadline row: checkbox · heading · trailing #A chip + date/overdue ----
    component DlRow: Rectangle {
        id: dr
        required property var item
        required property int idx        // global index into root.flat
        property bool late: false        // overdue styling (accent tint + border)
        property bool hot: false         // #A high-priority: accent tint + "A" chip, never dimmed
        property bool dim: false         // faded-back (the rest of the AHEAD section)
        width: sectionsCol.width
        height: 30
        radius: root.theme.radiusBtn
        // #A rows stay fully lit; other AHEAD rows fade back a touch.
        opacity: dr.dim ? root.dimAlpha : 1
        // selected row wins; else a faint accent wash for overdue / #A rows, flat otherwise
        color: root.sel === idx ? root.theme.rowHi
             : (late || hot) ? root.theme.accentSoft : "transparent"

        Rectangle {                       // checkbox
            id: box
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 15; radius: 4
            color: "transparent"
            border.width: 1.5
            border.color: boxMa.containsMouse ? root.theme.accent
                        : (dr.late || dr.hot) ? root.theme.accent : root.theme.faint
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
            anchors.right: trail.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: dr.item ? dr.item.text : ""
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }
        Row {
            id: trail
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            // solid accent "A" chip, so a high-priority item reads at a glance
            Rectangle {
                visible: dr.hot
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 4
                color: root.theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "A"
                    color: root.theme.bg
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall - 1
                    font.bold: true
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // overdue → "-9d" (days late); dated → weekday+day ("Sat 1")
                text: dr.late ? (dr.item.delta + "d") : root.fmtDate(dr.item ? dr.item.date : "")
                color: (dr.late || dr.hot) ? root.theme.accent : root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
            }
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
        width: sectionsCol.width
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

    // a group of full EventCards (a day's events), interleaved into a section above
    // its tasks. `dimmed` fades the whole group back (the AHEAD section).
    component EvGroup: Column {
        id: eg
        property var items: []
        property bool dimmed: false
        visible: eg.items.length > 0
        width: sectionsCol.width
        spacing: 10
        topPadding: eg.items.length > 0 ? 4 : 0
        bottomPadding: eg.items.length > 0 ? 2 : 0
        Repeater {
            model: eg.items
            delegate: EventCard {
                theme: root.theme
                width: eg.width
                nowMs: root.cal ? root.cal.nowMs : 0
                showAccount: root.showAccount
                dimmed: eg.dimmed
            }
        }
    }

    // ---- entrance droplet: wells out of the pill lip and expands into the panel
    //      footprint (rendered behind the panel; the panel fades in over it) ----
    NotificationDroplet {
        id: drop
        x: panel.x
        width: panel.width
        y: panel.y - root.dropGap
        height: root.dropGap
        theme: root.theme
        fallDistance: root.dropGap
        cardWidth: panel.width
        cardHeight: panel.height
        cardRadius: root.theme.radiusCard
        bgColor: root.theme.bg
        accentColor: root.theme.accent
        // land on the same surface the launcher / expanded pill use (theme.bg)
        cardColor: root.theme.bg
        onLanded: root.contentIn = true
    }

    // ---- the panel ----
    Rectangle {
        id: panel
        x: Math.max(8, Math.min(root.px, root.width - width - 8))
        y: Math.max(8, Math.min(root.py, root.height - height - 8))
        width: 400
        height: panelCol.implicitHeight + root.theme.pad * 2
        radius: root.theme.radiusCard
        // same surface as the launcher / expanded pill (PillSurface uses theme.bg)
        color: root.theme.bg
        border.color: root.theme.border
        border.width: 1

        // the droplet grows the rect; the panel content just fades in over it, after a
        // short lead pause so the accent rect finishes expanding before content resolves
        // (the rect reads as *becoming* the panel — no scale, which would fight it).
        opacity: root.contentIn ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic }
            }
        }

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
                    text: "AGENDA"
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

            // sections scroll as a group once they exceed bodyMax (deadlines + events
            // can get long); the title/hint header above stays pinned.
            Flickable {
                id: bodyFlick
                width: parent.width
                height: Math.min(sectionsCol.implicitHeight, root.bodyMax)
                contentHeight: sectionsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: sectionsCol
                    width: bodyFlick.width
                    spacing: 2

                    // ==== OVERDUE — only tasks due before today ====
                    SectionHead {
                        visible: root.lateItems.length > 0
                        label: "Overdue"; count: root.lateItems.length; tint: root.theme.accent
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

                    // ==== TODAY — today's events, then tasks due today ====
                    Item { visible: root.hasToday; width: 1; height: 4 }
                    SectionHead {
                        visible: root.hasToday
                        label: "Today"
                        count: root.todayEvents.length + root.todayItems.length
                        tint: root.theme.textDim
                    }
                    EvGroup { items: root.todayEvents }
                    Repeater {
                        model: root.todayItems
                        delegate: DlRow {
                            required property var modelData
                            required property int index
                            item: modelData
                            idx: root.lateItems.length + index
                        }
                    }

                    // ==== AHEAD (dimmed) — #A priorities first (lit), then tomorrow's
                    //      events, then tasks due tomorrow ====
                    Item { visible: root.hasAhead; width: 1; height: 4 }
                    SectionHead {
                        visible: root.hasAhead
                        opacity: root.dimAlpha
                        label: "Ahead"
                        count: root.aheadPriority.length + root.tomorrowEvents.length + root.tomorrowTasks.length
                        tint: root.theme.faint
                    }
                    // #A high-priority upcoming tasks (any day) — pulled to the top, lit
                    Repeater {
                        model: root.aheadPriority
                        delegate: DlRow {
                            required property var modelData
                            required property int index
                            item: modelData
                            idx: root.lateItems.length + root.todayItems.length + index
                            hot: true
                        }
                    }
                    // tomorrow's events, faded back with the rest of AHEAD
                    EvGroup { items: root.tomorrowEvents; dimmed: true }
                    // tasks due tomorrow (excluding the #A ones shown above), faded back
                    Repeater {
                        model: root.tomorrowTasks
                        delegate: DlRow {
                            required property var modelData
                            required property int index
                            item: modelData
                            idx: root.lateItems.length + root.todayItems.length
                                 + root.aheadPriority.length + index
                            dim: true
                        }
                    }

                    // ---- empty state: nothing on the agenda at all ----
                    Item { visible: root.whollyEmpty; width: 1; height: 4 }
                    Rectangle {
                        visible: root.whollyEmpty
                        width: sectionsCol.width
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
                                text: "Nothing on your agenda."
                                color: root.theme.textDim
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsNormal
                            }
                        }
                    }
                }
            }
        }
    }
}
