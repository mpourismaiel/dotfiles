pragma ComponentBehavior: Bound
// JungleView.qml — the scrolling per-week jungle (HabitMenu's centerpiece).
//
// THE WHOLE GARDEN IS ONE ISOMETRIC LATTICE. Screen position of grid cell
// (c,r): x = (c−r)·tileW/2, y = (c+r)·tileH/2 — "levels" (c+r) are th/2
// bands. Every week's cluster (first habit on the center tile, the rest
// spiraling clockwise around it) has its center on that shared lattice, and
// the SEPARATOR between weeks is a row of FIVE lattice cells on the level
// between the clusters — middle cell at x=0, exactly below both jungle
// centers, edge-touching the clusters' shoulder cells when parity allows
// (vertex-touching otherwise). Cluster centers land on even levels (a
// centered cell needs c=r), so the gap below a cluster whose lowest cell is
// at level L is L+1 rounded up to even — everything stays on the one grid,
// delegate heights are exact multiples of tileH/2, and consecutive
// delegates continue the lattice seamlessly.
//
// Trees overhang upward past their delegate (each Canvas extends `overhang`
// px above and paints translated); `z: index` stacks older (lower) weeks
// above, the classic painter's order — a lower jungle's canopy rises over
// the row above it. Floor vegetation density = the week's total score
// share; separator tiles carry a little season-palette vegetation and are
// snow-washed when the week is frozen. The garden's head (newest week) rests
// at the vertical middle of the view — half a viewport of sky above it — and
// weeks are generated lazily: only delegates within ~300px of the viewport
// exist (cacheBuffer), regrown deterministically when scrolled back. A soft
// fade at the bottom keeps focus on the current week; trees sway on `windT`
// (HabitMenu's breeze clock).
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
    // LAZY GENERATION: delegates (tiles, tree geometry, canvases) only exist
    // for weeks in or near the viewport — ListView instantiates them as they
    // scroll in and destroys them ~300px after they scroll out, either
    // direction. Re-entering regrows the identical week (everything is a pure
    // function of habiq's seeds), so nothing needs to persist.
    cacheBuffer: 300
    // the in-view week (legend highlight): whichever delegate covers the
    // viewport's vertical middle — the same line the garden's head rests on
    readonly property int focusWeek: indexAt(width / 2, contentY + height * 0.5)
    function scrollToWeek(i) {
        positionViewAtIndex(i, ListView.Center);
    }

    // isometric grid metrics (shared by delegate paint + hit-testing)
    readonly property int tileW: 56
    readonly property int tileH: 28
    readonly property int overhang: 84   // canopy allowance painted above each delegate
    // the top of the garden rests at the vertical MIDDLE of the view (not the
    // top edge): the header pads half a viewport of sky above the newest week,
    // which also gives its canopy room
    header: Item { width: 1; height: Math.max(jungle.overhang, jungle.height / 2) }
    // the header resizes with the view, but ListView anchors ITEMS (not the
    // header) across that change, so without a re-pin the head drifts to the
    // top edge. Pin back to the beginning whenever geometry/model settles —
    // only while we're still within the first screen, so a user who has
    // scrolled deep is never yanked.
    function _pinStart() {
        if (!moving && !dragging && contentY - originY < height * 0.6)
            positionViewAtBeginning();
    }
    onCountChanged: Qt.callLater(_pinStart)
    onHeightChanged: Qt.callLater(_pinStart)

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
        // lattice extent of the cluster: how many levels it reaches above (lUp)
        // and below (lDn) its center
        readonly property int lUp: {
            var m = 0;
            for (var i = 0; i < pos.length; i++)
                m = Math.max(m, -(pos[i].c + pos[i].r));
            return m;
        }
        readonly property int lDn: {
            var m = 0;
            for (var i = 0; i < pos.length; i++)
                m = Math.max(m, pos[i].c + pos[i].r);
            return m;
        }
        readonly property bool hasSep: index < jungle.count - 1
        // separator level below this centre: first level past the cluster,
        // bumped to EVEN so the middle separator cell sits at x = 0
        readonly property int sepGap: ((lDn + 1) % 2 === 0) ? (lDn + 1) : (lDn + 2)
        // centre-to-centre advance to the next week. The separator sits at level
        // sepGap; the next cluster's TOP row must land one level past it (sepGap
        // + 1), so the next centre is lUp + sepGap + 1 levels down — no empty
        // level between the separator and the next jungle, no overlap. Kept even
        // so every cluster centre stays on an even lattice level (valid x = 0);
        // for the habit set here lUp is odd, so it already comes out even.
        readonly property int advance: {
            var a = lUp + sepGap + 1;
            return (a % 2 === 0) ? a : a + 1;
        }
        // the delegate height IS that advance (for the last week, just enough to
        // hold the cluster) — so stacked delegates continue one seamless lattice
        height: (hasSep ? advance : (lUp + 1 + lDn + 1)) * jungle.tileH / 2
        width: jungle.width
        readonly property real centerY: (lUp + 1) * jungle.tileH / 2
        // older (lower, nearer the viewer) weeks paint over newer ones' rows —
        // iso painter's order across delegates
        z: index

        // screen-space center of cell i's tile inside this delegate
        function cellCenter(i) {
            var p = pos[i];
            return {
                x: width / 2 + (p.c - p.r) * jungle.tileW / 2,
                y: centerY + (p.c + p.r) * jungle.tileH / 2
            };
        }
        function cellAt(mx, my) {
            // nearest tile center within a diamond-ish radius, with a little
            // upward allowance for the trunk above the tile
            var best = -1, bestD = 1e9;
            for (var i = 0; i < cells.length; i++) {
                var cc = cellCenter(i);
                var dx = Math.abs(mx - cc.x), dy = my - cc.y;
                var d = dx + Math.abs(dy) * 2;
                if (dx < jungle.tileW * 0.55 && dy < jungle.tileH && dy > -jungle.tileH * 1.5 && d < bestD) {
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
            // extends `overhang` px above the delegate so canopies can rise
            // into the previous week's rows; painting is translated to keep
            // item-local coordinates. Also + tileH below, because the separator
            // sits ON the delegate's bottom edge — its lower half crosses into
            // the next week and would otherwise be clipped.
            y: -jungle.overhang
            width: parent.width
            height: parent.height + jungle.overhang + (block.hasSep ? jungle.tileH : 0)
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
                ctx.translate(0, jungle.overhang);  // item-local coords from here on
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

                function tile(cx2, cy2, frozen) {
                    ctx.beginPath();
                    ctx.moveTo(cx2, cy2 - jungle.tileH / 2);
                    ctx.lineTo(cx2 + jungle.tileW / 2, cy2);
                    ctx.lineTo(cx2, cy2 + jungle.tileH / 2);
                    ctx.lineTo(cx2 - jungle.tileW / 2, cy2);
                    ctx.closePath();
                    ctx.fillStyle = frozen ? "#5a6068" : soil;
                    ctx.fill();
                    ctx.strokeStyle = frozen ? "#8b95a0" : soilHi;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                    if (frozen) {   // snow wash
                        ctx.globalAlpha = 0.55;
                        ctx.fillStyle = "#dfe6ec";
                        ctx.fill();
                        ctx.globalAlpha = 1;
                    }
                }
                function tuftAt(seed, tx, ty, frozen) {
                    var t = Tg.tuft(seed);
                    var sway = Math.sin(cv.wt * 2.1 + tx * 0.3) * 0.9;
                    ctx.strokeStyle = frozen ? "#c9d2da" : (warm ? "#6b5a35" : "#55663d");
                    ctx.lineWidth = 1;
                    for (var b = 0; b < t.blades.length; b++) {
                        ctx.beginPath();
                        ctx.moveTo(tx, ty);
                        ctx.lineTo(tx + t.blades[b].x2 + sway, ty + t.blades[b].y2);
                        ctx.stroke();
                    }
                }

                // ---- cluster tiles ----
                for (var oi = 0; oi < order.length; oi++) {
                    i = order[oi];
                    var cc = block.cellCenter(i);
                    tile(cc.x, cc.y, block.cells[i].week.band === "frozen");
                }

                // ---- separator row: 5 lattice cells on the level between this
                //      jungle and the older one, middle cell dead-center ----
                if (block.hasSep) {
                    var sy = block.centerY + block.sepGap * jungle.tileH / 2;
                    var rowSeed = block.cells.length ? block.cells[0].week.seed : 1;
                    for (var k = -2; k <= 2; k++) {
                        var sx = block.width / 2 + k * jungle.tileW;
                        tile(sx, sy, frozenWeek);
                        // a little random vegetation in the season's palette
                        var pr = Tg.rng32(rowSeed + (k + 2) * 211);
                        var tufts = 1 + Math.floor(pr() * 2);
                        for (var tn = 0; tn < tufts; tn++)
                            tuftAt(rowSeed * 17 + (k + 2) * 53 + tn * 7,
                                   sx + (pr() - 0.5) * (jungle.tileW - 18),
                                   sy + (pr() - 0.5) * (jungle.tileH - 10), frozenWeek);
                    }
                }

                // ---- floor vegetation (density = week total score share) ----
                var veg = wk.vegetation || 0;
                for (i = 0; i < block.cells.length; i++) {
                    var center = block.cellCenter(i);
                    var n = Math.round(veg * 7);
                    for (var v = 0; v < n; v++) {
                        var rr = Tg.rng32(block.cells[i].week.seed + v * 131);
                        tuftAt(block.cells[i].week.seed * 31 + v * 7 + 1,
                               center.x + (rr() - 0.5) * (jungle.tileW - 16),
                               center.y + (rr() - 0.5) * (jungle.tileH - 8), frozenWeek);
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
