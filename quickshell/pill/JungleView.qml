pragma ComponentBehavior: Bound
// JungleView.qml — the scrolling per-week jungle (HabitMenu's centerpiece).
// One delegate per ISO week, newest at the top: an isometric terrain cluster
// with one cell per habit — first habit on the center tile, the rest spiraling
// clockwise outward — each cell growing that habit's weekly tree (treegen.js
// L-systems, deterministic from habiq's per-week seed). Floor vegetation
// density = the week's total score share; a separator terrain strip divides
// consecutive weeks; frozen weeks grow snow. A soft fade at the bottom keeps
// focus on the current week. Trees sway on `windT` (HabitMenu's breeze clock).
import QtQuick
import "treegen.js" as Tg

ListView {
    id: jungle
    required property var theme
    property var weeksList: []      // [{key,label,season,vegetation,cells:[{rowId,name,week}]}] newest first
    property real windT: 0          // breeze clock (seconds-ish)
    // hover/click surface for HabitMenu: cell = one habit's tile+tree
    signal cellHovered(int weekIndex, var cell, real sceneX, real sceneY)
    signal hoverEnded()
    signal cellClicked(var cell)

    clip: true
    model: weeksList
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    // the in-view week (legend highlight): whichever delegate covers the line
    // a third down the viewport
    readonly property int focusWeek: indexAt(width / 2, contentY + height * 0.33)
    function scrollToWeek(i) {
        positionViewAtIndex(i, ListView.Beginning);
    }

    // isometric grid metrics (shared by delegate paint + hit-testing)
    readonly property int tileW: 56
    readonly property int tileH: 28
    readonly property int treeRoom: 74   // canopy space above the cluster
    readonly property int sepRoom: 30    // separator terrain strip below

    // center tile first, then clockwise around it, ring by ring (top → right →
    // bottom → left), in iso grid coords {c,r}
    function spiral(n) {
        var out = [{ c: 0, r: 0 }];
        for (var ring = 1; out.length < n; ring++) {
            var walk = [];
            var c = 0, r = -ring;                    // top corner
            var moves = [[1, 1], [-1, 1], [-1, -1], [1, -1]]; // cw: →br, →bl, →tl, →tr
            for (var m = 0; m < 4; m++)
                for (var s = 0; s < ring; s++) {
                    walk.push({ c: c, r: r });
                    c += moves[m][0]; r += moves[m][1];
                }
            for (var i = 0; i < walk.length && out.length < n; i++)
                out.push(walk[i]);
        }
        return out;
    }

    delegate: Item {
        id: block
        required property var modelData
        required property int index
        readonly property var cells: modelData.cells || []
        readonly property var pos: jungle.spiral(cells.length)
        readonly property int rings: {
            var m = 0;
            for (var i = 0; i < pos.length; i++)
                m = Math.max(m, Math.abs(pos[i].c), Math.abs(pos[i].r));
            return m;
        }
        readonly property int clusterH: (rings * 2 + 1) * jungle.tileH
        width: jungle.width
        height: jungle.treeRoom + clusterH + jungle.sepRoom

        // screen-space center of cell i's tile inside this delegate
        function cellCenter(i) {
            var p = pos[i];
            return {
                x: width / 2 + (p.c - p.r) * jungle.tileW / 2,
                y: jungle.treeRoom + clusterH / 2 + (p.c + p.r) * jungle.tileH / 2
            };
        }
        function cellAt(mx, my) {
            // nearest tile center within a diamond-ish radius; trees overhang
            // upward, so accept hits up to the canopy above the tile too
            var best = -1, bestD = 1e9;
            for (var i = 0; i < cells.length; i++) {
                var cc = cellCenter(i);
                var dx = Math.abs(mx - cc.x), dy = my - cc.y;
                var d = dx + Math.abs(dy) * 2;
                if (dx < jungle.tileW * 0.55 && dy < jungle.tileH && dy > -jungle.treeRoom && d < bestD) {
                    bestD = d; best = i;
                }
            }
            return best;
        }

        // per-row tree geometry, cached per (seed, stage) — regrown only when
        // the report changes, not on every breeze repaint
        property var _trees: ({})
        function treeFor(cell) {
            var k = cell.week.seed + ":" + cell.week.stage;
            if (!_trees[k]) _trees[k] = Tg.build(cell.week.seed, cell.week.stage);
            return _trees[k];
        }

        Canvas {
            id: cv
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            property real wt: jungle.windT
            onWtChanged: requestPaint()
            Component.onCompleted: requestPaint()

            function leafColor(week, season) {
                if (week.band === "dead") return "#655a4b";
                if (week.band === "low") return "#8a6a45";
                if (week.band === "mid") return "#b59a63";
                var green = season === "spring" || season === "summer";
                return green ? "#74b06a" : "#d78f3c";
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var wk = block.modelData;
                var frozenWeek = false;
                var i;
                for (i = 0; i < block.cells.length; i++)
                    if (block.cells[i].week.band === "frozen") frozenWeek = true;

                // draw back-to-front: sort cell indices by screen y
                var order = [];
                for (i = 0; i < block.cells.length; i++) order.push(i);
                order.sort(function (a, b) { return block.cellCenter(a).y - block.cellCenter(b).y; });

                var warm = wk.season === "fall" || wk.season === "winter";
                var soil = warm ? "#33291e" : "#2c2f20";
                var soilHi = warm ? "#41332a" : "#3a3d2a";

                // ---- tiles ----
                for (var oi = 0; oi < order.length; oi++) {
                    i = order[oi];
                    var cc = block.cellCenter(i);
                    var frozen = block.cells[i].week.band === "frozen";
                    ctx.beginPath();
                    ctx.moveTo(cc.x, cc.y - jungle.tileH / 2);
                    ctx.lineTo(cc.x + jungle.tileW / 2, cc.y);
                    ctx.lineTo(cc.x, cc.y + jungle.tileH / 2);
                    ctx.lineTo(cc.x - jungle.tileW / 2, cc.y);
                    ctx.closePath();
                    ctx.fillStyle = frozen ? "#5a6068" : soil;
                    ctx.fill();
                    ctx.strokeStyle = frozen ? "#8b95a0" : soilHi;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                    if (frozen) {   // snow wash on the tile
                        ctx.globalAlpha = 0.55;
                        ctx.fillStyle = "#dfe6ec";
                        ctx.fill();
                        ctx.globalAlpha = 1;
                    }
                }

                // ---- floor vegetation (density = week total score share) ----
                var veg = wk.vegetation || 0;
                for (i = 0; i < block.cells.length; i++) {
                    var center = block.cellCenter(i);
                    var n = Math.round(veg * 7);
                    for (var v = 0; v < n; v++) {
                        var t = Tg.tuft(block.cells[i].week.seed * 31 + v * 7 + 1);
                        var rr = Tg.rng32(block.cells[i].week.seed + v * 131);
                        var px = center.x + (rr() - 0.5) * (jungle.tileW - 16);
                        var py = center.y + (rr() - 0.5) * (jungle.tileH - 8);
                        var sway = Math.sin(cv.wt * 2.1 + px * 0.3) * 0.9;
                        ctx.strokeStyle = frozenWeek ? "#c9d2da"
                            : (warm ? "#6b5a35" : "#55663d");
                        ctx.lineWidth = 1;
                        for (var b = 0; b < t.blades.length; b++) {
                            ctx.beginPath();
                            ctx.moveTo(px, py);
                            ctx.lineTo(px + t.blades[b].x2 + sway, py + t.blades[b].y2);
                            ctx.stroke();
                        }
                    }
                }

                // ---- trees ----
                for (oi = 0; oi < order.length; oi++) {
                    i = order[oi];
                    var cell = block.cells[i];
                    var cw = cell.week;
                    var geo = block.treeFor(cell);
                    var c2 = block.cellCenter(i);
                    // scale to a stage-appropriate height inside the canopy room
                    var targetH = 16 + (cw.stage - 1) * 16 + cw.sizeRatio * 10;
                    var sc = targetH / geo.h;
                    var phase = (cw.seed % 628) / 100;
                    var lc = leafColor(cw, wk.season);
                    var dead = cw.band === "dead";
                    var snowFrac = cw.band === "frozen" ? 1 : Math.min(1, (cw.frozenDays || 0) / 7);

                    // trunk + branches (depth-shaded, wind-sheared by height)
                    for (var s = 0; s < geo.segs.length; s++) {
                        var seg = geo.segs[s];
                        var w1 = Math.max(1, (3.4 - seg.d * 0.8) * sc * 0.5 + 0.6);
                        var sway1 = Math.sin(cv.wt * 1.4 + phase + (-seg.y1) * 0.05 * sc) * 1.6 * (-seg.y1 * sc / targetH);
                        var sway2 = Math.sin(cv.wt * 1.4 + phase + (-seg.y2) * 0.05 * sc) * 1.6 * (-seg.y2 * sc / targetH);
                        ctx.strokeStyle = dead ? "#4a4038" : (seg.d === 0 ? "#5d4630" : "#6d5638");
                        ctx.lineWidth = w1;
                        ctx.beginPath();
                        ctx.moveTo(c2.x + seg.x1 * sc + sway1, c2.y + seg.y1 * sc);
                        ctx.lineTo(c2.x + seg.x2 * sc + sway2, c2.y + seg.y2 * sc);
                        ctx.stroke();
                    }
                    // foliage: diamonds (dead trees keep only sparse dark stubs)
                    for (var l = 0; l < geo.leaves.length; l++) {
                        if (dead && l % 3 !== 0) continue;
                        var leaf = geo.leaves[l];
                        var lr = Math.max(1.6, leaf.r * sc * 0.9);
                        var lx = c2.x + leaf.x * sc
                               + Math.sin(cv.wt * 1.4 + phase + (-leaf.y) * 0.05 * sc) * 1.8 * (-leaf.y * sc / targetH);
                        var ly = c2.y + leaf.y * sc;
                        var snowy = snowFrac > 0 && (l % 7) < snowFrac * 7;
                        ctx.fillStyle = dead ? "#5a5148" : (snowy ? "#e6ebf0" : lc);
                        ctx.globalAlpha = dead ? 0.8 : 0.95 - (leaf.d * 0.04);
                        ctx.beginPath();
                        ctx.moveTo(lx, ly - lr);
                        ctx.lineTo(lx + lr, ly);
                        ctx.lineTo(lx, ly + lr);
                        ctx.lineTo(lx - lr, ly);
                        ctx.closePath();
                        ctx.fill();
                        ctx.globalAlpha = 1;
                    }
                }

                // ---- separator terrain strip (older week begins below) ----
                if (block.index < jungle.count - 1) {
                    var sy = block.height - jungle.sepRoom / 2;
                    for (var st = -3; st <= 3; st++) {
                        var sx = block.width / 2 + st * jungle.tileW * 0.62;
                        ctx.beginPath();
                        ctx.moveTo(sx, sy - jungle.tileH * 0.28);
                        ctx.lineTo(sx + jungle.tileW * 0.35, sy);
                        ctx.lineTo(sx, sy + jungle.tileH * 0.28);
                        ctx.lineTo(sx - jungle.tileW * 0.35, sy);
                        ctx.closePath();
                        ctx.globalAlpha = 0.5;
                        ctx.fillStyle = soil;
                        ctx.fill();
                        ctx.globalAlpha = 1;
                        ctx.strokeStyle = soilHi;
                        ctx.lineWidth = 1;
                        ctx.stroke();
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: (mouse) => {
                var i = block.cellAt(mouse.x, mouse.y);
                if (i >= 0) {
                    var p = block.mapToItem(jungle, mouse.x, mouse.y);
                    jungle.cellHovered(block.index, block.cells[i], p.x, p.y);
                } else {
                    jungle.hoverEnded();
                }
            }
            onExited: jungle.hoverEnded()
            onClicked: (mouse) => {
                var i = block.cellAt(mouse.x, mouse.y);
                if (i >= 0) jungle.cellClicked(block.cells[i]);
            }
        }
    }
}
