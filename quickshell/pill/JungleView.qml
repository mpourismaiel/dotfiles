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
// Every tile is a chunk of earth torn from the ground, not a flat diamond: a
// grassy surface diamond riding an organic underside clump (a seeded lumpy
// mound bulging out and down below the front edges, deepest under the centre,
// studded with crumbling clods, pebbles and roots), with grass speckle and a
// fringe spilling over the front faces — so each cluster reads as a chunky
// floating island, neighbours cover each other's clumps and dirt only shows on
// the rim. Trees overhang upward past their delegate (each Canvas extends
// `overhang` px above and paints translated, plus `underhang` below for the
// bottom tiles' clump + roots); `z: index` stacks older (lower) weeks above,
// the classic painter's order — a lower jungle's canopy rises over the row
// above it. Every tile stays lush: baseline floor tufts scale with the week's
// mood band (happier plants get denser turf, rocks and more flowers) plus a
// small total-score bonus; separator tiles carry a little season-palette
// vegetation and everything is snow-washed when the week is frozen. The garden's head (newest week) rests
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
    readonly property int tileDepth: 12  // dirt-block extrusion below each tile's surface
    readonly property int overhang: 84   // canopy allowance painted above each delegate
    // room painted BELOW each delegate: the bottom tiles' lower diamond half
    // (tileH/2) + the dirt block (tileDepth) + dangling roots
    readonly property int underhang: 50
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

        // per-jungle species draft: no two trees of the same kind share a week
        // (until every species is on the field) — deterministic from the seeds
        readonly property var speciesMap: {
            var seeds = [];
            for (var i = 0; i < cells.length; i++) seeds.push(cells[i].week.seed);
            return Tg.assignSpecies(seeds);
        }
        // per-row tree geometry, cached per (seed, stage, species) — regrown
        // only when the report changes, not on every breeze repaint
        property var _trees: ({})
        function treeFor(i) {
            var cell = cells[i];
            var k = cell.week.seed + ":" + cell.week.stage + ":" + speciesMap[i];
            if (!_trees[k]) _trees[k] = Tg.build(cell.week.seed, cell.week.stage, speciesMap[i]);
            return _trees[k];
        }

        Canvas {
            id: cv
            // extends `overhang` px above the delegate so canopies can rise
            // into the previous week's rows; painting is translated to keep
            // item-local coordinates. Also `underhang` below: the separator
            // sits ON the delegate's bottom edge, and every bottom tile's
            // dirt block + roots reach past it — both would otherwise clip.
            y: -jungle.overhang
            width: parent.width
            height: parent.height + jungle.overhang + jungle.underhang
            renderStrategy: Canvas.Cooperative
            property real wt: jungle.windT
            onWtChanged: requestPaint()
            Component.onCompleted: requestPaint()

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
                // grassy-green turf on top; fall/winter lean a touch olive/gold
                var soil = warm ? "#6f7d3c" : "#4e7f42";
                var soilHi = warm ? "#8a9a4c" : "#63a054";
                var tuftBase = warm ? "#7c7b3c" : "#4f7a3a";

                // each tile is a chunk of earth torn from the ground: the grassy
                // surface diamond rides an organic underside clump — a lumpy
                // mound bulging out and down below the diamond's two front edges,
                // deepest under the centre, studded with crumbling clods, pebbles
                // and roots poking out — then the turf gets grass speckle and a
                // fringe spilling over the front faces. All deterministic from
                // the tile's seed. Neighbours drawn back-to-front cover each
                // other's clumps, so dirt only shows on a cluster's outer rim.
                function tile(cx2, cy2, frozen, seed) {
                    var tw = jungle.tileW / 2, th = jungle.tileH / 2, td = jungle.tileDepth;
                    var pr = Tg.rng32(((seed || 1) ^ 0x9e3779b9) >>> 0);
                    var soilRgb = Tg.hexRgb(soil);
                    var dirtL = frozen ? "#3a4049" : (warm ? "#211910" : "#1d2012");
                    var dirtR = frozen ? "#454c55" : (warm ? "#2a1f15" : "#242717");
                    var rootC = frozen ? "#5c646e" : (warm ? "#4d3a24" : "#43402a");

                    // ---- organic earth clump under the tile ----
                    var lx = cx2 - tw;
                    var rx0 = cx2 + tw;
                    var bvy = cy2 + th;                    // bottom vertex y (seam low point)
                    var mound = td + 8 + pr() * 9;         // how far the clump hangs below the vertex
                    var belly = tw * (0.74 + pr() * 0.14); // clump half-width at its widest
                    var cornDrop = 3 + pr() * 5;           // slight hang past the side corners
                    var dcx = cx2 + (pr() - 0.5) * 5;      // centre of the deepest point (wobbled)
                    var dby = bvy + mound;                 // deepest y

                    // Bulging underside for one half: from the seam corner it
                    // drops with a rounded shoulder, bows out to a wide waist,
                    // then curls back into the deepest centre point.
                    function underside(side, sx, sy) {
                        var wx = cx2 + side * belly * (0.62 + pr() * 0.1);  // waist (widest bulge)
                        var wy = dby - mound * (0.12 + pr() * 0.1);
                        ctx.quadraticCurveTo(cx2 + side * belly * 1.02, sy + mound * 0.5, wx, wy);
                        ctx.quadraticCurveTo(cx2 + side * belly * 0.26, dby + 2 + pr() * 4, dcx, dby);
                    }

                    // right (lit) half: seam B→R, bulging underside R→D, inner drop D→B
                    ctx.beginPath();
                    ctx.moveTo(cx2, bvy);
                    ctx.lineTo(rx0, cy2);
                    underside(1, rx0, cy2);
                    ctx.lineTo(cx2, bvy);
                    ctx.closePath();
                    ctx.fillStyle = dirtR;
                    ctx.fill();
                    // left (shadowed) half, mirrored
                    ctx.beginPath();
                    ctx.moveTo(cx2, bvy);
                    ctx.lineTo(lx, cy2);
                    underside(-1, lx, cy2);
                    ctx.lineTo(cx2, bvy);
                    ctx.closePath();
                    ctx.fillStyle = dirtL;
                    ctx.fill();

                    // parabola following the belly: y at horizontal fraction u (0 = centre)
                    function bellyY(u) { return dby - (dby - (cy2 + cornDrop)) * (u * u); }

                    // faint strata seams curving with the earth
                    ctx.strokeStyle = "rgba(0,0,0,0.16)";
                    ctx.lineWidth = 1;
                    ctx.lineCap = "round";
                    for (var s = 0; s < 2; s++) {
                        var ss = pr() < 0.5 ? -1 : 1;
                        var u0 = 0.25 + pr() * 0.45;
                        var ex0 = cx2 + ss * belly * u0;
                        var ey0 = cy2 + (bvy - cy2) * u0 + 2 + pr() * 4;
                        ctx.beginPath();
                        ctx.moveTo(ex0 - ss * belly * 0.26, ey0);
                        ctx.quadraticCurveTo(ex0, ey0 + 2, ex0 + ss * belly * 0.26, ey0);
                        ctx.stroke();
                    }
                    // pebbles / dry crumbs studding the earth
                    ctx.fillStyle = frozen ? Tg.shade(Tg.hexRgb("#c8d2dc"), 0, 0.3)
                                           : Tg.shade(Tg.hexRgb("#a3845c"), 0, 0.28);
                    for (var pn = 0; pn < 3; pn++) {
                        var ps = pr() < 0.5 ? -1 : 1;
                        var pt = 0.2 + pr() * 0.65;
                        ctx.beginPath();
                        ctx.arc(cx2 + ps * belly * pt * 0.85, cy2 + 4 + pr() * (mound * 0.75),
                                0.9 + pr() * 0.9, 0, Math.PI * 2);
                        ctx.fill();
                    }
                    // crumbling clods hanging just under the belly
                    var nClods = 1 + Math.floor(pr() * 2);
                    for (var cn = 0; cn < nClods; cn++) {
                        var cs = (pr() - 0.5) * belly * 1.3;
                        ctx.fillStyle = cs < 0 ? dirtL : dirtR;
                        ctx.beginPath();
                        ctx.arc(dcx + cs, dby - 2 + pr() * 4, 2.0 + pr() * 2.4, 0, Math.PI * 2);
                        ctx.fill();
                    }
                    // roots poking out of the underside and hanging down, thick arc + tail
                    ctx.strokeStyle = rootC;
                    ctx.lineCap = "round";
                    var nr = 3 + Math.floor(pr() * 3);
                    for (var rn = 0; rn < nr; rn++) {
                        var u = (pr() - 0.5) * 1.7;   // -0.85..0.85 across the belly
                        var rx = dcx + u * belly;
                        var ry = bellyY(u) - 1;
                        var len = 8 + pr() * 14;
                        var drift = (pr() - 0.5) * 9;
                        ctx.lineWidth = 1.4 + pr() * 0.8;
                        ctx.beginPath();
                        ctx.moveTo(rx, ry);
                        ctx.quadraticCurveTo(rx + drift * 0.3, ry + len * 0.55, rx + drift, ry + len);
                        ctx.stroke();
                        ctx.lineWidth = 0.7;
                        ctx.beginPath();
                        ctx.moveTo(rx + drift, ry + len);
                        ctx.quadraticCurveTo(rx + drift + (pr() - 0.5) * 5, ry + len + 4,
                                             rx + drift + (pr() - 0.5) * 7, ry + len + 6 + pr() * 5);
                        ctx.stroke();
                    }
                    ctx.lineCap = "butt";
                    ctx.lineWidth = 1;

                    // surface diamond on top — grassy green
                    ctx.beginPath();
                    ctx.moveTo(cx2, cy2 - th);
                    ctx.lineTo(cx2 + tw, cy2);
                    ctx.lineTo(cx2, cy2 + th);
                    ctx.lineTo(cx2 - tw, cy2);
                    ctx.closePath();
                    ctx.fillStyle = frozen ? "#5a6068" : soil;
                    ctx.fill();
                    ctx.strokeStyle = frozen ? "#8b95a0" : soilHi;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                    if (frozen) {   // snow wash
                        ctx.fillStyle = Tg.shade(Tg.hexRgb("#dfe6ec"), 0, 0.55);
                        ctx.fill();
                        return;
                    }
                    // grass speckle: scattered lighter/darker flecks so the turf isn't flat
                    for (var sp = 0; sp < 5; sp++) {
                        var a = pr(), b = pr();
                        var gx = cx2 + (a - b) * tw * 0.82;
                        var gy = cy2 + (a + b - 1) * th * 0.82;
                        ctx.fillStyle = Tg.shade(soilRgb, pr() < 0.5 ? 0.16 : -0.12, 0.7);
                        ctx.beginPath();
                        ctx.arc(gx, gy, 0.8 + pr() * 0.7, 0, Math.PI * 2);
                        ctx.fill();
                    }
                    // grass fringe overhanging the two front faces (turf spilling over dirt)
                    ctx.lineCap = "round";
                    ctx.lineWidth = 1;
                    for (var si = 0; si < 2; si++) {
                        var fside = si === 0 ? -1 : 1;
                        var nb = 5 + Math.floor(pr() * 3);
                        for (var bn = 0; bn < nb; bn++) {
                            var ft0 = 0.08 + pr() * 0.84;   // along the front edge, corner→bottom vertex
                            var fex = cx2 + fside * tw * (1 - ft0);
                            var fey = cy2 + th * ft0;
                            var flen = 2.5 + pr() * 3.0;
                            var fdrift = fside * (0.4 + pr() * 1.2);
                            ctx.strokeStyle = Tg.shade(soilRgb, pr() < 0.4 ? 0.14 : -0.08, 0.92);
                            ctx.beginPath();
                            ctx.moveTo(fex, fey);
                            ctx.quadraticCurveTo(fex + fdrift * 0.5, fey + flen * 0.6, fex + fdrift, fey + flen);
                            ctx.stroke();
                        }
                    }
                    ctx.lineCap = "butt";
                }
                function tuftAt(seed, tx, ty, frozen) {
                    Tg.renderTuft(ctx, Tg.tuft(seed), tx, ty, cv.wt, tuftBase, frozen);
                }

                // ---- cluster tiles ----
                for (var oi = 0; oi < order.length; oi++) {
                    i = order[oi];
                    var cc = block.cellCenter(i);
                    tile(cc.x, cc.y, block.cells[i].week.band === "frozen",
                         block.cells[i].week.seed);
                }

                // ---- separator row: 5 lattice cells on the level between this
                //      jungle and the older one, middle cell dead-center ----
                if (block.hasSep) {
                    var sy = block.centerY + block.sepGap * jungle.tileH / 2;
                    var rowSeed = block.cells.length ? block.cells[0].week.seed : 1;
                    for (var k = -2; k <= 2; k++) {
                        var sx = block.width / 2 + k * jungle.tileW;
                        tile(sx, sy, frozenWeek, rowSeed + (k + 2) * 211);
                        // a little random vegetation in the season's palette
                        var pr = Tg.rng32(rowSeed + (k + 2) * 211);
                        var tufts = 1 + Math.floor(pr() * 2);
                        for (var tn = 0; tn < tufts; tn++)
                            tuftAt(rowSeed * 17 + (k + 2) * 53 + tn * 7,
                                   sx + (pr() - 0.5) * (jungle.tileW - 18),
                                   sy + (pr() - 0.5) * (jungle.tileH - 10), frozenWeek);
                    }
                }

                // ---- floor vegetation: every tile stays lush (even empty/dead
                //      plants keep a grassy base), and the happier the plant the
                //      denser it gets; rocks and flowers are scattered on top ----
                var veg = wk.vegetation || 0;
                var vtw = jungle.tileW / 2, vth = jungle.tileH / 2;
                // sample a point uniformly inside a tile's surface diamond (inset)
                function spot(vr, center, inset) {
                    var a = vr(), b = vr();
                    return { x: center.x + (a - b) * vtw * inset,
                             y: center.y + (a + b - 1) * vth * inset };
                }
                for (i = 0; i < block.cells.length; i++) {
                    var center = block.cellCenter(i);
                    var band = block.cells[i].week.band;
                    var seed = block.cells[i].week.seed;
                    // baseline tufts by mood + a small shared score bonus
                    var base = band === "frozen" ? 3 : band === "dead" ? 4
                             : band === "low" ? 5 : band === "mid" ? 6 : 8; // "high" — lushest
                    var n = base + Math.round(veg * 3);
                    var vr = Tg.rng32((seed ^ 0x51ed270b) >>> 0);
                    for (var v = 0; v < n; v++) {
                        var sp = spot(vr, center, 0.86);
                        tuftAt(seed * 31 + v * 7 + 1, sp.x, sp.y, frozenWeek);
                    }
                    // a couple of small rocks per tile
                    var rocks = 1 + Math.floor(vr() * 2);
                    for (var rn = 0; rn < rocks; rn++) {
                        var rsp = spot(vr, center, 0.7);
                        Tg.renderRock(ctx, seed * 53 + rn * 17 + 3, rsp.x, rsp.y, frozenWeek);
                    }
                    // flowers — a scatter that blooms more for happier plants
                    var flowers = band === "frozen" ? 0 : band === "dead" ? 1
                                : band === "low" ? 1 : band === "mid" ? 2 : 3; // "high"
                    for (var fn = 0; fn < flowers; fn++) {
                        var fsp = spot(vr, center, 0.78);
                        Tg.renderFlower(ctx, seed * 71 + fn * 29 + 5, fsp.x, fsp.y,
                                        cv.wt, warm, band === "frozen");
                    }
                }

                // ---- trees (species render shared with the habit cards) ----
                for (oi = 0; oi < order.length; oi++) {
                    i = order[oi];
                    var cell = block.cells[i];
                    var cw = cell.week;
                    var geo = block.treeFor(i);
                    var c2 = block.cellCenter(i);
                    // scale to a stage-appropriate height inside the canopy room
                    var targetH = 16 + (cw.stage - 1) * 16 + cw.sizeRatio * 10;
                    Tg.render(ctx, geo, {
                        x: c2.x, y: c2.y,
                        scale: targetH / geo.h, targetH: targetH,
                        windT: cv.wt, phase: (cw.seed % 628) / 100,
                        leaf: Tg.leafBase(cw.band, wk.season),
                        dead: cw.band === "dead",
                        snowFrac: cw.band === "frozen" ? 1 : Math.min(1, (cw.frozenDays || 0) / 7)
                    });
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
