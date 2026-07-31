pragma ComponentBehavior: Bound
// AppMenu.qml — a floating right-click context menu for a DesktopEntry, styled
// like the taskbar app menu (glyph rows) but without window actions. It's a
// full-size overlay (anchors.fill your host) with an outside-click backdrop; the
// menu itself is positioned at (px,py) and clamped to stay inside the overlay, so
// hosting it above the pill (full-screen win level, not the launcher's clipped
// body) lets it drop out of the pill without clipping. Lists entry.actions (New
// Window, …) and, when showFavourite is set, an Add/Remove favourite row driven by
// the host (isFavourite in, favouriteToggled(entry) out). openFor(entry,x,y,fav,
// showFav) shows it; running an action or toggling favourite closes it.
import QtQuick

Item {
    id: root
    required property var theme
    property var entry: null            // DesktopEntry (null → hidden)
    property bool showFavourite: false
    property bool isFavourite: false
    property bool showPin: false        // offer a Pin/Unpin to taskbar row
    property bool isPinned: false
    property real px: 0                 // requested point, in this overlay's coords
    property real py: 0
    // the entry's launcher/desktop actions (empty for entries that define none)
    readonly property var entryActions: entry && entry.actions ? entry.actions : []
    // whether the app-management section (favourite / pin rows) is shown at all
    readonly property bool hasManageRows: showFavourite || showPin
    signal launched()                   // an action was run
    signal favouriteToggled(var entry)  // the favourite row was clicked
    signal pinToggled(var entry)        // the pin/unpin row was clicked
    signal dismissed()                  // backdrop / after any action

    anchors.fill: parent                // full overlay so the menu can sit anywhere
    visible: entry !== null
    z: 1000

    // opts: { fav, showFav, pinned, showPin } — all optional.
    function openFor(e, x, y, opts) {
        opts = opts || {};
        entry = e;
        isFavourite = !!opts.fav;
        showFavourite = opts.showFav !== undefined ? opts.showFav : false;
        isPinned = !!opts.pinned;
        showPin = opts.showPin !== undefined ? opts.showPin : false;
        px = x;
        py = y;
    }
    function close() { entry = null; root.dismissed(); }

    MouseArea {                          // backdrop: outside click dismisses
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.close()
    }

    // one clickable menu row (leading glyph + label), matching the taskbar app
    // menu's Row0. `fill`/`glyphColor` let the favourite row draw a filled accent
    // star when the entry is already a favourite.
    component CtxRow: Rectangle {
        id: cr
        property string glyph: ""
        property string label: ""
        property int fill: 0
        property color glyphColor: root.theme.textDim
        signal act()
        width: menuCol.width
        height: 34
        radius: root.theme.radiusBtn
        color: crMa.containsMouse ? root.theme.rowHi : "transparent"
        MSym {
            id: crIc
            visible: cr.glyph !== ""
            anchors.left: parent.left; anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            icon: cr.glyph; size: 18; fill: cr.fill; weight: 500
            color: cr.glyphColor
        }
        Text {
            anchors.left: crIc.right; anchors.leftMargin: 12
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: cr.label
            color: root.theme.text
            font.family: root.theme.family; font.pixelSize: root.theme.fsNormal
        }
        MouseArea {
            id: crMa
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: cr.act()
        }
    }

    Rectangle {
        id: menu
        // clamp reactively so the menu stays fully inside the overlay even as its
        // height settles after `entry` changes (drops downward from the cursor).
        x: Math.max(0, Math.min(root.px, root.width - width))
        y: Math.max(0, Math.min(root.py, root.height - height))
        width: 230
        height: menuCol.implicitHeight + 8
        radius: root.theme.radiusCard
        color: root.theme.bgElevated
        border.color: root.theme.border
        border.width: 1

        Column {
            id: menuCol
            x: 4; y: 4
            width: parent.width - 8
            spacing: 1

            Text {
                width: parent.width; elide: Text.ElideRight
                leftPadding: 10; bottomPadding: 5; topPadding: 4
                text: root.entry ? root.entry.name : ""
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            // ---- the entry's own launcher actions (New Window, …) ----
            Repeater {
                model: root.entryActions
                delegate: CtxRow {
                    required property var modelData
                    glyph: "open_in_new"
                    label: modelData.name
                    onAct: { modelData.execute(); root.launched(); root.close(); }
                }
            }
            // separator before the manage rows (only when actions sit above them)
            Item {
                visible: root.hasManageRows && root.entryActions.length > 0
                width: menuCol.width; height: 9
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 4; anchors.rightMargin: 4
                    height: 1; color: root.theme.divider
                }
            }
            // ---- favourite toggle (host-driven) ----
            CtxRow {
                visible: root.showFavourite
                glyph: "star"
                fill: root.isFavourite ? 1 : 0
                glyphColor: root.isFavourite ? root.theme.accent : root.theme.faint
                label: root.isFavourite ? "Remove favourite" : "Add favourite"
                onAct: { root.favouriteToggled(root.entry); root.close(); }
            }
            // ---- pin to taskbar toggle (host-driven) ----
            CtxRow {
                visible: root.showPin
                glyph: root.isPinned ? "keep_off" : "keep"
                fill: root.isPinned ? 1 : 0
                glyphColor: root.isPinned ? root.theme.accent : root.theme.textDim
                label: root.isPinned ? "Unpin from taskbar" : "Pin to taskbar"
                onAct: { root.pinToggled(root.entry); root.close(); }
            }
        }
    }
}
