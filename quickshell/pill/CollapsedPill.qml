pragma ComponentBehavior: Bound
// CollapsedPill.qml — the collapsed pill: the hh:mm clock plus camera/screen
// privacy indicators that pop in (OutBack scale + animated slot width so the clock
// slides over) while live. `solid` (a live camera/recording) shows the clock at
// full opacity. Screen recording is a bold red dot that emits a fading ring once
// every 5s (a recording "pulse").
import QtQuick
import Quickshell
import Quickshell.Widgets

// A vertical stack: the clock row (clock + notification/privacy glyphs) on top,
// and — only when an org DEADLINE is due or overdue — a compact under-line
// beneath it ("⚑ 3 LATE · 2 TODAY"). The under-line grows the pill and shrinks
// the clock 2px; clicking it (or right-clicking the pill) opens the deadlines
// popup (see deadlinesActivated / AgendaMenu.qml).
Column {
    id: root
    required property var theme
    property string clock: ""
    property bool solid: false          // privacy-rest: clock at full opacity
    property bool cameraOn: false
    property bool recordingOn: false    // screen being shared/recorded
    property bool hasUnread: false      // un-cleared notifications waiting in history
    property bool dnd: false            // do-not-disturb: dot instead of the app strip
    // grouped history (one entry per app: { app, items:[Notification,…] }, newest
    // app first) → the resting app-icon glance strip. `iconsMax` caps how many app
    // icons show before a "+N" overflow chip.
    property var notifGroups: []
    property int iconsMax: 4
    // org-deadline watch (from OrgAgenda): overdue ("late") and due-today counts.
    // The under-line shows only while one of these is non-zero.
    property int lateCount: 0
    property int todayCount: 0
    readonly property bool hasDue: lateCount > 0 || todayCount > 0
    // imminent-meeting watch (from CalendarEvents): minutes until the next meeting
    // starting within 10 min, or -1 when none. Shown in the same under-line, in the
    // urgent style, next to the deadline counts.
    property int meetingMins: -1
    readonly property bool hasMeeting: meetingMins >= 0
    // the under-line is present whenever there's a deadline OR an imminent meeting.
    readonly property bool hasUnderline: hasDue || hasMeeting
    // the under-line was clicked (open the full deadlines list).
    signal deadlinesActivated()

    spacing: 2

    // ---- clock row: hh:mm clock + notification / privacy glyphs (the original
    // resting layout, unchanged apart from the 2px clock shrink while due) ----
    Row {
    id: clockRow
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 6
    // unread-notifications dot (left of the clock): a small filled accent circle
    // while notifications sit un-cleared in history. Normally the per-app icon
    // strip (right of the clock) conveys this, so the dot is only a *fallback*
    // shown in do-not-disturb (auto-on during a screencast) — when the app-icon
    // strip is hidden to avoid revealing notification sources. Slides in/out like
    // the privacy icons (animated slot width).
    Item {
        readonly property bool showDot: root.hasUnread && root.dnd
        anchors.verticalCenter: parent.verticalCenter
        width: showDot ? 6 : 0
        height: 6
        visible: width > 0 || dot.opacity > 0   // stay alive through the shrink-out
        Behavior on width { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
        Rectangle {
            id: dot
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            // same colour + translucency as the clock: full opacity when the pill
            // is solid (privacy-rest), otherwise the clock's 0.78 alpha.
            color: root.solid ? root.theme.text
                 : Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.78)
            opacity: parent.showDot ? 1 : 0
            scale: parent.showDot ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
            Behavior on scale  { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.clock
        // full opacity while a camera/recording is live (the pill is solid then);
        // otherwise slightly translucent so the floating pill reveals a hint of
        // what's behind it (readable on any backdrop)
        color: root.solid ? root.theme.text
             : Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.78)
        font.family: root.theme.serif
        // shrink 2px while the under-line shows, so the two lines fit the
        // resting pill without it feeling cramped.
        font.pixelSize: root.theme.fsLarge - (root.hasUnderline ? 2 : 0)
    }
    // ---- notification app-icon strip: one icon per app that has un-cleared
    // notifications (deduped via notifGroups, newest app first), so a glance shows
    // *which* apps are waiting. Sits right of the clock, before the privacy
    // (recording / camera) indicators. Hidden in do-not-disturb (auto-on during a
    // screencast) so a sensitive share doesn't reveal notification sources — the
    // fallback unread dot covers that case instead; dropping DND brings the icons
    // back. Capped at `iconsMax` with a "+N" overflow chip.
    Row {
        id: appStrip
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        // left-pad from the clock only when there's actually something to show
        leftPadding: shown.length > 0 ? 2 : 0
        readonly property var shown: root.dnd
            ? [] : root.notifGroups.slice(0, root.iconsMax)
        readonly property int overflow: root.dnd
            ? 0 : Math.max(0, root.notifGroups.length - root.iconsMax)

        Repeater {
            model: appStrip.shown
            delegate: Item {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14
                IconImage {
                    id: appImg
                    anchors.centerIn: parent
                    implicitSize: 14
                    // reuse the history card's resolution: an absolute-path appIcon
                    // (notify-send -i /path) loads as a file:// URL; icon *names* go
                    // through the theme lookup, with a generic fallback.
                    source: {
                        const items = parent.modelData.items;
                        const n = (items && items.length) ? items[0] : null;
                        const ic = n ? (n.appIcon || "") : "";
                        if (ic.indexOf("file:") === 0) return ic;
                        if (ic.indexOf("/") === 0) return "file://" + ic;
                        return Quickshell.iconPath(ic, "dialog-information");
                    }
                    opacity: root.solid ? 1 : 0.85
                    scale: 1
                    // pop-in when a new app first appears in the strip
                    Component.onCompleted: { appImg.scale = 0.4; appImg.scale = 1; }
                    Behavior on scale { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
                }
            }
        }
        // overflow chip: "+N" when more apps are waiting than fit
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: appStrip.overflow > 0
            text: "+" + appStrip.overflow
            color: root.solid ? root.theme.text
                 : Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.78)
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
        }
    }
    // screen-recording indicator — a bold red dot that pulses (emits a fading,
    // expanding ring) once every 5s while the screen is being shared/recorded.
    // Same pop-in / shrink-out slot behaviour as the camera glyph so the
    // clock slides over when it appears/disappears.
    Item {
        id: recSlot
        anchors.verticalCenter: parent.verticalCenter
        width: root.recordingOn ? 14 : 0
        height: 14
        visible: width > 0 || recDot.opacity > 0   // stay alive through the shrink-out
        Behavior on width { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }

        // radiating pulse ring — one expand+fade per 5s cycle (1.5s pulse, 3.5s rest)
        Rectangle {
            id: recRing
            anchors.centerIn: recDot
            width: recDot.width
            height: recDot.height
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.theme.danger
            opacity: 0
            SequentialAnimation {
                running: root.recordingOn
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: recRing; property: "scale"; from: 0.9; to: 2.6; duration: 1500; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        NumberAnimation { target: recRing; property: "opacity"; from: 0; to: 0.55; duration: 250 }
                        NumberAnimation { target: recRing; property: "opacity"; from: 0.55; to: 0; duration: 1250; easing.type: Easing.InCubic }
                    }
                }
                PauseAnimation { duration: 3500 }
            }
        }
        // the dot itself — pops in / shrinks out like the other privacy indicators
        Rectangle {
            id: recDot
            anchors.centerIn: parent
            width: 12
            height: 12
            radius: 6
            color: root.theme.danger
            opacity: root.recordingOn ? 1 : 0
            scale: root.recordingOn ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
            Behavior on scale  { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
        }
    }
    // camera indicator — static model so the delegate persists (a reactive
    // model would rebuild and skip the animation); it reads its live state directly.
    Repeater {
        model: [
            { ic: "videocam", col: root.theme.good }
        ]
        delegate: Item {
            id: privIcon
            required property int index
            required property var modelData
            readonly property bool on: root.cameraOn
            anchors.verticalCenter: parent.verticalCenter
            width: privIcon.on ? 15 : 0
            height: 15
            visible: width > 0 || privImg.opacity > 0   // stay alive through the shrink-out
            Behavior on width { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
            MSym {
                id: privImg
                anchors.centerIn: parent
                icon: privIcon.modelData.ic
                size: 15
                fill: 1
                weight: 500
                color: privIcon.modelData.col
                opacity: privIcon.on ? 1 : 0
                scale: privIcon.on ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
                Behavior on scale  { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
            }
        }
    }
    } // clockRow

    // ---- under-line: "⚑ N LATE · M TODAY · 🗓 K MIN TO MEETING" beneath the clock.
    // Present only when a deadline is due/overdue OR a meeting is imminent (takes no
    // vertical space otherwise, so the resting pill stays a plain clock). The flag +
    // "LATE" and the meeting notice glow accent (urgent); "TODAY" stays muted.
    // Clicking anywhere on it opens the deadlines popup (right-clicking the whole
    // pill does the same, wired in init.qml).
    Item {
        id: dueLine
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.hasUnderline
        implicitWidth: dueRow.implicitWidth
        implicitHeight: root.hasUnderline ? dueRow.implicitHeight : 0
        width: implicitWidth
        height: implicitHeight

        Row {
            id: dueRow
            anchors.centerIn: parent
            spacing: 5

            MSym {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasDue
                icon: "flag"
                size: 12
                fill: 1
                weight: 600
                // accent (alarm) while overdue, muted when only due-today items remain
                color: root.lateCount > 0 ? root.theme.accent : root.theme.textDim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.lateCount > 0
                text: root.lateCount + " LATE"
                color: root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.lateCount > 0 && root.todayCount > 0
                text: "·"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.todayCount > 0
                // "N DUE TODAY" on its own, but just "N TODAY" once "N LATE"
                // already carries the "due" sense to its left (matches the spec).
                text: root.todayCount + (root.lateCount > 0 ? " TODAY" : " DUE TODAY")
                color: root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            // separator before the meeting notice, only when a deadline count sits
            // to its left.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasMeeting && root.hasDue
                text: "·"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
            }
            // ---- imminent-meeting notice (urgent style): a calendar icon + "K MIN
            // TO MEETING" (or "MEETING NOW" at zero). Shown whenever a meeting starts
            // within the next 10 minutes.
            MSym {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasMeeting
                icon: "event_upcoming"
                size: 12
                fill: 1
                weight: 600
                color: root.theme.accent
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasMeeting
                text: root.meetingMins === 0 ? "MEETING NOW"
                    : root.meetingMins + " MIN TO MEETING"
                color: root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
        }
        // click the message to open the full deadlines list. z lifts it above the
        // pill's resting focus MouseArea (CollapsedPill is stacked over it in
        // init.qml, so only this rectangle intercepts — the clock passes through).
        MouseArea {
            anchors.fill: parent
            z: 5
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.deadlinesActivated()
        }
    }
}
