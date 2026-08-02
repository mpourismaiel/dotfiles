pragma ComponentBehavior: Bound
// NotificationStack.qml — the active notifications as a deck. At rest the newest
// card is on top and the rest peek out below it (offset + scaled back); hovering
// the stack drops them into a full vertical list and sets `notifs.held` so every
// card pauses + resets its countdown. `implicitHeight` reports the laid-out
// height (deck vs expanded) so the pill can size to it. Reused for the collapsed-
// pill morph and the floating stack under an open pill.
import QtQuick

Item {
    id: stack
    required property var theme
    required property var notifs

    readonly property bool expanded: hover.hovered
    readonly property int peek: 14            // px each resting card peeks below the top one
    readonly property int gap: 8              // px between cards when expanded
    readonly property int maxDeck: 4          // how many cards are visible at rest
    readonly property int headroom: 0
    // the cards keep a fixed width; when there's a stack (>1 popup) a gutter holds
    // a "dismiss all" pill to the *right* of the cards. We pad BOTH sides by the
    // same amount (the left gutter is empty/transparent) so the cards stay centred
    // in the centred pill — the stack widening for the button must not shift them.
    // The gutter is inside the stack's own width, so the morph pill (sized to this)
    // doesn't clip the button and the input mask still covers it.
    readonly property int cardWidth: 420
    // the right gutter is sized to hold the "dismiss all" pill fully clear of the
    // card (its width + a gap), so it never overlaps the notification.
    readonly property int dismissRail: rep.count > 1 ? Math.ceil(dismissAll.width) + 16 : 0

    width: cardWidth + dismissRail * 2
    implicitWidth: cardWidth + dismissRail * 2
    height: implicitHeight

    // bumped whenever a card's height changes, to recompute the layout reactively
    property int relayout: 0

    readonly property real collapsedH: {
        stack.relayout;
        const it = rep.itemAt(0);
        const base = it ? it.implicitHeight : 0;
        return base + Math.max(0, Math.min(rep.count, stack.maxDeck) - 1) * stack.peek;
    }
    // the top (newest) card's footprint — the NotificationDroplet expands into this
    // so the droplet's final rectangle matches the card it becomes.
    readonly property real topCardWidth: cardWidth
    readonly property real topCardHeight: {
        stack.relayout;
        const it = rep.itemAt(0);
        return it ? it.implicitHeight : 0;
    }
    readonly property real expandedH: {
        stack.relayout;
        let yy = 0;
        for (let j = 0; j < rep.count; j++) {
            const it = rep.itemAt(j);
            yy += (it ? it.implicitHeight : 0);
        }
        return yy + Math.max(0, rep.count - 1) * stack.gap;
    }
    implicitHeight: (expanded ? expandedH : collapsedH) + headroom
    Behavior on implicitHeight { NumberAnimation { duration: stack.theme.anim; easing.type: Easing.OutCubic } }

    HoverHandler { id: hover; onHoveredChanged: stack.notifs.hold(hover.hovered) }

    Repeater {
        id: rep
        model: stack.notifs.active
        delegate: NotificationView {
            id: card
            required property int index
            required property var modelData
            theme: stack.theme
            notifs: stack.notifs
            notification: modelData
            showProgress: true
            x: stack.dismissRail          // centred: equal gutter on each side
            width: stack.cardWidth

            onImplicitHeightChanged: stack.relayout++

            readonly property real expandedY: {
                stack.relayout;
                let yy = 0;
                for (let j = 0; j < index; j++) {
                    const it = rep.itemAt(j);
                    yy += (it ? it.implicitHeight : 0) + stack.gap;
                }
                return yy;
            }
            y: stack.headroom + (stack.expanded ? expandedY : index * stack.peek)
            z: rep.count - index                 // newest (0) on top
            transformOrigin: Item.Top
            scale: stack.expanded ? 1 : Math.max(0.9, 1 - index * 0.04)
            opacity: stack.expanded ? 1 : (index < stack.maxDeck ? Math.max(0, 1 - index * 0.22) : 0)
            visible: stack.expanded || index < stack.maxDeck

            Behavior on y       { NumberAnimation { duration: stack.theme.anim; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: stack.theme.anim; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: stack.theme.animFast } }
        }
    }

    // "dismiss all" pill — sits in the right gutter, beside the top card (aligned
    // with its close-X row), whenever there's a stack (>1 popup); clears the whole
    // popup deck at once (history is kept, exactly like dismissing each card's X).
    Rectangle {
        id: dismissAll
        visible: rep.count > 1
        z: 10000
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 0            // aligned with the top card's top edge
        height: 26
        width: dismissRow.implicitWidth + 20
        radius: height / 2
        color: dismissMa.containsMouse ? stack.theme.danger : stack.theme.bg
        border.color: stack.theme.border
        border.width: 1
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: stack.theme.animFast } }
        Row {
            id: dismissRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Dismiss all"
                color: dismissMa.containsMouse ? "#ffffff" : stack.theme.textDim
                font.family: stack.theme.mono
                font.pixelSize: stack.theme.fsSmall
                font.letterSpacing: stack.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            MSym {
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                size: 15
                color: dismissMa.containsMouse ? "#ffffff" : stack.theme.faint
            }
        }
        MouseArea {
            id: dismissMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: stack.notifs.dismissAll()
        }
    }
}
