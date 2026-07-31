pragma ComponentBehavior: Bound
// ActionBurstPill.qml — action-burst overlay content. One mini-pill per kind in
// `kinds` (["desktops"], ["language"], ["level"], or a combination), each with the
// hovered-pill surface; two live kinds pop apart on entry. language: fromLabel ->
// (flashing arrow during phase 2) -> toLabel. desktops: a DesktopDots row with the
// dot sliding to dotIdx. level (volume / brightness): an icon in the left column,
// a title over a progress bar in the right column; the bar animates from levelFrom
// to levelTo across phase 2.
import QtQuick

Row {
    id: root
    required property var theme
    required property var kinds         // canonical order: "desktops", "language", "level"
    required property var desktops
    property int phase: 0              // 0 idle, 1 pre, 2 animate, 3 post
    property string fromLabel: ""
    property string toLabel: ""
    property int dotIdx: 0
    // level (volume / brightness) burst: glyph + title over a from->to progress bar
    property string levelIcon: ""
    property string levelTitle: ""
    property real   levelFrom: 0
    property real   levelTo: 0

    spacing: 8                          // the gap between two pills
    Repeater {
        model: root.kinds
        delegate: Rectangle {
            id: cell
            required property int index
            required property string modelData
            readonly property bool isLang: modelData === "language"
            readonly property bool isLevel: modelData === "level"
            height: isLevel ? 44 : 28
            width: cellBody.implicitWidth + 24
            radius: isLevel ? 16 : 12
            color: root.theme.bg            // same surface as the hovered pill
            border.color: root.theme.border
            border.width: 1
            // pop apart: only when two pills are shown, slide from centre out
            transform: Translate {
                NumberAnimation on x {
                    running: root.kinds.length === 2
                    from: cell.index === 0 ? 14 : -14
                    to: 0
                    duration: 180
                    easing.type: Easing.OutBack
                }
            }

            Item {
                id: cellBody
                anchors.centerIn: parent
                implicitWidth: cell.isLevel ? levelRow.implicitWidth
                             : cell.isLang ? langRow.implicitWidth : dots.implicitWidth
                implicitHeight: cell.height

                Row {                            // language: EN -> FA
                    id: langRow
                    anchors.centerIn: parent
                    visible: cell.isLang
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fromLabel; color: root.theme.textDim
                        font.family: root.theme.mono; font.pixelSize: root.theme.fsNormal
                        font.letterSpacing: root.theme.labelSpacing; font.capitalization: Font.AllUppercase
                    }
                    MSym {                       // arrow flashes during the animate phase
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "arrow_right_alt"; size: 18; color: root.theme.accent
                        opacity: root.phase === 2 ? 1 : 0.3
                        Behavior on opacity { NumberAnimation { duration: 110 } }
                        SequentialAnimation on scale {
                            running: root.phase === 2; loops: 2
                            NumberAnimation { from: 1.0; to: 1.35; duration: 75 }
                            NumberAnimation { from: 1.35; to: 1.0; duration: 75 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.toLabel; color: root.theme.text
                        font.family: root.theme.mono; font.pixelSize: root.theme.fsNormal
                        font.letterSpacing: root.theme.labelSpacing; font.capitalization: Font.AllUppercase
                    }
                }

                DesktopDots {                    // desktops: dots with a sliding active dot
                    id: dots
                    anchors.centerIn: parent
                    visible: !cell.isLang && !cell.isLevel
                    theme: root.theme
                    desktops: root.desktops
                    activeIdx: root.dotIdx
                }

                Row {                            // level: [icon] | [title / progress bar]
                    id: levelRow
                    anchors.centerIn: parent
                    visible: cell.isLevel
                    spacing: 10
                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: root.levelIcon; size: 22; color: root.theme.accent
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Text {
                            text: root.levelTitle; color: root.theme.textDim
                            font.family: root.theme.mono; font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        Rectangle {              // progress track + fill (from -> to)
                            id: barTrack
                            width: 130; height: 6; radius: 3
                            color: root.theme.track
                            // the fill sits at levelFrom until the animate phase, then
                            // eases to levelTo — same phase-2 cue as the other bursts.
                            property real prog: root.phase >= 2 ? root.levelTo : root.levelFrom
                            Behavior on prog {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                            Rectangle {
                                width: Math.max(0, Math.min(1, barTrack.prog)) * parent.width
                                height: parent.height; radius: parent.radius
                                color: root.theme.accent
                            }
                        }
                    }
                }
            }
        }
    }
}
