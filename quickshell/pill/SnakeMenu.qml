pragma ComponentBehavior: Bound
// SnakeMenu.qml — the classic Snake, played inside the control panel (menu 14,
// opened from the Games list). A square 15×15 field on the left; score / best /
// length / live speed, the rules and New game · Pause on the right — the same
// layout as Brick Breaker (menu 12), whose pane config this reuses.
//
// The snake glides one cell per tick, smoothly: a shared `prog` 0→1 animation runs
// each tick and every segment interpolates from the cell it held to the cell the
// segment ahead just left, so the whole body slides continuously even though the
// model is grid-stepped. There are no walls — the field WRAPS: the head that runs
// off one edge reappears on the opposite one, and because each segment interpolates
// along the *shortest toroidal path* (drawing a wrap "ghost" as it straddles the
// seam) the body crosses an edge one cell at a time rather than teleporting whole.
//
// Eating grows the snake *immediately* (the head lands on the apple and the tail is
// simply not retracted that tick, so length +1 at once). The apple's old tile is
// remembered as a BULGE: the segment sitting on it renders fatter, and the bulge
// stays parked on that world tile while the body slides through it — until the tail
// finally passes the tile, when the bulge clears. So an eaten apple visibly travels
// down the body as a lump. The freshly added tail segment *sprouts* (scales in), so
// growth reads as the tail extending rather than a cell popping into place. Apples
// pop in with a scale animation and just vanish the instant they are eaten.
//
// Keys (the pane grabs the keyboard while it is menu 14, see init.qml
// grabsKeyboard): arrows or H/J/K/L steer, P pauses. Opens paused; on game over
// Enter/Space starts a new game, Escape closes. Full state (body, direction, apple,
// bulges, score, best) persists into the shared launcher settings under `snake`, so
// closing the panel or restarting the shell resumes mid-game.
import QtQuick

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — persistence lives in settings.snake
    signal closeRequested()

    // park-drag: the header grip drives these; init.qml catches them and moves the
    // whole pane (shared tetris* park state — see the Connections block).
    signal parkDragStart(real sx, real sy)
    signal parkDragMove(real sx, real sy)
    signal parkDragEnd()

    // ---- geometry ----
    readonly property int cols: 15
    readonly property int rows: 15
    readonly property int cell: 20
    readonly property real fieldW: cols * cell       // 300
    readonly property real fieldH: rows * cell       // 300

    // ---- speed ----
    // deliberately unhurried — quickens a little as the snake grows, floored so it
    // never becomes frantic.
    readonly property int baseInterval: 300          // ms per step at score 0
    readonly property int moveInterval: Math.max(150, root.baseInterval - root.score * 3)

    // ---- state ----
    // body is head→tail; each segment is { x, y } and keeps its cell for its lifetime
    // (movement = unshift a new head, pop the tail unless we just ate). `bulges` is a
    // list of world tiles where apples were eaten and are still travelling down the
    // body (a tile clears once the tail retracts past it).
    property var body: []
    property var bulges: []                           // [{ x, y }] world tiles still digesting
    property var dir: ({ "x": 1, "y": 0 })            // committed heading, applied each tick
    property var nextDir: ({ "x": 1, "y": 0 })        // queued heading from the last key press
    property var apple: null                           // { x, y } or null when the board is full
    property int score: 0
    property int best: 0
    property bool over: false
    property bool paused: false
    property int snakeLen: 0                            // body.length, mirrored for the Repeater model
    property int snakeRev: 0                            // bump to re-read `body` / `bulges` in the render
    property int appleRev: 0                            // bump to re-pop the apple's appear animation
    property bool snap: false                           // when true, segments jump (no glide) on the next rev
    property bool ready: false                          // false during initial build → no sprout on load
    property real prog: 1                               // 0→1 interpolation across the current step

    readonly property color snakeColor: root.theme.accent
    readonly property color headColor: Qt.lighter(root.theme.accent, 1.35)
    readonly property color appleColor: "#e0574a"

    // world tiles currently bulging, as a lookup keyed "x,y" (re-read on snakeRev)
    readonly property var bulgeSet: {
        root.snakeRev;
        var m = ({});
        for (var i = 0; i < root.bulges.length; i++) m[root.bulges[i].x + "," + root.bulges[i].y] = true;
        return m;
    }

    // ---- helpers ----
    function cellKey(x, y) { return x + "," + y; }

    function spawnApple() {
        var occ = ({});
        for (var i = 0; i < root.body.length; i++) occ[root.cellKey(root.body[i].x, root.body[i].y)] = true;
        var free = [];
        for (var y = 0; y < root.rows; y++)
            for (var x = 0; x < root.cols; x++)
                if (!occ[root.cellKey(x, y)]) free.push({ "x": x, "y": y });
        if (free.length === 0) { root.apple = null; return; }   // board full — nowhere to place
        root.apple = free[Math.floor(Math.random() * free.length)];
        root.appleRev++;
    }

    function newGame() {
        var cx = Math.floor(root.cols / 2), cy = Math.floor(root.rows / 2);
        root.body = [
            { "x": cx,     "y": cy },
            { "x": cx - 1, "y": cy },
            { "x": cx - 2, "y": cy }
        ];
        root.bulges = [];
        root.dir = { "x": 1, "y": 0 };
        root.nextDir = { "x": 1, "y": 0 };
        root.score = 0;
        root.over = false;
        root.paused = false;
        root.snakeLen = root.body.length;
        root.spawnApple();
        root.prog = 1;
        root.snap = true; root.snakeRev++; root.snap = false;   // land segments on their cells, no glide
        root.save();
    }

    function die() {
        root.over = true;
        if (root.score > root.best) root.best = root.score;
        root.save();
    }

    // steer — ignore a reversal into the neck (opposite of the committed heading)
    function steer(dx, dy) {
        if (root.over || root.paused) return;
        if (dx === -root.dir.x && dy === -root.dir.y) return;
        root.nextDir = { "x": dx, "y": dy };
    }

    // one step: commit the queued heading, wrap at the edges, grow immediately on an
    // apple (tail kept), and clear any bulge whose tile the tail has now passed.
    function step() {
        root.dir = root.nextDir;
        var nx = (root.body[0].x + root.dir.x + root.cols) % root.cols;   // wrap
        var ny = (root.body[0].y + root.dir.y + root.rows) % root.rows;

        var willEat = root.apple && nx === root.apple.x && ny === root.apple.y;

        // self-collision — the tail cell frees up this step UNLESS we're growing
        for (var i = 0; i < root.body.length; i++) {
            if (!willEat && i === root.body.length - 1) continue;
            if (root.body[i].x === nx && root.body[i].y === ny) { root.die(); return; }
        }

        root.body.unshift({ "x": nx, "y": ny });
        if (willEat) {
            root.bulges.push({ "x": nx, "y": ny });   // remember the apple's tile as a lump
            root.score++;
            if (root.score > root.best) root.best = root.score;
            root.spawnApple();                          // old apple simply vanishes; a fresh one pops in
            // tail NOT popped → length grows now
        } else {
            root.body.pop();
        }

        // a bulge lives only while its tile is still part of the body
        var occ = ({});
        for (var k = 0; k < root.body.length; k++) occ[root.cellKey(root.body[k].x, root.body[k].y)] = true;
        root.bulges = root.bulges.filter(b => occ[root.cellKey(b.x, b.y)]);

        root.snakeLen = root.body.length;
        root.prog = 0;
        root.snakeRev++;      // segments re-read body → glide begins
        progAnim.restart();
        root.save();
    }

    function togglePause() { if (!root.over) { root.paused = !root.paused; root.save(); } }

    // ---- persistence (shared launcher settings, key `snake`) ----
    function save() {
        root.settings.snake = {
            "body": root.body, "bulges": root.bulges, "dir": root.dir, "apple": root.apple,
            "score": root.score, "best": root.best, "over": root.over
        };
    }
    function load() {
        var s = root.settings.snake;
        if (s && s.body && s.body.length) {
            root.body = s.body;
            root.bulges = s.bulges || [];
            root.dir = s.dir || { "x": 1, "y": 0 };
            root.nextDir = root.dir;
            root.apple = s.apple || null;
            root.score = s.score || 0;
            root.best = s.best || 0;
            root.over = !!s.over;
            root.snakeLen = root.body.length;
            if (!root.apple && !root.over) root.spawnApple();
            root.prog = 1;
            root.snap = true; root.snakeRev++; root.snap = false;
        } else {
            root.newGame();
        }
    }
    // load, then always open PAUSED — a fresh or resumed game waits for P / Resume,
    // so the field never starts sliding the instant the pane opens. `ready` flips on
    // after the first build so segments present at load don't sprout.
    Component.onCompleted: { root.load(); if (!root.over) root.paused = true; Qt.callLater(() => root.ready = true); }
    Component.onDestruction: root.save()

    // ---- clocks ----
    Timer {
        id: sim
        interval: root.moveInterval
        repeat: true
        running: !root.over && !root.paused
        onTriggered: root.step()
    }
    // drives the per-step glide; runs to completion independent of pause so pausing
    // settles the snake on its grid cells.
    NumberAnimation {
        id: progAnim
        target: root
        property: "prog"
        from: 0; to: 1
        duration: root.moveInterval
        easing.type: Easing.Linear
    }

    // ---- a single snake block (body cell / head), reused for the wrap ghost ----
    component SnakeBlock: Item {
        id: blk
        property real u: 20                 // cell size
        property bool head: false
        property bool bulged: false
        property real dirx: 1
        property real diry: 0
        property color bodyColor: "#e05a4d"
        property color headColor: "#f0897d"
        Rectangle {
            id: r
            anchors.centerIn: parent
            // a bulged cell SWELLS past the cell — the lump parked on the apple's tile
            width: blk.u - 2 + (blk.bulged ? 7 : 0)
            height: blk.u - 2 + (blk.bulged ? 7 : 0)
            radius: 7
            color: blk.head ? blk.headColor : blk.bodyColor
            antialiasing: true
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
            // eyes — head only, pointed along the heading
            Repeater {
                model: blk.head ? 2 : 0
                delegate: Rectangle {
                    required property int index
                    width: 4; height: 4; radius: 2
                    color: "#101014"
                    readonly property real fwd: 0.30
                    readonly property real side: (index === 0 ? -0.20 : 0.20)
                    x: r.width * (0.5 + blk.dirx * fwd + (-blk.diry) * side) - 2
                    y: r.height * (0.5 + blk.diry * fwd + (blk.dirx) * side) - 2
                }
            }
        }
    }

    // keyboard sink — holds focus for the whole pane (the pill grabs the compositor
    // keyboard for menu 14). Mouse-transparent, so the buttons still work.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Component.onCompleted: keys.forceActiveFocus()
        Keys.onPressed: (e) => {
            if (root.over) {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.newGame(); e.accepted = true; }
                else if (e.key === Qt.Key_Escape) { root.save(); root.closeRequested(); e.accepted = true; }
                return;
            }
            switch (e.key) {
            case Qt.Key_Up:    case Qt.Key_K: root.steer(0, -1);          e.accepted = true; break;
            case Qt.Key_Down:  case Qt.Key_J: root.steer(0, 1);           e.accepted = true; break;
            case Qt.Key_Left:  case Qt.Key_H: root.steer(-1, 0);          e.accepted = true; break;
            case Qt.Key_Right: case Qt.Key_L: root.steer(1, 0);           e.accepted = true; break;
            case Qt.Key_P:                    root.togglePause();         e.accepted = true; break;
            case Qt.Key_N:                    root.newGame();             e.accepted = true; break;
            case Qt.Key_Escape:               root.save(); root.closeRequested(); e.accepted = true; break;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Snake"
            onBack: root.closeRequested()
            // drag grip — park the pane anywhere by this handle (right of the title).
            // Emits scene-pos park signals; init.qml moves the whole pill.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 26
                radius: root.theme.radiusBtn
                color: (gripDrag.active || gripMa.hovered) ? root.theme.rowHi : root.theme.row
                border.width: 1
                border.color: root.theme.border
                MSym {
                    anchors.centerIn: parent
                    icon: "drag_indicator"
                    size: 17
                    color: (gripDrag.active || gripMa.hovered) ? root.theme.text : root.theme.textDim
                }
                HoverHandler { id: gripMa }
                DragHandler {
                    id: gripDrag
                    target: null
                    cursorShape: Qt.SizeAllCursor
                    onActiveChanged: {
                        if (gripDrag.active) root.parkDragStart(gripDrag.centroid.scenePosition.x, gripDrag.centroid.scenePosition.y);
                        else root.parkDragEnd();
                    }
                    onCentroidChanged: if (gripDrag.active) root.parkDragMove(gripDrag.centroid.scenePosition.x, gripDrag.centroid.scenePosition.y);
                }
            }
        }

        Row {
            width: parent.width
            height: parent.height - 26 - root.theme.gap
            spacing: 16

            // ---- the field ----
            Rectangle {
                id: well
                anchors.verticalCenter: parent.verticalCenter
                width: root.fieldW + 2
                height: root.fieldH + 2
                color: "#0f0c08"
                radius: root.theme.radiusSmall
                border.width: 1
                border.color: root.theme.border
                clip: true                                // clips wrap ghosts at the seam

                Item {
                    id: field
                    x: 1; y: 1
                    width: root.fieldW
                    height: root.fieldH

                    // faint cell grid
                    Repeater {
                        model: root.rows * root.cols
                        delegate: Rectangle {
                            required property int index
                            x: (index % root.cols) * root.cell
                            y: Math.floor(index / root.cols) * root.cell
                            width: root.cell
                            height: root.cell
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.03)
                        }
                    }

                    // apple — pops in on spawn, vanishes the instant it is eaten
                    Rectangle {
                        id: appleRect
                        visible: !!root.apple
                        width: root.cell - 5
                        height: root.cell - 5
                        radius: width / 2
                        x: (root.apple ? root.apple.x * root.cell : 0) + (root.cell - width) / 2
                        y: (root.apple ? root.apple.y * root.cell : 0) + (root.cell - height) / 2
                        color: root.appleColor
                        antialiasing: true
                        Rectangle {   // little leaf highlight so it reads as fruit
                            width: 4; height: 4; radius: 2
                            x: parent.width * 0.28; y: parent.height * 0.22
                            color: Qt.rgba(1, 1, 1, 0.5)
                        }
                        transform: Scale {
                            origin.x: appleRect.width / 2
                            origin.y: appleRect.height / 2
                            xScale: appleRect.pop
                            yScale: appleRect.pop
                        }
                        property real pop: 1
                        Behavior on pop { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                        Connections {
                            target: root
                            function onAppleRevChanged() { appleRect.pop = 0; Qt.callLater(() => appleRect.pop = 1); }
                        }
                    }

                    // the snake. The delegate pool is FIXED at the board's max length
                    // (cols·rows) and built once when the pane opens — growing the snake
                    // just *activates* an already-built slot, so eating never instantiates
                    // a delegate mid-step (which stalled the whole field for a frame). A
                    // slot interpolates from the cell it held to the cell body[i] now
                    // names, along the shortest toroidal path, driven by the shared `prog`.
                    // Positions read `snakeRev` DIRECTLY — body is a plain JS array mutated
                    // in place.
                    Repeater {
                        model: root.cols * root.rows
                        delegate: Item {
                            id: seg
                            required property int index
                            anchors.fill: parent
                            readonly property bool live: { root.snakeRev; return root.body && root.body.length > seg.index; }
                            readonly property bool head: seg.index === 0
                            visible: seg.live
                            z: seg.head ? 3 : 2

                            // from → to grid cells for this step (updated on every rev)
                            property real fromX: 0
                            property real fromY: 0
                            property real toX: 0
                            property real toY: 0
                            property bool wasLive: false        // was this slot part of the snake last rev?
                            // sprout: a slot that just became part of the snake (a grown
                            // tail) scales in; slots present at load do not (ready still
                            // false then).
                            property real growth: 1

                            // Re-read on every step. A slot that just went live (the snake
                            // grew into it) SNAPS onto its cell and sprouts — no glide from a
                            // stale/zero position. Otherwise it slides one cell.
                            function sync() {
                                var nowLive = root.body.length > seg.index;
                                if (!nowLive) { seg.wasLive = false; return; }
                                var c = root.body[seg.index];
                                if (!seg.wasLive) {
                                    seg.fromX = seg.toX = c.x; seg.fromY = seg.toY = c.y;
                                    seg.wasLive = true;
                                    if (root.ready) { seg.growth = 0; growthAnim.restart(); }
                                    return;
                                }
                                if (root.snap) { seg.fromX = seg.toX = c.x; seg.fromY = seg.toY = c.y; }
                                else { seg.fromX = seg.toX; seg.fromY = seg.toY; seg.toX = c.x; seg.toY = c.y; }
                            }
                            Component.onCompleted: {
                                if (root.body.length > seg.index) {
                                    var c = root.body[seg.index];
                                    seg.toX = seg.fromX = c.x; seg.toY = seg.fromY = c.y;
                                    seg.wasLive = true;
                                }
                            }
                            Connections { target: root; function onSnakeRevChanged() { seg.sync(); } }
                            NumberAnimation {
                                id: growthAnim
                                target: seg; property: "growth"
                                from: 0; to: 1
                                duration: root.moveInterval
                                easing.type: Easing.OutBack
                            }

                            // shortest toroidal delta (±1 cell) and the wrap flags
                            readonly property real dx: { var d = seg.toX - seg.fromX; if (d > 1) d -= root.cols; else if (d < -1) d += root.cols; return d; }
                            readonly property real dy: { var d = seg.toY - seg.fromY; if (d > 1) d -= root.rows; else if (d < -1) d += root.rows; return d; }
                            readonly property bool wrapX: Math.abs(seg.toX - seg.fromX) > 1
                            readonly property bool wrapY: Math.abs(seg.toY - seg.fromY) > 1
                            // continuous cell position (may run just past an edge mid-wrap).
                            // Gated on `live` so the ~200 dormant pool slots don't re-evaluate
                            // every animation frame (prog isn't tracked while live is false).
                            readonly property real cx: seg.live ? (seg.fromX + seg.dx * root.prog) : 0
                            readonly property real cy: seg.live ? (seg.fromY + seg.dy * root.prog) : 0
                            readonly property bool bulged: { root.snakeRev; return seg.live && root.bulgeSet[seg.toX + "," + seg.toY] === true; }

                            // primary block
                            SnakeBlock {
                                width: root.cell; height: root.cell
                                x: seg.cx * root.cell
                                y: seg.cy * root.cell
                                scale: seg.growth
                                u: root.cell; head: seg.head; bulged: seg.bulged
                                dirx: root.dir.x; diry: root.dir.y
                                bodyColor: root.snakeColor; headColor: root.headColor
                            }
                            // wrap ghost — the copy entering the opposite edge as the
                            // primary slides off; only present while straddling a seam.
                            SnakeBlock {
                                visible: seg.wrapX || seg.wrapY
                                width: root.cell; height: root.cell
                                x: (seg.wrapX ? seg.cx - Math.sign(seg.dx) * root.cols : seg.cx) * root.cell
                                y: (seg.wrapY ? seg.cy - Math.sign(seg.dy) * root.rows : seg.cy) * root.cell
                                scale: seg.growth
                                u: root.cell; head: seg.head; bulged: seg.bulged
                                dirx: root.dir.x; diry: root.dir.y
                                bodyColor: root.snakeColor; headColor: root.headColor
                            }
                        }
                    }
                }

                // paused / game-over veil
                Rectangle {
                    anchors.fill: parent
                    visible: root.paused || root.over
                    color: Qt.rgba(0x0f / 255.0, 0x0c / 255.0, 0x08 / 255.0, 0.78)
                    radius: well.radius
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.over ? "GAME OVER" : "PAUSED"
                            color: root.over ? root.theme.accent : root.theme.text
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsLarge + 6
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.over ? "Enter to play again" : "P to resume · arrows / hjkl to steer"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                }
            }

            // ---- side column: stats · rules · controls ----
            Column {
                width: parent.width - well.width - 16
                spacing: 12

                // score / best / length / speed
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { "k": "Score",  "v": root.score.toString() },
                            { "k": "Best",   "v": root.best.toString() },
                            { "k": "Length", "v": root.snakeLen.toString() },
                            { "k": "Speed",  "v": (root.baseInterval / root.moveInterval).toFixed(1) + "×" }
                        ]
                        delegate: Column {
                            id: statCol
                            required property var modelData
                            spacing: 1
                            Text {
                                text: statCol.modelData.k
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                                font.capitalization: Font.AllUppercase
                            }
                            Text {
                                text: statCol.modelData.v
                                color: root.theme.text
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge + 3
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider }

                // how it plays
                Text {
                    width: parent.width
                    text: "Eat the apples to grow. Each one rides down the body as a lump until the tail passes its tile. Walls wrap around — only your own body is fatal."
                    wrapMode: Text.WordWrap
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsSmall
                }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider }

                // controls cheat-sheet
                Column {
                    width: parent.width
                    spacing: 3
                    Repeater {
                        model: [
                            "↑↓←→ / HJKL   Steer",
                            "P   Pause      N   New game"
                        ]
                        delegate: Text {
                            id: ruleRow
                            required property var modelData
                            width: parent.width
                            text: ruleRow.modelData
                            color: root.theme.textDim
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }

                // action buttons — New game · Pause/Resume
                Row {
                    spacing: 8
                    Rectangle {
                        width: 92; height: 30
                        radius: root.theme.radiusBtn
                        color: newMa.containsMouse ? root.theme.rowHi : root.theme.row
                        border.width: 1
                        border.color: root.theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "New game"
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            id: newMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.newGame(); keys.forceActiveFocus(); }
                        }
                    }
                    Rectangle {
                        width: 78; height: 30
                        radius: root.theme.radiusBtn
                        color: pauseMa.containsMouse ? root.theme.rowHi : root.theme.row
                        border.width: 1
                        border.color: root.theme.border
                        opacity: root.over ? 0.4 : 1
                        Text {
                            anchors.centerIn: parent
                            text: root.paused ? "Resume" : "Pause"
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            id: pauseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.togglePause(); keys.forceActiveFocus(); }
                        }
                    }
                }
            }
        }
    }
}
