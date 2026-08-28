pragma ComponentBehavior: Bound
// InvadersMenu.qml — "Chicken Invaders", a roguelike mini shooter played inside
// the control panel (menu 18, opened from the Games list). A 495×490 starfield
// on the left (drifting stars — the ship reads as travelling); wave / score /
// best / hull, the run's upgrade loadout, the rules and New run · Pause on the
// right — the same two-column layout as Snake (menu 14) / Brick Breaker
// (menu 12), just much roomier.
//
// The loop: a formation of chickens sweeps side-to-side and slowly descends,
// raining eggs (egg drop speed steps up every 3rd wave). Your ship AUTOFIRES —
// you only fly (←→ / H·L), dodging eggs and lining up shots. Egg hits and
// chickens diving past the hull line each cost 1 hull; at 0 hull the run ends.
//
// The roguelike part is the DRAFT. Before wave 1 you arm the ship: pick ONE of
// three attack paths, locked for the whole run —
//   • bullet — streams of shots (upgrades: +streams, fire rate, pierce)
//   • laser  — an instant full-height beam every 2s, pierces everything
//              (upgrades: width, damage, burn time)
//   • vapor  — a rotating smoke orb that drifts up dealing damage-per-second
//              to whatever it overlaps (upgrades: size, acid)
// After clearing every EVEN wave (2, 4, 6 …) a draft of three offers upgrades
// from your path + the spaceship tracks (hull plating, thrusters, evasion) —
// capped at 15 picks per run, path pick included. Odd waves (and drafts with
// nothing left to offer) breathe through a short "next wave incoming"
// interlude instead. Upgrades last one run — die and the next run re-arms from
// scratch; only the best score/wave persists.
//
// Simulation: one 16ms tick moves the ship, integrates bullets / eggs / vapor
// orbs / the laser window, spawns eggs, and resolves collisions; everything
// lives in plain JS arrays rendered through FIXED delegate pools that re-read
// positions on a per-tick `simRev` bump (Snake's pool pattern — no delegate
// churn mid-flight, no stale renders from mutating var objects in place). The
// starfield is the same idea: a fixed pool of 72 dots whose y drifts down and
// WRAPS at the field edge, so the "travelling" effect never instantiates a
// star out of view. Chicken positions derive from a single formation origin
// (fx, fy) plus per-slot wobble, so the whole flock is two properties.
//
// Keys (the pane grabs the keyboard while it is menu 18, see init.qml
// grabsKeyboard): ←→ / H·L fly · P pause · N new run · Esc closes. In a draft,
// arrows move the highlight and Enter/Space picks (1/2/3 jump-pick, clicking
// works too — hovering a card moves the highlight with it). Opens paused; on
// game over Enter/Space starts a new run. Between-wave state (wave, score,
// hull, path, upgrade levels, picks, best) persists into the shared launcher
// settings under `invaders`; flight is transient — reopening mid-wave restarts
// that wave fresh, and a run closed mid-draft re-rolls its cards.
import QtQuick

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — persistence lives in settings.invaders
    signal closeRequested()

    // park-drag: the header grip drives these; init.qml catches them and moves the
    // whole pane (shared tetris* park state — see the Connections block).
    signal parkDragStart(real sx, real sy)
    signal parkDragMove(real sx, real sy)
    signal parkDragEnd()

    // ---- geometry ----
    readonly property real fieldW: 495
    readonly property real fieldH: 490
    readonly property int cols: 6
    readonly property int maxRows: 4
    readonly property int slotW: 40
    readonly property int slotH: 32
    readonly property real chickW: 24                // one "chicken width" — laser/vapor sizes scale off it
    readonly property real shipY: fieldH - 16
    readonly property real dangerY: fieldH - 42      // a chicken past this line strafes the hull

    // ---- run state (persisted between waves) ----
    property int wave: 1
    property int score: 0
    property int hp: 3
    property int maxHp: 3
    property string path: ""                          // "" until armed, then bullet | laser | vapor
    property var lv: ({})                             // per-track levels: { count: 2, plating: 1, … }
    property int picks: 0                             // drafted picks this run (path included)
    readonly property int maxPicks: 15
    property var best: ({ "score": 0, "wave": 0 })
    property bool over: false
    property var draft: null                          // null, or the offered card keys
    property bool draftAdv: false                     // this draft advances to the next wave on pick
    property int draftSel: 0                          // keyboard highlight into `draft`
    property bool wavePause: false                    // the no-draft interlude between waves
    property bool paused: false

    // ---- flight state (transient — never persisted) ----
    property real shipX: fieldW / 2
    property int moveDir: 0                           // -1 / 0 / 1 from held keys
    property var chix: []                             // per slot { alive, hp } (hp goes fractional under vapor)
    property int chickRows: 2
    property int aliveCount: 0
    property var bullets: []                          // { x, y, vx, vy, thru }
    property var eggs: []                             // { x, y, vy, age }
    property var blobs: []                            // vapor orbs: { x, y }
    property real laserX: 0                           // frozen beam position (fired at the ship's x)
    property real laserT: 0                           // ms of beam life left (0 = off)
    property var laserHits: ({})                      // chicken slots already burned by this beam
    property var pops: []                             // kill puffs: { x, y, age }
    property real fx: 30                              // formation origin (sweeps)
    property real fy: 8                               //   … and descends
    property real formT: 0                            // ms since the wave spawned
    property real tSim: 0                             // ms since the pane opened (flicker/blink/spin clocks)
    property real starT: 0                            // starfield drift clock (only advances while flying)
    property real fireAcc: 0
    property real invulnMs: 0                         // post-hit mercy window
    property int simRev: 0                            // bump per tick — pools re-read the arrays

    // ---- derived stats (path + track levels → numbers) ----
    readonly property real shipSpeed: 150 * (1 + 0.3 * (root.lv.thrusters || 0))
    readonly property real evade: 0.1 * (root.lv.evasion || 0)
    // bullet path
    readonly property int streams: 1 + (root.lv.count || 0)
    readonly property real fireMs: 420 / (1 + 0.2 * (root.lv.rapid || 0))
    readonly property int pierce: root.lv.pierce || 0
    // laser path — an instant beam every laserMs, alive upMs, beamW wide
    readonly property real laserMs: 2000
    readonly property real upMs: 100 + 50 * (root.lv.luptime || 0)
    readonly property real beamW: root.chickW * (0.1 + 0.2 * (root.lv.lwidth || 0))
    readonly property real laserDmg: 1 + (root.lv.ldmg || 0)
    // vapor path — an orb every vaporMs, vaporSize square, vaporDps while overlapping
    readonly property real vaporMs: 1200
    readonly property real vaporSize: root.chickW * (2 + 0.25 * (root.lv.vsize || 0))
    readonly property real vaporDps: 0.2 + 0.2 * (root.lv.vdmg || 0)
    readonly property int chickHp: 1 + Math.floor((root.wave - 1) / 2)
    readonly property real eggSpeed: 100 + 30 * Math.floor((root.wave - 1) / 3)   // steps up every 3rd wave

    // every draftable card. `path` scopes a track to its attack path ("ship"
    // tracks are always offered); the three "path:*" cards are the level-0
    // arm-your-ship pick — once one is chosen the other paths never appear.
    readonly property var draftDefs: ({
        "path:bullet": { "name": "Bullet Cannon", "icon": "north",       "max": 1, "desc": "streams of shot — count, rate, pierce" },
        "path:laser":  { "name": "Laser Lance",   "icon": "flash_on",    "max": 1, "desc": "instant piercing beam every 2s" },
        "path:vapor":  { "name": "Vapor Orb",     "icon": "cyclone",     "max": 1, "desc": "drifting cloud that melts the flock" },
        "count":    { "path": "bullet", "name": "Streams",      "icon": "call_split",    "max": 4, "desc": "+1 bullet stream" },
        "rapid":    { "path": "bullet", "name": "Rapid Fire",   "icon": "speed",         "max": 5, "desc": "fire 20% faster" },
        "pierce":   { "path": "bullet", "name": "Skewers",      "icon": "swap_vert",     "max": 2, "desc": "shots pierce +1 chicken" },
        "lwidth":   { "path": "laser",  "name": "Wide Beam",    "icon": "expand",        "max": 4, "desc": "beam +20% chicken width" },
        "ldmg":     { "path": "laser",  "name": "Hot Beam",     "icon": "bolt",          "max": 1, "desc": "beam damage 1 → 2" },
        "luptime":  { "path": "laser",  "name": "Long Burn",    "icon": "timer",         "max": 3, "desc": "beam lingers +0.05s" },
        "vsize":    { "path": "vapor",  "name": "Big Cloud",    "icon": "open_in_full",  "max": 4, "desc": "cloud +¼ chicken size" },
        "vdmg":     { "path": "vapor",  "name": "Acid Cloud",   "icon": "science",       "max": 4, "desc": "+0.2 damage per second" },
        "plating":  { "path": "ship",   "name": "Hull Plating", "icon": "shield",        "max": 99, "desc": "+1 max hull, patch 1" },
        "thrusters":{ "path": "ship",   "name": "Thrusters",    "icon": "rocket_launch", "max": 99, "desc": "fly 30% faster" },
        "evasion":  { "path": "ship",   "name": "Evasion",      "icon": "alt_route",     "max": 5, "desc": "+10% chance to dodge eggs" }
    })
    readonly property var trackOrder: ["count", "rapid", "pierce", "lwidth", "ldmg", "luptime", "vsize", "vdmg", "plating", "thrusters", "evasion"]
    // the loadout rows shown in the sidebar: the chosen path's tracks + ship tracks
    readonly property var sideTracks: {
        root.path;
        var keys = [];
        for (var i = 0; i < root.trackOrder.length; i++) {
            var d = root.draftDefs[root.trackOrder[i]];
            if (d.path === root.path || d.path === "ship") keys.push(root.trackOrder[i]);
        }
        return keys;
    }

    // chickens tint darker as they hold more health (like Brick Breaker's brick
    // palette). Vapor deals fractional damage, so index by ceil(hp).
    readonly property var chickPal: ["#ece4d6", "#e6cb96", "#d9a441", "#c57f3a", "#a85f38", "#8f4a3a"]
    function chickColor(hp) { return root.chickPal[Math.min(root.chickPal.length - 1, Math.max(0, Math.ceil(hp) - 1))]; }

    // ---- formation position (origin + per-slot wobble; used by sim AND render) ----
    function chickX(i) { return root.fx + (i % root.cols) * root.slotW + 20 + 2.5 * Math.sin(root.formT / 260 + i * 1.7); }
    function chickY(i) { return root.fy + Math.floor(i / root.cols) * root.slotH + 14 + 3 * Math.sin(root.formT / 340 + i); }

    // ---- run lifecycle ----
    function spawnWave() {
        root.chickRows = Math.min(root.maxRows, 2 + Math.floor((root.wave - 1) / 3));
        var c = [];
        for (var i = 0; i < root.chickRows * root.cols; i++)
            c.push({ "alive": true, "hp": root.chickHp });
        root.chix = c;
        root.aliveCount = c.length;
        root.bullets = []; root.eggs = []; root.blobs = []; root.pops = [];
        root.laserT = 0; root.laserHits = {};
        root.formT = 0; root.fireAcc = 0; root.invulnMs = 0;
        root.fx = (root.fieldW - root.cols * root.slotW) / 2; root.fy = 8;
        root.simRev++;
    }

    function newRun() {
        root.wave = 1;
        root.score = 0;
        root.path = "";
        root.lv = {};
        root.picks = 0;
        root.maxHp = 3;
        root.hp = 3;
        root.over = false;
        root.draft = null;
        root.draftAdv = false;
        root.wavePause = false;
        waveGap.stop();
        root.shipX = root.fieldW / 2;
        root.spawnWave();
        root.paused = false;
        root.rollDraft(false);                        // level 0: arm the ship (attack paths only)
    }

    function gameOver() {
        root.over = true;
        if (root.score > root.best.score)
            root.best = { "score": root.score, "wave": root.wave };
        root.save();
    }

    // what the next draft could offer. Before the path pick: exactly the three
    // attack paths. After: the chosen path's unmaxed tracks + ship tracks, or
    // nothing once the 15-pick budget is spent.
    function draftPool() {
        if (!root.path) return ["path:bullet", "path:laser", "path:vapor"];
        if (root.picks >= root.maxPicks) return [];
        var pool = [];
        for (var i = 0; i < root.trackOrder.length; i++) {
            var k = root.trackOrder[i], d = root.draftDefs[k];
            if ((d.path === root.path || d.path === "ship") && (root.lv[k] || 0) < d.max) pool.push(k);
        }
        return pool;
    }

    function rollDraft(advance) {
        var pool = root.draftPool();
        if (pool.length === 0) {                      // nothing to offer — breathe instead
            root.wavePause = true;
            waveGap.restart();
            root.save();
            return;
        }
        if (root.path) {                              // upgrade drafts randomize; the path trio keeps its order
            for (var i = pool.length - 1; i > 0; i--) {              // Fisher–Yates
                var j = Math.floor(Math.random() * (i + 1));
                var t = pool[i]; pool[i] = pool[j]; pool[j] = t;
            }
            pool = pool.slice(0, Math.min(3, pool.length));
        }
        root.draft = pool;
        root.draftSel = 0;
        root.draftAdv = !!advance;
        root.save();
    }

    function pickUpgrade(idx) {
        if (!root.draft || idx >= root.draft.length) return;
        var key = root.draft[idx];
        root.picks++;
        if (key.indexOf("path:") === 0) {
            root.path = key.substring(5);
            root.fireAcc = 0;
        } else {
            var u = {};
            for (var k in root.lv) u[k] = root.lv[k];
            u[key] = (u[key] || 0) + 1;
            root.lv = u;                              // fresh object — loadout bindings re-read
            if (key === "plating") { root.maxHp++; root.hp = Math.min(root.maxHp, root.hp + 1); }
        }
        var adv = root.draftAdv;
        root.draft = null;
        root.draftAdv = false;
        if (adv) root.nextWave(); else root.save();
    }

    function nextWave() {
        root.wave++;
        root.spawnWave();
        root.save();
    }

    function togglePause() { if (!root.over && !root.draft && !root.wavePause) { root.paused = !root.paused; root.save(); } }

    // ---- persistence (shared launcher settings, key `invaders`) ----
    // flight is transient: reopening mid-wave restarts the wave fresh; a run
    // closed mid-draft re-rolls (the level-0 path draft if unarmed, an advancing
    // upgrade draft otherwise — upgrade drafts only ever happen on wave clears).
    function save() {
        root.settings.invaders = {
            "wave": root.wave, "score": root.score, "hp": root.hp, "maxHp": root.maxHp,
            "path": root.path, "lv": root.lv, "picks": root.picks,
            "draft": !!root.draft, "over": root.over, "best": root.best
        };
    }
    function load() {
        var s = root.settings.invaders;
        root.best = (s && s.best) ? s.best : { "score": 0, "wave": 0 };
        if (s && s.wave && s.lv !== undefined) {
            root.wave = s.wave;
            root.score = s.score || 0;
            root.path = s.path || "";
            root.lv = s.lv || {};
            root.picks = s.picks || 0;
            root.maxHp = s.maxHp || 3;
            root.hp = (s.hp !== undefined) ? s.hp : root.maxHp;
            root.over = !!s.over;
            root.spawnWave();
            if (s.draft && !root.over) root.rollDraft(!!root.path);
        } else {
            root.newRun();
        }
    }
    // load, then always open PAUSED — the flock never starts sliding the instant
    // the pane opens (a draft or game-over veil is its own resting state).
    Component.onCompleted: { root.load(); if (!root.over && !root.draft) root.paused = true; }
    Component.onDestruction: root.save()

    // ---- combat helpers ----
    function fireBullets() {
        var n = Math.min(5, root.streams);
        var spd = 320;
        var shots = n === 1 ? [{ "dx": 0, "ang": 0 }]
                  : n === 2 ? [{ "dx": -5, "ang": 0 }, { "dx": 5, "ang": 0 }]
                  : n === 3 ? [{ "dx": 0, "ang": 0 }, { "dx": -6, "ang": -0.14 }, { "dx": 6, "ang": 0.14 }]
                  : n === 4 ? [{ "dx": -4, "ang": 0 }, { "dx": 4, "ang": 0 }, { "dx": -8, "ang": -0.18 }, { "dx": 8, "ang": 0.18 }]
                  : [{ "dx": 0, "ang": 0 }, { "dx": -5, "ang": 0 }, { "dx": 5, "ang": 0 }, { "dx": -9, "ang": -0.2 }, { "dx": 9, "ang": 0.2 }];
        for (var i = 0; i < shots.length; i++) {
            if (root.bullets.length >= 48) break;
            root.bullets.push({
                "x": root.shipX + shots[i].dx, "y": root.shipY - 12,
                "vx": Math.sin(shots[i].ang) * spd, "vy": -Math.cos(shots[i].ang) * spd,
                "thru": root.pierce
            });
        }
    }

    // damage one chicken slot; returns nothing. Fractional damage (vapor) just
    // nudges hp — the kill fires once it dips to/under zero.
    function damageChick(k, dmg) {
        var c = root.chix[k];
        if (!c.alive) return;
        c.hp -= dmg;
        if (c.hp <= 0) {
            c.alive = false;
            root.aliveCount--;
            root.score += 5 + root.wave;
            if (root.score > root.best.score) root.best = { "score": root.score, "wave": root.wave };
            root.addPop(root.chickX(k), root.chickY(k));
        }
    }

    function hullHit() {
        root.hp--;
        root.invulnMs = 1200;
        if (root.hp <= 0) root.gameOver();
    }

    function addPop(x, y) {
        if (root.pops.length >= 10) root.pops.shift();
        root.pops.push({ "x": x, "y": y, "age": 0 });
    }

    // ---- the tick: ship → formation → weapon → projectiles → eggs → cleanup ----
    function tick() {
        var dt = 16;
        root.tSim += dt;
        root.formT += dt;
        root.starT = (root.starT + dt) % 3600000;
        if (root.invulnMs > 0) root.invulnMs -= dt;

        // ship
        if (root.moveDir !== 0)
            root.shipX = Math.max(14, Math.min(root.fieldW - 14, root.shipX + root.moveDir * root.shipSpeed * dt / 1000));

        // formation sweep + slow descent (a touch quicker every wave; rate scaled
        // to the tall field so a wave keeps roughly the same time pressure)
        var formW = root.cols * root.slotW;
        root.fx = (root.fieldW - formW) / 2 + ((root.fieldW - formW) / 2 - 6) * Math.sin(root.formT / 1000 * 0.9);
        root.fy = 8 + (4.2 + 0.6 * root.wave) * root.formT / 1000;

        // ---- the armed weapon ----
        root.fireAcc += dt;
        if (root.path === "laser") {
            if (root.laserT > 0) {
                root.laserT -= dt;
                // burn every chicken crossing the beam once per firing
                for (var lk = 0; lk < root.chix.length; lk++) {
                    if (!root.chix[lk].alive || root.laserHits[lk]) continue;
                    if (Math.abs(root.chickX(lk) - root.laserX) < root.beamW / 2 + 12) {
                        root.laserHits[lk] = true;
                        root.damageChick(lk, root.laserDmg);
                    }
                }
            }
            if (root.fireAcc >= root.laserMs) {
                root.fireAcc = 0;
                root.laserX = root.shipX;
                root.laserT = root.upMs;
                root.laserHits = {};
            }
        } else if (root.path === "vapor") {
            if (root.fireAcc >= root.vaporMs && root.blobs.length < 4) {
                root.fireAcc = 0;
                root.blobs.push({ "x": root.shipX, "y": root.shipY - 24 });
            }
            var half = root.vaporSize / 2;
            for (var vb = root.blobs.length - 1; vb >= 0; vb--) {
                var o = root.blobs[vb];
                o.y -= 320 * dt / 1000;
                if (o.y < -half) { root.blobs.splice(vb, 1); continue; }
                for (var vk = 0; vk < root.chix.length; vk++) {
                    if (!root.chix[vk].alive) continue;
                    if (Math.abs(root.chickX(vk) - o.x) < half + 12 && Math.abs(root.chickY(vk) - o.y) < half + 11)
                        root.damageChick(vk, root.vaporDps * dt / 1000);
                }
            }
        } else {   // bullet (the default path)
            if (root.fireAcc >= root.fireMs) { root.fireAcc = 0; root.fireBullets(); }
        }

        // bullets vs chickens
        for (var i = root.bullets.length - 1; i >= 0; i--) {
            var b = root.bullets[i];
            b.x += b.vx * dt / 1000; b.y += b.vy * dt / 1000;
            if (b.y < -12 || b.x < -8 || b.x > root.fieldW + 8) { root.bullets.splice(i, 1); continue; }
            for (var k = 0; k < root.chix.length; k++) {
                if (!root.chix[k].alive) continue;
                if (Math.abs(b.x - root.chickX(k)) < 15 && Math.abs(b.y - root.chickY(k)) < 13) {
                    root.damageChick(k, 1);
                    if (b.thru > 0) b.thru--; else root.bullets.splice(i, 1);
                    break;
                }
            }
        }

        // egg rain — flock-wide rate rises with the wave; drop speed steps every 3rd
        if (root.aliveCount > 0 && root.eggs.length < 16
                && Math.random() < (0.5 + 0.13 * root.wave) * dt / 1000) {
            var alive = [];
            for (var a = 0; a < root.chix.length; a++) if (root.chix[a].alive) alive.push(a);
            var src = alive[Math.floor(Math.random() * alive.length)];
            root.eggs.push({ "x": root.chickX(src), "y": root.chickY(src) + 12, "vy": root.eggSpeed, "age": 0 });
        }

        // eggs vs ship (evasion may whiff the hit into a puff)
        for (var e = root.eggs.length - 1; e >= 0; e--) {
            var g = root.eggs[e];
            g.y += g.vy * dt / 1000;
            g.age += dt;
            if (g.y > root.fieldH + 8) { root.eggs.splice(e, 1); continue; }
            if (root.invulnMs <= 0 && Math.abs(g.x - root.shipX) < 15
                    && g.y > root.shipY - 10 && g.y < root.shipY + 10) {
                root.eggs.splice(e, 1);
                if (root.evade > 0 && Math.random() < root.evade) { root.addPop(g.x, g.y); continue; }
                root.hullHit();
                if (root.over) break;
            }
        }

        // a chicken past the hull line strafes the hull and flies off
        if (!root.over) {
            for (var d = 0; d < root.chix.length; d++) {
                if (!root.chix[d].alive) continue;
                if (root.chickY(d) > root.dangerY) {
                    root.chix[d].alive = false;
                    root.aliveCount--;
                    root.hullHit();
                    if (root.over) break;
                }
            }
        }

        // kill puffs age out
        for (var p = root.pops.length - 1; p >= 0; p--) {
            root.pops[p].age += dt;
            if (root.pops[p].age > 320) root.pops.splice(p, 1);
        }

        root.simRev++;

        // wave cleared → even waves draft (if there is anything left), the rest
        // take the short interlude
        if (!root.over && root.aliveCount === 0) {
            if (root.wave % 2 === 0 && root.draftPool().length > 0) {
                root.rollDraft(true);
            } else {
                root.wavePause = true;
                waveGap.restart();
                root.save();
            }
        }
    }

    Timer {
        id: sim
        interval: 16
        repeat: true
        running: !root.over && !root.paused && !root.draft && !root.wavePause
        onTriggered: root.tick()
    }
    // the between-wave breather (odd waves, or nothing left to draft)
    Timer {
        id: waveGap
        interval: 1500
        onTriggered: { root.wavePause = false; root.nextWave(); }
    }

    // keyboard sink — holds focus for the whole pane (the pill grabs the compositor
    // keyboard for menu 18). Mouse-transparent, so the buttons still work.
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Component.onCompleted: keys.forceActiveFocus()
        Keys.onPressed: (e) => {
            if (root.over) {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.newRun(); e.accepted = true; }
                else if (e.key === Qt.Key_Escape) { root.save(); root.closeRequested(); e.accepted = true; }
                else if (e.key === Qt.Key_N) { root.newRun(); e.accepted = true; }
                return;
            }
            if (root.draft) {
                var n = root.draft.length;
                switch (e.key) {
                case Qt.Key_1: root.pickUpgrade(0); e.accepted = true; return;
                case Qt.Key_2: root.pickUpgrade(1); e.accepted = true; return;
                case Qt.Key_3: root.pickUpgrade(2); e.accepted = true; return;
                case Qt.Key_Up:   case Qt.Key_Left:  case Qt.Key_K: case Qt.Key_H:
                    root.draftSel = (root.draftSel + n - 1) % n; e.accepted = true; return;
                case Qt.Key_Down: case Qt.Key_Right: case Qt.Key_J: case Qt.Key_L:
                    root.draftSel = (root.draftSel + 1) % n; e.accepted = true; return;
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                    root.pickUpgrade(root.draftSel); e.accepted = true; return;
                }
            }
            switch (e.key) {
            case Qt.Key_Left:  case Qt.Key_H: if (!e.isAutoRepeat) root.moveDir = -1; e.accepted = true; break;
            case Qt.Key_Right: case Qt.Key_L: if (!e.isAutoRepeat) root.moveDir = 1;  e.accepted = true; break;
            case Qt.Key_P:                    root.togglePause();                     e.accepted = true; break;
            case Qt.Key_N:                    root.newRun();                          e.accepted = true; break;
            case Qt.Key_Escape:               root.save(); root.closeRequested();    e.accepted = true; break;
            }
        }
        Keys.onReleased: (e) => {
            if (e.isAutoRepeat) return;
            if ((e.key === Qt.Key_Left || e.key === Qt.Key_H) && root.moveDir === -1) { root.moveDir = 0; e.accepted = true; }
            if ((e.key === Qt.Key_Right || e.key === Qt.Key_L) && root.moveDir === 1) { root.moveDir = 0; e.accepted = true; }
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Chicken Invaders"
            onBack: root.closeRequested()
            // drag grip — park the pane anywhere by this handle (right of the title).
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
                clip: true

                Item {
                    id: field
                    x: 1; y: 1
                    width: root.fieldW
                    height: root.fieldH

                    // drifting starfield — a FIXED pool of white dots at five
                    // index-derived opacity tiers; y drifts down (brighter = faster,
                    // a cheap parallax) and WRAPS at the bottom edge, so the same 72
                    // delegates recycle forever and nothing is ever spawned off-view.
                    Repeater {
                        model: 72
                        delegate: Rectangle {
                            required property int index
                            readonly property int tier: index % 5
                            readonly property var tiers: [0.05, 0.08, 0.12, 0.18, 0.28]
                            x: (index * 97 + 13) % root.fieldW
                            y: ((index * 61 + 29) + root.starT * (8 + tier * 7) / 1000) % root.fieldH
                            width: index % 7 === 0 ? 2 : 1
                            height: width
                            radius: width / 2
                            color: Qt.rgba(1, 1, 1, tiers[tier])
                        }
                    }

                    // the hull line the flock must not cross
                    Rectangle {
                        x: 0; y: root.dangerY
                        width: root.fieldW; height: 1
                        color: Qt.rgba(0xd6 / 255.0, 0x5c / 255.0, 0x4a / 255.0, 0.18)
                    }

                    // ---- chickens (fixed pool, positions from the formation origin) ----
                    Repeater {
                        model: root.cols * root.maxRows
                        delegate: Item {
                            id: chick
                            required property int index
                            readonly property bool live: { root.simRev; return chick.index < root.chix.length && root.chix[chick.index].alive; }
                            readonly property real chp: { root.simRev; return chick.live ? root.chix[chick.index].hp : 1; }
                            visible: chick.live
                            x: { root.simRev; return chick.live ? root.chickX(chick.index) - 12 : 0; }
                            y: { root.simRev; return chick.live ? root.chickY(chick.index) - 11 : 0; }
                            width: 24; height: 22
                            // comb
                            Rectangle { x: 9; y: 0; width: 6; height: 6; radius: 3; color: "#d65c5c" }
                            // body — darkens with remaining health
                            Rectangle {
                                x: 2; y: 4; width: 20; height: 14; radius: 7
                                color: root.chickColor(chick.chp)
                                antialiasing: true
                            }
                            // wing stubs
                            Rectangle { x: 0;  y: 8; width: 5; height: 8; radius: 2.5; color: Qt.darker(root.chickColor(chick.chp), 1.18) }
                            Rectangle { x: 19; y: 8; width: 5; height: 8; radius: 2.5; color: Qt.darker(root.chickColor(chick.chp), 1.18) }
                            // eyes (facing you, menacingly)
                            Rectangle { x: 7;  y: 8; width: 3; height: 3; radius: 1.5; color: "#101014" }
                            Rectangle { x: 14; y: 8; width: 3; height: 3; radius: 1.5; color: "#101014" }
                            // beak
                            Rectangle { x: 10; y: 17; width: 4; height: 4; radius: 1; color: "#d68a3c" }
                        }
                    }

                    // ---- the laser beam (instant, frozen at its firing x) ----
                    Rectangle {   // outer glow
                        visible: root.laserT > 0
                        x: root.laserX - (root.beamW / 2 + 3); y: 0
                        width: root.beamW + 6; height: root.shipY - 12
                        radius: width / 2
                        color: root.theme.accent
                        opacity: root.laserT > 0 ? 0.12 + 0.25 * (root.laserT / root.upMs) : 0
                    }
                    Rectangle {   // hot core
                        visible: root.laserT > 0
                        x: root.laserX - root.beamW / 2; y: 0
                        width: Math.max(2, root.beamW); height: root.shipY - 12
                        color: "#fff3dc"
                        opacity: root.laserT > 0 ? 0.5 + 0.5 * (root.laserT / root.upMs) : 0
                    }

                    // ---- vapor orbs (rotating smoke — three offset puffs) ----
                    Repeater {
                        model: 4
                        delegate: Item {
                            id: orb
                            required property int index
                            readonly property bool live: { root.simRev; return orb.index < root.blobs.length; }
                            visible: orb.live
                            x: { root.simRev; return orb.live ? root.blobs[orb.index].x - root.vaporSize / 2 : 0; }
                            y: { root.simRev; return orb.live ? root.blobs[orb.index].y - root.vaporSize / 2 : 0; }
                            width: root.vaporSize
                            height: root.vaporSize
                            rotation: (root.tSim / 6 + orb.index * 90) % 360
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.72; height: width; radius: width / 2
                                color: Qt.rgba(0.78, 0.84, 0.78, 0.22)
                            }
                            Rectangle {
                                x: parent.width * 0.05; y: parent.height * 0.28
                                width: parent.width * 0.45; height: width; radius: width / 2
                                color: Qt.rgba(0.72, 0.8, 0.72, 0.3)
                            }
                            Rectangle {
                                x: parent.width * 0.52; y: parent.height * 0.12
                                width: parent.width * 0.4; height: width; radius: width / 2
                                color: Qt.rgba(0.85, 0.9, 0.85, 0.26)
                            }
                        }
                    }

                    // ---- bullets ----
                    Repeater {
                        model: 48
                        delegate: Rectangle {
                            required property int index
                            readonly property bool live: { root.simRev; return index < root.bullets.length; }
                            visible: live
                            x: { root.simRev; return live ? root.bullets[index].x - 1.5 : 0; }
                            y: { root.simRev; return live ? root.bullets[index].y - 5 : 0; }
                            width: 3; height: 10; radius: 1.5
                            color: root.theme.accent
                        }
                    }

                    // ---- eggs (pop in, wobble as they fall) ----
                    Repeater {
                        model: 16
                        delegate: Rectangle {
                            required property int index
                            readonly property bool live: { root.simRev; return index < root.eggs.length; }
                            visible: live
                            x: { root.simRev; return live ? root.eggs[index].x - 3.5 : 0; }
                            y: { root.simRev; return live ? root.eggs[index].y - 5 : 0; }
                            width: 7; height: 10; radius: 3.5
                            // spawn pop (scale in over ~140ms) + a fall wobble tied to
                            // the egg's own y, so each egg tumbles on its own beat
                            scale: { root.simRev; return live ? Math.min(1, root.eggs[index].age / 140) : 1; }
                            rotation: { root.simRev; return live ? 20 * Math.sin(root.eggs[index].y / 16 + index * 2.1) : 0; }
                            color: "#ece4d6"
                            border.width: 1
                            border.color: "#c9bfae"
                        }
                    }

                    // ---- kill puffs (expanding, fading rings) ----
                    Repeater {
                        model: 10
                        delegate: Rectangle {
                            required property int index
                            readonly property bool live: { root.simRev; return index < root.pops.length; }
                            readonly property real age: { root.simRev; return live ? root.pops[index].age / 320 : 0; }
                            visible: live
                            x: { root.simRev; return live ? root.pops[index].x - width / 2 : 0; }
                            y: { root.simRev; return live ? root.pops[index].y - height / 2 : 0; }
                            width: 8 + 22 * age
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.rgba(0xec / 255.0, 0xe4 / 255.0, 0xd6 / 255.0, 0.7 * (1 - age))
                        }
                    }

                    // ---- the ship (blinks through the post-hit mercy window) ----
                    Item {
                        id: ship
                        visible: !root.over
                        x: root.shipX - 14
                        y: root.shipY - 10
                        width: 28; height: 20
                        opacity: root.invulnMs > 0 ? (Math.floor(root.tSim / 100) % 2 ? 0.3 : 0.9) : 1
                        // wings
                        Rectangle { x: 0; y: 10; width: 28; height: 7; radius: 2; color: Qt.darker(root.theme.accent, 1.25) }
                        // fuselage
                        Rectangle { x: 10; y: 0; width: 8; height: 18; radius: 3; color: root.theme.accent }
                        // cockpit
                        Rectangle { x: 12; y: 4; width: 4; height: 5; radius: 2; color: Qt.lighter(root.theme.accent, 1.5) }
                        // exhaust flicker
                        Rectangle {
                            x: 12.5; y: 18; width: 3
                            height: (Math.floor(root.tSim / 96) % 2) ? 6 : 4
                            radius: 1.5
                            color: "#d68a3c"
                        }
                    }
                }

                // ---- draft veil: arm the ship (level 0) / pick an upgrade ----
                Rectangle {
                    anchors.fill: parent
                    visible: !!root.draft
                    color: Qt.rgba(0x0f / 255.0, 0x0c / 255.0, 0x08 / 255.0, 0.86)
                    radius: well.radius
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.path ? "WAVE " + root.wave + " CLEARED" : "ARM YOUR SHIP"
                            color: root.theme.accent
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsLarge + 4
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.path
                                ? "draft an upgrade — ↑↓ + enter · 1 2 3 · click"
                                : "one attack path, locked for the run"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        Item { width: 1; height: 4 }
                        Repeater {
                            model: root.draft || []
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                required property int index
                                readonly property var def: root.draftDefs[card.modelData]
                                readonly property bool isPath: card.modelData.indexOf("path:") === 0
                                readonly property int clv: root.lv[card.modelData] || 0
                                readonly property bool sel: card.index === root.draftSel
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 320; height: 56
                                radius: root.theme.radiusBtn
                                color: (card.sel || cardMa.containsMouse) ? root.theme.rowHi : root.theme.row
                                border.width: 1
                                border.color: card.sel ? root.theme.accent : root.theme.border
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    spacing: 10
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20; height: 20; radius: 6
                                        color: root.theme.accentSoft
                                        Text {
                                            anchors.centerIn: parent
                                            text: (card.index + 1)
                                            color: root.theme.accent
                                            font.family: root.theme.mono
                                            font.pixelSize: root.theme.fsSmall
                                        }
                                    }
                                    MSym {
                                        anchors.verticalCenter: parent.verticalCenter
                                        icon: card.def.icon
                                        size: 22
                                        color: root.theme.accent
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Text {
                                            text: card.def.name + (card.isPath ? "" : "   Lv " + card.clv + " → " + (card.clv + 1))
                                            color: root.theme.text
                                            font.family: root.theme.serif
                                            font.pixelSize: root.theme.fsLarge
                                        }
                                        Text {
                                            text: card.def.desc
                                            color: root.theme.textDim
                                            font.family: root.theme.mono
                                            font.pixelSize: root.theme.fsSmall
                                        }
                                    }
                                }
                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // hovering moves the keyboard highlight with the mouse
                                    onEntered: root.draftSel = card.index
                                    onClicked: { root.pickUpgrade(card.index); keys.forceActiveFocus(); }
                                }
                                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                            }
                        }
                    }
                }

                // ---- between-wave interlude (odd waves / nothing left to draft) ----
                Rectangle {
                    anchors.fill: parent
                    visible: root.wavePause && !root.over
                    color: Qt.rgba(0x0f / 255.0, 0x0c / 255.0, 0x08 / 255.0, 0.66)
                    radius: well.radius
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "WAVE " + root.wave + " CLEARED"
                            color: root.theme.accent
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsLarge + 4
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "next wave incoming"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                }

                // ---- paused / game-over veil ----
                Rectangle {
                    anchors.fill: parent
                    visible: (root.paused || root.over) && !root.draft && !root.wavePause
                    color: Qt.rgba(0x0f / 255.0, 0x0c / 255.0, 0x08 / 255.0, 0.78)
                    radius: well.radius
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.over ? "COOP COOKED" : "PAUSED"
                            color: root.over ? root.theme.accent : root.theme.text
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsLarge + 6
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.over
                                ? "wave " + root.wave + " · score " + root.score
                                : "P to fly · ←→ / H·L to move"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        Text {
                            visible: root.over
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Enter to fly again"
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                }
            }

            // ---- side column: stats · loadout · rules · controls ----
            Column {
                width: parent.width - well.width - 16
                spacing: 12

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 6
                    Repeater {
                        model: [
                            { "k": "Wave",  "v": root.wave.toString() },
                            { "k": "Score", "v": root.score.toString() },
                            { "k": "Best",  "v": root.best.score.toString() },
                            { "k": "Hull",  "v": root.hp + "/" + root.maxHp }
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

                // the run's loadout: chosen path + every track it can still draft
                // from (dim = not taken yet), plus the pick budget
                Column {
                    width: parent.width
                    spacing: 5
                    Item {
                        width: parent.width
                        height: 16
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.path ? root.draftDefs["path:" + root.path].name : "Unarmed"
                            color: root.theme.text
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsNormal + 1
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "PICKS " + root.picks + "/" + root.maxPicks
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall - 1
                            font.letterSpacing: root.theme.labelSpacing
                        }
                    }
                    Repeater {
                        model: root.sideTracks
                        delegate: Item {
                            id: trackRow
                            required property var modelData
                            readonly property var def: root.draftDefs[trackRow.modelData]
                            readonly property int l: root.lv[trackRow.modelData] || 0
                            width: parent.width
                            height: 17
                            opacity: trackRow.l > 0 ? 1 : 0.45
                            MSym {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                icon: trackRow.def.icon
                                size: 13
                                color: root.theme.accent
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 20
                                anchors.verticalCenter: parent.verticalCenter
                                text: trackRow.def.name
                                color: root.theme.textDim
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsSmall
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: trackRow.def.max > 90 ? "×" + trackRow.l : trackRow.l + "/" + trackRow.def.max
                                color: trackRow.l > 0 ? root.theme.accent : root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall - 1
                            }
                        }
                    }
                    Text {
                        visible: !root.path
                        width: parent.width
                        text: "Draft an attack path to begin."
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall - 1
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider }

                Text {
                    width: parent.width
                    text: "The flock sweeps, descends and rains eggs — faster every third wave. Guns autofire; you just fly. Drafts before wave 1 and after even waves: one attack path per run, " + root.maxPicks + " picks total."
                    wrapMode: Text.WordWrap
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsSmall
                }

                Rectangle { width: parent.width; height: 1; color: root.theme.divider }

                Column {
                    width: parent.width
                    spacing: 3
                    Repeater {
                        model: [
                            "←→ / H·L   Fly",
                            "↑↓ + Enter / 1·2·3   Draft pick",
                            "P   Pause      N   New run"
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
                            text: "New run"
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsSmall
                        }
                        MouseArea {
                            id: newMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.newRun(); keys.forceActiveFocus(); }
                        }
                    }
                    Rectangle {
                        width: 78; height: 30
                        radius: root.theme.radiusBtn
                        color: pauseMa.containsMouse ? root.theme.rowHi : root.theme.row
                        border.width: 1
                        border.color: root.theme.border
                        opacity: (root.over || root.draft || root.wavePause) ? 0.4 : 1
                        Text {
                            anchors.centerIn: parent
                            text: root.paused ? "Fly" : "Pause"
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
