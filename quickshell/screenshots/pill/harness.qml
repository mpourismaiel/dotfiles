pragma ComponentBehavior: Bound
// harness.qml — off-screen screenshot gallery for the pill (screenshot harness only).
// Hosts the REAL leaf components (CollapsedPill, DesktopDots, Taskbar, StatusIcons)
// and the REAL menus against Mock* state objects, inside a FloatingWindow. It never
// instantiates a NotificationServer, winbridge, or any Process/DBus source, so it
// cannot touch the live pill. A grabber steps through each stage and saves a PNG.
import QtQuick
import Quickshell

FloatingWindow {
    id: win
    visible: true
    implicitWidth: 900
    implicitHeight: 560
    color: "#151310"
    property string outDir: "@OUT@"

    Theme { id: theme }
    MockNetState  { id: netState }
    MockNotifs    { id: notifs }
    MockClip      { id: clip }
    MockMemos     { id: memos }
    MockOrg       { id: org }
    MockFinance   { id: fin }
    MockCal       { id: cal }
    MockBrightness { id: brightness }
    // stand-in for the launcher settings JsonAdapter (feature flags + dirs)
    QtObject {
        id: mockSettings
        property bool orgAgendaEnabled: true
        property string orgAgendaDir: "~/org"
        property bool financeEnabled: true
        property string financeDir: "~/Documents/finance"
        // seed a mid-game Tetris so the screenshot shows a real stack, not an empty well
        property var tetris: ({
            "board": (function () {
                var b = [];
                for (var r = 0; r < 20; r++) {
                    var row = [];
                    for (var c = 0; c < 10; c++)
                        row.push((r >= 15 && !((r + c) % 4 === 0 && c > 5)) ? ["I","J","L","O","S","T","Z"][(r + c) % 7] : "");
                    b.push(row);
                }
                return b;
            })(),
            "cur": { "type": "T", "rot": 0, "x": 4, "y": 2 },
            "queue": ["I", "L", "S", "Z"],
            "bag": ["O", "J"],
            "score": 1240, "lines": 7, "level": 1, "high": 3200,
            "over": false, "paused": false
        })
    }

    // mock clock strings so the dashboard is deterministic
    readonly property string clockShort: "09:41"
    readonly property string clockDate:  "WED, 22 JUL"

    // ---- a pill-shaped host for an open menu (bg surface + padded content area) ----
    component MenuHost: Item {
        id: host
        property int pillW: 520
        property int pillH: 470
        default property alias content: inner.data
        width: pillW
        height: pillH
        PillSurface {
            anchors.fill: parent
            anchors.leftMargin: -34
            anchors.rightMargin: -34
            theme: theme
            radius: theme.radiusPanel
            wing: 34
            fillColor: theme.bg
        }
        Item { id: inner; anchors.fill: parent; anchors.margins: theme.pad }
    }

    // ======================= gallery states =======================
    // SHOT_ONLY (env) renders just the states whose name contains this substring,
    // skipping the rest instantly — a fast single-target loop while iterating on one
    // pane. Empty = render everything (the full regression pass; run this when done).
    property string only: (Quickshell.env("SHOT_ONLY") || "")
    property int _shot: -1
    property var _states: [
        { name: "resting",       comp: cResting },
        { name: "resting-rec",   comp: cRestingRec },
        { name: "resting-due",   comp: cRestingDue },
        { name: "resting-meeting", comp: cRestingMeeting },
        { name: "deadlines",     comp: cDeadlines },
        { name: "dashboard",     comp: cDashboard },
        { name: "menu-network",  comp: cNet },
        { name: "menu-volume",   comp: cVol },
        { name: "menu-bluetooth", comp: cBt },
        { name: "menu-battery",  comp: cBatt },
        { name: "menu-clipboard", comp: cClip },
        { name: "menu-calendar", comp: cCal },
        { name: "menu-finance", comp: cFin },
        { name: "menu-finance-add", comp: cFinAdd },
        { name: "menu-finance-wishlist", comp: cFinWish },
        { name: "menu-finance-forecast", comp: cFinFore },
        { name: "menu-finance-plan", comp: cFinPlan },
        { name: "menu-tetris",   comp: cTetris },
        { name: "settings",      comp: cSettings },
        { name: "menu-notifhistory", comp: cNotifHist },
        { name: "notif-stack",   comp: cNotifStack },
        { name: "power-hush",    comp: cPowerHush },
        { name: "power-blaze",   comp: cPowerBlaze },
        { name: "power-ledger",  comp: cPowerLedger },
        { name: "power-split",   comp: cPowerSplit }
    ]

    Loader { id: stage; anchors.centerIn: parent }

    function _next() {
        win._shot++;
        if (win._shot >= win._states.length) { Qt.quit(); return; }
        // SHOT_ONLY: skip non-matching states with no grab delay (keeps the same
        // _shot index, so filenames match a full run — e.g. pill-17-menu-tetris.png)
        if (win.only && win._states[win._shot].name.indexOf(win.only) < 0) { Qt.callLater(win._next); return; }
        stage.sourceComponent = win._states[win._shot].comp;
        grabTimer.restart();
    }
    Timer { id: startTimer; interval: 900; running: true; onTriggered: win._next() }
    Timer {
        id: grabTimer; interval: 800; repeat: false     // room for entrance animations
        onTriggered: {
            var it = stage.item;
            var s = win._states[win._shot];
            if (!it) { Qt.callLater(win._next); return; }
            it.grabToImage(function (res) {
                res.saveToFile(win.outDir + "/pill-" + win._shot + "-" + s.name + ".png");
                Qt.callLater(win._next);
            }, Qt.size(Math.ceil(it.width * 2), Math.ceil(it.height * 2)));
        }
    }

    // ---------------- resting collapsed pill ----------------
    Component {
        id: cResting
        Item {
            width: 168; height: 30
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort; hasUnread: true
                notifGroups: notifs.grouped; iconsMax: 4
            }
        }
    }
    // resting with a live screen-recording (solid + red pulse dot + unread)
    Component {
        id: cRestingRec
        Item {
            width: 150; height: 30
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bg
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort; solid: true; recordingOn: true; cameraOn: true
                // a screencast auto-enters DND → app strip hidden, generic dot shown
                dnd: true; hasUnread: true; notifGroups: notifs.grouped; iconsMax: 4
            }
        }
    }

    // resting pill with an org-deadline under-line (overdue + due-today counts).
    // Taller pill, 2px-smaller clock, "⚑ N LATE · M TODAY" beneath it.
    Component {
        id: cRestingDue
        Item {
            width: 360; height: 48
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort
                lateCount: org.lateCount; todayCount: org.todayCount
                // combined with an imminent meeting to show the full under-line
                meetingMins: 7
            }
        }
    }
    // resting pill with only an imminent-meeting notice (no deadlines) —
    // "⚑-free" under-line: just the calendar icon + "N MIN TO MEETING".
    Component {
        id: cRestingMeeting
        Item {
            width: 200; height: 48
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort
                meetingMins: 3
            }
        }
    }
    // the floating agenda list (right-click / under-line target): org deadlines + events
    Component {
        id: cDeadlines
        Item {
            width: 420; height: 980
            AgendaMenu {
                // bodyMax raised so the whole list (deadlines + events) shows in the
                // still; live it stays capped and scrolls.
                anchors.fill: parent; theme: theme; org: org; cal: cal
                bodyMax: 1200
                open: true; px: 8; py: 8
            }
        }
    }

    // ---------------- hovered dashboard (two rows) ----------------
    Component {
        id: cDashboard
        Item {
            id: dash
            width: 640; height: 150
            PillSurface {
                anchors.fill: parent; anchors.leftMargin: -34; anchors.rightMargin: -34
                theme: theme; radius: theme.radiusPanel; wing: 34; fillColor: theme.bg
            }
            // Row 1: datetime + desktop dots (left) | taskbar (right)
            Item {
                x: theme.pad + 8; y: 20
                width: dash.width - (theme.pad + 8) * 2; height: 36
                Column {
                    anchors.left: parent.left; anchors.top: parent.top
                    anchors.topMargin: -10; spacing: 9
                    Item {
                        implicitWidth: dtColMock.implicitWidth; implicitHeight: dtColMock.implicitHeight
                        Column {
                            id: dtColMock
                            spacing: 1
                            Text { id: clockTimeMock; text: win.clockShort; color: theme.text; font.family: theme.serif; font.pixelSize: 34; lineHeight: 0.9 }
                            Text { text: win.clockDate; color: theme.textDim; font.family: theme.mono
                                   font.pixelSize: theme.fsSmall; font.letterSpacing: theme.labelSpacing
                                   font.capitalization: Font.AllUppercase; lineHeight: 0.95 }
                        }
                        // tiny tetromino button beside the clock (mirrors init.qml)
                        Rectangle {
                            anchors.left: dtColMock.right; anchors.leftMargin: 12
                            anchors.verticalCenter: clockTimeMock.verticalCenter
                            width: 26; height: 26; radius: theme.radiusSmall; color: "transparent"
                            Item {
                                id: tetGlyphMock
                                anchors.centerIn: parent; width: 15; height: 10
                                readonly property int u: 5
                                Repeater {
                                    model: [[1,0],[2,0],[0,1],[1,1]]
                                    delegate: Rectangle {
                                        required property var modelData
                                        x: modelData[0] * tetGlyphMock.u; y: modelData[1] * tetGlyphMock.u
                                        width: tetGlyphMock.u - 1; height: tetGlyphMock.u - 1; radius: 1; color: theme.accent
                                    }
                                }
                            }
                        }
                    }
                    DesktopDots {
                        theme: theme
                        desktops: [{ id: "1", name: "one" }, { id: "2", name: "two" },
                                   { id: "3", name: "three" }, { id: "4", name: "four" }]
                        activeIdx: 1
                    }
                }
                Taskbar {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    theme: theme
                    activeWindow: "w-code"
                    groups: [
                        { key: "pin:firefox", icon: "firefox", entry: null, wins: [{ uuid: "w-ff" }], desks: [], onAll: false, pinned: true },
                        { key: "win:code", icon: "visual-studio-code", entry: null,
                          wins: [{ uuid: "w-code" }, { uuid: "w-code2" }], desks: [], onAll: false, pinned: false },
                        { key: "win:kitty", icon: "kitty", entry: null, wins: [{ uuid: "w-kitty" }], desks: [], onAll: false, pinned: false },
                        { key: "pin:telegram", icon: "telegram", entry: null, wins: [], desks: [], onAll: false, pinned: true }
                    ]
                }
            }
            // divider
            Rectangle { x: theme.pad + 8 + 60; y: 86; width: dash.width - (theme.pad + 8) - x; height: 1; color: theme.divider }
            // Row 2: launcher glyph (left) | status icons (right)
            Item {
                x: theme.pad + 8; y: 100
                width: dash.width - (theme.pad + 8) * 2; height: 42
                Rectangle {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: 42; height: 42; radius: 12; color: theme.accentSoft
                    MSym { anchors.centerIn: parent; icon: "grid_view"; size: 22; fill: 1; weight: 500; color: theme.accent }
                }
                StatusIcons {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    theme: theme; notifs: notifs; netState: netState; open: true; menu: 0
                }
            }
        }
    }

    // ---------------- menus ----------------
    Component { id: cNet;  MenuHost { NetworkMenu   { anchors.fill: parent; theme: theme; netState: netState } } }
    Component { id: cVol;  MenuHost { VolumeMenu    { anchors.fill: parent; theme: theme } } }
    Component { id: cBt;   MenuHost { BluetoothMenu { anchors.fill: parent; theme: theme } } }
    Component { id: cBatt; MenuHost { BatteryMenu   { anchors.fill: parent; theme: theme; brightness: brightness } } }
    Component { id: cClip; MenuHost { pillH: 670; ClipboardMenu { anchors.fill: parent; theme: theme; clip: clip; memos: memos } } }
    Component { id: cCal;  MenuHost { pillW: 760; CalendarMenu  { anchors.fill: parent; theme: theme; org: org; fin: fin; cal: cal } } }
    Component { id: cFin;  MenuHost { pillW: 760; FinanceMenu   { anchors.fill: parent; theme: theme; fin: fin } } }
    Component { id: cTetris; MenuHost { pillW: 480; pillH: 556; TetrisMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    // the launcher's Settings page (Org Agenda page shown: toggle + directory field)
    Component { id: cSettings; MenuHost { pillW: 760; SettingsMenu { anchors.fill: parent; theme: theme; acc: null; settings: mockSettings; page: 1 } } }
    Component {
        id: cFinAdd
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("add")
            }
        }
    }
    Component {
        id: cFinWish
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("wishlist")
            }
        }
    }
    Component {
        id: cFinFore
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("forecast")
            }
        }
    }
    Component {
        id: cFinPlan
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("plan")
            }
        }
    }
    Component { id: cNotifHist; MenuHost { NotificationHistory { anchors.fill: parent; theme: theme; notifs: notifs } } }
    Component {
        id: cNotifStack
        Item {
            width: st.implicitWidth; height: st.implicitHeight
            NotificationStack { id: st; anchors.centerIn: parent; theme: theme; notifs: notifs }
        }
    }

    // ---------------- power-confirmation designs (extracted PowerConfirm.qml) ----------------
    component PowerCanvas: Item {
        property string variant: "1a"
        property string action: "shutdown"
        property string msg: "Really?"
        width: 1280; height: 800
        PowerConfirm {
            anchors.fill: parent; theme: theme; active: true
            action: parent.action; msg: parent.msg; variant: parent.variant; clock: win.clockShort
        }
    }
    Component { id: cPowerHush;   PowerCanvas { variant: "1a"; action: "shutdown"; msg: "Really?" } }
    Component { id: cPowerBlaze;  PowerCanvas { variant: "1b"; action: "reboot";   msg: "No shit!" } }
    Component { id: cPowerLedger; PowerCanvas { variant: "1c"; action: "logout";   msg: "Are you serious?" } }
    Component { id: cPowerSplit;  PowerCanvas { variant: "1d"; action: "shutdown"; msg: "No kidding?" } }
}
