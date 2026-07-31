pragma ComponentBehavior: Bound
// AppContextMenu.qml — the taskbar app right-click menu, rendered inside the pill
// (like the control-panel menus). MenuHeader shows the app name; below it: for a
// grouped app (>1 window) a split-row submenu per window (click body=activateRequested
// to focus, click chevron=expand that window's ActionBlock) + separator, the app's
// launcher actions (DesktopEntries.heuristicLookup(icon).actions) + separator, an "All
// windows" ActionBlock — Move to Desktop (inline accordion over `desktops`), Minimize,
// Maximize, Keep Above/Below, Close. launchRequested(execString) runs a launcher
// action; windowAction(verb, uuids) drives KWin against those uuids; the host
// clears win.ctxGroup after either (so acting closes the menu). closeRequested() backs
// out. implicitHeight (header + rows) sizes the ctx-mode pill.
import QtQuick
import Quickshell

Item {
    id: root
    required property var theme
    required property var group          // { icon, entry, wins, desks, onAll }
    property var desktops: []            // [{ id, name }] — KWin virtual desktops
    // which desktops the group's windows occupy (radio-marked in the list)
    readonly property var winDesks: root.group && root.group.desks ? root.group.desks : []
    readonly property bool winOnAll: !!(root.group && root.group.onAll)
    property bool isPinned: false        // whether this app is pinned to the taskbar
    signal launchRequested(string execString)
    signal activateRequested(string id)  // focus one window (a grouped app's title row)
    // act on the given window uuids: minimize|maximize|above|below|close|desktop:<id>
    signal windowAction(string verb, var uuids)
    signal pinToggled(var entry)         // the Pin/Unpin row was clicked (resolved entry)
    signal closeRequested()

    // the host (init.qml appGroups) already resolved the best DesktopEntry; fall
    // back to a heuristic lookup on the icon name for safety.
    readonly property var entry: root.group
        ? (root.group.entry || DesktopEntries.heuristicLookup(root.group.icon))
        : null
    readonly property var actions: root.entry && root.entry.actions ? root.entry.actions : []
    // all window uuids in the group (the whole-group action targets), and whether
    // this app has more than one open window (→ per-window submenus).
    readonly property var allUuids: root.group && root.group.wins ? root.group.wins.map(w => w.uuid) : []
    readonly property bool grouped: !!(root.group && root.group.wins && root.group.wins.length > 1)

    // header + content, independent of the height we're actually given (so the pill
    // can bind its ctx-mode height to this without a layout cycle).
    implicitHeight: header.implicitHeight + root.theme.gap + bodyCol.implicitHeight

    // one clickable menu row: optional leading glyph, label, optional trailing chevron.
    // splitChev = the chevron is its own hit target (a rounded button that toggles the
    // submenu via chevAct); the rest of the row fires act(). Used for the window-title
    // rows — click the row to focus the window, click the chevron to open its menu.
    // Without splitChev the whole row fires act() (chevron is just an affordance).
    component Row0: Rectangle {
        id: r0
        property string glyph: ""
        property string label: ""
        property bool chev: false
        property bool expanded: false
        property bool danger: false
        property real indent: 0
        property bool splitChev: false
        property bool chevHover: false
        readonly property real chevZone: 40   // right-edge px that hit the chevron
        signal act()
        signal chevAct()
        width: parent ? parent.width : 0
        height: 34
        radius: root.theme.radiusBtn
        // while the pointer is over the split chevron, the row body doesn't highlight
        // (the chevron button does instead) so the two targets read as distinct.
        color: (r0ma.containsMouse && !r0.chevHover) ? root.theme.rowHi : "transparent"
        MSym {
            id: r0ic
            visible: r0.glyph !== ""
            anchors.left: parent.left; anchors.leftMargin: 10 + r0.indent
            anchors.verticalCenter: parent.verticalCenter
            icon: r0.glyph; size: 18
            color: r0.danger ? root.theme.accent : root.theme.textDim
        }
        Text {
            anchors.left: r0.glyph !== "" ? r0ic.right : parent.left
            anchors.leftMargin: r0.glyph !== "" ? 12 : 12 + r0.indent
            anchors.right: parent.right; anchors.rightMargin: 34
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: r0.label
            color: r0.danger ? root.theme.accent : root.theme.text
            font.family: root.theme.family; font.pixelSize: root.theme.fsNormal
        }
        Rectangle {                          // chevron (its own button when splitChev)
            visible: r0.chev
            anchors.right: parent.right; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: root.theme.radiusBtn
            color: (r0.splitChev && r0.chevHover) ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: r0.expanded ? "expand_more" : "chevron_right"
                size: 18
                color: (r0.splitChev && r0.chevHover) ? root.theme.text : root.theme.faint
            }
        }
        MouseArea {
            id: r0ma
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onPositionChanged: (m) => r0.chevHover = r0.splitChev && r0.chev && m.x > r0.width - r0.chevZone
            onExited: r0.chevHover = false
            onClicked: (m) => {
                if (r0.splitChev && r0.chev && m.x > r0.width - r0.chevZone) r0.chevAct();
                else r0.act();
            }
        }
    }
    component Sep: Rectangle {
        width: parent ? parent.width : 0
        height: 9
        color: "transparent"
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 4; anchors.rightMargin: 4
            height: 1; color: root.theme.divider
        }
    }
    // small mono section label ("All windows")
    component Label0: Text {
        width: parent ? parent.width : 0
        leftPadding: 10; topPadding: 6; bottomPadding: 2
        color: root.theme.faint
        font.family: root.theme.mono; font.pixelSize: root.theme.fsSmall
        font.letterSpacing: root.theme.labelSpacing; font.capitalization: Font.AllUppercase
    }
    // the KWin window-action rows for `targets` (uuids) — reused for the whole group
    // and for each individual window. Each block owns its Move-to-Desktop accordion;
    // `deskMark`/`markAll` say which desktop entries to radio-mark (where the
    // target(s) currently live).
    component ActionBlock: Column {
        id: ab
        property var targets: []
        property var deskMark: []
        property bool markAll: false
        property real indent: 0
        property bool deskExpanded: false
        // `windowRows` shows the KWin per-window actions (Move/Minimize/…/Close);
        // a not-running pinned app has no windows, so its whole-group block hides
        // them and shows only the pin row. `showPin` adds the app-level Pin/Unpin
        // row (whole-group block only — pinning is per-app, not per-window).
        property bool windowRows: true
        property bool showPin: false
        width: parent ? parent.width : 0
        spacing: 2

        Row0 {
            visible: ab.windowRows && root.desktops.length > 0
            indent: ab.indent
            glyph: "dashboard"; label: "Move to Desktop"
            chev: true; expanded: ab.deskExpanded
            onAct: ab.deskExpanded = !ab.deskExpanded
        }
        Row0 {
            visible: ab.windowRows && root.desktops.length > 0 && ab.deskExpanded
            indent: ab.indent + 26; label: "All Desktops"
            glyph: ab.markAll ? "radio_button_checked" : "radio_button_unchecked"
            onAct: root.windowAction("desktop:all", ab.targets)
        }
        Repeater {
            model: (ab.windowRows && ab.deskExpanded) ? root.desktops : []
            delegate: Row0 {
                required property var modelData
                indent: ab.indent + 26
                glyph: ab.deskMark.indexOf(modelData.id) >= 0 ? "radio_button_checked" : "radio_button_unchecked"
                label: modelData.name
                onAct: root.windowAction("desktop:" + modelData.id, ab.targets)
            }
        }
        Row0 { visible: ab.windowRows; indent: ab.indent; glyph: "minimize";                   label: "Minimize";          onAct: root.windowAction("minimize", ab.targets) }
        Row0 { visible: ab.windowRows; indent: ab.indent; glyph: "crop_square";                label: "Maximize";          onAct: root.windowAction("maximize", ab.targets) }
        Row0 { visible: ab.windowRows; indent: ab.indent; glyph: "keyboard_double_arrow_up";   label: "Keep Above Others"; onAct: root.windowAction("above", ab.targets) }
        Row0 { visible: ab.windowRows; indent: ab.indent; glyph: "keyboard_double_arrow_down"; label: "Keep Below Others"; onAct: root.windowAction("below", ab.targets) }
        // Pin/Unpin — after the window actions, before the Close separator.
        Row0 {
            visible: ab.showPin
            indent: ab.indent
            glyph: root.isPinned ? "keep_off" : "keep"
            label: root.isPinned ? "Unpin from taskbar" : "Pin to taskbar"
            onAct: root.pinToggled(root.entry)
        }
        Sep { visible: ab.windowRows }
        Row0 { visible: ab.windowRows; indent: ab.indent; glyph: "close"; label: "Close"; danger: true; onAct: root.windowAction("close", ab.targets) }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            id: header
            theme: root.theme
            title: root.entry ? root.entry.name : (root.group ? root.group.icon : "")
            onBack: root.closeRequested()
        }

        Flickable {
            id: bodyFlick
            width: parent.width
            height: parent.height - header.height - root.theme.gap
            contentHeight: bodyCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // width MUST reference the Flickable id, not `parent.width`: a Column's
            // parent inside a Flickable is the contentItem (width tied to
            // contentWidth ~ 0), and children binding `parent.width` back to it
            // stalls the positioner (implicitHeight stays 0).
            Column {
                id: bodyCol
                width: bodyFlick.width
                spacing: 2

                // ---- grouped app: one expandable submenu per open window ----
                // each window's title expands (chevron) to the same action block as
                // a single-app menu, but targeting just that window. Only shown when
                // the app has >1 instance; a separator sets them off below.
                Repeater {
                    model: root.grouped ? root.group.wins : []
                    delegate: Column {
                        id: winItem
                        required property var modelData
                        property bool expanded: false
                        width: parent ? parent.width : 0
                        spacing: 2
                        Row0 {
                            glyph: "web_asset"; label: winItem.modelData.title
                            chev: true; expanded: winItem.expanded
                            // click the row → focus the window; click the chevron → open its menu
                            splitChev: true
                            onAct: root.activateRequested(winItem.modelData.id)
                            onChevAct: winItem.expanded = !winItem.expanded
                        }
                        ActionBlock {
                            visible: winItem.expanded
                            indent: 26
                            targets: [winItem.modelData.uuid]
                            markAll: winItem.modelData.desk === "all"
                            deskMark: winItem.modelData.desk && winItem.modelData.desk !== "all"
                                ? [winItem.modelData.desk] : []
                        }
                    }
                }
                Sep { visible: root.grouped }

                // ---- the app's own launcher actions (New Window, …) ----
                Repeater {
                    model: root.actions
                    delegate: Row0 {
                        required property var modelData
                        glyph: "open_in_new"
                        label: modelData.name
                        onAct: root.launchRequested(modelData.execString)
                    }
                }
                Sep { visible: root.actions.length > 0 }

                // ---- window actions for the whole group (or the single window) ----
                // + the app-level Pin/Unpin row. A not-running pinned app (no
                // windows) shows only the pin row; a running app shows the full
                // window actions with pin inserted before Close.
                Label0 { visible: root.grouped; text: "All windows" }
                ActionBlock {
                    targets: root.allUuids
                    markAll: root.winOnAll
                    deskMark: root.winDesks
                    windowRows: root.allUuids.length > 0
                    showPin: root.entry !== null
                }
            }
        }
    }
}
