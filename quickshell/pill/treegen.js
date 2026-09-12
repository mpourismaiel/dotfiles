// treegen.js — deterministic procedural plants for the habit-tracker jungle.
//
// Real L-systems (Lindenmayer systems): each "family" is an axiom + rewrite
// rules + branching angle; a family is a consistent organism whose four growth
// stages (small plant → small tree → medium tree → large tree) are the same
// rule set at increasing iteration depth. 24 families = 12 rule sets × 2
// foliage builds, further varied per-seed by deterministic jitter. Nothing is
// stored: build(seed, stage) always regrows the identical tree for the same
// (seed, stage), so the jungle is a pure function of habiq's report.
//
// Geometry is returned in tree-local coordinates: origin at the root, +y DOWN
// (screen space), the tree grows toward negative y. The renderer scales to its
// cell and applies wind/color/snow — no styling decisions live here.
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

// ---- the 12 L-system rule sets -------------------------------------------
// angle in degrees; iters = expansion depth per growth stage (1..4); step =
// base segment length per stage (keeps young plants readable, not microscopic).
var RULESETS = [
    { axiom: "X", rules: { X: "F[+X]F[-X]+X", F: "FF" }, angle: 20,   iters: [1, 2, 3, 4], step: [7, 6, 5, 4.2] },
    { axiom: "X", rules: { X: "F[+X][-X]FX", F: "FF" },  angle: 25.7, iters: [1, 2, 3, 4], step: [8, 6, 5, 4.5] },
    { axiom: "X", rules: { X: "F-[[X]+X]+F[+FX]-X", F: "FF" }, angle: 22.5, iters: [1, 2, 3, 3], step: [6, 5, 4, 5.5] }, // fern
    { axiom: "F", rules: { F: "FF+[+F-F-F]-[-F+F+F]" }, angle: 22.5, iters: [1, 1, 2, 2], step: [7, 10, 7, 9] },  // bush
    { axiom: "F", rules: { F: "F[+F]F[-F]F" },          angle: 25.7, iters: [1, 2, 2, 3], step: [8, 6, 8, 4] },   // weed
    { axiom: "F", rules: { F: "F[+F]F[-F][F]" },        angle: 20,   iters: [1, 2, 3, 3], step: [8, 6, 5, 6.5] },
    { axiom: "F", rules: { F: "FF-[-F+F+F]+[+F-F-F]" }, angle: 26,   iters: [1, 1, 2, 2], step: [7, 10, 7, 9] },
    { axiom: "X", rules: { X: "F[++X][--X]F[+X]-FX", F: "FF" }, angle: 18, iters: [1, 2, 3, 3], step: [7, 6, 5, 6] }, // conifer-ish
    { axiom: "X", rules: { X: "FF[+X][-X][X]", F: "F" }, angle: 30,  iters: [1, 2, 3, 4], step: [9, 8, 7, 6] },   // palm-y whorl
    { axiom: "X", rules: { X: "F[+X]F[-X][X]", F: "FF" }, angle: 32, iters: [1, 2, 3, 4], step: [7, 6, 5, 4.5] }, // wide canopy
    { axiom: "X", rules: { X: "F[-X]F[-X]+X", F: "FF" }, angle: 24,  iters: [1, 2, 3, 4], step: [7, 6, 5, 4.2] }, // leaning
    { axiom: "F", rules: { F: "F[+FF][-FF]F[-F][+F]F" }, angle: 35,  iters: [1, 1, 2, 2], step: [6, 9, 6, 7] }    // gnarled oak
];

var FAMILY_COUNT = RULESETS.length * 2;

// family = ruleset × foliage build (0: sparse big diamonds, 1: dense small)
function familySpec(index) {
    var f = ((index % FAMILY_COUNT) + FAMILY_COUNT) % FAMILY_COUNT;
    var rs = RULESETS[f % RULESETS.length];
    var dense = f >= RULESETS.length;
    return {
        ruleset: rs,
        dense: dense,
        // dense builds tilt a little narrower so the two reads differ clearly
        angleMul: dense ? 0.85 : 1.0,
        leafR: dense ? 2.2 : 3.6,
        leafEvery: dense ? 1 : 2   // leaf at every pop vs every other pop
    };
}

