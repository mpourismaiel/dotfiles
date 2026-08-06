pragma ComponentBehavior: Bound
// TetrisMenu.qml — a very basic Tetris, played inside the control panel (menu 9,
// opened from the tiny tetromino button beside the expanded-pill clock). A 10×20
// well on the left; score / level, the next three pieces, the rules and the
// New game · Pause controls on the right. Gravity is a Timer whose interval
// shrinks with the level. The whole game state (board, falling piece, 7-bag
// queue, score, high score, paused/over flags) is persisted into the shared
// launcher settings under `tetris`, so closing the panel and reopening it — or
// restarting the shell — resumes exactly where you left off.
//
// Keys (the pane grabs the keyboard while it is menu 9, see init.qml
// grabsKeyboard): ←/→ move · ↑ or X rotate CW · Z rotate CCW · ↓ soft-drop ·
// Space/Enter hard-drop · P pause · Esc close. On game over, Enter/Space starts
// a new game. Opens paused; a screenshot button in the header saves a pretty
// snapshot (well + next + score/level) to ~/Pictures/Screenshots (+ clipboard).
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — persistence lives in settings.tetris
    signal closeRequested()

    // park-drag: the header grip drives these; init.qml catches them and moves the
    // whole pane (see the Connections block wired to menuLoader.item). The pane body
    // no longer drags — only this grip — so it matches Block Blast.
    signal parkDragStart(real sx, real sy)
    signal parkDragMove(real sx, real sy)
    signal parkDragEnd()

    // ---- geometry ----
    readonly property int cols: 10
    readonly property int rows: 20
    readonly property int cell: 24

    // ---- pieces: four rotation states each, as [x,y] cells inside a 3-wide box
    //      (4-wide for I). O never rotates. These are the classic Tetris shapes. ----
    readonly property var types: ["I", "J", "L", "O", "S", "T", "Z"]
    readonly property var shapes: ({
        "I": [ [[0,1],[1,1],[2,1],[3,1]], [[2,0],[2,1],[2,2],[2,3]], [[0,2],[1,2],[2,2],[3,2]], [[1,0],[1,1],[1,2],[1,3]] ],
        "J": [ [[0,0],[0,1],[1,1],[2,1]], [[1,0],[2,0],[1,1],[1,2]], [[0,1],[1,1],[2,1],[2,2]], [[1,0],[1,1],[0,2],[1,2]] ],
        "L": [ [[2,0],[0,1],[1,1],[2,1]], [[1,0],[1,1],[1,2],[2,2]], [[0,1],[1,1],[2,1],[0,2]], [[0,0],[1,0],[1,1],[1,2]] ],
        "O": [ [[1,0],[2,0],[1,1],[2,1]], [[1,0],[2,0],[1,1],[2,1]], [[1,0],[2,0],[1,1],[2,1]], [[1,0],[2,0],[1,1],[2,1]] ],
        "S": [ [[1,0],[2,0],[0,1],[1,1]], [[1,0],[1,1],[2,1],[2,2]], [[1,1],[2,1],[0,2],[1,2]], [[0,0],[0,1],[1,1],[1,2]] ],
        "T": [ [[1,0],[0,1],[1,1],[2,1]], [[1,0],[1,1],[2,1],[1,2]], [[0,1],[1,1],[2,1],[1,2]], [[1,0],[0,1],[1,1],[1,2]] ],
        "Z": [ [[0,0],[1,0],[1,1],[2,1]], [[2,0],[1,1],[2,1],[1,2]], [[0,1],[1,1],[1,2],[2,2]], [[1,0],[0,1],[1,1],[0,2]] ]
    })
    readonly property var colors: ({
        "I": "#4fc3d6", "J": "#5b7fd6", "L": "#d68a3c", "O": "#d6c23c",
        "S": "#5cc46a", "T": "#b05cd6", "Z": "#d65c5c"
    })

    // ---- state ----
    property var board: []                  // rows × cols; each cell is "" or a piece letter
    property var cur: null                  // { type, rot, x, y } — the falling piece
    property var queue: []                  // upcoming piece letters (≥ 4 kept)
    property var bag: []                    // current shuffled 7-bag remainder
    property int score: 0
    property int lines: 0
    property int level: 1
    property int high: 0
    property bool over: false
    property bool paused: false
    property var flashRows: []              // rows completing this drop, flashing before removal
    property int rev: 0                     // bump to refresh the derived board `view`

    // ---- helpers ----
    function newRow() { var r = []; for (var c = 0; c < cols; c++) r.push(""); return r; }
    function newBoard() { var g = []; for (var i = 0; i < rows; i++) g.push(newRow()); return g; }

    function nextType() {
        if (bag.length === 0) {
            bag = types.slice();
            for (var i = bag.length - 1; i > 0; i--) {          // Fisher–Yates shuffle
                var j = Math.floor(Math.random() * (i + 1));
                var t = bag[i]; bag[i] = bag[j]; bag[j] = t;
            }
        }
        return bag.shift();
    }
    function refillQueue() { while (queue.length < 4) queue.push(nextType()); }

    // does `type` at rotation `rot` / origin (px,py) hit a wall, the floor or a
    // settled cell? (cells above the top — cy < 0 — are allowed, so a piece can
    // spawn partly off-screen.)
    function collides(type, rot, px, py) {
        var s = shapes[type][rot];
        for (var i = 0; i < 4; i++) {
            var cx = px + s[i][0];
            var cy = py + s[i][1];
            if (cx < 0 || cx >= cols || cy >= rows) return true;
            if (cy >= 0 && board[cy][cx]) return true;
        }
        return false;
    }

    function newGame() {
        board = newBoard();
        cur = null; queue = []; bag = [];
        score = 0; lines = 0; level = 1;
        over = false; paused = false;
        spawn();
        rev++;
        save();
    }

    function spawn() {
        refillQueue();
        var t = queue.shift();
        refillQueue();
        cur = { "type": t, "rot": 0, "x": 3, "y": 0 };
        if (collides(cur.type, cur.rot, cur.x, cur.y)) {        // no room to enter → game over
            over = true;
            cur = null;
        }
        rev++;
    }

    // stamp the falling piece into the board; if it completes any rows, flash
    // them (deferred clear — `finalizeClear` drops + scores them once the flash
    // finishes); otherwise spawn the next piece right away.
    function lock() {
        var s = shapes[cur.type][cur.rot];
        for (var i = 0; i < 4; i++) {
            var cx = cur.x + s[i][0];
            var cy = cur.y + s[i][1];
            if (cy >= 0) board[cy][cx] = cur.type;
        }
        cur = null;
        var full = fullRows();
        if (full.length > 0) {
            flashRows = full;                                   // → render a bright flash over them
            flashTimer.restart();                               // → finalizeClear() when it ends
            rev++;                                              // save happens in finalizeClear
        } else {
            spawn();
            save();
            rev++;
        }
    }

    function fullRows() {
        var out = [];
        for (var r = 0; r < rows; r++) {
            var full = true;
            for (var c = 0; c < cols; c++) { if (!board[r][c]) { full = false; break; } }
            if (full) out.push(r);
        }
        return out;
    }

    // after the row-flash: drop the completed rows, score, banner, next piece.
    // Rebuild the board keeping the non-cleared rows in order, then pad the top
    // with fresh empty rows — do NOT splice+unshift in a loop, since each unshift
    // renumbers the remaining flashRows indices and clears the wrong rows.
    function finalizeClear() {
        var cleared = flashRows.length;
        if (cleared === 0) return;
        var drop = {};
        for (var i = 0; i < flashRows.length; i++) drop[flashRows[i]] = true;
        var kept = [];
        for (var r = 0; r < rows; r++) if (!drop[r]) kept.push(board[r]);
        while (kept.length < rows) kept.unshift(newRow());
        board = kept;
        flashRows = [];
        lines += cleared;
        score += [0, 100, 300, 500, 800][cleared] * level;
        level = 1 + Math.floor(lines / 10);
        if (score > high) high = score;
        if (cleared >= 2) popBanner(["", "", "DOUBLE", "TRIPLE", "TETRIS!"][cleared], cleared === 4);
        spawn();
        save();
        rev++;
    }

    // line-clear flair — a centred banner that pops + fades (TETRIS! is accent + big)
    property string bannerText: ""
    property bool bannerBig: false
    function popBanner(t, big) { bannerText = t; bannerBig = !!big; bannerAnim.restart(); }

    // gravity / soft-drop: fall one row, or lock if we can't
    function step() {
        if (!cur || over || paused) return;
        if (!collides(cur.type, cur.rot, cur.x, cur.y + 1)) { cur.y++; rev++; }
        else lock();
    }
    function softDrop() { if (cur && !over && !paused) { step(); score += 1; } }
    function hardDrop() {
        if (!cur || over || paused) return;
        var d = 0;
        while (!collides(cur.type, cur.rot, cur.x, cur.y + 1)) { cur.y++; d++; }
        score += d * 2;
        lock();
    }
    function move(dx) {
        if (!cur || over || paused) return;
        if (!collides(cur.type, cur.rot, cur.x + dx, cur.y)) { cur.x += dx; rev++; }
    }
    // rotate with simple wall kicks (nudge ±1, ±2 off a wall)
    function rotate(dir) {
        if (!cur || over || paused) return;
        var nr = (cur.rot + (dir > 0 ? 1 : 3)) % 4;
        var kicks = [0, -1, 1, -2, 2];
        for (var k = 0; k < kicks.length; k++) {
            if (!collides(cur.type, nr, cur.x + kicks[k], cur.y)) {
                cur.x += kicks[k]; cur.rot = nr; rev++; return;
            }
        }
    }
    function togglePause() { if (!over) { paused = !paused; rev++; save(); } }

    // ---- persistence (shared launcher settings, key `tetris`) ----
    function save() {
        root.settings.tetris = {
            "board": board, "cur": cur, "queue": queue, "bag": bag,
            "score": score, "lines": lines, "level": level, "high": high,
            "over": over, "paused": paused
        };
    }
    function load() {
        var s = root.settings.tetris;
        if (s && s.board && s.board.length === rows) {
            board = s.board;
            cur = s.cur || null;
            queue = s.queue || [];
            bag = s.bag || [];
            score = s.score || 0;
            lines = s.lines || 0;
            level = s.level || 1;
            high = s.high || 0;
            over = !!s.over;
            paused = !!s.paused;
            rev++;
        } else {
            newGame();
        }
    }
    // load, then always open PAUSED (a fresh game or a resumed one waits for the
    // player to hit P / Resume — so the pane never starts dropping the instant it
    // opens, and the opening screenshot is a still frame).
    Component.onCompleted: { load(); if (!over) { paused = true; rev++; } }
    // resume exactly here next time the pane opens. If we're mid-flash (closed in
    // the ~260ms window), finish the clear first so we never persist a full,
    // un-cleared row with no active piece.
    Component.onDestruction: { if (flashRows.length > 0) finalizeClear(); save(); }

    // ---- screenshot: grab the pretty share card → save + copy ----
    property bool shareMode: false          // share card overlay is up (also the grab source)
    property string shotName: ""            // filename of the last saved shot
    readonly property string shotTmp: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tetris-share.png"
    readonly property string shotDir: (Quickshell.env("HOME") || "/tmp") + "/Pictures/Screenshots"
    Process { id: shotSaver }               // command set per-shot: mkdir + cp + wl-copy
    Timer { id: shotDismiss; interval: 1600; onTriggered: root.shareMode = false }
    function takeShot() {
        shareMode = true;                                   // reveal the card so it renders...
        Qt.callLater(function () {                          // ...then grab it next tick
            shareCard.grabToImage(function (res) {
                if (!res) { root.shareMode = false; return; }
                res.saveToFile(root.shotTmp);
                root.shotName = "tetris-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss") + ".png";
                shotSaver.command = ["sh", "-c",
                    "mkdir -p '" + root.shotDir + "' && cp '" + root.shotTmp + "' '" + root.shotDir + "/" + root.shotName +
                    "' && (wl-copy --type image/png < '" + root.shotTmp + "' || true)"];
                shotSaver.running = true;
                shotDismiss.restart();
            });
        });
    }

    // ---- derived: the board merged with the falling piece, for rendering ----
    readonly property var view: {
        rev;                                                    // dependency: recompute on every change
        var g = [];
        for (var r = 0; r < rows; r++) g.push((board[r] ? board[r].slice() : newRow()));
        if (cur) {
            var s = shapes[cur.type][cur.rot];
            for (var i = 0; i < 4; i++) {
                var cx = cur.x + s[i][0];
                var cy = cur.y + s[i][1];
                if (cy >= 0 && cy < rows && cx >= 0 && cx < cols) g[cy][cx] = cur.type;
            }
        }
        return g;
    }

    // gravity clock — faster each level, floored so it never becomes unplayable.
    // Naturally idle while `cur` is null (during a line-flash there is no piece).
    Timer {
        id: gravity
        interval: Math.max(90, 520 - (root.level - 1) * 45)
        running: !root.over && !root.paused && root.cur !== null
        repeat: true
        onTriggered: root.step()
    }

    // line-flash duration — after it elapses the completed rows are dropped/scored
    Timer {
        id: flashTimer
        interval: 260
        onTriggered: root.finalizeClear()
    }

    // keyboard sink — holds focus for the whole pane so the arrow keys drive the
    // game from the first keystroke (the pill grabs the compositor keyboard for
    // menu 9). A plain Item is mouse-transparent, so the buttons still click.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        // claim the window's keyboard focus the moment the pane loads (the pill
        // grabs the compositor keyboard for menu 9 — see init.qml grabsKeyboard —
        // but nothing hands focus to this sink unless we ask, so keys wouldn't
        // otherwise reach the game).
        Component.onCompleted: keys.forceActiveFocus()
        Keys.onPressed: (e) => {
            if (root.over) {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.newGame(); e.accepted = true; }
                else if (e.key === Qt.Key_Escape) { root.save(); root.closeRequested(); e.accepted = true; }
                return;
            }
            switch (e.key) {
            case Qt.Key_Left:   root.move(-1);      e.accepted = true; break;
            case Qt.Key_Right:  root.move(1);       e.accepted = true; break;
            case Qt.Key_Down:   root.softDrop();    e.accepted = true; break;
            case Qt.Key_Up:
            case Qt.Key_X:      root.rotate(1);     e.accepted = true; break;
            case Qt.Key_Z:      root.rotate(-1);    e.accepted = true; break;
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:  root.hardDrop();    e.accepted = true; break;
            case Qt.Key_P:      root.togglePause(); e.accepted = true; break;
            case Qt.Key_Escape: root.save(); root.closeRequested(); e.accepted = true; break;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Tetris"
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
            // screenshot button, right-aligned in the header trailing slot — saves
            // a pretty snapshot of the board + next + score/level.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 26
                radius: root.theme.radiusBtn
                color: shotMa.containsMouse ? root.theme.rowHi : root.theme.row
                border.width: 1
                border.color: root.theme.border
                MSym {
                    anchors.centerIn: parent
                    icon: "photo_camera"
                    size: 17
                    color: shotMa.containsMouse ? root.theme.text : root.theme.textDim
                }
                MouseArea {
                    id: shotMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.takeShot(); keys.forceActiveFocus(); }
                }
            }
        }

        Row {
            width: parent.width
            height: parent.height - 26 - root.theme.gap
            spacing: 16

            // ---- the well ----
            Rectangle {
                id: well
                width: root.cols * root.cell + 2
                height: root.rows * root.cell + 2
                color: "#0f0c08"
                radius: root.theme.radiusSmall
                border.width: 1
                border.color: root.theme.border
                clip: true

                Item {
                    x: 1; y: 1
                    width: root.cols * root.cell
                    height: root.rows * root.cell

                    Repeater {
                        model: root.rows * root.cols
                        delegate: Rectangle {
                            id: cellRect
                            required property int index
                            readonly property int cc: index % root.cols
                            readonly property int rr: Math.floor(index / root.cols)
                            readonly property string t: {
                                var v = root.view;
                                return (v && v[rr]) ? v[rr][cc] : "";
                            }
                            x: cc * root.cell
                            y: rr * root.cell
                            width: root.cell
                            height: root.cell
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.045)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 2
                                visible: cellRect.t !== ""
                                color: cellRect.t !== "" ? root.colors[cellRect.t] : "transparent"
                            }
                        }
                    }

                    // line-clear flash: a bright bar over each completing row that
                    // flares then fades (over the flashTimer's 260ms), before the row
                    // is actually dropped. One delegate per flashing row index.
                    Repeater {
                        model: root.flashRows
                        delegate: Rectangle {
                            required property var modelData
                            x: 0
                            y: modelData * root.cell
                            width: root.cols * root.cell
                            height: root.cell
                            radius: 2
                            color: "#fbf7ee"
                            opacity: 0
                            SequentialAnimation on opacity {
                                running: true
                                NumberAnimation { from: 0.0; to: 0.9; duration: 70 }
                                NumberAnimation { from: 0.9; to: 0.0; duration: 190 }
                            }
                        }
                    }
                }

                // line-clear banner (DOUBLE / TRIPLE / TETRIS!) — pops + fades
                Text {
                    id: banner
                    anchors.centerIn: parent
                    text: root.bannerText
                    color: root.bannerBig ? root.theme.accent : root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: root.bannerBig ? (root.theme.fsLarge + 22) : (root.theme.fsLarge + 8)
                    opacity: 0
                    scale: 0.6
                    SequentialAnimation {
                        id: bannerAnim
                        running: false
                        ParallelAnimation {
                            NumberAnimation { target: banner; property: "opacity"; from: 0; to: 1; duration: 120 }
                            NumberAnimation { target: banner; property: "scale"; from: 0.6; to: 1.15; duration: 170; easing.type: Easing.OutBack }
                        }
                        PauseAnimation { duration: 340 }
                        ParallelAnimation {
                            NumberAnimation { target: banner; property: "opacity"; to: 0; duration: 240 }
                            NumberAnimation { target: banner; property: "scale"; to: 1.35; duration: 240 }
                        }
                    }
                }

                // paused / game-over veil over the well
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
                            text: root.over ? "Enter to play again" : "P to resume"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                }
            }

            // ---- side column: stats · next · rules · controls ----
            Column {
                width: parent.width - well.width - 16
                spacing: 12

                // score / high / level / lines
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { "k": "Score", "v": root.score },
                            { "k": "Best",  "v": root.high },
                            { "k": "Level", "v": root.level },
                            { "k": "Lines", "v": root.lines }
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
                                text: statCol.modelData.v.toString()
                                color: root.theme.text
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge + 3
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider }

                // next three pieces
                Text {
                    text: "Next"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Row {
                    spacing: 8
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            id: prev
                            required property int index
                            // `queue` is mutated in place (shift/push), so its identity
                            // never changes — depend on `rev` to re-read it each turn.
                            readonly property string t: {
                                root.rev;
                                return (root.queue && root.queue.length > index) ? root.queue[index] : "";
                            }
                            readonly property int u: 9        // mini cell size
                            width: u * 4 + 8
                            height: u * 2 + 8
                            radius: root.theme.radiusSmall
                            color: "#0f0c08"
                            border.width: 1
                            border.color: root.theme.border
                            Item {
                                anchors.centerIn: parent
                                width: prev.u * 4
                                height: prev.u * 2
                                Repeater {
                                    model: prev.t !== "" ? root.shapes[prev.t][0] : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        x: modelData[0] * prev.u
                                        y: modelData[1] * prev.u
                                        width: prev.u - 1
                                        height: prev.u - 1
                                        radius: 1
                                        color: prev.t !== "" ? root.colors[prev.t] : "transparent"
                                    }
                                }
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
                            "← →   Move",
                            "↑ / X   Rotate",
                            "↓   Soft drop",
                            "Space   Hard drop",
                            "P   Pause",
                            "Clear rows to score"
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

    // ---- screenshot share overlay: the pretty snapshot card + a "saved" toast ----
    // `shareCard` is the grabToImage target — its contents are exactly what lands in
    // the PNG (board · next · score/level), independent of the veil/toast around it.
    Rectangle {
        anchors.fill: parent
        visible: root.shareMode
        color: Qt.rgba(0, 0, 0, 0.74)

        MouseArea { anchors.fill: parent; onClicked: root.shareMode = false }   // click to dismiss

        Rectangle {
            id: shareCard
            anchors.centerIn: parent
            width: 340
            height: shareCol.implicitHeight + 40
            radius: root.theme.radiusPanel
            color: root.theme.bgElevated
            border.width: 1
            border.color: root.theme.borderStrong

            Column {
                id: shareCol
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 14

                // wordmark
                Text {
                    text: "TETRIS"
                    color: root.theme.accent
                    font.family: root.theme.serif
                    font.pixelSize: root.theme.fsLarge + 9
                }

                Row {
                    spacing: 16

                    // mini board — filled cells only, on a dark well (clean for a shot)
                    Rectangle {
                        width: root.cols * 12 + 2
                        height: root.rows * 12 + 2
                        color: "#0f0c08"
                        radius: root.theme.radiusSmall
                        border.width: 1
                        border.color: root.theme.border
                        clip: true
                        Item {
                            x: 1; y: 1
                            width: root.cols * 12
                            height: root.rows * 12
                            Repeater {
                                model: root.rows * root.cols
                                delegate: Item {
                                    id: mcell
                                    required property int index
                                    readonly property int cc: index % root.cols
                                    readonly property int rr: Math.floor(index / root.cols)
                                    readonly property string t: {
                                        var v = root.view;
                                        return (v && v[rr]) ? v[rr][cc] : "";
                                    }
                                    x: cc * 12
                                    y: rr * 12
                                    width: 12
                                    height: 12
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        radius: 2
                                        visible: mcell.t !== ""
                                        color: mcell.t !== "" ? root.colors[mcell.t] : "transparent"
                                    }
                                }
                            }
                        }
                    }

                    // stats + next
                    Column {
                        spacing: 12

                        Column {
                            spacing: 1
                            Text {
                                text: "SCORE"
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                            }
                            Text {
                                text: root.score.toString()
                                color: root.theme.text
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge + 12
                            }
                        }

                        Row {
                            spacing: 20
                            Column {
                                spacing: 1
                                Text {
                                    text: "LEVEL"
                                    color: root.theme.faint
                                    font.family: root.theme.mono
                                    font.pixelSize: root.theme.fsSmall
                                    font.letterSpacing: root.theme.labelSpacing
                                }
                                Text {
                                    text: root.level.toString()
                                    color: root.theme.text
                                    font.family: root.theme.serif
                                    font.pixelSize: root.theme.fsLarge + 4
                                }
                            }
                            Column {
                                spacing: 1
                                Text {
                                    text: "LINES"
                                    color: root.theme.faint
                                    font.family: root.theme.mono
                                    font.pixelSize: root.theme.fsSmall
                                    font.letterSpacing: root.theme.labelSpacing
                                }
                                Text {
                                    text: root.lines.toString()
                                    color: root.theme.text
                                    font.family: root.theme.serif
                                    font.pixelSize: root.theme.fsLarge + 4
                                }
                            }
                        }

                        Column {
                            spacing: 5
                            Text {
                                text: "NEXT"
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                            }
                            Row {
                                spacing: 6
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        id: np
                                        required property int index
                                        readonly property string t: {
                                            root.rev;
                                            return (root.queue && root.queue.length > index) ? root.queue[index] : "";
                                        }
                                        readonly property int u: 8
                                        width: u * 4 + 6
                                        height: u * 2 + 6
                                        radius: root.theme.radiusSmall
                                        color: "#0f0c08"
                                        border.width: 1
                                        border.color: root.theme.border
                                        Item {
                                            anchors.centerIn: parent
                                            width: np.u * 4
                                            height: np.u * 2
                                            Repeater {
                                                model: np.t !== "" ? root.shapes[np.t][0] : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    x: modelData[0] * np.u
                                                    y: modelData[1] * np.u
                                                    width: np.u - 1
                                                    height: np.u - 1
                                                    radius: 1
                                                    color: np.t !== "" ? root.colors[np.t] : "transparent"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // saved toast under the card (NOT part of the grab)
        Text {
            anchors.horizontalCenter: shareCard.horizontalCenter
            anchors.top: shareCard.bottom
            anchors.topMargin: 14
            text: root.shotName ? ("Saved · " + root.shotName) : "Saving…"
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
            font.letterSpacing: root.theme.labelSpacing
        }
    }
}
