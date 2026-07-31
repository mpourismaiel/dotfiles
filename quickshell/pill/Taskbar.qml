pragma ComponentBehavior: Bound
// Taskbar.qml — app icons for the hovered dashboard (Row 1). Pinned apps first (in
// saved order, running or not), then the remaining open apps. Each tile is a group
// { key, icon, entry, wins, pinned }; a count badge for 2+ windows and an underline
// shown only while running (accent when active). A pinned-but-unopened tile (wins
// empty) reads dimmed with no underline; activated(group) launches it (parent does
// the launch-vs-cycle split). contextRequested(group) = right-click (app menu, where
// Pin/Unpin lives). Tiles drag-reorder within their section (pinned<->pinned or
// open<->open only — never across, so a drag can't pin/unpin); on release,
// reordered(keys) hands the parent the new full key order. The hover highlight is
// the dashboard's shared square (tiles report themselves via itemEntered).
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    required property var theme
    required property var groups         // [{ key, icon, entry, wins, pinned }]
    required property string activeWindow
    signal activated(var group)
    signal contextRequested(var group)
    signal reordered(var keys)           // new full tile-key order after a drag
    signal itemEntered(var item)         // tile hovered -> move the shared indicator

    // during-drag scratch: the live key order + whether any move actually happened
    // (so a plain click doesn't emit a spurious reorder).
    property var dragOrder: []
    property bool didReorder: false

    // keyboard nav (init.qml's dashboard handler): the tiles as an ordered strip
    readonly property int tileCount: taskList.count
    function tileAt(i) { return taskList.itemAtIndex(i); }

    // app icons are bigger than the menu/tray glyphs, so the app row is spaced 1.5x
    // the base icon spacing to keep the tiles from crowding.
    readonly property real tileSpacing: Math.round(root.theme.iconSpacing * 1.5)
    // size deterministically from the tile count (tiles are fixed appCell-wide) so
    // the ListView always has a real width to lay out in — binding to contentWidth
    // can deadlock at width 0 (no width → no delegates → contentWidth 0 → …).
    implicitWidth: {
        const n = root.groups.length;
        return n > 0 ? n * root.theme.appCell + (n - 1) * root.tileSpacing : 0;
    }
    implicitHeight: root.theme.appCell

    ListView {
        id: taskList
        anchors.fill: parent
        orientation: ListView.Horizontal
        interactive: false               // no flicking; it's sized to its content
        spacing: root.tileSpacing
        // keep every tile realised (small set; live delegates are needed so a drag
        // can reparent them and so the count/order stays exact).
        cacheBuffer: 100000

        // tiles slide out of the way as one is dragged across them.
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: root.theme.animFast }
        }

        model: DelegateModel {
            id: tbModel
            model: root.groups

            delegate: MouseArea {
                id: appMa
                required property var modelData
                required property int index
                readonly property int visualIndex: DelegateModel.itemsIndex
                readonly property bool active: appMa.modelData.wins.some(w => w.uuid === root.activeWindow)
                readonly property bool running: appMa.modelData.wins.length > 0
                // the shared hover square wants a little extra padding around app
                // tiles (their icons run larger than the menu/tray glyphs).
                readonly property int hoverPad: 5
                // keyboard nav: Enter = left-click (cycle windows / launch)
                function keyClick() { root.activated(appMa.modelData); }

                width: root.theme.appCell
                height: root.theme.appCell
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                drag.target: tileBg
                drag.axis: Drag.XAndYAxis
                onContainsMouseChanged: if (appMa.containsMouse) root.itemEntered(appMa);
                onPressed: {
                    root.dragOrder = root.groups.map(g => g.key);
                    root.didReorder = false;
                }
                onReleased: {
                    if (root.didReorder) root.reordered(root.dragOrder);
                }
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) root.activated(appMa.modelData);
                    else root.contextRequested(appMa.modelData);
                }

                // reorder as a tile is dragged over — but only within the same
                // section (pinned stays with pinned, open with open), so a drag can
                // never move an app across the pinned boundary (i.e. never pins or
                // unpins — that's the menu's job).
                DropArea {
                    anchors.fill: parent
                    onEntered: (drag) => {
                        const from = drag.source.visualIndex;
                        const to = appMa.visualIndex;
                        if (from === to)
                            return ;
                        if (drag.source.modelData.pinned !== appMa.modelData.pinned)
                            return ;

                        tbModel.items.move(from, to);
                        const o = root.dragOrder.slice();
                        o.splice(to, 0, o.splice(from, 1)[0]);
                        root.dragOrder = o;
                        root.didReorder = true;
                    }
                }

                Item {
                    id: tileBg
                    width: appMa.width
                    height: appMa.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    z: tileBg.Drag.active ? 2 : 0
                    Drag.active: appMa.drag.active
                    Drag.source: appMa
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2

                    IconImage {
                        id: appIcon
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: root.theme.appIcon
                        // a pinned app that isn't running reads dimmed so it's clearly
                        // "pinned, not open" rather than just another running tile.
                        opacity: appMa.running ? 1 : 0.6
                        // some icon names resolve to a path that still fails to decode;
                        // when that happens fall back to the generic app glyph so a tile
                        // never renders blank.
                        property bool failed: false
                        source: appIcon.failed
                                ? Quickshell.iconPath("application-x-executable")
                                : Quickshell.iconPath(appMa.modelData.icon, "application-x-executable")
                        onStatusChanged: if (status === Image.Error) appIcon.failed = true;
                    }
                    Rectangle {                  // window-count badge (2+ windows)
                        visible: appMa.modelData.wins.length > 1
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -3
                        anchors.rightMargin: -3
                        width: 15; height: 15; radius: 7.5
                        color: root.theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: appMa.modelData.wins.length
                            font.family: root.theme.family
                            color: "#ffffff"; font.pixelSize: 9; font.bold: true
                        }
                    }
                    Rectangle {                  // running / active indicator (running only)
                        visible: appMa.running
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 2
                        radius: 1
                        width: appMa.active ? 20 : 7
                        color: appMa.active ? root.theme.accent : root.theme.faint
                        Behavior on width { NumberAnimation { duration: root.theme.animFast } }
                    }

                    // while dragging, lift the tile out of the row so it floats and
                    // follows the cursor (the row's other tiles reflow underneath).
                    states: State {
                        when: tileBg.Drag.active
                        ParentChange { target: tileBg; parent: taskList }
                        AnchorChanges {
                            target: tileBg
                            anchors.horizontalCenter: undefined
                            anchors.verticalCenter: undefined
                        }
                    }
                }
            }
        }
    }
}
