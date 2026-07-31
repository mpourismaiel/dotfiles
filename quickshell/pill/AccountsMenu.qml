pragma ComponentBehavior: Bound
// AccountsMenu.qml — calendar account manager (launcher settings overlay). Lists KDE
// (read-only) + pill accounts, adds Google via loopback OAuth or Proton via an ICS
// share URL, removes pill accounts. Drives AccountsState; paints an opaque background
// so it fully covers the launcher body while open.
import QtQuick

Item {
    id: root
    required property var theme
    property var acc                       // AccountsState (may be null)
    signal closeRequested()

    property bool protonForm: false        // the Proton URL form is showing
    property bool protonSubmitted: false   // a submit is in flight (to auto-close on success)

    function _provColor(p) { return p === "proton" ? "#8a6fdf" : root.theme.event; }
    function _provName(p) { return p === "proton" ? "Proton" : "Google"; }

    Component.onCompleted: if (root.acc) root.acc.load()

    // auto-close the Proton form once a submit succeeds (no error)
    Connections {
        target: root.acc
        function onBusyChanged() {
            if (root.acc && !root.acc.busy && root.protonSubmitted) {
                root.protonSubmitted = false;
                if (!root.acc.lastError) {
                    root.protonForm = false;
                    urlInput.text = "";
                    labelInput.text = "";
                }
            }
        }
    }

    // opaque backdrop so the launcher body doesn't bleed through
    Rectangle { anchors.fill: parent; color: root.theme.bg }

    // ---- header ----
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30
        Rectangle {
            id: backBtn
            width: 26
            height: 26
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            radius: root.theme.radiusBtn
            color: backMa.containsMouse ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "chevron_left"
                size: 18
                color: backMa.containsMouse ? root.theme.text : root.theme.textDim
            }
            MouseArea {
                id: backMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }
        Text {
            anchors.left: backBtn.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Calendar accounts"
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: root.theme.fsLarge + 2
        }
    }
    Rectangle {
        id: headRule
        anchors.top: header.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: root.theme.divider
    }

    // ---- body ----
    Flickable {
        anchors.top: headRule.bottom
        anchors.topMargin: root.theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: col.height
        clip: true
        Column {
            id: col
            width: parent.width
            spacing: 8

            // ---- existing accounts ----
            Repeater {
                model: root.acc ? root.acc.accounts : []
                delegate: Rectangle {
                    id: accRow
                    required property var modelData
                    width: col.width
                    height: 48
                    radius: root.theme.radiusRow
                    color: root.theme.row

                    MSym {
                        id: provIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        icon: accRow.modelData.provider === "proton" ? "lock" : "account_circle"
                        size: 22
                        color: root._provColor(accRow.modelData.provider)
                    }
                    Column {
                        anchors.left: provIcon.right
                        anchors.leftMargin: 10
                        anchors.right: trailing.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: accRow.modelData.label
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            text: root._provName(accRow.modelData.provider)
                                + (accRow.modelData.source === "kde" ? "  ·  KDE (read-only)" : "")
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall - 1
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                    // trailing: remove (pill accounts) or a lock (KDE, read-only)
                    Item {
                        id: trailing
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        MSym {
                            visible: !accRow.modelData.removable
                            anchors.centerIn: parent
                            icon: "lock"
                            size: 15
                            color: root.theme.faint
                        }
                        Rectangle {
                            visible: accRow.modelData.removable
                            anchors.fill: parent
                            radius: root.theme.radiusBtn
                            color: rmMa.containsMouse ? root.theme.rowHi : "transparent"
                            MSym {
                                anchors.centerIn: parent
                                icon: "delete"
                                size: 16
                                color: rmMa.containsMouse ? root.theme.danger : root.theme.textDim
                            }
                            MouseArea {
                                id: rmMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !(root.acc && root.acc.busy)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.acc) root.acc.remove(accRow.modelData.id)
                            }
                            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                        }
                    }
                }
            }
            Text {
                visible: !root.acc || root.acc.accounts.length === 0
                text: "No accounts yet."
                color: root.theme.faint
                font.family: root.theme.family
                font.italic: true
                font.pixelSize: root.theme.fsNormal
            }

            // error line
            Text {
                visible: !!(root.acc && root.acc.lastError)
                width: col.width
                wrapMode: Text.WordWrap
                text: root.acc ? root.acc.lastError : ""
                color: root.theme.danger
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall - 1
            }

            Rectangle { width: col.width; height: 1; color: root.theme.divider }
            Text {
                text: "Add account"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }

            // ---- add Google ----
            Rectangle {
                width: col.width
                height: 42
                radius: root.theme.radiusRow
                color: gMa.containsMouse && !(root.acc && root.acc.busy)
                     ? root.theme.rowHi : root.theme.row
                opacity: (root.acc && root.acc.busy && root.acc.busyKind !== "google") ? 0.5 : 1
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: (root.acc && root.acc.busy && root.acc.busyKind === "google")
                            ? "progress_activity" : "add"
                        size: 18
                        color: root.theme.event
                        RotationAnimation on rotation {
                            running: !!(root.acc && root.acc.busy && root.acc.busyKind === "google")
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 900
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.acc && root.acc.busy && root.acc.busyKind === "google")
                            ? "Waiting for browser sign-in…" : "Add Google account"
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                }
                MouseArea {
                    id: gMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !(root.acc && root.acc.busy)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.acc) root.acc.addGoogle()
                }
                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }

            // ---- add Proton (toggles the URL form) ----
            Rectangle {
                width: col.width
                height: 42
                radius: root.theme.radiusRow
                color: pMa.containsMouse && !(root.acc && root.acc.busy)
                     ? root.theme.rowHi : root.theme.row
                border.width: root.protonForm ? 1 : 0
                border.color: root._provColor("proton")
                opacity: (root.acc && root.acc.busy && root.acc.busyKind !== "proton") ? 0.5 : 1
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "lock"
                        size: 18
                        color: root._provColor("proton")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add Proton calendar"
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                }
                MouseArea {
                    id: pMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !(root.acc && root.acc.busy)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.protonForm = !root.protonForm;
                        if (root.protonForm) urlInput.forceActiveFocus();
                    }
                }
                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }

            // ---- Proton URL form ----
            Column {
                visible: root.protonForm
                width: col.width
                spacing: 6
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Proton has no calendar API. In Proton Calendar open your "
                        + "calendar → Share → Share with anyone, and paste the ICS link."
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsSmall
                }
                // URL field
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: root.theme.radiusBtn
                    color: root.theme.bgElevated
                    border.width: 1
                    border.color: urlInput.activeFocus ? root._provColor("proton") : root.theme.border
                    TextInput {
                        id: urlInput
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
                        Keys.onEscapePressed: root.protonForm = false
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: urlInput.text.length === 0
                            text: "https://calendar.proton.me/api/calendar/…/calendar.ics"
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            elide: Text.ElideRight
                        }
                    }
                }
                // optional label field
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: root.theme.radiusBtn
                    color: root.theme.bgElevated
                    border.width: 1
                    border.color: labelInput.activeFocus ? root._provColor("proton") : root.theme.border
                    TextInput {
                        id: labelInput
                        objectName: "pillKbInput"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                        clip: true
                        selectByMouse: true
                        selectionColor: root.theme.accentDim
                        Keys.onEscapePressed: root.protonForm = false
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: labelInput.text.length === 0
                            text: "Label (optional)"
                            color: root.theme.faint
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                    }
                }
                // add / cancel
                Row {
                    spacing: 8
                    Rectangle {
                        width: addTxt.implicitWidth + 28
                        height: 32
                        radius: root.theme.radiusBtn
                        color: addMa.containsMouse ? root.theme.accent : root.theme.accentSoft
                        opacity: (urlInput.text.length > 0 && !(root.acc && root.acc.busy)) ? 1 : 0.5
                        Text {
                            id: addTxt
                            anchors.centerIn: parent
                            text: (root.acc && root.acc.busy && root.acc.busyKind === "proton")
                                ? "Adding…" : "Add"
                            color: addMa.containsMouse ? "#ffffff" : root.theme.accent
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: urlInput.text.length > 0 && !(root.acc && root.acc.busy)
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.acc) return;
                                root.protonSubmitted = true;
                                root.acc.addProton(urlInput.text, labelInput.text);
                            }
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                    Rectangle {
                        width: cancelTxt.implicitWidth + 28
                        height: 32
                        radius: root.theme.radiusBtn
                        color: cancelMa.containsMouse ? root.theme.rowHi : root.theme.row
                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.protonForm = false
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                }
            }
        }
    }
}
