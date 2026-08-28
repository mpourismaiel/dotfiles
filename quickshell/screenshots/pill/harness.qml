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
    // stand-in for the theme-overrides JsonAdapter (Settings → Appearance).
    // A couple of overrides so the Appearance page shows reset dots + a non-default
    // preset state; the rest fall back to Theme defaults.
    QtObject {
        id: mockThemeSettings
        property var colors: ({ "accent": "#e0662a", "money": "rgba(217, 164, 65, 0.9)" })
        property string clockStyle: "1e"   // a non-default pick so the card shows active
    }
    // stand-in for the launcher settings JsonAdapter (feature flags + dirs)
    QtObject {
        id: mockSettings
        property bool orgAgendaEnabled: true
        property string orgAgendaDir: "~/org"
        property bool financeEnabled: true
        property string financeDir: "~/Documents/finance"
        // Done page config (Settings › Productivity)
        property var productivityDirs: ["~/Documents/projects/awesome", "~/Documents/projects/teamwork", "~/work/shledger"]
        property var productivityEmails: ["you@example.com", "you@work.dev"]
        // seed a few emoji favourites so the picker opens on its Favorites tab
        property var emojiFavorites: ["😀", "🔥", "❤️", "🎉", "👍", "🚀", "😂", "✅"]
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
        // seed a mid-game Block Blast so the screenshot shows a real board + tray
        property var blockBlast: ({
            "board": (function () {
                var b = [];
                var fill = ["i4", "sq2", "jL", "tT", "sS", "cl2", "cl3", "d3"];
                for (var r = 0; r < 10; r++) {
                    var row = [];
                    for (var c = 0; c < 10; c++)
                        row.push(((r + c) % 3 === 0 && !(r === 4 && c > 5)) ? fill[(r * 10 + c) % fill.length] : "");
                    b.push(row);
                }
                return b;
            })(),
            "tray": [
                { "kind": "jL", "cells": [[0,0],[0,1],[1,1],[2,1]] },
                { "kind": "sq3", "cells": [[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]] },
                { "kind": "d2", "cells": [[0,0],[1,0]] }
            ],
            "score": 860, "best": 2140, "combo": 3, "over": false
        })
        // seed a mid-game Snake with a bulge (eaten apple) partway down the body. Head
        // points right into a long runway so it survives the ~800ms grab window when
        // the harness unpauses it (see cSnake).
        property var snake: ({
            "body": [
                { "x": 7, "y": 7 }, { "x": 6, "y": 7 }, { "x": 5, "y": 7 },
                { "x": 4, "y": 7 }, { "x": 3, "y": 7 }, { "x": 2, "y": 7 }
            ],
            "bulges": [ { "x": 4, "y": 7 } ],
            "dir": { "x": 1, "y": 0 },
            "apple": { "x": 11, "y": 3 },
            "score": 14, "best": 22, "over": false
        })
        property var minesweeper: ({ "diff": 0, "best": [ 42, 0, 0 ] })
    }

    // stand-in for DoneState (seeded CODE + AGENDA data, no bridge calls)
    MockDone { id: mockDone }

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
        { name: "clock-styles",  comp: cClockStyles },
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
        { name: "menu-finance-register", comp: cFinReg },
        { name: "menu-finance-category", comp: cFinCat },
        { name: "menu-tetris",   comp: cTetris },
        { name: "menu-tetris-share", comp: cTetrisShare },
        { name: "menu-blockblast", comp: cBlockBlast },
        { name: "menu-blockblast-combo", comp: cBlockBlastCombo },
        { name: "menu-blockblast-share", comp: cBlockBlastShare },
        { name: "menu-snake",    comp: cSnake },
        { name: "menu-minesweeper", comp: cMine },
        { name: "settings",      comp: cSettings },
        { name: "settings-productivity", comp: cSettingsProd },
        { name: "menu-emoji",    comp: cEmoji },
        { name: "menu-emoji-search", comp: cEmojiSearch },
        { name: "menu-done",     comp: cDone },
        { name: "menu-done-loading", comp: cDoneLoading },
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
    // every collapsed-clock design (Settings → Appearance → Clock and Agenda),
    // each shown resting (clock only) and with a sample agenda under-line. Each pill
    // is sized by the SAME dynamic rule init.qml uses for the real resting pill —
    // width = max(56, content + 23), height = max(28|48, content + 7) — so the
    // screenshot shows whether every style actually fits (no overflow, no cramping).
    // A dashed keyline traces each pill so any clipping is obvious.
    Component {
        id: cClockStyles
        // one sized pill hosting a CollapsedPill, mirroring init's resting bindings
        component StylePill: Item {
            id: sp
            property string styleId: "1a"
            property bool due: false
            width: Math.max(56, cp.implicitWidth + 23)
            height: Math.max(sp.due ? 48 : 28, cp.implicitHeight + 7)
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            // keyline exactly on the pill bounds — content spilling past it = overflow
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Math.min(theme.radiusPanel, height / 2)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
            }
            CollapsedPill {
                id: cp
                anchors.centerIn: parent; theme: theme
                styleOverride: sp.styleId
                clock: "09:41"
                lateCount: sp.due ? 1 : 0
                todayCount: sp.due ? 1 : 0
                meetingMins: sp.due ? 10 : -1
            }
        }
        Rectangle {
            width: 720
            color: theme.desk
            implicitHeight: stylesCol.height + 32
            Column {
                id: stylesCol
                x: 16; y: 16
                width: parent.width - 32
                spacing: 14
                Repeater {
                    model: theme.clockStyles
                    delegate: Row {
                        required property var modelData
                        spacing: 20
                        Text {
                            width: 168
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.id + " · " + modelData.name
                            color: theme.textDim
                            font.family: theme.family
                            font.pixelSize: 13
                        }
                        StylePill {
                            anchors.verticalCenter: parent.verticalCenter
                            styleId: modelData.id
                        }
                        StylePill {
                            anchors.verticalCenter: parent.verticalCenter
                            styleId: modelData.id
                            due: true
                        }
                    }
                }
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
                        // two tiny game buttons stacked beside the clock (mirrors init.qml):
                        // S-tetromino (Tetris) over plus/T (Block Blast)
                        Column {
                            anchors.left: dtColMock.right; anchors.leftMargin: 12
                            anchors.verticalCenter: clockTimeMock.verticalCenter
                            spacing: 4
                            Rectangle {
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
                            Rectangle {
                                width: 26; height: 26; radius: theme.radiusSmall; color: "transparent"
                                Item {
                                    id: blockGlyphMock
                                    anchors.centerIn: parent; width: 15; height: 10
                                    readonly property int u: 5
                                    Repeater {
                                        model: [[1,0],[0,1],[1,1],[2,1]]
                                        delegate: Rectangle {
                                            required property var modelData
                                            x: modelData[0] * blockGlyphMock.u; y: modelData[1] * blockGlyphMock.u
                                            width: blockGlyphMock.u - 1; height: blockGlyphMock.u - 1; radius: 1; color: theme.accent
                                        }
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
    // Tetris with the screenshot share card up (shareMode toggled after load; no grab
    // Process runs — this just previews the pretty card layout).
    Component { id: cTetrisShare; MenuHost { pillW: 480; pillH: 556;
        TetrisMenu { id: tsh; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: { tsh.shotName = "tetris-20260806-101500.png"; tsh.shareMode = true; } }
    } }
    Component { id: cBlockBlast; MenuHost { pillW: 480; pillH: 556; BlockBlastMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    // Block Blast mid-combo-flare (fires popCombo ~450ms before the 800ms grab, so
    // the "3× COMBO" flare is caught at full pop). Preview only — no real drop.
    Component { id: cBlockBlastCombo; MenuHost { pillW: 480; pillH: 556;
        BlockBlastMenu { id: bcm; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 350; onTriggered: bcm.popCombo(3) }
    } }
    Component { id: cBlockBlastShare; MenuHost { pillW: 480; pillH: 556;
        BlockBlastMenu { id: bsh; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: { bsh.shotName = "blockblast-20260807-101500.png"; bsh.shareMode = true; } }
    } }
    // Snake — unpaused after load so the field (snake + digesting lump + apple) is
    // visible rather than under the PAUSED veil. Preview only.
    Component { id: cSnake; MenuHost { pillW: 560; pillH: 400;
        SnakeMenu { id: snk; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: snk.paused = false }
    } }
    // Minesweeper — reveal a couple of cells after load so the field shows numbers /
    // flood-filled area rather than a blank grid. Preview only.
    Component { id: cMine; MenuHost { pillW: 560; pillH: 420;
        MinesweeperMenu { id: mine; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: { mine.reveal(20); mine.toggleFlag(0); } }
    } }
    // the launcher's Settings page (Org Agenda page shown: toggle + directory field)
    Component { id: cSettings; MenuHost { pillW: 860; pillH: 580; SettingsMenu { anchors.fill: parent; theme: theme; acc: null; settings: mockSettings; themeSettings: mockThemeSettings; page: 0 } } }
    // the Productivity settings page (project dirs + author emails)
    Component { id: cSettingsProd; MenuHost { pillW: 860; pillH: 580; SettingsMenu { anchors.fill: parent; theme: theme; acc: null; settings: mockSettings; themeSettings: mockThemeSettings; page: 4 } } }
    // the emoji picker (menu 16) opened on its Favorites tab (mockSettings seeds a
    // few favourites), plus a search variant (Timer types a query post-load)
    Component { id: cEmoji; MenuHost { pillW: 600; pillH: 470; EmojiMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    Component { id: cEmojiSearch; MenuHost { pillW: 600; pillH: 470;
        EmojiMenu { id: emo; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: emo.query = "heart" }
    } }
    // the Done work-history page (menu 15) over the seeded MockDone
    Component { id: cDone; MenuHost { pillW: 820; pillH: 560; DoneMenu { anchors.fill: parent; theme: theme; done: mockDone } } }
    // the Done page mid-load (skeleton chapters + busy stripe)
    Component { id: cDoneLoading; MenuHost { pillW: 820; pillH: 420; DoneMenu { anchors.fill: parent; theme: theme; done: MockDone { loading: true } } } }
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
    Component {
        id: cFinReg
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("register")
            }
        }
    }
    Component {
        id: cFinCat
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: { openMode("register"); registerFilter = "category"; loadRegisterView(); }
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
