pragma ComponentBehavior: Bound
// MinesweeperMenu.qml — classic Minesweeper, played inside the control panel
// (menu 17, opened from the Games list). A square grid on the left; mines-left /
// time / best / difficulty, the rules and New game on the right — the same
// two-column layout as Snake (menu 14) and Brick Breaker (menu 12).
//
// Mouse-only, like Block Blast (menu 10): this pane does NOT grab the keyboard
// (see init.qml grabsKeyboard). Left-click reveals a cell, right-click toggles a
// flag. The first reveal is always safe — mines are placed only after it, avoiding
// the clicked cell and its neighbours, so the opening click always opens an area.
// Revealing a zero-adjacency cell flood-fills its region; revealing a mine ends the
// game and shows the field. You win when every non-mine cell is revealed.
//
// Difficulty (Beginner 9×9/10, Intermediate 12×12/26, Expert 16×16/50) is chosen in
// the side column. The well is a FIXED square — the cell size scales with the grid
// so the board always fits the same well and the pane never resizes. Best time is
// kept PER difficulty; the in-progress board is deliberately NOT persisted (games
// are short and the wall-clock timer wouldn't survive a resume), only the best
// times and the selected difficulty live in the shared launcher settings under
// `minesweeper`.
import QtQuick

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — persistence lives in settings.minesweeper
    signal closeRequested()

    // park-drag: the header grip drives these; init.qml catches them and moves the
    // whole pane (shared tetris* park state — see its Connections block).
    signal parkDragStart(real sx, real sy)
    signal parkDragMove(real sx, real sy)
    signal parkDragEnd()

    // ---- difficulty ----
    // one entry per level. `n` is the side length, `mines` the bomb count.
    readonly property var levels: [
        { "name": "Beginner",     "n": 9,  "mines": 10 },
        { "name": "Intermediate", "n": 12, "mines": 26 },
        { "name": "Expert",       "n": 16, "mines": 50 }
    ]
    property int diff: 0
    readonly property var level: root.levels[root.diff]
    readonly property int cols: root.level.n
    readonly property int mines: root.level.mines

    // ---- geometry ----
    // the well is a fixed square; the cell shrinks as the grid grows so the board
    // always fills the same 300px well.
    readonly property int fieldPx: 300
    readonly property int cell: Math.floor(root.fieldPx / root.cols)
    readonly property real fieldW: root.cell * root.cols

    // ---- state ----
    // board is a flat JS array of length cols·cols; each cell is
    // { mine, rev, flag, adj }. `boardRev` bumps to re-read it in the render (the
    // array is mutated in place, like Snake's body).
    property var board: []
    property int boardRev: 0
    property bool started: false            // first reveal has happened (mines placed, clock running)
    property bool over: false               // hit a mine
    property bool won: false                // cleared every safe cell
    property int flags: 0                   // flags currently planted
    property int revealed: 0                // safe cells uncovered
    property int time: 0                    // elapsed seconds since first reveal
    property var best: [0, 0, 0]            // best time per difficulty, 0 = none yet

    readonly property int minesLeft: root.mines - root.flags
    readonly property int safeCells: root.cols * root.cols - root.mines
    readonly property int curBest: root.best[root.diff] || 0

    // classic 1–8 adjacency palette, tuned for the dark amber deck
    readonly property var numColors: [
        "transparent", "#6ea8ff", "#7fce8f", "#e0574a", "#b48ce0",
        "#e0a35a", "#5ad0d0", "#d7d2c8", "#9a9488"
    ]

    // ---- helpers ----
    function idx(x, y) { return y * root.cols + x; }

    function neighbors(i) {
        var x = i % root.cols, y = Math.floor(i / root.cols), out = [];
        for (var dy = -1; dy <= 1; dy++)
            for (var dx = -1; dx <= 1; dx++) {
                if (dx === 0 && dy === 0) continue;
                var nx = x + dx, ny = y + dy;
                if (nx >= 0 && nx < root.cols && ny >= 0 && ny < root.cols) out.push(root.idx(nx, ny));
            }
        return out;
    }

    // build an empty board for the current difficulty (mines placed on first reveal)
    function reset() {
        var n = root.cols * root.cols, b = new Array(n);
        for (var i = 0; i < n; i++) b[i] = { "mine": false, "rev": false, "flag": false, "adj": 0 };
        root.board = b;
        root.started = false;
        root.over = false;
        root.won = false;
        root.flags = 0;
        root.revealed = 0;
        root.time = 0;
        root.boardRev++;
    }

    // scatter mines after the first click, skipping the safe cell + its neighbours so
    // the opening reveal always flood-fills, then tally each cell's adjacency count.
    function placeMines(safe) {
        var block = ({});
        block[safe] = true;
        var nb = root.neighbors(safe);
        for (var k = 0; k < nb.length; k++) block[nb[k]] = true;

        var pool = [];
        for (var i = 0; i < root.board.length; i++) if (!block[i]) pool.push(i);
        // Fisher–Yates partial shuffle → take the first `mines`
        for (var p = 0; p < root.mines && p < pool.length; p++) {
            var j = p + Math.floor(Math.random() * (pool.length - p));
            var t = pool[p]; pool[p] = pool[j]; pool[j] = t;
            root.board[pool[p]].mine = true;
        }
        for (var c = 0; c < root.board.length; c++) {
            if (root.board[c].mine) continue;
            var a = 0, ns = root.neighbors(c);
            for (var m = 0; m < ns.length; m++) if (root.board[ns[m]].mine) a++;
            root.board[c].adj = a;
        }
    }

    // reveal a cell (left click). First reveal seeds the mines + starts the clock.
    // A zero-adjacency cell flood-fills its region; a mine ends the game.
    function reveal(i) {
        if (root.over || root.won) return;
        var cellObj = root.board[i];
        if (cellObj.rev || cellObj.flag) return;

        if (!root.started) { root.placeMines(i); root.started = true; }

        if (cellObj.mine) {
            root.board[i].rev = true;
            root.lose();
            return;
        }

        // iterative flood: reveal this cell, and if it has no adjacent mines, spill
        // into its neighbours (unflagged, unrevealed) and repeat.
        var stack = [i];
        while (stack.length) {
            var j = stack.pop();
            var cj = root.board[j];
            if (cj.rev || cj.flag || cj.mine) continue;
            cj.rev = true;
            root.revealed++;
            if (cj.adj === 0) {
                var ns = root.neighbors(j);
                for (var k = 0; k < ns.length; k++) {
                    var cn = root.board[ns[k]];
                    if (!cn.rev && !cn.flag && !cn.mine) stack.push(ns[k]);
                }
            }
        }

        root.boardRev++;
        if (root.revealed >= root.safeCells) root.win();
    }

    function toggleFlag(i) {
        if (root.over || root.won) return;
        var cellObj = root.board[i];
        if (cellObj.rev) return;
        cellObj.flag = !cellObj.flag;
        root.flags += cellObj.flag ? 1 : -1;
        root.boardRev++;
    }

    function lose() {
        root.over = true;
        // expose every mine so the field reads as a loss
        for (var i = 0; i < root.board.length; i++) if (root.board[i].mine) root.board[i].rev = true;
        root.boardRev++;
    }

    function win() {
        root.won = true;
        // auto-flag the last mines so the cleared board reads tidy
        for (var i = 0; i < root.board.length; i++) if (root.board[i].mine && !root.board[i].flag) { root.board[i].flag = true; }
        root.flags = root.mines;
        if (root.curBest === 0 || root.time < root.curBest) {
            var b = root.best.slice();
            b[root.diff] = root.time;
            root.best = b;
        }
        root.boardRev++;
        root.save();
    }

    function setDiff(d) {
        if (d === root.diff) { root.reset(); return; }
        root.diff = d;
        root.reset();
        root.save();
    }

    function fmtTime(s) {
        var m = Math.floor(s / 60), r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    // ---- persistence (shared launcher settings, key `minesweeper`) ----
    function save() {
        root.settings.minesweeper = { "diff": root.diff, "best": root.best };
    }
    function load() {
        var s = root.settings.minesweeper;
        if (s) {
            root.diff = (typeof s.diff === "number") ? Math.max(0, Math.min(2, s.diff)) : 0;
            if (s.best && s.best.length === 3) root.best = s.best;
        }
    }

    Component.onCompleted: { root.load(); root.reset(); }
    Component.onDestruction: root.save()

    // the elapsed-time clock — ticks once a second while a game is live
    Timer {
        interval: 1000
        repeat: true
        running: root.started && !root.over && !root.won
        onTriggered: if (root.time < 999) root.time++
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Minesweeper"
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

            // ---- the minefield ----
            Rectangle {
                id: well
                anchors.verticalCenter: parent.verticalCenter
                width: root.fieldW + 2
                height: root.fieldW + 2
                color: "#0f0c08"
                radius: root.theme.radiusSmall
                border.width: 1
                border.color: root.theme.border
                clip: true

                Item {
                    id: grid
                    x: 1; y: 1
                    width: root.fieldW
                    height: root.fieldW

                    Repeater {
                        model: root.cols * root.cols
                        delegate: Item {
                            id: tile
                            required property int index
                            // Each field reads `boardRev` + the array DIRECTLY. The board
                            // cells are mutated in place, so binding through an intermediate
                            // `var` that returns the same object reference would NOT re-fire
                            // (QML skips change-notify on identical refs) — inlining the int
                            // counter, as Snake does, makes every field re-evaluate on a bump.
                            readonly property bool rev:  { root.boardRev; var b = root.board[tile.index]; return b ? b.rev : false; }
                            readonly property bool flag: { root.boardRev; var b = root.board[tile.index]; return b ? b.flag : false; }
                            readonly property bool mine: { root.boardRev; var b = root.board[tile.index]; return b ? b.mine : false; }
                            readonly property int adj:   { root.boardRev; var b = root.board[tile.index]; return b ? b.adj : 0; }

                            x: (tile.index % root.cols) * root.cell
                            y: Math.floor(tile.index / root.cols) * root.cell
                            width: root.cell
                            height: root.cell

                            // the cell face — a raised tile when hidden, a sunken well
                            // when revealed. A revealed mine on a lost board glows red.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 3
                                color: tile.rev
                                    ? (tile.mine ? "#4a1712" : Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.05))
                                    : (tileMa.containsMouse && !root.over && !root.won ? root.theme.rowHi : root.theme.row)
                                border.width: 1
                                border.color: tile.rev ? Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.04) : root.theme.border

                                // adjacency count on a revealed safe cell
                                Text {
                                    anchors.centerIn: parent
                                    visible: tile.rev && !tile.mine && tile.adj > 0
                                    text: tile.adj
                                    color: root.numColors[tile.adj]
                                    font.family: root.theme.mono
                                    font.bold: true
                                    font.pixelSize: Math.max(11, root.cell - 12)
                                }

                                // mine — a filled pip on a revealed mine (loss)
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: tile.rev && tile.mine
                                    width: Math.max(6, root.cell - 14)
                                    height: width
                                    radius: width / 2
                                    color: "#e0574a"
                                    antialiasing: true
                                }

                                // flag — a small triangular pennant on a flagged tile
                                Item {
                                    anchors.centerIn: parent
                                    visible: tile.flag && !tile.rev
                                    width: Math.max(8, root.cell - 12)
                                    height: width
                                    Rectangle {   // pole
                                        x: parent.width * 0.5 - 1
                                        y: 1
                                        width: 2
                                        height: parent.height - 2
                                        color: root.theme.textDim
                                    }
                                    Canvas {
                                        anchors.fill: parent
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.fillStyle = "#e0574a";
                                            ctx.beginPath();
                                            ctx.moveTo(width * 0.5, 1);
                                            ctx.lineTo(width * 0.5, height * 0.55);
                                            ctx.lineTo(width * 0.12, height * 0.28);
                                            ctx.closePath();
                                            ctx.fill();
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: tileMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (e) => {
                                    if (e.button === Qt.RightButton) root.toggleFlag(tile.index);
                                    else root.reveal(tile.index);
                                }
                            }
                        }
                    }
                }

                // win / loss veil
                Rectangle {
                    anchors.fill: parent
                    visible: root.over || root.won
                    color: Qt.rgba(0x0f / 255.0, 0x0c / 255.0, 0x08 / 255.0, 0.80)
                    radius: well.radius
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.won ? "CLEARED" : "BOOM"
                            color: root.won ? root.theme.accent : "#e0574a"
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsLarge + 6
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.won ? (root.fmtTime(root.time) + " · click for a new game") : "click for a new game"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.reset() }
                }
            }

            // ---- side column: difficulty · stats · rules · button ----
            Column {
                width: parent.width - well.width - 16
                spacing: 12

                // difficulty selector — a segmented row; picking one starts a fresh
                // board at that size.
                Row {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.levels
                        delegate: Rectangle {
                            id: diffBtn
                            required property var modelData
                            required property int index
                            readonly property bool sel: root.diff === diffBtn.index
                            width: (parent.width - 12) / 3
                            height: 28
                            radius: root.theme.radiusBtn
                            color: diffBtn.sel ? root.theme.accentSoft : (diffMa.containsMouse ? root.theme.rowHi : root.theme.row)
                            border.width: 1
                            border.color: diffBtn.sel ? root.theme.accent : root.theme.border
                            Text {
                                anchors.centerIn: parent
                                text: diffBtn.modelData.name.charAt(0)   // B / I / E
                                color: diffBtn.sel ? root.theme.accent : root.theme.text
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.bold: diffBtn.sel
                            }
                            MouseArea {
                                id: diffMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setDiff(diffBtn.index)
                            }
                            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                        }
                    }
                }

                // mines-left / time / best / level
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { "k": "Mines",  "v": root.minesLeft.toString() },
                            { "k": "Time",   "v": root.fmtTime(root.time) },
                            { "k": "Best",   "v": root.curBest > 0 ? root.fmtTime(root.curBest) : "—" },
                            { "k": "Level",  "v": root.level.name }
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
                    text: "Left-click a cell to uncover it — the number says how many mines touch it. Right-click to flag a suspected mine. The first click is always safe. Clear every safe cell to win."
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
                            "Left-click   Reveal",
                            "Right-click  Flag"
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

                // New game — rebuilds the board at the current difficulty
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
                        onClicked: root.reset()
                    }
                }
            }
        }
    }
}
