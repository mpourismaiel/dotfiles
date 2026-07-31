pragma ComponentBehavior: Bound
// PowerConfirm.qml — full-screen shutdown / reboot / logout confirmation page. Four
// interchangeable designs (1a Hush / 1b Blaze / 1c Ledger / 1d Split) selected by
// `variant` ("1a".."1d"); each renders the action word + a one-liner `msg` and wires
// yes/no to confirmed() / cancelled(). Escape / "no" -> cancelled(); Enter / "yes" ->
// confirmed(). Extracted verbatim from init.qml (was an inline Rectangle) so the
// designs live in one reusable, screenshot-able place.
// Fonts required: IBM Plex Mono, Newsreader, DM Serif Display, Instrument Serif.
import QtQuick

Rectangle {
    id: root
    required property var theme
    property bool active: false
    property string action: ""       // "shutdown" | "reboot" | "logout"
    property string msg: ""          // random one-liner shown big
    property string variant: "1a"    // which design ("1a".."1d")
    property string clock: ""        // hh:mm (Blaze header)
    signal confirmed()
    signal cancelled()

    // uppercased action word for the mono labels ("SHUTDOWN" etc.)
    readonly property string actionUpper: root.action.toUpperCase()

    anchors.fill: parent
    color: "#09080a"
    opacity: root.active ? 1 : 0
    visible: opacity > 0
    focus: root.active
    Keys.onEscapePressed: root.cancelled()
    Keys.onReturnPressed: root.confirmed()
    Keys.onEnterPressed: root.confirmed()

    // swallow every stray click so nothing leaks to the launcher behind
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    // only the chosen design is built (and rebuilt on each open, so the
    // entrance animations re-run and "random" re-rolls).
    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: root.variant === "1b" ? cBlaze : root.variant === "1c" ? cLedger : root.variant === "1d" ? cSplit : cHush
    }

    // ---------------- 1a — HUSH : restrained, italic serif ----------------
    Component {
        id: cHush

        Item {
            anchors.fill: parent

            // near-black vertical wash (approximates the mockup's radial)
            Rectangle {
                anchors.fill: parent

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#17131a"
                    }

                    GradientStop {
                        position: 0.55
                        color: "#0d0b0e"
                    }

                    GradientStop {
                        position: 1
                        color: "#090809"
                    }

                }

            }

            Column {
                id: hushCol

                anchors.centerIn: parent
                width: Math.min(760, parent.width - 120)
                spacing: 0
                opacity: 0

                NumberAnimation {
                    target: hushCol
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 700
                    easing.type: Easing.OutCubic
                    running: true
                }

                NumberAnimation {
                    target: hushTr
                    property: "y"
                    from: 14
                    to: 0
                    duration: 700
                    easing.type: Easing.OutCubic
                    running: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.action
                    color: "#7a7076"
                    font.family: "IBM Plex Mono"
                    font.weight: Font.Medium
                    font.pixelSize: 15
                    font.letterSpacing: 6
                    font.capitalization: Font.AllUppercase
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: Text.HorizontalFit
                    text: root.msg
                    color: "#d95435"
                    topPadding: 22
                    bottomPadding: 4
                    font.family: "Instrument Serif"
                    font.italic: true
                    font.pixelSize: 190
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(520, parent.width)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Everything unsaved will be closed. This can’t be undone."
                    color: "#8f868c"
                    font.family: "Newsreader"
                    font.pixelSize: 22
                    lineHeight: 1.45
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 52
                    spacing: 56

                    Column {
                        spacing: 6

                        Text {
                            text: "Yes, " + root.action
                            color: "#e9e2e6"
                            font.family: "Newsreader"
                            font.pixelSize: 30

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmed()
                            }

                        }

                        Rectangle {
                            width: parent.width
                            height: 2
                            color: "#cf4a2c"
                        }

                    }

                    Text {
                        text: "Cancel"
                        color: hushNo.containsMouse ? "#b9b1b6" : "#6b6369"
                        font.family: "Newsreader"
                        font.pixelSize: 30

                        MouseArea {
                            id: hushNo

                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelled()
                        }

                    }

                }

                transform: Translate {
                    id: hushTr

                    y: 14
                }

            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                text: "ESC TO CANCEL · ↵ TO CONFIRM"
                color: "#463f45"
                font.family: "IBM Plex Mono"
                font.pixelSize: 12
                font.letterSpacing: 2
            }

        }

    }

    // ---------------- 1b — BLAZE : full color flood, brutalist ----------------
    Component {
        id: cBlaze

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#cf4a2c"
            }

            // header — system tag (left) + live clock (right)
            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 52
                anchors.topMargin: 44
                text: "SYSTEM · " + root.actionUpper
                color: "#3d130a"
                font.family: "IBM Plex Mono"
                font.pixelSize: 14
                font.letterSpacing: 4
                font.capitalization: Font.AllUppercase
            }

            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 52
                anchors.topMargin: 44
                text: root.clock
                color: "#3d130a"
                font.family: "IBM Plex Mono"
                font.pixelSize: 14
                font.letterSpacing: 3
            }

            // headline + subtitle, left-aligned, riding above the buttons
            Column {
                id: blazeCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: blazeButtons.top
                anchors.leftMargin: 52
                anchors.rightMargin: 52
                anchors.bottomMargin: 60
                spacing: 24
                opacity: 0

                NumberAnimation {
                    target: blazeCol
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 700
                    easing.type: Easing.OutCubic
                    running: true
                }

                NumberAnimation {
                    target: blazeTr
                    property: "y"
                    from: 14
                    to: 0
                    duration: 700
                    easing.type: Easing.OutCubic
                    running: true
                }

                Text {
                    width: parent.width
                    fontSizeMode: Text.HorizontalFit
                    text: root.msg
                    color: "#160805"
                    font.family: "DM Serif Display"
                    font.pixelSize: 200
                    font.letterSpacing: -3
                    lineHeight: 0.82
                }

                Text {
                    width: Math.min(560, parent.width)
                    wrapMode: Text.WordWrap
                    text: "All apps will close. Hold nothing back."
                    color: "#4a1b0e"
                    font.family: "Newsreader"
                    font.pixelSize: 24
                    lineHeight: 1.4
                }

                transform: Translate {
                    id: blazeTr

                    y: 14
                }

            }

            // full-width yes / no bar
            Row {
                id: blazeButtons

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Rectangle {
                    width: parent.width / 2
                    height: 108
                    color: "#160805"

                    Text {
                        anchors.centerIn: parent
                        text: "Yes"
                        color: "#f4c9bc"
                        font.family: "DM Serif Display"
                        font.pixelSize: 40
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmed()
                    }

                }

                Rectangle {
                    width: parent.width / 2
                    height: 108
                    color: blazeNo.containsMouse ? "#c33f22" : "transparent"

                    // left keyline between the two halves
                    Rectangle {
                        anchors.left: parent.left
                        width: 2
                        height: parent.height
                        color: "#a5361f"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "No"
                        color: "#3d130a"
                        font.family: "DM Serif Display"
                        font.pixelSize: 40
                    }

                    MouseArea {
                        id: blazeNo

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }

                }

            }

            // top keyline above the button bar
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: blazeButtons.top
                height: 2
                color: "#a5361f"
            }

        }

    }

    // ---------------- 1c — LEDGER : editorial, keyline frame ----------------
    Component {
        id: cLedger

        Item {
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#0d0b0e"
            }

            Column {
                id: ledgerCol

                anchors.centerIn: parent
                width: Math.min(760, parent.width * 0.82)
                spacing: 26
                opacity: 0

                NumberAnimation {
                    target: ledgerCol
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 700
                    easing.type: Easing.OutCubic
                    running: true
                }

                NumberAnimation {
                    target: ledgerTr
                    property: "y"
                    from: 14
                    to: 0
                    duration: 700
                    easing.type: Easing.OutCubic
                    running: true
                }

                // keyline: pulsing dot · label · rule to the right edge
                Item {
                    width: parent.width
                    height: 14

                    Rectangle {
                        id: ledgerDot

                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: "#cf4a2c"

                        SequentialAnimation on opacity {
                            running: true
                            loops: Animation.Infinite

                            NumberAnimation {
                                from: 0.55
                                to: 0.9
                                duration: 1200
                                easing.type: Easing.InOutSine
                            }

                            NumberAnimation {
                                from: 0.9
                                to: 0.55
                                duration: 1200
                                easing.type: Easing.InOutSine
                            }

                        }

                    }

                    Text {
                        id: ledgerTag

                        anchors.left: ledgerDot.right
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Confirm " + root.action
                        color: "#7a7076"
                        font.family: "IBM Plex Mono"
                        font.pixelSize: 13
                        font.letterSpacing: 4
                        font.capitalization: Font.AllUppercase
                    }

                    Rectangle {
                        anchors.left: ledgerTag.right
                        anchors.leftMargin: 16
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: "#241f26"
                    }

                }

                Text {
                    width: parent.width
                    fontSizeMode: Text.HorizontalFit
                    text: root.msg
                    color: "#ece6e9"
                    font.family: "Newsreader"
                    font.weight: Font.Normal
                    font.pixelSize: 96
                    font.letterSpacing: -1
                    lineHeight: 1.02
                }

                Text {
                    width: Math.min(600, parent.width)
                    wrapMode: Text.WordWrap
                    text: "Your session ends and open work closes. You’ll need to sign back in."
                    color: "#8f868c"
                    font.family: "Newsreader"
                    font.pixelSize: 23
                    lineHeight: 1.5
                }

                Row {
                    topPadding: 20
                    spacing: 16

                    Rectangle {
                        width: ledgerYes.implicitWidth + 68
                        height: ledgerYes.implicitHeight + 36
                        radius: 3
                        color: "#cf4a2c"

                        Text {
                            id: ledgerYes

                            anchors.centerIn: parent
                            text: root.actionUpper
                            color: "#0f0d0f"
                            font.family: "IBM Plex Mono"
                            font.pixelSize: 15
                            font.letterSpacing: 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmed()
                        }

                    }

                    Rectangle {
                        width: ledgerNo.implicitWidth + 68
                        height: ledgerNo.implicitHeight + 36
                        radius: 3
                        color: ledgerNoMa.containsMouse ? "#1a151b" : "transparent"
                        border.width: 1
                        border.color: "#2d272e"

                        Text {
                            id: ledgerNo

                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: "#b9b1b6"
                            font.family: "IBM Plex Mono"
                            font.pixelSize: 15
                            font.letterSpacing: 2
                        }

                        MouseArea {
                            id: ledgerNoMa

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelled()
                        }

                    }

                }

                transform: Translate {
                    id: ledgerTr

                    y: 14
                }

            }

        }

    }

    // ---------------- 1d — SPLIT : decisive left / right ----------------
    Component {
        id: cSplit

        Item {
            anchors.fill: parent

            Row {
                anchors.fill: parent

                // left half — YES (confirm)
                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: splitYesMa.containsMouse ? "#141014" : "#0d0b0e"

                    Column {
                        anchors.centerIn: parent
                        spacing: 20

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Yes"
                            color: splitYesMa.containsMouse ? "#e9603f" : "#d95435"
                            font.family: "DM Serif Display"
                            font.pixelSize: 120
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "power off now"
                            color: "#7a7076"
                            font.family: "IBM Plex Mono"
                            font.pixelSize: 13
                            font.letterSpacing: 3
                            font.capitalization: Font.AllUppercase
                        }

                    }

                    MouseArea {
                        id: splitYesMa

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmed()
                    }

                }

                // right half — NO (cancel)
                Rectangle {
                    width: parent.width / 2
                    height: parent.height
                    color: splitNoMa.containsMouse ? "#100e11" : "#0a090b"

                    Column {
                        anchors.centerIn: parent
                        spacing: 20

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No"
                            color: splitNoMa.containsMouse ? "#6a636c" : "#4d4750"
                            font.family: "DM Serif Display"
                            font.pixelSize: 120
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "stay awake"
                            color: "#5a535a"
                            font.family: "IBM Plex Mono"
                            font.pixelSize: 13
                            font.letterSpacing: 3
                            font.capitalization: Font.AllUppercase
                        }

                    }

                    MouseArea {
                        id: splitNoMa

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelled()
                    }

                }

            }

            // centre divider
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: "#221d23"
            }

            // the question, centred at the top
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 44
                text: root.msg
                color: "#5a535a"
                font.family: "IBM Plex Mono"
                font.pixelSize: 14
                font.letterSpacing: 6
                font.capitalization: Font.AllUppercase
            }

        }

    }

    Behavior on opacity { NumberAnimation { duration: root.theme.anim } }
}
