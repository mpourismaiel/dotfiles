pragma ComponentBehavior: Bound
// FeaturePage.qml — one Settings content page for an optional feature (Org Agenda,
// Finance). A title + blurb, an enable toggle, and — once enabled — a directory
// field. Purely a view: it reads featureOn/path in and emits featureToggled(bool) /
// pathEdited(string) so the host (SettingsMenu) can persist to the settings JSON.
import QtQuick

Item {
    id: root
    required property var theme
    property string title: ""
    property string blurb: ""
    property string enableLabel: "Enable"
    property string pathLabel: "Directory"
    property string pathPlaceholder: ""
    property bool featureOn: false             // current persisted enable state
    property string path: ""                   // current persisted directory
    signal featureToggled(bool value)
    signal pathEdited(string value)

    // seed the field once from `path`, then let the user drive it (no binding, so
    // typing doesn't fight the source). Re-seed if the page is re-shown with a
    // different stored value while the field isn't focused.
    function _seed() { if (!pathInput.activeFocus) pathInput.text = root.path; }
    Component.onCompleted: _seed()
    onPathChanged: _seed()
    onVisibleChanged: if (visible) _seed()

    Flickable {
        anchors.fill: parent
        contentHeight: col.height
        clip: true
        Column {
            id: col
            width: parent.width
            spacing: 12

            Text {
                text: root.title
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: root.theme.fsLarge + 4
            }
            Text {
                width: col.width
                wrapMode: Text.WordWrap
                text: root.blurb
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }

            Rectangle { width: col.width; height: 1; color: root.theme.divider }

            // enable toggle row
            Item {
                width: col.width
                height: 40
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.enableLabel
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                }
                PillToggle {
                    id: enableToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.theme
                    checked: root.featureOn
                    onToggled: (v) => root.featureToggled(v)
                }
            }

            // directory field — only meaningful once enabled
            Column {
                width: col.width
                spacing: 6
                opacity: root.featureOn ? 1 : 0.4
                enabled: root.featureOn
                Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }

                Text {
                    text: root.pathLabel
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: root.theme.radiusBtn
                    color: root.theme.bgElevated
                    border.width: 1
                    border.color: pathInput.activeFocus ? root.theme.accent : root.theme.border
                    TextInput {
                        id: pathInput
                        objectName: "pillKbInput"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        clip: true
                        selectByMouse: true
                        selectionColor: root.theme.accentDim
                        onTextChanged: if (text !== root.path) root.pathEdited(text)
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: pathInput.text.length === 0
                            text: root.pathPlaceholder
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Applies immediately. ~ expands to your home directory."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsSmall - 1
                }
            }
        }
    }
}
