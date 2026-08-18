pragma ComponentBehavior: Bound
// BrickBreakerMenu.qml — a paddle-less "ballz"-style brick breaker, played inside
// the control panel (menu 12, opened from the Games list). A 6×10 grid of bricks
// on the left; round / balls / best / live speed, the rules and New game · Pause
// on the right — the same layout as Tetris (menu 9).
//
// The loop, each round: you AIM by pressing anywhere in the field and dragging —
// a fading dotted line previews the shot and its first wall bounce (300px of
// path). Release to fire. The balls launch one-by-one, 0.03s apart, from the
// launch origin, bounce off walls and bricks (−1 health per hit) and rain back
// down. The FIRST ball to touch the floor sets the launch origin for the next
// round. Once every ball is home the round advances: the whole field shifts down
// one row, a fresh row spawns at the top (2–6 of the 6 cells filled, weighted to
// fewer; each brick's health = the round number) and you gain one more ball
// (balls == round, plus any earned from bonus bricks). Game over the moment a new
// round would push a brick past the bottom row.
//
// Ball count grows forever — by round N you fire N balls; at 0.03s spacing even
// 100 balls launch in ~3s. If the field ever bores you, the sim auto-speeds:
// 1× until 5s of flight, ramping to 1.5× (5s), 2× (10s) and 5× (15s) — done by
// sub-stepping, never by teleporting balls (so they can't tunnel through bricks).
//
// Special bricks (flat 8% per spawned brick, one of three, normal health):
//   • spray   (blur_on)     — every hit also deals its damage to all 8 neighbours
//   • explode (flare)       — when destroyed, wipes its entire row outright,
//                             chaining any other specials caught in the blast
//   • addball (add_circle)  — grants one permanent extra ball when destroyed
//
// Keys (the pane grabs the keyboard while it is menu 12, see init.qml
// grabsKeyboard): P pause · N / Esc… — aiming is all mouse. Opens paused; on game
// over Enter/Space starts a new game. Full state (grid, round, balls, launch
// origin, best) persists into the shared launcher settings under `brickBreaker`,
// so closing the panel or restarting the shell resumes between rounds.
import QtQuick

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — persistence lives in settings.brickBreaker
    signal closeRequested()

    // park-drag: the header grip drives these; init.qml catches them and moves the
    // whole pane (shared tetris* park state — see the Connections block). The pane
    // body no longer drags — only this grip — so the field is free for aiming.
    signal parkDragStart(real sx, real sy)
    signal parkDragMove(real sx, real sy)
    signal parkDragEnd()

    // ---- geometry ----
    readonly property int cols: 6
    readonly property int rows: 10
    readonly property int cellW: 50
    readonly property int cellH: 30
    readonly property real ballR: 5
    readonly property real baseSpeed: 4.6            // px per physics sub-step (< a cell → no tunnelling)
    // playfield extent in field-local pixels — the launch line IS the floor.
    readonly property real fieldW: cols * cellW      // 300
    readonly property real fieldH: rows * cellH      // 300

    // ---- state ----
    property var grid: []                            // rows × cols; each cell null or { hp, max, special }
    property int round: 1
    property int balls: 1                            // launch count next round (== round + bonus-brick balls)
    property int best: 0                             // highest round reached
    property real launchX: fieldW / 2                // origin the next round fires from
    property bool over: false
    property bool paused: false
    property int gridRev: 0                          // bump to re-read `grid` in the render
    property int ballRev: 0                          // bump every physics tick for ball positions

    // ---- flight state (transient — never persisted; a round only rests between shots) ----
    property var flyBalls: []                        // active balls: { x, y, vx, vy }
    property int activeCount: 0                       // flyBalls.length, mirrored for the sim's `running`
    property bool launching: false                   // still firing this round's balls one-by-one
    property int toFire: 0                           // balls left to spit out this round
    property real fireX: fieldW / 2                  // THIS round's frozen firing origin — every ball this
                                                     // round launches from here, even after the first ball
                                                     // lands and moves launchX (which only sets NEXT round)
    property int firedThisRound: 0
    property int landedThisRound: 0
    property bool firstLandedDone: false             // has the first ball set next round's origin yet?
    property real flightMs: 0                        // real ms since this round's first ball launched (drives speed)

    // ---- aiming ----
    property bool aiming: false
    property bool aimValid: false
    property var aimDir: ({ "x": 0, "y": -1 })       // unit launch direction (up is negative y)
    property var aimDots: []                         // preview points: [{ x, y, t }] (t 0→1 along the path)

    readonly property bool canAim: !over && !paused && !launching && activeCount === 0

    // speed multiplier ramps with time-in-flight, resets each round (see header)
    readonly property real speedMul: {
        var t = flightMs;
        if (t <= 5000) return 1 + 0.5 * (t / 5000);
        if (t <= 10000) return 1.5 + 0.5 * ((t - 5000) / 5000);
        if (t <= 15000) return 2 + 3 * ((t - 10000) / 5000);
        return 5;
    }

    // brick fill colour cycles by health so a wall of mixed-age bricks reads clearly
    readonly property var brickPal: ["#5cc46a", "#4fc3d6", "#5b7fd6", "#b05cd6", "#d6c23c", "#d68a3c", "#d65c5c"]
    function brickColor(hp) { return root.brickPal[Math.max(0, (hp - 1)) % root.brickPal.length]; }
    // per-special accents (border + icon tint) and their glyphs
    readonly property var specColor: ({ "spray": "#4fc3d6", "explode": "#d68a3c", "addball": "#5cc46a" })
    readonly property var specIcon: ({ "spray": "blur_on", "explode": "flare", "addball": "add_circle" })

    // ---- helpers ----
    function emptyRow() { var r = []; for (var c = 0; c < root.cols; c++) r.push(null); return r; }
    function emptyGrid() { var g = []; for (var i = 0; i < root.rows; i++) g.push(emptyRow()); return g; }

    // how many of the 6 cells a new row fills — weighted toward fewer (2:5 3:4 4:3 5:2 6:1)
    function pickFill() {
        var r = Math.random() * 15;
        if (r < 5) return 2;
        if (r < 9) return 3;
        if (r < 12) return 4;
        if (r < 14) return 5;
        return 6;
    }
    // a fresh top row for round `rn`: random cells, health == rn, flat 8% special each
    function spawnRow(rn) {
        var row = root.emptyRow();
        var idx = [0, 1, 2, 3, 4, 5];
        for (var i = idx.length - 1; i > 0; i--) {              // Fisher–Yates
            var j = Math.floor(Math.random() * (i + 1));
            var t = idx[i]; idx[i] = idx[j]; idx[j] = t;
        }
        var count = root.pickFill();
        for (var k = 0; k < count; k++) {
            var special = "";
            if (Math.random() < 0.08) special = ["spray", "explode", "addball"][Math.floor(Math.random() * 3)];
            row[idx[k]] = { "hp": rn, "max": rn, "special": special };
        }
        return row;
    }

    function newGame() {
        var g = root.emptyGrid();
        g[0] = root.spawnRow(1);
        root.grid = g;
        root.round = 1; root.balls = 1;
        root.launchX = root.fieldW / 2;
        root.over = false; root.paused = false;
        root.flyBalls = []; root.activeCount = 0; root.launching = false; root.toFire = 0;
        root.firedThisRound = 0; root.landedThisRound = 0; root.firstLandedDone = false; root.flightMs = 0;
        root.aiming = false; root.aimValid = false; root.aimDots = [];
        if (root.round > root.best) root.best = root.round;
        root.gridRev++; root.ballRev++;
        root.save();
    }

    // ---- damage & destruction ----
    // reduce one brick's health; queue it for destruction when it hits 0 (once)
    function damageCell(r, c, dmg, queue) {
        if (r < 0 || r >= root.rows || c < 0 || c >= root.cols) return;
        var b = root.grid[r][c];
        if (!b || b.hp <= 0) return;
        b.hp -= dmg;
        if (b.hp <= 0) queue.push([r, c]);
    }
    // a ball struck (r,c): apply 1 damage (spray fans it to 8 neighbours), then
    // drain the destruction queue — explode wipes its row outright and can chain
    // other specials, addball grants a permanent ball.
    function hitBrick(r, c) {
        var b = root.grid[r][c];
        if (!b) return;
        var q = [];
        if (b.special === "spray") {
            root.damageCell(r, c, 1, q);
            for (var dr = -1; dr <= 1; dr++)
                for (var dc = -1; dc <= 1; dc++)
                    if (dr !== 0 || dc !== 0) root.damageCell(r + dr, c + dc, 1, q);
        } else {
            root.damageCell(r, c, 1, q);
        }
        while (q.length > 0) {
            var rc = q.shift();
            var br = root.grid[rc[0]][rc[1]];
            if (!br) continue;                                  // already gone (chain / double-hit)
            root.grid[rc[0]][rc[1]] = null;
            if (br.special === "addball") root.balls++;         // permanent extra ball
            if (br.special === "explode")                       // wipe the whole row outright → chains
                for (var cc = 0; cc < root.cols; cc++)
                    if (root.grid[rc[0]][cc]) q.push([rc[0], cc]);
        }
        root.gridRev++;
    }

    // ---- physics ----
    // which brick cell (if any) sits under a field-local point
    function brickCellAt(px, py) {
        if (px < 0 || px >= root.fieldW || py < 0 || py >= root.fieldH) return null;
        var c = Math.floor(px / root.cellW);
        var r = Math.floor(py / root.cellH);
        if (r < 0 || r >= root.rows || c < 0 || c >= root.cols) return null;
        return root.grid[r][c] ? { "row": r, "col": c } : null;
    }
    // keep a ball from getting stuck skimming near-horizontal: enforce a minimum
    // vertical component, re-solving vx to preserve overall speed.
    function enforceMinVy(b) {
        var sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        var minv = 0.32 * sp;
        if (Math.abs(b.vy) < minv) {
            var s = b.vy < 0 ? -1 : 1;
            b.vy = s * minv;
            var nvx = Math.sqrt(Math.max(0, sp * sp - b.vy * b.vy));
            b.vx = (b.vx < 0 ? -1 : 1) * nvx;
        }
    }
    // one integration sub-step: move every ball one baseSpeed, resolve walls / bricks
    // / floor on each axis. Landed balls drop out; the first sets next round's origin.
    function stepPhysics() {
        var BR = root.ballR, W = root.fieldW, FL = root.fieldH;
        var survivors = [];
        for (var i = 0; i < root.flyBalls.length; i++) {
            var b = root.flyBalls[i];
            // horizontal
            b.x += b.vx;
            if (b.x < BR) { b.x = BR; b.vx = -b.vx; }
            else if (b.x > W - BR) { b.x = W - BR; b.vx = -b.vx; }
            else {
                var hx = root.brickCellAt(b.x + (b.vx > 0 ? BR : -BR), b.y);
                if (hx) { root.hitBrick(hx.row, hx.col); b.vx = -b.vx; b.x += b.vx; }
            }
            // vertical
            b.y += b.vy;
            if (b.y < BR) { b.y = BR; b.vy = -b.vy; }
            else {
                var hy = root.brickCellAt(b.x, b.y + (b.vy > 0 ? BR : -BR));
                if (hy) { root.hitBrick(hy.row, hy.col); b.vy = -b.vy; b.y += b.vy; }
            }
            // floor → this ball is home
            if (b.y + BR >= FL) {
                root.landedThisRound++;
                if (!root.firstLandedDone) {
                    root.firstLandedDone = true;
                    root.launchX = Math.max(BR, Math.min(W - BR, b.x));
                }
                continue;
            }
            root.enforceMinVy(b);
            survivors.push(b);
        }
        root.flyBalls = survivors;
        root.activeCount = survivors.length;
        if (!root.launching && root.activeCount === 0 && root.firedThisRound > 0) root.endRound();
    }

    // ---- launch ----
    function launch() {
        if (!root.canAim) return;
        root.launching = true;
        root.toFire = root.balls;
        root.fireX = root.launchX;                    // freeze this round's origin BEFORE any ball can land
        root.flightMs = 0;
        root.firedThisRound = 0; root.landedThisRound = 0; root.firstLandedDone = false;
        fireT.start();
    }
    function fireOne() {
        if (root.toFire <= 0) { root.launching = false; fireT.stop(); return; }
        root.flyBalls.push({
            "x": root.fireX,
            "y": root.fieldH - root.ballR - 1,
            "vx": root.aimDir.x * root.baseSpeed,
            "vy": root.aimDir.y * root.baseSpeed
        });
        root.toFire--;
        root.firedThisRound++;
        root.activeCount = root.flyBalls.length;
        root.ballRev++;
    }

    // round is over once every launched ball is home: advance the field, reset flight
    function endRound() {
        root.advanceRound();
        root.firedThisRound = 0; root.landedThisRound = 0; root.firstLandedDone = false; root.flightMs = 0;
    }
    function advanceRound() {
        var last = root.grid[root.rows - 1];
        for (var c = 0; c < root.cols; c++) {
            if (last[c]) { root.over = true; root.save(); return; }  // shift would push a brick off → lose
        }
        var g = [];
        g.push(root.spawnRow(root.round + 1));                       // new top row, health = new round
        for (var r = 0; r < root.rows - 1; r++) g.push(root.grid[r]);// everything else slides down one
        root.grid = g;
        root.round++; root.balls++;
        if (root.round > root.best) root.best = root.round;
        root.gridRev++;
        root.save();
    }

    // ---- aiming ----
    function updateAim(mx, my) {
        var ox = root.launchX, oy = root.fieldH;
        var dx = mx - ox, dy = my - oy;
        if (Math.sqrt(dx * dx + dy * dy) < 8) { root.aimValid = false; root.aimDots = []; return; }
        var ang = Math.atan2(-dy, dx);                              // angle above horizontal
        var minA = 0.2618, maxA = Math.PI - 0.2618;                // clamp ≥15° off horizontal
        if (ang < minA) ang = minA;
        if (ang > maxA) ang = maxA;
        root.aimDir = { "x": Math.cos(ang), "y": -Math.sin(ang) };
        root.aimValid = true;
        root.aimDots = root.computeAimDots(root.aimDir);
    }
    // trace the shot 150px, reflecting off side walls, stopping at a brick/floor;
    // sample a dot every 12px, tagged with normalised distance for the fade.
    function computeAimDots(dir) {
        var BR = root.ballR, W = root.fieldW, FL = root.fieldH;
        var pts = [];
        var x = root.launchX, y = FL - BR - 1, vx = dir.x, vy = dir.y;
        var step = 5, dist = 0, maxd = 300, sinceDot = 0;
        while (dist < maxd) {
            x += vx * step; y += vy * step; dist += step; sinceDot += step;
            if (x < BR) { x = BR; vx = -vx; }
            else if (x > W - BR) { x = W - BR; vx = -vx; }
            if (y < BR) { y = BR; vy = -vy; }
            if (y >= FL - BR) break;
            if (root.brickCellAt(x, y)) break;
            if (sinceDot >= 12) { sinceDot = 0; pts.push({ "x": x, "y": y, "t": dist / maxd }); }
        }
        return pts;
    }

    function togglePause() { if (!root.over) { root.paused = !root.paused; root.save(); } }

    // ---- persistence (shared launcher settings, key `brickBreaker`) ----
    function save() {
        root.settings.brickBreaker = {
            "grid": root.grid, "round": root.round, "balls": root.balls,
            "launchX": root.launchX, "over": root.over, "best": root.best
        };
    }
    function load() {
        var s = root.settings.brickBreaker;
        if (s && s.grid && s.grid.length === root.rows) {
            root.grid = s.grid;
            root.round = s.round || 1;
            root.balls = s.balls || 1;
            root.launchX = (s.launchX !== undefined) ? s.launchX : (root.fieldW / 2);
            root.over = !!s.over;
            root.best = s.best || 0;
            // flight is transient — always resume idle (aiming), between rounds
            root.flyBalls = []; root.activeCount = 0; root.launching = false; root.toFire = 0;
            root.firedThisRound = 0; root.landedThisRound = 0; root.firstLandedDone = false; root.flightMs = 0;
            root.aiming = false; root.aimValid = false; root.aimDots = [];
            root.gridRev++; root.ballRev++;
        } else {
            root.newGame();
        }
    }
    // load, then always open PAUSED (a fresh or resumed game waits for P / Resume,
    // so the field never starts moving the instant the pane opens).
    Component.onCompleted: { root.load(); if (!root.over) root.paused = true; }
    Component.onDestruction: root.save()

    // ---- clocks ----
    // physics: real 16ms tick, sub-stepped `speedMul` times so fractional speeds are
    // smooth and no sub-step ever exceeds baseSpeed (< a cell → no tunnelling).
    Timer {
        id: sim
        interval: 16
        repeat: true
        running: !root.over && !root.paused && (root.launching || root.activeCount > 0)
        property real acc: 0
        onTriggered: {
            root.flightMs += sim.interval;
            sim.acc += root.speedMul;
            var guard = 0;
            while (sim.acc >= 1 && guard < 32) { root.stepPhysics(); sim.acc -= 1; guard++; }
            root.ballRev++;
        }
    }
    // launch drip — one ball every 0.03s while a round is firing
    Timer {
        id: fireT
        interval: 30
        repeat: true
        running: false
        onTriggered: root.fireOne()
    }

    // keyboard sink — holds focus for the whole pane (the pill grabs the compositor
    // keyboard for menu 12). Mouse-transparent, so aiming and buttons still work.
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
            case Qt.Key_P:      root.togglePause();                 e.accepted = true; break;
            case Qt.Key_N:      root.newGame();                     e.accepted = true; break;
            case Qt.Key_Escape: root.save(); root.closeRequested(); e.accepted = true; break;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Brick Breaker"
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
            // the side column (stats + legend + rules + buttons) is taller than the
            // square field, so it sets the pane height — centre the well vertically in
            // the row so the leftover splits above/below instead of gaping beneath it.
            Rectangle {
                id: well
                anchors.verticalCenter: parent.verticalCenter
                width: root.fieldW + 2
                height: root.fieldH + 2
                color: "#0f0c08"
                radius: root.theme.radiusSmall
                border.width: 1
                border.color: root.theme.border
                clip: true

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
                            x: (index % root.cols) * root.cellW
                            y: Math.floor(index / root.cols) * root.cellH
                            width: root.cellW
                            height: root.cellH
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.04)
                        }
                    }

                    // bricks
                    Repeater {
                        model: root.rows * root.cols
                        delegate: Item {
                            id: brickCell
                            required property int index
                            readonly property int cc: index % root.cols
                            readonly property int rr: Math.floor(index / root.cols)
                            readonly property var b: {
                                root.gridRev;
                                return (root.grid[rr]) ? root.grid[rr][cc] : null;
                            }
                            // hp is read from the grid on every gridRev bump — NOT via
                            // b.hp, since a hit mutates the brick object in place (its
                            // reference never changes) and QML would not see it, freezing
                            // the health number + colour until the brick died.
                            readonly property int hp: {
                                root.gridRev;
                                var bb = (root.grid[rr]) ? root.grid[rr][cc] : null;
                                return bb ? bb.hp : 0;
                            }
                            x: cc * root.cellW
                            y: rr * root.cellH
                            width: root.cellW
                            height: root.cellH
                            visible: !!b

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1.5
                                radius: 4
                                color: brickCell.hp > 0 ? root.brickColor(brickCell.hp) : "transparent"
                                border.width: (brickCell.b && brickCell.b.special !== "") ? 2 : 0
                                border.color: (brickCell.b && brickCell.b.special !== "") ? root.specColor[brickCell.b.special] : "transparent"

                                // special glyph, tucked top-right, faint over the fill
                                MSym {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 2
                                    visible: brickCell.b && brickCell.b.special !== ""
                                    icon: (brickCell.b && brickCell.b.special !== "") ? root.specIcon[brickCell.b.special] : ""
                                    size: 12
                                    color: Qt.rgba(0x10 / 255.0, 0x10 / 255.0, 0x14 / 255.0, 0.72)
                                }
                                // health number
                                Text {
                                    anchors.centerIn: parent
                                    text: brickCell.hp > 0 ? brickCell.hp.toString() : ""
                                    color: "#101014"
                                    font.family: root.theme.mono
                                    font.pixelSize: root.theme.fsSmall + 1
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // aim preview — fading dotted line + reflection
                    Repeater {
                        model: root.canAim && root.aiming && root.aimValid ? root.aimDots : []
                        delegate: Rectangle {
                            required property var modelData
                            width: 4; height: 4; radius: 2
                            x: modelData.x - 2
                            y: modelData.y - 2
                            color: root.theme.accent
                            opacity: 0.9 * (1 - modelData.t)
                        }
                    }

                    // active balls. NB: x/y must depend on `ballRev` DIRECTLY — the ball
                    // is a plain JS object mutated in place, and QML does not observe
                    // `b.x` mutations (the object reference never changes), so binding to
                    // `b.x` alone would freeze the ball at its first frame.
                    Repeater {
                        model: root.activeCount
                        delegate: Rectangle {
                            required property int index
                            readonly property bool live: {
                                root.ballRev;
                                return root.flyBalls && root.flyBalls.length > index;
                            }
                            visible: live
                            width: root.ballR * 2
                            height: root.ballR * 2
                            radius: root.ballR
                            x: { root.ballRev; return live ? root.flyBalls[index].x - root.ballR : 0; }
                            y: { root.ballRev; return live ? root.flyBalls[index].y - root.ballR : 0; }
                            color: "#fbf7ee"
                        }
                    }

                    // launch-origin marker — a little nub on the floor where the next shot fires
                    Rectangle {
                        visible: root.canAim
                        width: 10; height: 10; radius: 5
                        x: root.launchX - 5
                        y: root.fieldH - 11
                        color: root.theme.accent
                        opacity: root.aiming ? 1 : 0.6
                    }

                    // aiming surface — press + drag to aim, release to fire
                    MouseArea {
                        id: aimMa
                        anchors.fill: parent
                        enabled: root.canAim
                        hoverEnabled: false
                        cursorShape: Qt.CrossCursor
                        onPressed: (m) => { root.aiming = true; root.updateAim(m.x, m.y); }
                        onPositionChanged: (m) => { if (root.aiming) root.updateAim(m.x, m.y); }
                        onReleased: {
                            if (root.aiming) {
                                var go = root.aimValid;
                                root.aiming = false;
                                root.aimDots = [];
                                if (go) root.launch();
                                keys.forceActiveFocus();
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
                            text: root.over ? "Enter to play again" : "P to resume · drag to aim"
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

                // round / balls / best / speed
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { "k": "Round", "v": root.round.toString() },
                            { "k": "Balls", "v": root.balls.toString() },
                            { "k": "Best",  "v": root.best.toString() },
                            { "k": "Speed", "v": (root.launching || root.activeCount > 0) ? (root.speedMul.toFixed(1) + "×") : "—" }
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

                // special-brick legend
                Text {
                    text: "Specials"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Column {
                    width: parent.width
                    spacing: 5
                    Repeater {
                        model: [
                            { "s": "spray",   "t": "Spray · hits 8 neighbours" },
                            { "s": "explode", "t": "Bomb · clears its row" },
                            { "s": "addball", "t": "Bonus · +1 ball" }
                        ]
                        delegate: Row {
                            id: legRow
                            required property var modelData
                            spacing: 7
                            Rectangle {
                                width: 18; height: 18; radius: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1.5
                                border.color: root.specColor[legRow.modelData.s]
                                MSym {
                                    anchors.centerIn: parent
                                    icon: root.specIcon[legRow.modelData.s]
                                    size: 12
                                    color: root.specColor[legRow.modelData.s]
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: legRow.modelData.t
                                color: root.theme.textDim
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsSmall
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider }

                // rules / controls cheat-sheet
                Column {
                    width: parent.width
                    spacing: 3
                    Repeater {
                        model: [
                            "P   Pause    N   New game",
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
