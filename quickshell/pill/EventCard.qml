pragma ComponentBehavior: Bound
// EventCard.qml — one calendar-event card, extracted from CalendarMenu so the same
// full-functionality card (imminent banner, per-calendar colour bar, expand-to-detail
// with location / description / guests / a Join button) can be reused in the agenda
// popup (AgendaMenu.qml). Caller sets `width`, hands it `modelData` (a normalized
// CalendarEvents event), a ticking `nowMs` (drives the imminent / past states) and
// `showAccount` (true when more than one account is signed in, so the card labels
// which calendar it came from).
import QtQuick

Column {
    id: root
    required property var theme
    required property var modelData
    property double nowMs: 0
    property bool showAccount: false
    property bool dimmed: false          // caller faded this card back (e.g. AHEAD section)

    spacing: 4
    // a fully-past event (now beyond its end) dims wholesale — colour bar, times,
    // title, description all fade together; `dimmed` layers a section-level fade on top.
    opacity: (root.past ? 0.45 : 1) * (root.dimmed ? 0.55 : 1)
    Behavior on opacity { NumberAnimation { duration: root.theme.anim } }
    property bool expanded: false
    // is there anything worth expanding into?
    readonly property bool hasDetail: !!(root.modelData.description
        || root.modelData.location || root.modelData.joinLink
        || (root.modelData.attendees && root.modelData.attendees.length))
    readonly property color barColor: (root.modelData.color
        && ("" + root.modelData.color).length)
        ? root.modelData.color : root.theme.event

    // minutes until this timed event starts (negative once it has started); 9999
    // for all-day / undated so they never nag
    readonly property int minsToStart: {
        if (root.modelData.allDay || !root.modelData.startTime)
            return 9999;
        var p = ("" + root.modelData.startKey).split("-");
        var t = ("" + root.modelData.startTime).split(":");
        var start = new Date(+p[0], +p[1] - 1, +p[2],
                             +t[0], +t[1], 0).getTime();
        return Math.round((start - root.nowMs) / 60000);
    }
    // "imminent": from 10 min before the start until 5 min after it
    readonly property bool imminent: root.minsToStart <= 10
                                  && root.minsToStart >= -5
    readonly property string imminentLabel:
          root.minsToStart > 0 ? ("Starts in " + root.minsToStart + " min")
        : root.minsToStart === 0 ? "Starting now"
        : ("Started " + (-root.minsToStart) + " min ago")

    // wall-clock (ms) of the event's end; a "past" event is one now beyond it.
    // All-day: end key is the exclusive next-day date, so it turns past at midnight.
    readonly property double endMs: {
        var p = ("" + root.modelData.endKey).split("-");
        if (root.modelData.allDay)
            return new Date(+p[0], +p[1] - 1, +p[2], 0, 0, 0).getTime();
        var et = root.modelData.endTime || root.modelData.startTime;
        if (!et) return NaN;
        var t = ("" + et).split(":");
        return new Date(+p[0], +p[1] - 1, +p[2], +t[0], +t[1], 0).getTime();
    }
    readonly property bool past: !isNaN(root.endMs) && root.nowMs > root.endMs

    // the time range shown in the header ("All day", "09:00", or "09:00 – 09:30")
    readonly property string timeLabel: root.modelData.allDay ? "All day"
        : (root.modelData.startTime
           + (root.modelData.endTime && root.modelData.endTime !== root.modelData.startTime
              ? " – " + root.modelData.endTime : ""))
    // a finished event collapses to a single struck-through "time  title" line (no
    // account/detail); expanding it restores the normal full card.
    readonly property bool compact: root.past && !root.expanded

    // imminent-meeting banner — makes the current / next-up event unmistakable
    Rectangle {
        visible: root.imminent
        width: root.width
        height: visible ? bannerRow.implicitHeight + 10 : 0
        radius: root.theme.radiusSmall
        color: root.theme.accentSoft
        border.width: 1
        border.color: root.theme.accent
        Row {
            id: bannerRow
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            MSym {
                icon: "notifications_active"
                size: 14
                fill: 1
                color: root.theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.imminentLabel
                color: root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // header row — click toggles expansion
    MouseArea {
        id: hdrMa
        width: root.width
        height: hdrRow.implicitHeight
        hoverEnabled: true
        cursorShape: root.hasDetail ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.hasDetail) root.expanded = !root.expanded
        Row {
            id: hdrRow
            width: hdrMa.width
            spacing: 8
            // per-calendar colour bar
            Rectangle {
                width: 3
                height: hdrCol.height
                radius: 1.5
                color: root.barColor
            }
            Column {
                id: hdrCol
                width: root.width - 3 - 16 - (root.hasDetail ? 24 : 0)
                spacing: 1
                // ---- finished + collapsed: one struck-through "time  title" line ----
                Text {
                    visible: root.compact
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.timeLabel + "  " + root.modelData.summary
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                    font.strikeout: true
                }
                // ---- normal layout: time line, title, account ----
                Text {
                    visible: !root.compact
                    text: root.timeLabel
                    color: root.theme.event
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Text {
                    visible: !root.compact
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.modelData.summary
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                }
                // which calendar/account (only useful with >1 account)
                Text {
                    visible: !root.compact && root.showAccount
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.modelData.calendar || root.modelData.account
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall - 1
                }
            }
            // chevron (only when there's detail)
            Item {
                width: root.hasDetail ? 24 : 0
                height: 24
                visible: root.hasDetail
                MSym {
                    anchors.centerIn: parent
                    icon: "expand_more"
                    size: 18
                    color: root.theme.textDim
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: root.theme.anim } }
                }
            }
        }
    }

    // detail — animated open/close
    Item {
        width: root.width
        height: root.expanded ? detailCol.implicitHeight : 0
        clip: true
        opacity: root.expanded ? 1 : 0
        Behavior on height { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
        Column {
            id: detailCol
            width: parent.width
            spacing: 6

            // location
            Row {
                visible: !!root.modelData.location
                width: detailCol.width
                spacing: 6
                MSym {
                    icon: "place"
                    size: 14
                    color: root.theme.faint
                    anchors.top: parent.top
                    anchors.topMargin: 1
                }
                Text {
                    width: detailCol.width - 20
                    wrapMode: Text.WordWrap
                    text: root.modelData.location
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsSmall
                }
            }
            // description
            Text {
                visible: !!root.modelData.description
                width: detailCol.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.modelData.description
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }
            // guests
            Column {
                visible: !!(root.modelData.attendees
                         && root.modelData.attendees.length > 0)
                width: detailCol.width
                spacing: 3
                Text {
                    text: "Guests"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall - 1
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Repeater {
                    model: root.modelData.attendees
                    delegate: Row {
                        id: att
                        required property var modelData
                        width: detailCol.width
                        spacing: 6
                        // response status dot
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: att.modelData.response === "accepted" ? root.theme.good
                                 : att.modelData.response === "declined" ? root.theme.danger
                                 : att.modelData.response === "tentative" ? root.theme.money
                                 : root.theme.faint
                        }
                        Text {
                            width: detailCol.width - 12
                            elide: Text.ElideRight
                            text: att.modelData.name
                                + (att.modelData.self ? " (you)" : "")
                            color: root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }
            }
            // join button → opens the meeting link in the browser
            Rectangle {
                visible: !!root.modelData.joinLink
                width: joinRow.implicitWidth + 22
                height: 26
                radius: root.theme.radiusBtn
                color: joinMa.containsMouse ? root.theme.event : root.theme.row
                border.width: 1
                border.color: root.theme.event
                Row {
                    id: joinRow
                    anchors.centerIn: parent
                    spacing: 6
                    MSym {
                        icon: "videocam"
                        size: 15
                        color: joinMa.containsMouse ? root.theme.bg : root.theme.event
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Join"
                        color: joinMa.containsMouse ? root.theme.bg : root.theme.event
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: joinMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(root.modelData.joinLink)
                }
                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }
        }
    }
}
