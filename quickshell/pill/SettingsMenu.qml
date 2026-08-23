pragma ComponentBehavior: Bound
// SettingsMenu.qml — the pill's Settings page (opened from the gear right of the
// games button on the expanded dashboard; menu 13 in init.qml). A "Settings"
// title, a left sidebar of page links, and a content pane on the right. Pages:
//   • Appearance       — retheme the pill: preset grid + per-colour editor with
//                        import/export (embedded AppearanceSettings). Default page.
//   • Online Accounts — the calendar account manager (embedded AccountsMenu).
//   • Org Agenda       — enable + pick the .org directory; off by default. When on,
//                        the calendar + agenda popup show org items (see OrgAgenda).
//   • Finance          — enable + pick the hledger repo; off by default. When on,
//                        the finance menu / nag / calendar finance signals turn on.
// Feature enablement + paths persist in the launcher settings JSON, and theme
// edits persist in theme.json (both wired in init.qml), so a fresh checkout works
// with both features off and nothing is hard-coded.
import QtQuick

Item {
    id: root
    required property var theme
    property var acc                       // AccountsState (Online Accounts page)
    property var settings                  // JsonAdapter (feature flags + dirs)
    property var themeSettings             // JsonAdapter (theme colour overrides)
    property var picker: null              // root.pickFolder(cb) — native folder picker
    signal closeRequested()

    property int page: 0                   // 0 appearance · 1 accounts · 2 org agenda · 3 finance · 4 productivity
    readonly property var pages: [
        { key: "appearance", label: "Appearance",      icon: "palette" },
        { key: "accounts",   label: "Online Accounts", icon: "account_circle" },
        { key: "org",        label: "Org Agenda",      icon: "event_note" },
        { key: "finance",    label: "Finance",         icon: "account_balance_wallet" },
        { key: "productivity", label: "Productivity",  icon: "commit" }
    ]

    // opaque backdrop so the launcher body doesn't bleed through
    Rectangle { anchors.fill: parent; color: root.theme.bg }

    // ---- header: back chevron + "Settings" ----
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
            text: "Settings"
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

    // ---- body: sidebar | content ----
    Item {
        anchors.top: headRule.bottom
        anchors.topMargin: root.theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // sidebar of page links
        Column {
            id: sidebar
            width: 176
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            spacing: 4
            Repeater {
                model: root.pages
                delegate: Rectangle {
                    id: navRow
                    required property int index
                    required property var modelData
                    readonly property bool active: root.page === navRow.index
                    width: sidebar.width
                    height: 38
                    radius: root.theme.radiusRow
                    color: navRow.active ? root.theme.accentSoft
                         : (navMa.containsMouse ? root.theme.rowHi : "transparent")
                    border.width: navRow.active ? 1 : 0
                    border.color: root.theme.accent
                    MSym {
                        id: navIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        icon: navRow.modelData.icon
                        size: 18
                        color: navRow.active ? root.theme.accent
                             : (navMa.containsMouse ? root.theme.text : root.theme.textDim)
                    }
                    Text {
                        anchors.left: navIcon.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: navRow.modelData.label
                        color: navRow.active ? root.theme.accent : root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                    MouseArea {
                        id: navMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.page = navRow.index
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }

        Rectangle {
            id: sideRule
            anchors.left: sidebar.right
            anchors.leftMargin: root.theme.gap
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: root.theme.divider
        }

        // ---- content pane ----
        Item {
            id: content
            anchors.left: sideRule.right
            anchors.leftMargin: root.theme.gap
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            // Appearance — theme editor (preset grid + per-colour rows)
            AppearanceSettings {
                anchors.fill: parent
                visible: root.page === 0
                theme: root.theme
                themeSettings: root.themeSettings
            }

            // Online Accounts — the existing account manager, embedded
            AccountsMenu {
                anchors.fill: parent
                visible: root.page === 1
                theme: root.theme
                acc: root.acc
                embedded: true
            }

            // Org Agenda config
            FeaturePage {
                anchors.fill: parent
                visible: root.page === 2
                theme: root.theme
                title: "Org Agenda"
                blurb: "Show your Org agenda — scheduled items and deadlines — in the "
                     + "calendar pane and the agenda popup. Needs a running Emacs daemon."
                enableLabel: "Enable Org agenda"
                pathLabel: "Org files directory"
                pathPlaceholder: "e.g. ~/org"
                featureOn: root.settings ? root.settings.orgAgendaEnabled : false
                path: root.settings ? root.settings.orgAgendaDir : ""
                onFeatureToggled: (v) => { if (root.settings) root.settings.orgAgendaEnabled = v; }
                onPathEdited: (v) => { if (root.settings) root.settings.orgAgendaDir = v; }
            }

            // Finance config
            FeaturePage {
                anchors.fill: parent
                visible: root.page === 3
                theme: root.theme
                title: "Finance"
                blurb: "Track spending with hledger: the finance menu, calendar money "
                     + "signals and the evening “nothing logged today” nag. "
                     + "Point it at your finance repo (the folder holding main.journal)."
                enableLabel: "Enable Finance"
                pathLabel: "Finance repository"
                pathPlaceholder: "e.g. ~/Documents/finance"
                featureOn: root.settings ? root.settings.financeEnabled : false
                path: root.settings ? root.settings.financeDir : ""
                onFeatureToggled: (v) => { if (root.settings) root.settings.financeEnabled = v; }
                onPathEdited: (v) => { if (root.settings) root.settings.financeDir = v; }
            }

            // Productivity — Done page config (project dirs + author emails)
            ProductivitySettings {
                anchors.fill: parent
                visible: root.page === 4
                theme: root.theme
                settings: root.settings
                picker: root.picker
            }
        }
    }
}
