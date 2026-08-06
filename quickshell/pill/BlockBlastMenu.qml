pragma ComponentBehavior: Bound
// BlockBlastMenu.qml — a Block-Blast / Woodoku-style puzzle, played inside the
// control panel (menu 10, opened from the tiny plus/T button below the Tetris
// button beside the expanded-pill clock). A compact top bar (score / best · New
// game) sits above a 10×10 grid and a tray of three blocks that fill the rest.
//
// Unlike Tetris this game is MOUSE-ONLY: press a tray block, drag it over the
// grid — a snap-shadow appears wherever it fits (nothing shows where it can't) —
// and release to animate-drop it into that spot; release off a valid spot and
// the block springs back to the tray. Filling any full row(s) and/or column(s)
// clears them all at once (they flash then vanish, Tetris-style); clearing 3+ in
// one drop is boosted, and clearing on consecutive drops multiplies by a rising
// combo. When the three tray blocks are all placed, three fresh ones appear —
// always chosen so at least one fits the board. The game ends when, after a drop,
// none of the remaining blocks can be placed anywhere.
//
// The whole state (board, tray, score, best, combo, over) is persisted into the
// shared launcher settings under `blockBlast`, so closing the panel and reopening
// it — or restarting the shell — resumes exactly where you left off. A screenshot
// button in the header saves a pretty snapshot (grid + score) to ~/Pictures/Screenshots.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — persistence lives in settings.blockBlast

    signal closeRequested()

    // park-drag: the header grip drives these; init.qml catches them and moves the
    // whole pane (mirrors Tetris — see the Connections block wired to menuLoader.item).
    signal parkDragStart(real sx, real sy)
    signal parkDragMove(real sx, real sy)
    signal parkDragEnd()

    // ---- geometry ----
    // The grid + tray fill the whole pane below a compact top bar (stats · New game).
    // `cell` is derived so the 10×10 grid is as large as the leftover space allows —
    // bounded by width OR the height left after the top bar, gaps and the tray row —
    // so there's maximum playing ground and no wasted space.
    readonly property int n: 10             // 10×10 grid
    readonly property int statsH: 46        // top bar height
    readonly property int trayCell: 20      // tray-preview cell size (px)
    readonly property int trayH: trayCell * 3 + 16   // one tray slot's height
    readonly property int cell: {
        var g = theme.gap;
        var availH = height - 26 - statsH - trayH - g * 3;   // header + bar + tray + 3 gaps
        return Math.max(22, Math.floor(Math.min(width, availH) / n));
    }
    readonly property int gridPx: n * cell + 2

    // ---- blocks: one color per distinct block; Tetris shapes reuse Tetris colors.
    //      Cells are [col,row] inside the shape's own box; presentation picks a
    //      random rotation+mirror orientation (see orientations()). ----
    readonly property var kinds: ["dot", "d2", "d3", "i4", "sq2", "sq3", "cl2", "cl3", "jL", "tT", "sS"]
    readonly property var colors: ({
        "dot": "#e0669e",   // 1×1                     (own — rose)
        "d2":  "#34b3a4",   // 2×1 line                (own — teal)
        "d3":  "#b0b040",   // 3×1 line                (own — olive)
        "i4":  "#4fc3d6",   // 4×1 line                (Tetris I — cyan)
        "sq2": "#d6c23c",   // 2×2 square              (Tetris O — yellow)
        "sq3": "#d68a3c",   // 3×3 square              (own — orange)
        "cl2": "#d65c5c",   // 2×2 corner L (3 cells)  (own — red)
        "cl3": "#c976c9",   // 3×3 corner L (5 cells)  (own — orchid)
        "jL":  "#5b7fd6",   // x·· / xxx               (Tetris J — blue)
        "tT":  "#b05cd6",   // ·x· / xxx               (Tetris T — purple)
        "sS":  "#5cc46a"    // x· / xx / ·x            (Tetris S — green)
    })
    readonly property var baseCells: ({
        "dot": [[0,0]],
        "d2":  [[0,0],[1,0]],
        "d3":  [[0,0],[1,0],[2,0]],
        "i4":  [[0,0],[1,0],[2,0],[3,0]],
        "sq2": [[0,0],[1,0],[0,1],[1,1]],
        "sq3": [[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]],
        "cl2": [[0,0],[0,1],[1,1]],
        "cl3": [[0,0],[0,1],[0,2],[1,2],[2,2]],
        "jL":  [[0,0],[0,1],[1,1],[2,1]],
        "tT":  [[1,0],[0,1],[1,1],[2,1]],
        "sS":  [[0,0],[0,1],[1,1],[1,2]]
    })

    // ---- state ----
    property var board: []                  // n×n; each cell "" or a block-kind key
    property var tray: [null, null, null]   // the three offered blocks: { kind, cells } or null once placed
    property int score: 0
    property int best: 0
    property int combo: 0                   // consecutive clearing drops (the combo multiplier)
    property bool over: false
    property var flashCells: []             // [{r,c}] cells clearing this drop, flashing before removal
    property var pendClearRows: []          // rows/cols pending removal once the flash ends
    property var pendClearCols: []
    property int rev: 0                      // bump to refresh derived reads of board/tray

    // ---- shape helpers ----
    function normalize(cells) {
        var minx = Infinity, miny = Infinity;
        for (var i = 0; i < cells.length; i++) { minx = Math.min(minx, cells[i][0]); miny = Math.min(miny, cells[i][1]); }
        var out = [];
        for (var j = 0; j < cells.length; j++) out.push([cells[j][0] - minx, cells[j][1] - miny]);
        return out;
    }
    function rot90(cells) {                  // (x,y) → (y,-x)
        var out = [];
        for (var i = 0; i < cells.length; i++) out.push([cells[i][1], -cells[i][0]]);
        return normalize(out);
    }
    function mirrorX(cells) {                // (x,y) → (-x,y)
        var out = [];
        for (var i = 0; i < cells.length; i++) out.push([-cells[i][0], cells[i][1]]);
        return normalize(out);
    }
    function cellsKey(cells) {
        var s = [];
        for (var i = 0; i < cells.length; i++) s.push(cells[i][0] + "," + cells[i][1]);
        s.sort();
        return s.join(";");
    }
    // every distinct rotation (×4) AND mirror of a block — deduped
    function orientations(kind) {
        var seen = ({});
        var out = [];
        var forms = [normalize(baseCells[kind]), mirrorX(baseCells[kind])];
        for (var f = 0; f < forms.length; f++) {
            var c = forms[f];
            for (var r = 0; r < 4; r++) {
                var k = cellsKey(c);
                if (!seen[k]) { seen[k] = true; out.push(c); }
                c = rot90(c);
            }
        }
        return out;
    }
    // a fresh block: uniform over the kinds, then a uniform orientation of it
    function makeBlock() {
        var kind = kinds[Math.floor(Math.random() * kinds.length)];
        var os = orientations(kind);
        return { "kind": kind, "cells": os[Math.floor(Math.random() * os.length)] };
    }

    // ---- board helpers ----
    function emptyBoard() {
        var g = [];
        for (var r = 0; r < n; r++) { var row = []; for (var c = 0; c < n; c++) row.push(""); g.push(row); }
        return g;
    }
    // does `cells` placed with top-left cell (ox,oy) sit fully on empty grid?
    function fits(cells, ox, oy) {
        for (var i = 0; i < cells.length; i++) {
            var x = ox + cells[i][0];
            var y = oy + cells[i][1];
            if (x < 0 || x >= n || y < 0 || y >= n) return false;
            if (board[y][x]) return false;
        }
        return true;
    }
    function canPlaceAnywhere(cells) {
        for (var oy = 0; oy < n; oy++)
            for (var ox = 0; ox < n; ox++)
                if (fits(cells, ox, oy)) return true;
        return false;
    }

    // deal three blocks, guaranteeing at least one fits the current board. Returns
    // false only if no placeable set could be found (board is effectively full).
    function deal() {
        for (var attempt = 0; attempt < 300; attempt++) {
            var t = [makeBlock(), makeBlock(), makeBlock()];
            if (canPlaceAnywhere(t[0].cells) || canPlaceAnywhere(t[1].cells) || canPlaceAnywhere(t[2].cells)) {
                tray = t;
                rev++;
                return true;
            }
        }
        return false;
    }

    function newGame() {
        board = emptyBoard();
        score = 0; combo = 0; over = false;
        flashCells = []; pendClearRows = []; pendClearCols = [];
        deal();                              // an empty board always yields a placeable set
        rev++;
        save();
    }

    // ---- placement + clearing ----
    // stamp tray[slot] onto the board at (ox,oy), score any completed rows/cols,
    // flash them (deferred removal in finalizeFlash), then hand off to postPlace.
    function place(slot, ox, oy) {
        var b = tray[slot];
        if (!b) return;
        for (var i = 0; i < b.cells.length; i++)
            board[oy + b.cells[i][1]][ox + b.cells[i][0]] = b.kind;
        var nt = tray.slice(); nt[slot] = null; tray = nt;

        // which rows / columns are now completely full?
        var fr = [], fc = [];
        for (var r = 0; r < n; r++) { var full = true; for (var c = 0; c < n; c++) if (!board[r][c]) { full = false; break; } if (full) fr.push(r); }
        for (var cc = 0; cc < n; cc++) { var f2 = true; for (var rr = 0; rr < n; rr++) if (!board[rr][cc]) { f2 = false; break; } if (f2) fc.push(cc); }
        var cleared = fr.length + fc.length;

        if (cleared > 0) {
            combo += 1;                       // this drop scored → combo rises
            var base = 10 * cleared * (cleared > 1 ? cleared * 0.5 : 1);   // 1→10 2→20 3→45 4→80 …
            var gained = Math.round(base * combo);
            score += gained;
            if (score > best) best = score;
            if (combo >= 2) popCombo(combo); else popBanner(cleared);
            // collect the flashing cells (union of the full rows and columns)
            var fcells = [];
            for (var a = 0; a < fr.length; a++) for (var x = 0; x < n; x++) fcells.push({ "r": fr[a], "c": x });
            for (var b2 = 0; b2 < fc.length; b2++) for (var y = 0; y < n; y++) fcells.push({ "r": y, "c": fc[b2] });
            flashCells = fcells;
            pendClearRows = fr; pendClearCols = fc;
            flashTimer.restart();             // → finalizeFlash() when the flash ends
        } else {
            combo = 0;                        // a non-clearing drop breaks the combo
            postPlace();
        }
        rev++;
        save();
    }

    // after the flash: actually drop the completed rows/columns, then check refill /
    // game-over. (Scoring already happened in place(); this is the visual removal.)
    function finalizeFlash() {
        if (flashCells.length === 0) return;
        for (var a = 0; a < pendClearRows.length; a++) for (var c = 0; c < n; c++) board[pendClearRows[a]][c] = "";
        for (var b = 0; b < pendClearCols.length; b++) for (var r = 0; r < n; r++) board[r][pendClearCols[b]] = "";
        flashCells = []; pendClearRows = []; pendClearCols = [];
        rev++;
        postPlace();
        save();
    }

    // refill when the tray is empty (guaranteed placeable), then decide game-over:
    // if none of the blocks still in the tray can be placed anywhere, it's over.
    function postPlace() {
        if (tray[0] === null && tray[1] === null && tray[2] === null) {
            if (!deal()) over = true;
        }
        if (!over) {
            var any = false;
            for (var i = 0; i < tray.length; i++) if (tray[i] && canPlaceAnywhere(tray[i].cells)) { any = true; break; }
            if (!any) over = true;
        }
        if (over && score > best) best = score;
        rev++;
    }

    // ---- clear flair ----
    // a centred banner names the multi-clear (DOUBLE / TRIPLE / QUAD!); a separate,
    // flashier combo flare ("3× COMBO") fires once the combo reaches 2.
    property string bannerText: ""
    property bool bannerBig: false
    function popBanner(cleared) {
        bannerText = cleared >= 4 ? "QUAD!" : cleared === 3 ? "TRIPLE" : cleared === 2 ? "DOUBLE" : "CLEAR";
        bannerBig = cleared >= 3;
        bannerAnim.restart();
    }
    property string comboText: ""
    function popCombo(combo) { comboText = combo + "× COMBO"; comboAnim.restart(); }

    // ---- persistence (shared launcher settings, key `blockBlast`) ----
    function save() {
        root.settings.blockBlast = {
            "board": board, "tray": tray, "score": score, "best": best,
            "combo": combo, "over": over
        };
    }
    function load() {
        var s = root.settings.blockBlast;
        if (s && s.board && s.board.length === n) {
            board = s.board;
            tray = s.tray || [null, null, null];
            score = s.score || 0;
            best = s.best || 0;
            combo = s.combo || 0;
            over = !!s.over;
            rev++;
        } else {
            newGame();
        }
    }
    Component.onCompleted: load();
    // resume exactly here next time. If we're mid-flash (closed in the ~260ms
    // window), finish the clear first so we never persist a full, un-cleared line.
    Component.onDestruction: { if (flashCells.length > 0) finalizeFlash(); save(); }

    Timer { id: flashTimer; interval: 260; onTriggered: root.finalizeFlash() }

    // ---- drag state ----
    property bool dragActive: false         // a block is being carried
    property bool dropping: false           // the release-drop animation is playing
    property int dragSlot: -1               // which tray slot is airborne
    property var dragCells: []              // its oriented cells
    property string dragKind: ""            // its color key
    property real dragW: 0                  // block pixel size (grid-cell scale)
    property real dragH: 0
    property real proxyX: 0                 // carried block's top-left, in root coords
    property real proxyY: 0
    property int shadowOX: -1               // snapped landing cell (top-left)
    property int shadowOY: -1
    property bool shadowValid: false        // does the block fit at the snapped spot?
    property real dropTX: 0                 // drop-animation targets (root coords)
    property real dropTY: 0

    function endDrag() {
        if (shadowValid) {
            dropping = true;
            var go = gridContent.mapToItem(root, 0, 0);
            dropTX = go.x + shadowOX * cell;
            dropTY = go.y + shadowOY * cell;
            dropAnim.restart();               // slide the block into the shadow, then commit
        } else {
            cancelDrag();
        }
    }
    function commitDrop() {
        place(dragSlot, shadowOX, shadowOY);
        dragActive = false; dropping = false; dragSlot = -1; shadowValid = false;
    }
    function cancelDrag() {
        dragActive = false; dragSlot = -1; shadowValid = false;
    }

    // the release-drop: slide the carried block from the pointer into the snapped
    // shadow cells, then stamp it onto the board.
    ParallelAnimation {
        id: dropAnim
        NumberAnimation { target: root; property: "proxyX"; to: root.dropTX; duration: 110; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "proxyY"; to: root.dropTY; duration: 110; easing.type: Easing.OutCubic }
        onFinished: root.commitDrop()
    }

    // ---- screenshot: grab the pretty share card → save + copy ----
    property bool shareMode: false
    property string shotName: ""
    readonly property string shotTmp: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/blockblast-share.png"
    readonly property string shotDir: (Quickshell.env("HOME") || "/tmp") + "/Pictures/Screenshots"
    Process { id: shotSaver }
    Timer { id: shotDismiss; interval: 1600; onTriggered: root.shareMode = false }
    function takeShot() {
        shareMode = true;
        Qt.callLater(function () {
            shareCard.grabToImage(function (res) {
                if (!res) { root.shareMode = false; return; }
                res.saveToFile(root.shotTmp);
                root.shotName = "blockblast-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss") + ".png";
                shotSaver.command = ["sh", "-c",
                    "mkdir -p '" + root.shotDir + "' && cp '" + root.shotTmp + "' '" + root.shotDir + "/" + root.shotName +
                    "' && (wl-copy --type image/png < '" + root.shotTmp + "' || true)"];
                shotSaver.running = true;
                shotDismiss.restart();
            });
        });
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            id: header
            theme: root.theme
            title: "Block Blast"
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

            // screenshot button
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
                    onClicked: root.takeShot()
                }
            }
        }

        // ---- top bar: score / best (left) · New game (right) ----
        Item {
            width: parent.width
            height: root.statsH

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 26
                Repeater {
                    model: [
                        { "k": "Score", "v": root.score },
                        { "k": "Best",  "v": root.best }
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
                            font.pixelSize: root.theme.fsLarge + 6
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 96; height: 32
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
                    onClicked: root.newGame()
                }
            }
        }

        // ---- play area: the 10×10 grid over the tray, filling the rest ----
        Column {
            width: parent.width
            spacing: root.theme.gap

            // grid (centered; sized to fill the leftover space via root.cell)
            Item {
                width: parent.width
                height: root.gridPx

                Rectangle {
                    id: grid
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.gridPx
                    height: root.gridPx
                    color: "#0f0c08"
                    radius: root.theme.radiusSmall
                    border.width: 1
                    border.color: root.theme.border
                    clip: true

                    Item {
                        id: gridContent
                        x: 1; y: 1
                        width: root.n * root.cell
                        height: root.n * root.cell

                        // settled cells
                        Repeater {
                            model: root.n * root.n
                            delegate: Rectangle {
                                id: gcell
                                required property int index
                                readonly property int cc: index % root.n
                                readonly property int rr: Math.floor(index / root.n)
                                readonly property string k: {
                                    root.rev;
                                    return (root.board[rr] ? root.board[rr][cc] : "") || "";
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
                                    radius: 3
                                    visible: gcell.k !== ""
                                    color: gcell.k !== "" ? root.colors[gcell.k] : "transparent"
                                }
                            }
                        }

                        // snap-shadow: where the carried block would land (only when it fits)
                        Repeater {
                            model: (root.dragActive && root.shadowValid) ? root.dragCells : []
                            delegate: Rectangle {
                                required property var modelData
                                x: (root.shadowOX + modelData[0]) * root.cell
                                y: (root.shadowOY + modelData[1]) * root.cell
                                width: root.cell
                                height: root.cell
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.14)
                                border.width: 2
                                border.color: root.colors[root.dragKind]
                            }
                        }

                        // line-clear flash — a bright square over each clearing cell
                        Repeater {
                            model: root.flashCells
                            delegate: Rectangle {
                                required property var modelData
                                x: modelData.c * root.cell
                                y: modelData.r * root.cell
                                width: root.cell
                                height: root.cell
                                radius: 3
                                color: "#fbf7ee"
                                opacity: 0
                                SequentialAnimation on opacity {
                                    running: true
                                    NumberAnimation { from: 0.0; to: 0.92; duration: 70 }
                                    NumberAnimation { from: 0.92; to: 0.0; duration: 190 }
                                }
                            }
                        }
                    }

                    // clear banner (COMBO / DOUBLE / TRIPLE …)
                    Text {
                        id: banner
                        anchors.centerIn: parent
                        text: root.bannerText
                        color: root.bannerBig ? root.theme.accent : root.theme.text
                        font.family: root.theme.serif
                        font.pixelSize: root.bannerBig ? (root.theme.fsLarge + 20) : (root.theme.fsLarge + 8)
                        opacity: 0
                        scale: 0.6
                        SequentialAnimation {
                            id: bannerAnim
                            running: false
                            ParallelAnimation {
                                NumberAnimation { target: banner; property: "opacity"; from: 0; to: 1; duration: 120 }
                                NumberAnimation { target: banner; property: "scale"; from: 0.6; to: 1.12; duration: 170; easing.type: Easing.OutBack }
                            }
                            PauseAnimation { duration: 320 }
                            ParallelAnimation {
                                NumberAnimation { target: banner; property: "opacity"; to: 0; duration: 240 }
                                NumberAnimation { target: banner; property: "scale"; to: 1.3; duration: 240 }
                            }
                        }
                    }

                    // combo flare — a bigger, bouncier "N× COMBO" once the combo hits 2
                    Text {
                        id: comboFlare
                        anchors.centerIn: parent
                        text: root.comboText
                        color: root.theme.accent
                        font.family: root.theme.serif
                        font.pixelSize: root.theme.fsLarge + 26
                        font.bold: true
                        opacity: 0
                        scale: 0.4
                        rotation: -6
                        SequentialAnimation {
                            id: comboAnim
                            running: false
                            ParallelAnimation {
                                NumberAnimation { target: comboFlare; property: "opacity"; from: 0; to: 1; duration: 110 }
                                NumberAnimation { target: comboFlare; property: "scale"; from: 0.4; to: 1.28; duration: 220; easing.type: Easing.OutBack }
                                NumberAnimation { target: comboFlare; property: "rotation"; from: -6; to: 3; duration: 220; easing.type: Easing.OutBack }
                            }
                            PauseAnimation { duration: 380 }
                            ParallelAnimation {
                                NumberAnimation { target: comboFlare; property: "opacity"; to: 0; duration: 280 }
                                NumberAnimation { target: comboFlare; property: "scale"; to: 1.55; duration: 280 }
                            }
                        }
                    }

                    // game-over veil over the grid
                    Rectangle {
                        anchors.fill: parent
                        visible: root.over
                        color: Qt.rgba(0x0f / 255.0, 0x0c / 255.0, 0x08 / 255.0, 0.80)
                        radius: grid.radius
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "GAME OVER"
                                color: root.theme.accent
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge + 6
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "New game to play again"
                                color: root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                                font.capitalization: Font.AllUppercase
                            }
                        }
                    }
                }
            }

            // ---- tray: the three offered blocks (drag sources), centered ----
            Item {
                width: parent.width
                height: root.trayH
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            id: slot
                            required property int index
                            readonly property var blk: { root.rev; return root.tray[index] || null; }
                            readonly property bool airborne: root.dragActive && root.dragSlot === index
                            width: (root.gridPx - 20) / 3
                            height: root.trayH
                            radius: root.theme.radiusSmall
                            color: "#0f0c08"
                            border.width: 1
                            border.color: root.theme.border
                            opacity: slot.blk ? 1 : 0.45

                            // block preview, centered; hidden while this slot is being carried
                            Item {
                                anchors.centerIn: parent
                                visible: slot.blk !== null && !slot.airborne
                                width: {
                                    if (!slot.blk) return 0;
                                    var mx = 0; for (var i = 0; i < slot.blk.cells.length; i++) mx = Math.max(mx, slot.blk.cells[i][0]);
                                    return (mx + 1) * root.trayCell;
                                }
                                height: {
                                    if (!slot.blk) return 0;
                                    var my = 0; for (var i = 0; i < slot.blk.cells.length; i++) my = Math.max(my, slot.blk.cells[i][1]);
                                    return (my + 1) * root.trayCell;
                                }
                                Repeater {
                                    model: slot.blk ? slot.blk.cells : []
                                    delegate: Rectangle {
                                        required property var modelData
                                        x: modelData[0] * root.trayCell
                                        y: modelData[1] * root.trayCell
                                        width: root.trayCell - 2
                                        height: root.trayCell - 2
                                        radius: 2
                                        color: root.colors[slot.blk.kind]
                                    }
                                }
                            }

                            MouseArea {
                                id: slotMa
                                anchors.fill: parent
                                preventStealing: true
                                enabled: !root.over && !root.dropping && slot.blk !== null
                                cursorShape: slot.blk ? Qt.OpenHandCursor : Qt.ArrowCursor
                                onPressed: (mouse) => {
                                    var b = root.tray[slot.index];
                                    if (!b) return;
                                    root.dragSlot = slot.index;
                                    root.dragCells = b.cells;
                                    root.dragKind = b.kind;
                                    var mx = 0, my = 0;
                                    for (var i = 0; i < b.cells.length; i++) { mx = Math.max(mx, b.cells[i][0]); my = Math.max(my, b.cells[i][1]); }
                                    root.dragW = (mx + 1) * root.cell;
                                    root.dragH = (my + 1) * root.cell;
                                    root.dragActive = true;
                                    slotMa.updateDrag(mouse);
                                }
                                onPositionChanged: (mouse) => { if (root.dragActive && !root.dropping) slotMa.updateDrag(mouse); }
                                onReleased: { if (root.dragActive && !root.dropping) root.endDrag(); }
                                onCanceled: { if (root.dragActive && !root.dropping) root.cancelDrag(); }
                                // carry the block (centered on the pointer, lifted a touch)
                                // and snap-check against the grid.
                                function updateDrag(mouse) {
                                    var p = slotMa.mapToItem(root, mouse.x, mouse.y);
                                    root.proxyX = p.x - root.dragW / 2;
                                    root.proxyY = p.y - root.dragH / 2 - root.cell * 0.6;
                                    var go = gridContent.mapToItem(root, 0, 0);
                                    var ox = Math.round((root.proxyX - go.x) / root.cell);
                                    var oy = Math.round((root.proxyY - go.y) / root.cell);
                                    if (root.fits(root.dragCells, ox, oy)) {
                                        root.shadowOX = ox; root.shadowOY = oy; root.shadowValid = true;
                                    } else {
                                        root.shadowValid = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    // ---- the carried block (drag proxy) — floats over everything, follows the pointer ----
    Item {
        id: proxy
        x: root.proxyX
        y: root.proxyY
        width: root.dragW
        height: root.dragH
        visible: root.dragActive
        z: 1000
        Repeater {
            model: root.dragActive ? root.dragCells : []
            delegate: Rectangle {
                required property var modelData
                x: modelData[0] * root.cell
                y: modelData[1] * root.cell
                width: root.cell
                height: root.cell
                radius: 3
                color: root.colors[root.dragKind]
                opacity: 0.92
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.25)
            }
        }
    }

    // ---- screenshot share overlay: the pretty snapshot card + a "saved" toast ----
    Rectangle {
        anchors.fill: parent
        visible: root.shareMode
        color: Qt.rgba(0, 0, 0, 0.74)
        MouseArea { anchors.fill: parent; onClicked: root.shareMode = false }

        Rectangle {
            id: shareCard
            anchors.centerIn: parent
            width: shareCol.implicitWidth + 40
            height: shareCol.implicitHeight + 40
            radius: root.theme.radiusPanel
            color: root.theme.bgElevated
            border.width: 1
            border.color: root.theme.borderStrong

            Column {
                id: shareCol
                x: 20
                y: 20
                spacing: 14

                Text {
                    text: "BLOCK BLAST"
                    color: root.theme.accent
                    font.family: root.theme.serif
                    font.pixelSize: root.theme.fsLarge + 9
                }

                Row {
                    spacing: 18

                    // mini board
                    Rectangle {
                        readonly property int u: 20
                        width: root.n * u + 2
                        height: root.n * u + 2
                        color: "#0f0c08"
                        radius: root.theme.radiusSmall
                        border.width: 1
                        border.color: root.theme.border
                        clip: true
                        Item {
                            x: 1; y: 1
                            width: parent.width - 2
                            height: parent.height - 2
                            Repeater {
                                model: root.n * root.n
                                delegate: Item {
                                    id: mcell
                                    required property int index
                                    readonly property int cc: index % root.n
                                    readonly property int rr: Math.floor(index / root.n)
                                    readonly property string k: {
                                        root.rev;
                                        return (root.board[rr] ? root.board[rr][cc] : "") || "";
                                    }
                                    x: cc * 20
                                    y: rr * 20
                                    width: 20
                                    height: 20
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        radius: 3
                                        visible: mcell.k !== ""
                                        color: mcell.k !== "" ? root.colors[mcell.k] : "transparent"
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        spacing: 14
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
                        Column {
                            spacing: 1
                            Text {
                                text: "BEST"
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                            }
                            Text {
                                text: root.best.toString()
                                color: root.theme.text
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge + 4
                            }
                        }
                    }
                }
            }
        }

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