var EXPAND_CAP = 9000;   // rewrite-string cap — bounds work per tree
var SEG_CAP = 520;       // drawn segments cap

function expand(rs, iterations) {
    var s = rs.axiom;
    for (var i = 0; i < iterations; i++) {
        var out = "";
        for (var j = 0; j < s.length; j++) {
            var ch = s[j];
            out += rs.rules[ch] || ch;
            if (out.length > EXPAND_CAP) return out.slice(0, EXPAND_CAP);
        }
        s = out;
    }
    return s;
}

// build(seed, stage 1..4) → { segs: [{x1,y1,x2,y2,d}], leaves: [{x,y,r,d}],
//                             h: height extent, family: index }
// d = bracket depth (0 = trunk) for width/shade; h > 0 even for tiny plants.
function build(seed, stage) {
    var rng = rng32(seed);
    var family = Math.floor(rng() * FAMILY_COUNT);
    var spec = familySpec(family);
    var rs = spec.ruleset;
    var st = Math.max(1, Math.min(4, stage)) - 1;
    var s = expand(rs, rs.iters[st]);
    var step = rs.step[st] * (0.85 + 0.3 * rng());
    var angle = rs.angle * spec.angleMul * (Math.PI / 180);

    var segs = [], leaves = [];
    var x = 0, y = 0, dir = -Math.PI / 2, depth = 0;
    var stack = [];
    var minY = 0, pops = 0;
    for (var i = 0; i < s.length && segs.length < SEG_CAP; i++) {
        var ch = s[i];
        if (ch === "F") {
            // deeper branches shorten; every segment gets a little jitter
            var len = step * Math.pow(0.92, depth) * (0.9 + 0.2 * rng());
            var nx = x + Math.cos(dir) * len;
            var ny = y + Math.sin(dir) * len;
            segs.push({ x1: x, y1: y, x2: nx, y2: ny, d: depth });
            x = nx; y = ny;
            if (y < minY) minY = y;
        } else if (ch === "+") {
            dir += angle * (0.75 + 0.5 * rng());
        } else if (ch === "-") {
            dir -= angle * (0.75 + 0.5 * rng());
        } else if (ch === "[") {
            stack.push({ x: x, y: y, dir: dir, depth: depth });
            depth++;
        } else if (ch === "]") {
            // a leaf cluster caps the branch we're leaving
            pops++;
            if (depth > 0 && pops % spec.leafEvery === 0) {
                var r = spec.leafR * (0.8 + 0.5 * rng()) * (1 + st * 0.25);
                leaves.push({ x: x, y: y, r: r, d: depth });
                if (spec.dense) {
                    leaves.push({ x: x + (rng() - 0.5) * 5, y: y - rng() * 4, r: r * 0.8, d: depth });
                    leaves.push({ x: x + (rng() - 0.5) * 5, y: y + (rng() - 0.5) * 3, r: r * 0.7, d: depth });
                }
            }
            var top = stack.pop();
            if (top) { x = top.x; y = top.y; dir = top.dir; depth = top.depth; }
        }
        // X and anything else: geometry no-op (placeholder symbol)
    }
    // crown the final tip too, so stage-1 sprouts get at least one leaf
    var r0 = spec.leafR * (1 + st * 0.25);
    leaves.push({ x: x, y: y, r: r0, d: depth + 1 });
    return { segs: segs, leaves: leaves, h: Math.max(6, -minY), family: family };
}

// Small ground tuft (floor vegetation): 2–4 grass blades + optional dot.
// Same determinism contract as build().
function tuft(seed) {
    var rng = rng32(seed);
    var blades = [];
    var n = 2 + Math.floor(rng() * 3);
    for (var i = 0; i < n; i++) {
        var a = -Math.PI / 2 + (rng() - 0.5) * 1.1;
        var l = 2.5 + rng() * 3.5;
        blades.push({ x2: Math.cos(a) * l, y2: Math.sin(a) * l });
    }
    return { blades: blades, dot: rng() < 0.35, dotR: 0.8 + rng() };
}
