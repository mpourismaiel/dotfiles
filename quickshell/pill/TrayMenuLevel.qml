pragma ComponentBehavior: Bound
// TrayMenuLevel.qml — one level of a tray item's DBus menu, as pill rows. Walks a
// QsMenuHandle via QsMenuOpener and repeats children (QsMenuEntry): isSeparator →
// divider; buttonType CheckBox/RadioButton → check/radio glyph from checkState; a
// DBus icon → Qt-themed Image; hasChildren → inline accordion holding a nested
// TrayMenuLevel (self-referencing, deferred behind a Loader so collapsed submenus
// don't open over DBus). Leaf click → modelData.triggered() then activated() so the
// host closes the menu.
import QtQuick
import Quickshell

Column {
    id: level
    // plain (not required) properties: submenus are instantiated via a Loader
    // `source` URL — the runtime-resolved self-reference that lets a QML component
    // recurse (a static TrayMenuLevel { } inside itself is rejected as recursive) —
    // and a URL-loaded item can't have required properties set before creation, so
    // the nested level sets these imperatively in the Loader's onLoaded.
    property var theme: null
    property var handle: null       // QsMenuHandle: the tray item's .menu, or a submenu entry
    property real indent: 0
    signal activated()

    width: parent ? parent.width : 0
    spacing: 2

    QsMenuOpener {
        id: opener
        menu: level.handle
    }

    Repeater {
        model: opener.children

        delegate: Column {
            id: entryCol
            required property var modelData
            property bool expanded: false
            width: level.width
            spacing: 2

            // ---- separator ----
            Item {
                visible: entryCol.modelData.isSeparator
                width: level.width
                height: visible ? 9 : 0
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 4 + level.indent; anchors.rightMargin: 4
                    height: 1; color: level.theme.divider
                }
            }

            // ---- entry row (leaf or submenu parent) ----
            Rectangle {
                id: row
                visible: !entryCol.modelData.isSeparator
                width: level.width
                height: visible ? 34 : 0
                radius: level.theme.radiusBtn
                opacity: entryCol.modelData.enabled ? 1 : 0.4
                color: (rowMa.containsMouse && entryCol.modelData.enabled) ? level.theme.rowHi : "transparent"

                // leading: check/radio glyph for toggles, else the DBus icon
                readonly property bool isCheck: entryCol.modelData.buttonType === QsMenuButtonType.CheckBox
                readonly property bool isRadio: entryCol.modelData.buttonType === QsMenuButtonType.RadioButton
                readonly property bool isToggle: row.isCheck || row.isRadio
                readonly property bool on: entryCol.modelData.checkState === Qt.Checked

                MSym {
                    id: tglGlyph
                    visible: row.isToggle
                    anchors.left: parent.left; anchors.leftMargin: 10 + level.indent
                    anchors.verticalCenter: parent.verticalCenter
                    size: 18
                    color: row.on ? level.theme.accent : level.theme.textDim
                    icon: row.isRadio
                        ? (row.on ? "radio_button_checked" : "radio_button_unchecked")
                        : (row.on ? "check_box" : "check_box_outline_blank")
                }
                Image {
                    id: dbusIcon
                    visible: !row.isToggle && entryCol.modelData.icon !== ""
                    anchors.left: parent.left; anchors.leftMargin: 10 + level.indent
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    source: entryCol.modelData.icon
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors.left: (row.isToggle) ? tglGlyph.right
                        : (dbusIcon.visible ? dbusIcon.right : parent.left)
                    anchors.leftMargin: (row.isToggle || dbusIcon.visible) ? 12 : 12 + level.indent
                    anchors.right: parent.right; anchors.rightMargin: 34
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: entryCol.modelData.text
                    color: level.theme.text
                    font.family: level.theme.family; font.pixelSize: level.theme.fsNormal
                }

                MSym {                              // submenu chevron
                    visible: entryCol.modelData.hasChildren
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    icon: entryCol.expanded ? "expand_more" : "chevron_right"
                    size: 18; color: level.theme.faint
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: entryCol.modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (entryCol.modelData.hasChildren) {
                            entryCol.expanded = !entryCol.expanded;
                        } else {
                            entryCol.modelData.triggered();
                            level.activated();
                        }
                    }
                }
            }

            // ---- inline submenu (deferred until first expanded) ----
            // Loaded by URL (not sourceComponent) so the self-reference resolves at
            // runtime — a static nested TrayMenuLevel { } is rejected as recursive.
            // Properties are set in onLoaded since a URL-loaded item can't take them
            // pre-creation; the child's `activated` is chained up to this level's.
            Loader {
                width: level.width
                active: entryCol.modelData.hasChildren && entryCol.expanded
                visible: active
                source: active ? "TrayMenuLevel.qml" : ""
                onLoaded: {
                    item.theme = level.theme;
                    item.handle = entryCol.modelData;
                    item.indent = level.indent + 26;
                    item.activated.connect(level.activated);
                }
            }
        }
    }
}
