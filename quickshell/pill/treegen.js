// treegen.js — deterministic procedural plants for the habit-tracker jungle.
//
// Twelve stylized SPECIES (oak, maple, willow, pine, spruce, birch, poplar,
// cypress, acacia, olive, shrub, fern), each a parametric recursive branching
// system: curved tapered limbs grown step-by-step with per-species lean /
// curl / spread, and a species canopy built from clustered soft blobs,
// stacked conifer tiers, tall columns, umbrella tops, drooping willow
// strands or arching fern fronds. A given seed always regrows the identical
// tree at each of the four growth stages (same species, same skeleton — the
// stage only deepens and lengthens it), so the jungle stays a pure function
// of habiq's report. Nothing is stored.
//
// build(seed, stage) returns renderer-agnostic geometry (y grows DOWN, the
// tree extends toward negative y, origin at the root):
//   { h, species, limbs: [{leafy, sway, pts: [{x,y,w}…]}],
//     puffs: [{kind: 0 ellipse | 1 triangle, x, y, rx, ry, tone: 0..2}] }
// render(ctx, geo, o) paints it — shared by JungleView and the habit cards —
// handling taper, multi-tone foliage, seasonal color, snow, dead trees and
// the breeze (o.windT/o.phase), so the look lives in exactly one place.
.pragma library

