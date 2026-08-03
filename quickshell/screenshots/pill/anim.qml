pragma ComponentBehavior: Bound
// anim.qml — off-screen ANIMATION capture harness for the pill (screenshot
// harness family). Sibling of harness.qml: where harness.qml grabs one still per
// state, this one plays a named animation scene and grabs a burst of frames on a
// timer, which animate.sh then encodes to mp4/gif (+ keeps the PNG frames for
// visual inspection). It hosts the REAL animated components (AgendaMenu,
// NotificationDroplet, NotificationStack) against Mock* state, inside a
// FloatingWindow — it never instantiates a NotificationServer / winbridge / DBus
// source, so it cannot touch the live pill.
//
// Each scene is an Item that exposes `function play()` (kick the animation from
// its start state) and, optionally, `settleMs` / `durationMs` overrides. The
// grabber: load scene -> wait settleMs -> play() + start frame timer -> grab a
// frame every FRAME_MS for durationMs -> next scene. Frames land in
// $OUT/frames/<scene>/f####.png.
import QtQuick
import Quickshell

FloatingWindow {
    id: win
    visible: true
    implicitWidth: 620
    implicitHeight: 360
    color: "#151310"
    property string outDir: "@OUT@"

    // capture cadence: 25 fps is plenty for these short UI moments and keeps
    // grabToImage from queuing up on the render thread.
    readonly property int frameMs: 40

    Theme { id: theme }
    MockNotifs { id: notifs }
    MockOrg    { id: org }

    // ======================= scenes =======================
    property int _scene: -1
    property var _scenes: [
        { name: "deadlines", comp: cDeadlines, settleMs: 450, durationMs: 700 },
        { name: "droplet",   comp: cDroplet,   settleMs: 450, durationMs: 1150 }
    ]

    Loader { id: stage; anchors.centerIn: parent }

    property int _frame: 0
    property int _framesLeft: 0

    function _nextScene() {
        win._scene++;
        if (win._scene >= win._scenes.length) { Qt.quit(); return; }
        stage.sourceComponent = win._scenes[win._scene].comp;
        win._frame = 0;
        settleTimer.interval = win._scenes[win._scene].settleMs;
        settleTimer.restart();
    }

    // after the scene settles: reset frame counter, start playing + capturing
    Timer {
        id: settleTimer
        onTriggered: {
            var s = win._scenes[win._scene];
            win._framesLeft = Math.ceil(s.durationMs / win.frameMs) + 3; // a few tail frames
            if (stage.item && stage.item.play) stage.item.play();
            frameTimer.restart();
        }
    }

    Timer {
        id: frameTimer
        interval: win.frameMs
        repeat: true
        running: false
        onTriggered: {
            var it = stage.item;
            var s = win._scenes[win._scene];
            if (!it) { running = false; Qt.callLater(win._nextScene); return; }
            var idx = win._frame;
            var name = s.name;
            it.grabToImage(function (res) {
                var pad = ("0000" + idx).slice(-4);
                res.saveToFile(win.outDir + "/frames/" + name + "-f" + pad + ".png");
            }, Qt.size(Math.ceil(it.width * 2), Math.ceil(it.height * 2)));
            win._frame++;
            win._framesLeft--;
            if (win._framesLeft <= 0) { running = false; Qt.callLater(win._nextScene); }
        }
    }

    Timer { id: startTimer; interval: 600; running: true; onTriggered: win._nextScene() }

    // ---------------- scene: agenda menu droplet entrance ----------------
    // Mirrors the live layout: a resting pill sits at the top, and on open the agenda
    // panel wells out of its bottom lip as a droplet that expands into the window.
    Component {
        id: cDeadlines
        Item {
            id: dscene
            width: 440; height: 520
            readonly property int lip: 40           // pill bottom (y=10 + height 30)
            function play() { menu.open = false; reopen.restart(); }
            Timer { id: reopen; interval: 60; onTriggered: menu.open = true }

            // resting pill (mock — surface + clock), attached to the top
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                width: 150; height: 30
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: theme.bg
                    border.color: theme.border; border.width: 1
                }
                Text {
                    anchors.centerIn: parent
                    text: "09:41"
                    color: theme.text; font.family: theme.serif; font.pixelSize: 17
                }
            }

            AgendaMenu {
                id: menu
                anchors.fill: parent
                theme: theme; org: org
                // panel centred under the pill, its top a dropGap below the lip
                open: false
                px: dscene.width / 2 - 200
                py: dscene.lip + 8
            }
        }
    }

    // ---------------- scene: notification water-droplet drop-out ----------------
    // Mirrors the live resting layout: the collapsed pill sits attached to the top
    // edge, the droplet detaches from its bottom lip, and the notification deck
    // floats below, its entrance synced to the droplet landing.
    Component {
        id: cDroplet
        Item {
            id: nscene
            width: 480; height: 320
            property bool entered: false
            readonly property int dropGap: 8

            function play() {
                entered = false;
                drop.play();
            }

            // resting pill (mock — just the surface + a clock), attached to the top
            Item {
                id: mockPill
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                width: 150; height: 30
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: theme.bgTranslucent
                    border.color: theme.border; border.width: 1
                }
                Text {
                    anchors.centerIn: parent
                    text: "09:41"
                    color: theme.text; font.family: theme.serif; font.pixelSize: 17
                }
            }

            // the droplet, anchored to the pill's bottom lip, centred on the pill —
            // declared BEFORE the deck so it renders behind it (the card fades in over
            // the expanded rect).
            NotificationDroplet {
                id: drop
                x: mockPill.x; width: mockPill.width
                y: mockPill.y + mockPill.height
                height: nscene.dropGap
                theme: theme
                fallDistance: nscene.dropGap
                cardWidth: deck.topCardWidth
                cardHeight: deck.topCardHeight
                cardRadius: theme.radiusCard
                bgColor: theme.bg
                accentColor: theme.accent
                cardColor: theme.card
                onLanded: nscene.entered = true
            }

            // the notification deck, floating dropGap below the pill lip; fades in
            // over the droplet's expanded rect.
            NotificationStack {
                id: deck
                anchors.horizontalCenter: parent.horizontalCenter
                y: mockPill.y + mockPill.height + nscene.dropGap
                theme: theme; notifs: notifs
                opacity: nscene.entered ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: 150 }
                        NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
