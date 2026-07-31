pragma ComponentBehavior: Bound
// NotificationHistory.qml — notification history pane. Notifications are grouped
// by app (newest-first within each group; a group floats to the top when it gets
// a fresh notification), each rendered as a NotificationView row. "Clear all"
// empties the history. Opened from the Row-2 notification status icon or the
// `notifications` IPC shortcut.
//
// Keyboard triage (the pane grabs the keyboard when open — see init.qml
// `grabsKeyboard`): the pane keeps ONE flat selection across all groups (`sel`,
// -1 = nothing focused). Up/Down move the selection; Left/Right focus the selected
// card's action buttons (`actionSel`, -1 = none, the default); Enter triggers the
// focused action, or — with no action focused — opens the notification (its
// `default` action, exactly like clicking the card); `i` focuses the inline-reply
// field (Telegram &c.); `x`/Delete forget the selected card. Escape steps back one
// level: an focused action/reply first returns focus to the card, then a second
// Escape (card or nothing focused) closes the pane. While the reply field holds
// focus the letter/Delete keys type into it (they never reach this handler).
import QtQuick

Item {
    id: root
    required property var theme
    required property var notifs
    signal closeRequested()

    // the pane is (re)created each time it opens; refresh the grouping then grab
    // keyboard focus so arrow-key navigation works from the first keystroke.
    Component.onCompleted: {
        if (root.notifs) root.notifs.rebuild();
        keyHandler.forceActiveFocus();
    }

    // ---- keyboard navigation state ------------------------------------------
    // A flat list of every notification in display order (group by group, newest
    // first within each), so one index walks the whole pane regardless of grouping.
    readonly property var flat: {
        const out = [];
        for (const g of (root.notifs ? root.notifs.grouped : []))
            for (const n of g.items) out.push(n);
        return out;
    }
    property int sel: -1                    // index into `flat`; -1 = nothing focused
    property int actionSel: -1              // index into selActions; -1 = none (default)
    property bool replyFocused: false       // the selected card's reply field has focus
    readonly property var selNotif: (root.sel >= 0 && root.sel < root.flat.length) ? root.flat[root.sel] : null
    // the selected card's non-default actions (Left/Right walk these; Enter fires one)
    readonly property var selActions: {
        const n = root.selNotif;
        if (!n) return [];
        return (n.actions || []).filter(a => a && a.identifier !== "default");
    }

    // move the selection (d = ±1); a fresh move drops any focused action
    function moveSel(d) {
        const n = root.flat.length;
        if (n === 0) { root.sel = -1; return; }
        let i = root.sel < 0 ? 0 : Math.max(0, Math.min(n - 1, root.sel + d));
        root.sel = i;
        root.actionSel = -1;
    }
    // Enter: fire the focused action, else open the notification (its `default`
    // action) exactly like clicking the card; drop it from the active popup stack
    // (the history copy stays — matches the card's own click handlers).
    function activateSel() {
        const n = root.selNotif;
        if (!n) return;
        if (root.actionSel >= 0) {
            const a = root.selActions[root.actionSel];
            if (a) { a.invoke(); root.notifs.drop(n); }
            return;
        }
        for (const a of (n.actions || []))
            if (a && a.identifier === "default") { a.invoke(); root.notifs.drop(n); return; }
    }
    // x / Delete: forget the selected card; keep the selection on the same slot
    // (now the next card) so repeated presses clear down the list.
    function deleteSel() {
        const n = root.selNotif;
        if (!n) return;
        const at = root.sel;
        root.actionSel = -1;
        root.notifs.forget(n);              // rebuilds `grouped` synchronously
        root.sel = root.flat.length === 0 ? -1 : Math.min(at, root.flat.length - 1);
    }
    // keep the selected card scrolled into view inside the Flickable
    function ensureVisible(item) {
        if (!item) return;
        const p = item.mapToItem(groupsCol, 0, 0);
        const top = p.y;
        const bot = top + item.height;
        if (top < flick.contentY)
            flick.contentY = top;
        else if (bot > flick.contentY + flick.height)
            flick.contentY = Math.max(0, bot - flick.height);
    }

    // the always-focused key sink for the pane (a plain Item is transparent to the
    // mouse, so the cards' own click handlers still work). Focus returns here when a
    // reply field is escaped. Letter/Delete keys only reach here while no reply field
    // holds focus — so they can't clobber a reply mid-typing.
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (root.actionSel >= 0) root.actionSel = -1;   // action -> card
                else root.closeRequested();                     // card/none -> close
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.moveSel(1); event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.moveSel(-1); event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                if (root.selNotif) { root.actionSel = Math.max(-1, root.actionSel - 1); event.accepted = true; }
            } else if (event.key === Qt.Key_Right) {
                const c = root.selActions.length;
                if (root.selNotif && c > 0) { root.actionSel = Math.min(c - 1, root.actionSel + 1); event.accepted = true; }
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activateSel(); event.accepted = true;
            } else if (event.key === Qt.Key_I) {
                if (root.selNotif && root.selNotif.hasInlineReply) { root.replyFocused = true; event.accepted = true; }
            } else if (event.key === Qt.Key_X || event.key === Qt.Key_Delete) {
                root.deleteSel(); event.accepted = true;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Notifications"
            onBack: root.closeRequested()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.notifs.grouped.length > 0
                text: "Clear all"
                color: clearMa.containsMouse ? root.theme.danger : root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
                MouseArea {
                    id: clearMa
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.notifs.clearAll()
                }
            }
        }

        Flickable {
            id: flick
            width: parent.width
            height: parent.height - 26 - root.theme.gap
            contentHeight: groupsCol.height
            clip: true
            Column {
                id: groupsCol
                width: parent.width
                spacing: root.theme.gap

                Repeater {
                    model: root.notifs.grouped
                    delegate: Column {
                        required property var modelData
                        width: groupsCol.width
                        spacing: 4
                        // group header: app name + count (left) | "Clear" (right),
                        // which dismisses the whole group's history at once.
                        Item {
                            width: parent.width
                            height: groupTitle.implicitHeight
                            Text {
                                id: groupTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.app + "  ·  " + modelData.items.length
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                                font.capitalization: Font.AllUppercase
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear"
                                color: grpClearMa.containsMouse ? root.theme.danger : root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                                font.capitalization: Font.AllUppercase
                                MouseArea {
                                    id: grpClearMa
                                    anchors.fill: parent; anchors.margins: -4
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.notifs.clearGroup(modelData)
                                }
                            }
                        }
                        Repeater {
                            model: modelData.items
                            delegate: NotificationView {
                                id: nv
                                required property var modelData
                                width: groupsCol.width
                                theme: root.theme
                                notifs: root.notifs
                                notification: modelData
                                inHistory: true
                                // keyboard-selection state pushed down from the pane
                                selected: root.selNotif === modelData
                                focusedAction: root.selNotif === modelData ? root.actionSel : -1
                                replyActive: root.selNotif === modelData && root.replyFocused
                                // reply Escape: return focus to the card (not close)
                                onReplyEscaped: {
                                    root.replyFocused = false;
                                    keyHandler.forceActiveFocus();
                                }
                                // clicking a card with the mouse also becomes the
                                // keyboard selection, so the two stay in sync
                                onCardClicked: root.sel = root.flat.indexOf(modelData)
                                onSelectedChanged: if (selected) root.ensureVisible(nv)
                            }
                        }
                    }
                }
                Text {
                    visible: root.notifs.grouped.length === 0
                    text: "No notifications"
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }
    }
}