// Deterministic 32-bit PRNG (mulberry32) — the only randomness source.
function rng32(seed) {
    var a = seed >>> 0;
    return function () {
        a |= 0; a = (a + 0x6D2B79F5) | 0;
        var t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// ---- color helpers (renderer-side) ----------------------------------------
function hexRgb(hex) {
    var n = parseInt(hex.slice(1), 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}
// f > 0 lighten toward white, f < 0 darken toward black
function shade(rgb, f, a) {
    var t = f < 0 ? 0 : 255, p = Math.abs(f);
    var r = Math.round((t - rgb.r) * p + rgb.r);
    var g = Math.round((t - rgb.g) * p + rgb.g);
    var b = Math.round((t - rgb.b) * p + rgb.b);
    return "rgba(" + r + "," + g + "," + b + "," + (a === undefined ? 1 : a) + ")";
}

// leaf base color: score band + season (fall/winter warm, spring/summer green)
function leafBase(band, season) {
    if (band === "dead") return "#655a4b";
    if (band === "low") return "#8a6a45";
    if (band === "mid") return "#b59a63";
    var warm = season === "fall" || season === "winter";
    return warm ? "#d78f3c" : "#74b06a";
}

// ---- species table ---------------------------------------------------------
// trunk: base length/width + lean (radians) + curl (wander per step)
// limbs: recursion depth cap, children range, angular spread, upward pull
// canopy: kind + sizing; sway = extra wind multiplier for the foliage
var SPECIES = [
    { name: "oak", hMul: 1.0,     bark: "#5d4630", trunk: { len: 22, w: 4.4, lean: 0.05, curl: 0.35 },
      limbs: { depth: 3, kids: [2, 3], spread: 0.6, up: 0.3, fall: 0.72 },
      canopy: { kind: "blob", size: 7.2, count: 2, aspect: 0.95 }, sway: 1.0 },
    { name: "maple", hMul: 1.0,   bark: "#66503a", trunk: { len: 26, w: 3.6, lean: 0.03, curl: 0.22 },
      limbs: { depth: 3, kids: [2, 3], spread: 0.65, up: 0.4, fall: 0.7 },
      canopy: { kind: "blob", size: 8.0, count: 3, aspect: 0.9 }, sway: 1.0 },
    { name: "willow", hMul: 1.05,  bark: "#5a4a36", trunk: { len: 30, w: 3.8, lean: 0.16, curl: 0.3 },
      limbs: { depth: 2, kids: [2, 3], spread: 0.75, up: 0.3, fall: 0.75 },
      canopy: { kind: "strand", size: 24, count: 4 }, sway: 1.8 },
    { name: "pine", hMul: 1.0,    bark: "#4f3f2e", trunk: { len: 34, w: 3.2, lean: 0.0, curl: 0.05 },
      limbs: { depth: 0, kids: [0, 0], spread: 0, up: 0, fall: 1 },
      canopy: { kind: "tier", size: 13, count: 4 }, sway: 0.6 },
    { name: "spruce", hMul: 1.05,  bark: "#463828", trunk: { len: 38, w: 2.8, lean: 0.0, curl: 0.04 },
      limbs: { depth: 0, kids: [0, 0], spread: 0, up: 0, fall: 1 },
      canopy: { kind: "tier", size: 9, count: 6 }, sway: 0.6 },
    { name: "birch", hMul: 1.0,   bark: "#c9c2b4", trunk: { len: 32, w: 2.0, lean: 0.08, curl: 0.18 },
      limbs: { depth: 2, kids: [1, 2], spread: 0.5, up: 0.55, fall: 0.66 },
      canopy: { kind: "blob", size: 5.5, count: 2, aspect: 0.85 }, sway: 1.2 },
    { name: "poplar", hMul: 1.05,  bark: "#6a5741", trunk: { len: 30, w: 3.0, lean: 0.0, curl: 0.08 },
      limbs: { depth: 0, kids: [0, 0], spread: 0, up: 0, fall: 1 },
      canopy: { kind: "column", size: 8.5, count: 3 }, sway: 0.8 },
    { name: "cypress", hMul: 0.85, bark: "#4a3c2c", trunk: { len: 16, w: 2.6, lean: 0.02, curl: 0.05 },
      limbs: { depth: 0, kids: [0, 0], spread: 0, up: 0, fall: 1 },
      canopy: { kind: "column", size: 7.0, count: 4 }, sway: 0.7 },
    { name: "acacia", hMul: 1.0,  bark: "#5d4630", trunk: { len: 26, w: 3.4, lean: 0.1, curl: 0.28 },
      limbs: { depth: 2, kids: [2, 3], spread: 0.9, up: 0.45, fall: 0.75 },
      canopy: { kind: "umbrella", size: 11, count: 3 }, sway: 0.9 },
    { name: "olive", hMul: 0.75,   bark: "#6e6152", trunk: { len: 18, w: 3.2, lean: 0.12, curl: 0.5 },
      limbs: { depth: 3, kids: [2, 2], spread: 0.95, up: 0.3, fall: 0.68 },
      canopy: { kind: "blob", size: 5.0, count: 4, aspect: 0.8, light: 0.12 }, sway: 1.1 },
    { name: "shrub", hMul: 0.5,   bark: "#5a4a36", trunk: { len: 7, w: 1.8, lean: 0.0, curl: 0.2, stems: 3 },
      limbs: { depth: 1, kids: [1, 2], spread: 0.8, up: 0.35, fall: 0.7 },
      canopy: { kind: "blob", size: 6.0, count: 1, aspect: 0.8 }, sway: 1.2 },
    { name: "fern", hMul: 0.45,    bark: "#55663d", trunk: { len: 0, w: 0, lean: 0, curl: 0 },
      limbs: { depth: 0, kids: [0, 0], spread: 0, up: 0, fall: 1 },
      canopy: { kind: "fern", size: 18, count: 7 }, sway: 1.6 }
];

var LIMB_CAP = 46;
var PUFF_CAP = 34;

// Deterministic per-jungle species draft: every cell draws a seed-shuffled
// preference order over all species; a species already granted in the same
// week sinks a full lap down the order (cost = timesUsed × N + rank), so two
// trees of the same kind can't share a jungle until every species is already
// on the field. Pure function of the seed list — same report, same forest.
function assignSpecies(seeds) {
    var used = {};
    var out = [];
    for (var i = 0; i < seeds.length; i++) {
        var rng = rng32(seeds[i]);
        var pref = [];
        for (var sp = 0; sp < SPECIES.length; sp++) pref.push(sp);
        for (var j = pref.length - 1; j > 0; j--) {   // Fisher–Yates by seed
            var k = Math.floor(rng() * (j + 1));
            var tmp = pref[j]; pref[j] = pref[k]; pref[k] = tmp;
        }
        var pick = pref[0], best = 1e9;
        for (var r = 0; r < pref.length; r++) {
            var cost = (used[pref[r]] || 0) * SPECIES.length + r;
            if (cost < best) { best = cost; pick = pref[r]; }
        }
        used[pick] = (used[pick] || 0) + 1;
        out.push(pick);
    }
    return out;
}

// grow one curved tapered limb; returns its tip {x, y, a, w}
function limb(g, rng, x, y, a, len, w0, w1, leafy, sway, curl, upPull) {
    var steps = 3;
    var pts = [{ x: x, y: y, w: w0 }];
    var aa = a;
    for (var i = 1; i <= steps; i++) {
        aa += (rng() - 0.5) * curl * 2 + (upPull || 0);
        x += Math.cos(aa) * (len / steps);
        y += Math.sin(aa) * (len / steps);
        pts.push({ x: x, y: y, w: w0 + (w1 - w0) * (i / steps) });
        if (y < g.minY) g.minY = y;
    }
    if (g.limbs.length < LIMB_CAP)
        g.limbs.push({ leafy: !!leafy, sway: sway || 1, pts: pts });
    return { x: x, y: y, a: aa, w: w1 };
}

function puff(g, kind, x, y, rx, ry, tone) {
    if (g.puffs.length >= PUFF_CAP) return;
    g.puffs.push({ kind: kind, x: x, y: y, rx: rx, ry: ry, tone: tone });
    if (y - ry < g.minY) g.minY = y - ry;
}

// cluster of soft blobs around a point: shadow base, mids riding on it, one
// small light cap — kept tight so a canopy reads as one mass, not bubbles
function blobCluster(g, rng, x, y, size, aspect) {
    puff(g, 0, x, y, size * (0.95 + rng() * 0.25), size * aspect * (0.9 + rng() * 0.2), 0);
    var n = 2 + Math.floor(rng() * 2);
    for (var i = 0; i < n; i++)
        puff(g, 0, x + (rng() - 0.5) * size * 1.1, y - size * aspect * (0.15 + rng() * 0.35),
             size * (0.5 + rng() * 0.3), size * aspect * (0.5 + rng() * 0.25), 1);
    puff(g, 0, x + (rng() - 0.5) * size * 0.5, y - size * aspect * (0.5 + rng() * 0.2),
         size * (0.26 + rng() * 0.12), size * aspect * (0.24 + rng() * 0.1), 2);
}

// recursive wood: branches off along/at the end of the parent
function grow(g, rng, spec, tip, depth, len, stage) {
    if (depth > Math.min(spec.limbs.depth, stage - 1)) {
        g.tips.push(tip);
        return;
    }
    var kids = spec.limbs.kids[0] +
               Math.floor(rng() * (spec.limbs.kids[1] - spec.limbs.kids[0] + 1));
    if (kids < 1) { g.tips.push(tip); return; }
    for (var i = 0; i < kids; i++) {
        var side = (i % 2 === 0 ? 1 : -1) * (0.35 + rng() * spec.limbs.spread);
        var a = tip.a + side;
        a += (-Math.PI / 2 - a) * spec.limbs.up;  // pull toward "up"
        var t = limb(g, rng, tip.x, tip.y, a, len * (0.8 + rng() * 0.4),
                     tip.w, Math.max(0.7, tip.w * 0.55), false, 1,
                     spec.trunk.curl, 0);
        grow(g, rng, spec, t, depth + 1, len * spec.limbs.fall, stage);
    }
}

// build(seed, stage 1..4[, species]): the full plant. `species` (from
// assignSpecies) overrides the seed's own draw; the draw is still consumed so
// an overridden tree is identical to one whose seed picked that species.
function build(seed, stage, species) {
    var rng = rng32(seed);
    var si = Math.floor(rng() * SPECIES.length);
    if (species !== undefined) si = species;
    var spec = SPECIES[si];
    var st = Math.max(1, Math.min(4, stage));
    var g = { limbs: [], puffs: [], tips: [], minY: -6,
              species: si, name: spec.name, bark: spec.bark, sway: spec.sway };
    var scale = [0.4, 0.62, 0.82, 1.0][st - 1];   // the same tree, younger

    if (spec.canopy.kind === "fern" || st === 1) {
        // seedling / fern: arching leafy fronds from the ground (species-tinted:
        // conifer seedlings get a tiny tier, others a sprout with baby blobs)
        if (st === 1 && spec.canopy.kind !== "fern") {
            var t0 = limb(g, rng, 0, 0, -Math.PI / 2 + (rng() - 0.5) * 0.2,
                          9, 1.6, 0.9, false, 1, 0.25, 0);
            if (spec.canopy.kind === "tier")
                puff(g, 1, t0.x, t0.y - 2, 5, 8, 1);
            else {
                puff(g, 0, t0.x, t0.y - 1, 4.2, 3.4, 0);
                puff(g, 0, t0.x + (rng() - 0.5) * 4, t0.y - 3.5, 2.6, 2.2, 2);
            }
        } else {
            var fronds = Math.round(spec.canopy.count * (0.5 + st * 0.16));
            for (var f = 0; f < fronds; f++) {
                var fa = -Math.PI / 2 + (f / (fronds - 1) - 0.5) * 1.9 + (rng() - 0.5) * 0.2;
                limb(g, rng, 0, 0, fa, spec.canopy.size * scale * (0.7 + rng() * 0.5),
                     1.6, 0.4, true, spec.sway, 0.22, 0.1 * Math.sign(fa + Math.PI / 2));
            }
        }
        g.h = Math.max(8, -g.minY) / (spec.hMul || 1);
        return g;
    }

    // ---- wood ----
    var stems = spec.trunk.stems || 1;
    for (var s = 0; s < stems; s++) {
        var sx = stems > 1 ? (s - (stems - 1) / 2) * 4 : 0;
        var lean = spec.trunk.lean * (rng() < 0.5 ? -1 : 1) * (0.6 + rng() * 0.8);
        var t = limb(g, rng, sx, 0, -Math.PI / 2 + lean,
                     spec.trunk.len * scale, spec.trunk.w * (0.5 + 0.5 * scale),
                     spec.trunk.w * 0.55, false, 1, spec.trunk.curl, 0);
        grow(g, rng, spec, t, 1, spec.trunk.len * 0.55 * scale, st);
    }

    // ---- canopy ----
    var c = spec.canopy;
    var i, tp;
    if (c.kind === "blob") {
        var nc = Math.min(g.tips.length, 4);   // more tips than this just merges to mush
        // pull clusters toward the canopy centroid so the crown reads as one
        // rounded mass with lobes, not a row of separate balls
        var mx = 0, my = 0;
        for (i = 0; i < g.tips.length; i++) { mx += g.tips[i].x; my += g.tips[i].y; }
        if (g.tips.length) { mx /= g.tips.length; my /= g.tips.length; }
        var csize = c.size * scale * (1.15 / Math.sqrt(Math.max(1, nc)));
        for (i = 0; i < nc; i++) {
            var bx = g.tips[i].x + (mx - g.tips[i].x) * 0.5;
            var by = g.tips[i].y + (my - g.tips[i].y) * 0.65;   // gather vertically harder
            blobCluster(g, rng, bx, by, csize * (0.85 + rng() * 0.3), c.aspect);
        }
        if (nc >= 2)   // dome the crown: one more mass riding on top of the centroid
            blobCluster(g, rng, mx, my - csize * c.aspect * 0.6, csize * 0.8, c.aspect);
    } else if (c.kind === "tier") {
        // stacked conifer triangles down from the top
        var top = g.tips.length ? g.tips[0] : { x: 0, y: -spec.trunk.len * scale };
        var n = Math.max(2, Math.round(c.count * scale));
        var span = -top.y * 0.78;
        for (i = 0; i < n; i++) {
            var ty = top.y + (i / n) * span;
            var tw = c.size * scale * (0.35 + 0.75 * (i + 1) / n);
            puff(g, 1, top.x * (1 - i / n / 2), ty, tw, span / n * 1.5, i === 0 ? 2 : (i % 2 ? 1 : 0));
        }
    } else if (c.kind === "column") {
        var base = g.tips.length ? g.tips[0] : { x: 0, y: -spec.trunk.len * scale };
        var n2 = Math.max(2, Math.round(c.count * scale));
        var colH = c.size * scale * 1.5;
        for (i = 0; i < n2; i++) {
            var frac = i / (n2 - 1 || 1);
            puff(g, 0, base.x + (rng() - 0.5) * 2, base.y - i * colH * 0.8,
                 c.size * scale * (1 - frac * 0.45), colH, i % 2 ? 1 : 0);
        }
        puff(g, 0, base.x, base.y - n2 * colH * 0.8, c.size * scale * 0.4, colH * 0.7, 2);
    } else if (c.kind === "umbrella") {
        // acacia: a small flat pad riding each tip, one wider wash over the
        // centroid — layered savanna canopy instead of a single table top
        var cx = 0, cy = 0;
        for (i = 0; i < g.tips.length; i++) { cx += g.tips[i].x; cy += g.tips[i].y; }
        if (g.tips.length) { cx /= g.tips.length; cy /= g.tips.length; }
        puff(g, 0, cx, cy - c.size * scale * 0.12, c.size * scale * 0.95, c.size * scale * 0.26, 0);
        for (i = 0; i < g.tips.length; i++) {
            tp = g.tips[i];
            puff(g, 0, tp.x, tp.y - 1.5, c.size * scale * (0.4 + rng() * 0.25),
                 c.size * scale * 0.17, i % 2 ? 1 : 2);
        }
    } else if (c.kind === "strand") {
        // willow: a small cap on each tip, then thick drooping leafy curtains —
        // the strands ARE the canopy, so they get real width and length
        for (i = 0; i < g.tips.length; i++) {
            tp = g.tips[i];
            puff(g, 0, tp.x, tp.y - 1, 4 * scale, 3 * scale, 1);
            var ns = c.count + Math.floor(rng() * 2);
            for (var k = 0; k < ns; k++) {
                // fan out from the tip, then arc over into the hang — longer
                // with age so a grown willow's curtains reach well down
                var sa = -1.5 + (k / Math.max(1, ns - 1)) * 3.0;
                limb(g, rng, tp.x, tp.y, sa,
                     c.size * scale * (0.6 + rng() * 0.4) * (0.6 + st * 0.12),
                     2.0, 0.6, true, spec.sway, 0.1, 0.42);
            }
        }
    }
    // hMul is the species height class: dividing it into h shrinks the render
    // scale, so shrubs and ferns stay modest ground plants instead of being
    // normalized up to full tree height
    g.h = Math.max(8, -g.minY) / (spec.hMul || 1);
    return g;
}

// ---- shared renderer -------------------------------------------------------
// o: { x, y (root on the tile), scale, windT, phase, targetH,
//      leaf (hex from leafBase), dead, snowFrac }
function render(ctx, geo, o) {
    var leaf = hexRgb(o.leaf);
    var bark = hexRgb(o.dead ? "#4a4038" : geo.bark);
    var snow = hexRgb("#e6ebf0");
    var sc = o.scale;

    function wind(px, py, mul) {
        return Math.sin(o.windT * 1.4 + o.phase + (-py) * 0.05 * sc)
               * 1.6 * mul * (-py * sc / o.targetH);
    }

    // wood + leafy strands (tapered polylines, per-segment width, round caps)
    ctx.lineCap = "round";
    for (var l = 0; l < geo.limbs.length; l++) {
        var lb = geo.limbs[l];
        var mul = lb.leafy ? geo.sway : 1;
        if (lb.leafy && o.dead && (l % 3 !== 0)) continue;  // dead: sparse strands
        for (var i = 1; i < lb.pts.length; i++) {
            var p0 = lb.pts[i - 1], p1 = lb.pts[i];
            var snowy = o.snowFrac > 0 && lb.leafy && (i + l) % 5 < o.snowFrac * 5;
            ctx.strokeStyle = lb.leafy
                ? (o.dead ? shade(bark, 0.1, 0.8)
                   : snowy ? shade(snow, 0, 0.9) : shade(leaf, i === 1 ? -0.18 : 0.06, 0.9))
                : shade(bark, i === 1 ? 0 : 0.12);
            ctx.lineWidth = Math.max(0.7, (p0.w + p1.w) / 2 * sc * (o.dead ? 1.2 : 1));
            ctx.beginPath();
            ctx.moveTo(o.x + p0.x * sc + wind(p0.x, p0.y, mul), o.y + p0.y * sc);
            ctx.lineTo(o.x + p1.x * sc + wind(p1.x, p1.y, mul), o.y + p1.y * sc);
            ctx.stroke();
        }
    }

    // foliage puffs: 0 = shadow tone, 1 = mid, 2 = light; snow whitens a share
    if (!o.dead) {
        var tones = [shade(leaf, -0.18, 0.92), shade(leaf, 0.02, 0.9), shade(leaf, 0.14, 0.85)];
        var snowTones = [shade(snow, -0.12, 0.94), shade(snow, 0, 0.94), shade(snow, 0.1, 0.95)];
        for (var p = 0; p < geo.puffs.length; p++) {
            var pf = geo.puffs[p];
            var wx = wind(pf.x, pf.y, geo.sway);
            var px = o.x + pf.x * sc + wx;
            var py = o.y + pf.y * sc;
            var isSnow = o.snowFrac > 0 && (p % 7) < o.snowFrac * 7;
            ctx.fillStyle = (isSnow ? snowTones : tones)[pf.tone];
            if (pf.kind === 1) {          // conifer tier
                ctx.beginPath();
                ctx.moveTo(px, py - pf.ry * sc);
                ctx.lineTo(px + pf.rx * sc, py + pf.ry * sc * 0.45);
                ctx.lineTo(px - pf.rx * sc, py + pf.ry * sc * 0.45);
                ctx.closePath();
                ctx.fill();
            } else {                      // soft ellipse blob
                ctx.save();
                ctx.translate(px, py);
                ctx.scale(Math.max(0.8, pf.rx * sc), Math.max(0.8, pf.ry * sc));
                ctx.beginPath();
                ctx.arc(0, 0, 1, 0, Math.PI * 2);
                ctx.restore();
                ctx.fill();
            }
        }
    } else {
        // a dead tree keeps a few dark leaf scraps clinging on
        for (var q = 0; q < geo.puffs.length; q += 4) {
            var pd = geo.puffs[q];
            ctx.fillStyle = "rgba(90,81,72,0.7)";
            ctx.save();
            ctx.translate(o.x + pd.x * sc, o.y + pd.y * sc);
            ctx.scale(Math.max(0.8, pd.rx * sc * 0.3), Math.max(0.8, pd.ry * sc * 0.3));
            ctx.beginPath();
            ctx.arc(0, 0, 1, 0, Math.PI * 2);
            ctx.restore();
            ctx.fill();
        }
    }
}

// ---- ground vegetation -----------------------------------------------------
// A tuft: 2–5 curved blades (quadratic arcs), occasionally a tiny flower.
function tuft(seed) {
    var rng = rng32(seed);
    var blades = [];
    var n = 2 + Math.floor(rng() * 4);
    for (var i = 0; i < n; i++) {
        var a = -Math.PI / 2 + (rng() - 0.5) * 1.3;
        var len = 3 + rng() * 4.5;
        var tx = Math.cos(a) * len, ty = Math.sin(a) * len;
        blades.push({
            // control point bows the blade sideways for a grass-like arc
            cx: tx * 0.4 + (rng() - 0.5) * 2.2, cy: ty * 0.55,
            x2: tx + (rng() - 0.5) * 1.5, y2: ty,
            tone: rng() < 0.4 ? 1 : 0
        });
    }
    return { blades: blades, flower: rng() < 0.18, fx: (rng() - 0.5) * 4, fr: 0.9 + rng() * 0.7 };
}

// draw a tuft at (x,y): curved swaying blades in two greens + optional flower
function renderTuft(ctx, t, x, y, windT, base, frozen) {
    var rgb = hexRgb(frozen ? "#c9d2da" : base);
    var sway = Math.sin(windT * 2.1 + x * 0.3) * 1.1;
    ctx.lineCap = "round";
    ctx.lineWidth = 1;
    for (var b = 0; b < t.blades.length; b++) {
        var bl = t.blades[b];
        ctx.strokeStyle = shade(rgb, bl.tone === 1 ? 0.18 : -0.05, 0.9);
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.quadraticCurveTo(x + bl.cx + sway * 0.5, y + bl.cy, x + bl.x2 + sway, y + bl.y2);
        ctx.stroke();
    }
    if (t.flower && !frozen) {
        ctx.fillStyle = "rgba(217,164,65,0.85)";   // little gold bloom
        ctx.beginPath();
        ctx.arc(x + t.fx + sway, y - 4.5, t.fr, 0, Math.PI * 2);
        ctx.fill();
    } else if (t.flower) {
        ctx.fillStyle = "rgba(230,235,240,0.9)";   // snow berry
        ctx.beginPath();
        ctx.arc(x + t.fx, y - 4, t.fr * 0.8, 0, Math.PI * 2);
        ctx.fill();
    }
}
