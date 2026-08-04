pragma ComponentBehavior: Bound
// ActionBurstPill.qml — action-burst content that REPLACES the resting pill's clock
// *in place*: a vertical COLUMN of surface-less rows (one per active burst), with NO
// surface of its own — the pill surface behind it is the background, so the pill grows
// / shrinks to fit. Rows are driven by a ListModel (`model`, one entry {kind} per live
// burst) so a new burst can be *inserted at the top* and the ones below *roll down*
// (the Column move transition) while the newcomer *revolves in* from above (folds down
// from -90° about its top edge, fading). Rows hug their content, so two stacked bursts
// sit tight together. Payload (dot index, from/to labels, level bar) still comes from
// the shared root properties, keyed off each row's `kind`.
//
// `boxed` restores a self-contained rounded surface for the one case where the burst
// floats just below the capture pill (capShow) instead of replacing the clock.
import QtQuick

Item {
    id: root
    required property var theme
    required property var model          // ListModel of { kind } — newest first (top)
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
    // draw a self-contained surface (floating below the capture pill); otherwise the
    // pill's own surface is the background and this is transparent.
    property bool boxed: false

    readonly property int padX: 14
    readonly property int padY: 6
    implicitWidth: col.implicitWidth + padX * 2
    implicitHeight: col.implicitHeight + padY * 2

    // self-contained surface only for the floating-below-capture case
    Rectangle {
        anchors.fill: parent
        visible: root.boxed
        radius: Math.min(root.theme.radiusPanel, height / 2)
        color: root.theme.bg
        border.color: root.theme.border
        border.width: 1
    }

    Column {
        id: col
        x: (root.width - width) / 2
        y: root.padY
        spacing: 4

        // a row inserted at the top pushes the rows below it *down* smoothly; pairs with
        // each row's own revolve-in entrance so a second burst rolls in over the first.
        move: Transition {
            NumberAnimation { properties: "y"; duration: 240; easing.type: Easing.OutCubic }
        }
        add: Transition {
            NumberAnimation { properties: "y"; duration: 240; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.model
            delegate: Item {
                id: cell
                required property int index
                required property string kind
                readonly property bool isLang: kind === "language"
                readonly property bool isLevel: kind === "level"
                // hug the content (plus a hair of vertical breathing room) so stacked
                // rows sit tight — no fixed 28/44 leaving a big gap between them.
                width: body.implicitWidth
                height: body.implicitHeight + 6

                // revolve in from above: fold down from -90° about the top edge while
                // fading in. Runs once on creation; the Column move transition handles
                // rolling the earlier rows down out of the way.
                property real appear: 0
                Component.onCompleted: appearAnim.start()
                NumberAnimation {
                    id: appearAnim
                    target: cell; property: "appear"
                    from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic
                }
                opacity: appear
                transform: Rotation {
                    origin.x: cell.width / 2; origin.y: 0
                    axis { x: 1; y: 0; z: 0 }
                    angle: (1 - cell.appear) * -90
                }

                Item {
                    id: body
                    anchors.centerIn: parent
                    implicitWidth: cell.isLevel ? levelRow.implicitWidth
                                 : cell.isLang ? langRow.implicitWidth : dots.implicitWidth
                    implicitHeight: cell.isLevel ? levelRow.implicitHeight
                                  : cell.isLang ? langRow.implicitHeight : dots.implicitHeight

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
}
