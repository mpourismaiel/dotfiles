pragma ComponentBehavior: Bound
// harness.qml — off-screen screenshot gallery for the pill (screenshot harness only).
// Hosts the REAL leaf components (CollapsedPill, DesktopDots, Taskbar, StatusIcons)
// and the REAL menus against Mock* state objects, inside a FloatingWindow. It never
// instantiates a NotificationServer, winbridge, or any Process/DBus source, so it
// cannot touch the live pill. A grabber steps through each stage and saves a PNG.
import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: win
    visible: true
    implicitWidth: 900
    implicitHeight: 560
    color: "#151310"
    property string outDir: "@OUT@"

    Theme { id: theme }
    MockNetState  { id: netState }
    MockNotifs    { id: notifs }
    MockClip      { id: clip }
    MockMemos     { id: memos }
    MockOrg       { id: org }
    MockFinance   { id: fin }
    MockCal       { id: cal }
    MockBrightness { id: brightness }
    // stand-in for the theme-overrides JsonAdapter (Settings → Appearance).
    // A couple of overrides so the Appearance page shows reset dots + a non-default
    // preset state; the rest fall back to Theme defaults.
    QtObject {
        id: mockThemeSettings
        property var colors: ({ "accent": "#e0662a", "money": "rgba(217, 164, 65, 0.9)" })
        property string clockStyle: "1e"   // a non-default pick so the card shows active
    }
    // stand-in for the launcher settings JsonAdapter (feature flags + dirs)
    QtObject {
        id: mockSettings
        property bool orgAgendaEnabled: true
        property string orgAgendaDir: "~/org"
        property bool financeEnabled: true
        property string financeDir: "~/Documents/finance"
        property bool habitsEnabled: true
        property string habitsDir: "~/Documents/habits"
        property bool updatesEnabled: true
        property var updateSources: ["pacman", "flatpak"]
        property string updatesDir: ""
        // Disk window (DiskState reads these; the plan is seeded per stage)
        property var diskProjectDirs: []
        property var diskGameDirs: []
        property int diskStaleDays: 180
        property bool diskDiscreet: false
        property var diskPlan: []
        // Done page config (Settings › Productivity)
        property var productivityDirs: ["~/Documents/projects/awesome", "~/Documents/projects/teamwork", "~/work/shledger"]
        property var productivityEmails: ["you@example.com", "you@work.dev"]
        // seed a few emoji favourites so the picker opens on its Favorites tab
        property var emojiFavorites: ["😀", "🔥", "❤️", "🎉", "👍", "🚀", "😂", "✅"]
        // seed a mid-game Tetris so the screenshot shows a real stack, not an empty well
        property var tetris: ({
            "board": (function () {
                var b = [];
                for (var r = 0; r < 20; r++) {
                    var row = [];
                    for (var c = 0; c < 10; c++)
                        row.push((r >= 15 && !((r + c) % 4 === 0 && c > 5)) ? ["I","J","L","O","S","T","Z"][(r + c) % 7] : "");
                    b.push(row);
                }
                return b;
            })(),
            "cur": { "type": "T", "rot": 0, "x": 4, "y": 2 },
            "queue": ["I", "L", "S", "Z"],
            "bag": ["O", "J"],
            "score": 1240, "lines": 7, "level": 1, "high": 3200,
            "over": false, "paused": false
        })
        // seed a mid-game Block Blast so the screenshot shows a real board + tray
        property var blockBlast: ({
            "board": (function () {
                var b = [];
                var fill = ["i4", "sq2", "jL", "tT", "sS", "cl2", "cl3", "d3"];
                for (var r = 0; r < 10; r++) {
                    var row = [];
                    for (var c = 0; c < 10; c++)
                        row.push(((r + c) % 3 === 0 && !(r === 4 && c > 5)) ? fill[(r * 10 + c) % fill.length] : "");
                    b.push(row);
                }
                return b;
            })(),
            "tray": [
                { "kind": "jL", "cells": [[0,0],[0,1],[1,1],[2,1]] },
                { "kind": "sq3", "cells": [[0,0],[1,0],[2,0],[0,1],[1,1],[2,1],[0,2],[1,2],[2,2]] },
                { "kind": "d2", "cells": [[0,0],[1,0]] }
            ],
            "score": 860, "best": 2140, "combo": 3, "over": false
        })
        // seed a mid-game Snake with a bulge (eaten apple) partway down the body. Head
        // points right into a long runway so it survives the ~800ms grab window when
        // the harness unpauses it (see cSnake).
        property var snake: ({
            "body": [
                { "x": 7, "y": 7 }, { "x": 6, "y": 7 }, { "x": 5, "y": 7 },
                { "x": 4, "y": 7 }, { "x": 3, "y": 7 }, { "x": 2, "y": 7 }
            ],
            "bulges": [ { "x": 4, "y": 7 } ],
            "dir": { "x": 1, "y": 0 },
            "apple": { "x": 11, "y": 3 },
            "score": 14, "best": 22, "over": false
        })
        property var minesweeper: ({ "diff": 0, "best": [ 42, 0, 0 ] })
        // seed a mid-game Brick Breaker (round 12): a wall of mixed-health bricks
        // with a few specials so the palette + legend icons show
        property var brickBreaker: ({
            "grid": (function () {
                var g = [];
                var specs = { "3": "spray", "8": "explode", "16": "addball", "22": "spray" };
                for (var r = 0; r < 10; r++) {
                    var row = [];
                    for (var c = 0; c < 6; c++) {
                        var i = r * 6 + c;
                        if (r < 5 && (i % 4 !== 1 || r === 0)) {
                            var hp = 12 - r * 2 - (c % 3);
                            row.push({ "hp": hp, "max": hp, "special": specs[String(i)] || "" });
                        } else
                            row.push(null);
                    }
                    g.push(row);
                }
                return g;
            })(),
            "round": 12, "balls": 14, "launchX": 180, "over": false, "best": 18
        })
        // seed a mid-run Chicken Invaders (wave 4, bullet path, a few picks) so the
        // formation shows tinted multi-hp chickens and the sidebar loadout renders
        property var invaders: ({
            "wave": 4, "score": 385, "hp": 3, "maxHp": 4,
            "path": "bullet",
            "lv": { "count": 2, "rapid": 1, "plating": 1, "evasion": 1 },
            "picks": 6, "draft": false, "over": false,
            "best": { "score": 1210, "wave": 9 }
        })
    }

    // stand-in for DoneState (seeded CODE + AGENDA data, no bridge calls)
    MockDone { id: mockDone }

    // stand-in for HabitState (pinned 8-week habiq jungle, no bridge calls)
    MockHabits { id: mockHabits }

    // ---- system updates: seed a real UpdateState (its bridge is neutered by
    // shoot.sh, so nothing runs) into one of the designed situations ----
    readonly property var updPkgs: [
        { name: "openssl", old: "3.6.1-1", "new": "3.6.2-1", cls: "required", restart: "", source: "pacman", advisory: { id: "AVG-2901", severity: "High" } },
        { name: "firefox", old: "158.0-1", "new": "158.0.2-1", cls: "required", restart: "", source: "pacman", advisory: { id: "AVG-2903", severity: "Critical" } },
        { name: "linux", old: "7.2.14.arch1-1", "new": "7.2.16.arch1-1", cls: "recommended", restart: "reboot", source: "pacman" },
        { name: "systemd", old: "260.1-1", "new": "260.2-1", cls: "recommended", restart: "reboot", source: "pacman" },
        { name: "mesa", old: "1:26.2.0-1", "new": "1:26.2.1-1", cls: "recommended", restart: "relogin", source: "pacman" },
        { name: "kwin", old: "6.7.1-1", "new": "6.7.2-1", cls: "recommended", restart: "relogin", source: "pacman" },
        { name: "quickshell", old: "0.3.0-1", "new": "0.3.1-1", cls: "recommended", restart: "pill", source: "pacman" },
        { name: "pipewire", old: "1:1.6.2-1", "new": "1:1.6.3-1", cls: "recommended", restart: "relogin", source: "pacman" },
        { name: "ripgrep", old: "15.1.0-1", "new": "15.2.0-1", cls: "optional", restart: "", source: "pacman" },
        { name: "imagemagick", old: "7.1.2.8-1", "new": "7.1.2.9-1", cls: "optional", restart: "", source: "pacman" },
        { name: "python-rich", old: "14.2.0-1", "new": "14.3.0-1", cls: "optional", restart: "", source: "pacman" },
        { name: "org.telegram.desktop", title: "Telegram", old: "", "new": "7.3.3", cls: "optional", restart: "", source: "flatpak" },
        { name: "yay", old: "13.0.1-1", "new": "13.1.0-1", cls: "optional", restart: "", source: "aur" }
    ]
    readonly property var updPhases: [
        { key: "sync", label: "Sync", state: "done", detail: "" },
        { key: "resolve", label: "Resolve", state: "done", detail: "" },
        { key: "download", label: "Download", state: "done", detail: "612.00 MiB" },
        { key: "install", label: "Install", state: "active", detail: "18 / 45" },
        { key: "hooks", label: "Hooks", state: "todo", detail: "" },
        { key: "flatpak", label: "Flatpak", state: "todo", detail: "4 apps" }
    ]
    function updRun(status, prompt) {
        var asking = status === "asking";
        var ph = JSON.parse(JSON.stringify(win.updPhases));
        if (asking) {
            ph[1].state = "active"; ph[1].detail = "1 question";
            ph[2].state = "todo"; ph[3].state = "todo"; ph[3].detail = "";
        }
        return { id: "2026-07-22_0941", dir: "/home/you/.local/state/pill/updates/2026-07-22_0941",
            status: status, phase: asking ? "resolve" : "install", phases: ph,
            pkgIndex: asking ? 0 : 18, pkgTotal: 45, dlDone: 45, dlTotal: 45, hookIndex: 0, hookTotal: 0,
            current: asking ? "" : "mesa", percent: asking ? 6 : 58, prompt: prompt || null, promptN: prompt ? 1 : 0,
            canStop: asking, startedAt: 1784698860,
            logTail: asking ? [":: Synchronizing package databases...", ":: Starting full system upgrade..."]
                : [":: Processing package changes...", "upgrading firefox...", "upgrading openssl...", "upgrading glib2...",
                   "upgrading libdrm...", "upgrading llvm-libs...", "upgrading mesa..."] };
    }
    readonly property var updAskReplace: ({ kind: "replace", tone: "ask", label: "Replace", n: 1, simple: true,
        title: "Swap jack2 for pipewire-jack?", raw: ":: Replace jack2 with extra/pipewire-jack? [Y/n]",
        kv: [["Goes", "jack2 1.9.22-2"], ["Comes", "extra/pipewire-jack"], ["Used by", "ardour, carla, qpwgraph"]],
        options: [{ id: "y", label: "Yes, replace", "default": true, danger: false },
                  { id: "n", label: "No, keep jack2", "default": false, danger: false }] })
    readonly property var updAskKey: ({ kind: "key", tone: "danger", label: "New key · not recognised", n: 1, simple: false,
        title: "This key is not a known Arch packager.", checkOk: false,
        raw: ":: Import PGP key 9A1B22C3D4E5F607, \"unknown <repo@example.org>\"? [Y/n]",
        kv: [["Key", "unknown <repo@example.org>"], ["Key ID", "9A1B22C3D4E5F607"],
             ["Check", "not in the installed Arch keyring"], ["Advice", "stop and verify the fingerprint yourself"]],
        options: [{ id: "n", label: "No, stop update", "default": true, danger: false },
                  { id: "y", label: "Yes, import anyway", "default": false, danger: true }] })
    function updHistory(extra) {
        var t = 1784698860;
        var h = [
            { kind: "check", id: "check-1", at: t - 1740, total: 12, level: "required", required: 2, recommended: 6, optional: 4, bytes: 641728512, restart: "reboot", hold: 0 },
            { kind: "check", id: "check-2", at: t - 45000, total: 9, level: "recommended", required: 0, recommended: 5, optional: 4, bytes: 520000000, restart: "reboot", hold: 0 },
            { kind: "check", id: "check-3", at: t - 88000, total: 4, level: "optional", required: 0, recommended: 0, optional: 4, bytes: 9000000, restart: "", hold: 0 },
            { kind: "update", id: "2026-07-13_2240", at: t - 9 * 86400, status: "done", updated: 112, seconds: 372, restart: "reboot",
              restartReasons: [], warnings: [], pacnew: [], error: "", errorKind: "", flatpak: 3,
              dir: "/home/you/.local/state/pill/updates/2026-07-13_2240", phases: [], logTail: [], pkgIndex: 112, pkgTotal: 112 }
        ];
        return extra ? [extra].concat(h) : h;
    }
    function seedUpd(u, variant) {
        u.ready = true;
        u.checkedAt = 1784698860000 - 1740000;
        u.nextAt = u.checkedAt + 12 * 3600000;
        u.level = "required";
        u.counts = { required: 2, recommended: 6, optional: 4, total: 12 };
        u.packages = win.updPkgs;
        u.restart = "reboot";
        u.downloadBytes = 641728512;
        u.daysBehind = 9;
        u.stateDir = "/home/you/.local/state/pill/updates";
        u.sourceRows = [
            { key: "pacman", label: "pacman", desc: "official repos · asks for your password", icon: "deployed_code", count: 11, available: true, enabled: true, togglable: true, failed: false },
            { key: "flatpak", label: "flatpak", desc: "apps · no password", icon: "apps", count: 1, available: true, enabled: true, togglable: true, failed: false },
            { key: "aur", label: "aur · yay", desc: "builds from source, can ask questions · opens in a terminal", icon: "construction", count: 1, available: true, enabled: false, togglable: false, failed: false },
            { key: "firmware", label: "firmware", desc: "fwupd not installed · appears if you add it", icon: "memory", count: 0, available: false, enabled: false, togglable: false, failed: false }
        ];
        u.history = win.updHistory(null);
        if (variant === "hold")
            u.hold = [{ title: "linux-firmware requires manual intervention", link: "https://archlinux.org/news/", at: 1784598860 }];
        else if (variant === "running") u.run = win.updRun("running", null);
        else if (variant === "ask") u.run = win.updRun("asking", win.updAskReplace);
        else if (variant === "key") u.run = win.updRun("asking", win.updAskKey);
        else if (variant === "done" || variant === "failed") {
            var ok = variant === "done";
            var e = { kind: "update", id: "2026-07-22_0941", at: 1784698860, status: ok ? "done" : "failed",
                updated: ok ? 45 : 0, seconds: 252, restart: ok ? "reboot" : "",
                restartReasons: ok ? [{ name: "linux", level: "reboot" }, { name: "systemd", level: "reboot" }, { name: "mesa", level: "relogin" }] : [],
                warnings: ok ? ["warning: /etc/mkinitcpio.conf installed as /etc/mkinitcpio.conf.pacnew"] : [],
                pacnew: ok ? [{ file: "/etc/mkinitcpio.conf", "new": "/etc/mkinitcpio.conf.pacnew" }] : [],
                error: ok ? "" : "error: failed to commit transaction (conflicting files)\nfoo: /usr/lib/libfoo.so exists in filesystem",
                errorKind: ok ? "" : "conflict", flatpak: ok ? 1 : 0,
                dir: "/home/you/.local/state/pill/updates/2026-07-22_0941",
                phases: win.updPhases.map(function (p) {
                    return { key: p.key, label: p.label, detail: (ok && p.key === "install") ? "45 / 45" : p.detail,
                             state: ok ? "done" : (p.key === "install" || p.key === "hooks" || p.key === "flatpak") ? "todo" : "done" }; }),
                logTail: ok ? ["upgrading systemd...", "upgrading mesa...", ":: Running post-transaction hooks...", "(12/12) Updating the desktop file MIME type cache..."]
                            : ["checking for file conflicts...", "error: failed to commit transaction (conflicting files)", "foo: /usr/lib/libfoo.so exists in filesystem", "Errors occurred, no packages were upgraded."],
                pkgIndex: ok ? 45 : 0, pkgTotal: 45 };
            u.history = win.updHistory(e);
            if (ok) {
                u.pendingRestart = { level: "reboot", reasons: e.restartReasons, run: e.id };
                u.level = "none"; u.counts = { required: 0, recommended: 0, optional: 0, total: 0 }; u.packages = [];
            }
        }
    }
    component UpdHost: MenuHost {
        id: uh
        property string variant: "pending"
        pillW: 860; pillH: 580
        UpdateState { id: uhState; enabled: true; Component.onCompleted: win.seedUpd(uhState, uh.variant) }
        UpdatesMenu { anchors.fill: parent; theme: theme; upd: uhState }
    }
    // ---- the Disk window's content (DiskView) on the invented demo scan
    //      (pill/diskdemo.json — see tests/make_diskdemo.py). The real DiskState
    //      is used; its bridge is neutered by shoot.sh, so nothing is scanned. ----
    FileView { id: diskDemoFile; path: Qt.resolvedUrl("diskdemo.json"); blockLoading: true }
    function seedDisk(d, view, variant) {
        d._loadScan(JSON.parse(diskDemoFile.text()));
        var best = d.overview.best;
        d.plan = best.slice(0, 4);
        if (variant === "projects") { d.page = "projects"; Qt.callLater(function () {
            var p = d.sections.projects.projects[0]; view.pageItem.sel = p; view.pageItem.selItem = p.items[0]; }); }
        else if (variant === "caches") { d.page = "caches"; Qt.callLater(function () { view.pageItem.sel = view.pageItem.entries[1].r; }); }
        else if (variant === "games") { d.discreet = true; d.page = "games"; }
        else if (variant === "files") {
            var H = d.disk.home, rows = [], src = d.sections.home.top;
            for (var i = 0; i < src.length; i++)
                rows.push({ name: src[i].name, path: src[i].path, dir: true, link: "", mode: "drwxr-xr-x", bytes: src[i].bytes, mtime: src[i].newest, kind: "dir", partial: false, cached: true });
            rows.push({ name: "node_modules", path: H + "/node_modules", dir: true, link: "", mode: "drwxr-xr-x", bytes: 3.4e9, mtime: src[0].newest - 4e7, kind: "deps", partial: false, cached: false });
            rows.push({ name: "holiday-2019.mkv", path: H + "/holiday-2019.mkv", dir: false, link: "", mode: "-rw-r--r--", bytes: 6.1e9, mtime: src[0].newest - 9e7, kind: "video", partial: false, cached: false });
            rows.push({ name: "old-backup.tar.zst", path: H + "/old-backup.tar.zst", dir: false, link: "", mode: "-rw-r--r--", bytes: 2.2e9, mtime: src[0].newest - 6e7, kind: "archive", partial: false, cached: false });
            d.listing = { path: H, parent: "/home", rows: rows, bytes: 3.4e11, error: "" };
            d.flagged = [H + "/node_modules", H + "/old-backup.tar.zst"];
            d.page = "files";
        }
        else if (variant === "review" || variant === "done") {
            // one item of every risk tier, as `diskbridge.py verify` would answer
            var want = { free: 2, cost: 2, state: 1, data: 2 }, items = [], ids = [], bytes = 0;
            var keys = Object.keys(d.items).sort(function (a, b) { return d.items[b].bytes - d.items[a].bytes; });
            for (var k = 0; k < keys.length; k++) {
                var it = d.items[keys[k]];
                if (!want[it.tier] || it.kind === "project") continue;
                want[it.tier]--;
                var v = Object.assign({}, it, { status: "ok", reason: "", bytes_now: it.bytes });
                items.push(v); ids.push(it.id); bytes += it.bytes;
            }
            d.plan = ids;
            d.page = "plan";
            if (variant === "review")
                d.review = { token: "demo", items: items, missing: [], bytes: bytes,
                             script: "#!/bin/sh\n# Cleanup plan from the pill's Disk window\nset -eu\n\n" + items.map(function (x) { return "# " + x.title + "\n" + x.cmd; }).join("\n") };
            else
                d.result = { ok: true, freed: bytes * 0.9, free: d.disk.main.free + bytes * 0.9, report: "/home/you/.local/state/pill/disk/reports/2026-11-14_101500.md",
                             results: items.map(function (x, n) { return { id: x.id, title: x.title, sub: x.sub, tier: x.tier, method: x.method, bytes: x.bytes,
                                 status: x.method === "terminal" ? "manual" : n === 3 ? "skipped" : x.method === "trash" ? "trashed" : x.method === "cmd" ? "ran" : "removed",
                                 detail: x.method === "terminal" ? "run in a terminal: " + x.cmd : n === 3 ? "no longer looks like a dependency folder" : "" }; }) };
        }
        else d.page = "overview";
    }
    component DiskHost: Item {
        id: dh
        property string variant: "overview"
        width: 1220; height: 780
        DiskState { id: dhState; settings: mockSettings; Component.onCompleted: win.seedDisk(dhState, dhView, dh.variant) }
        DiskView { id: dhView; anchors.fill: parent; theme: theme; disk: dhState }
    }
    // one resting pill wearing the lip in a given mood
    component LipPill: Item {
        id: lp
        property string mood: "none"
        property real progress: 0
        property bool ask: false
        width: 210; height: ask ? 48 : 30
        PillSurface {
            id: lpSurf
            anchors.fill: parent; theme: theme
            radius: Math.min(theme.radiusPanel, height / 2); wing: 12
            fillColor: theme.bgTranslucent
        }
        UpdateLip {
            anchors.fill: lpSurf; theme: theme
            radius: lpSurf.radius; wing: 12
            mood: lp.mood; progress: lp.progress
        }
        CollapsedPill {
            anchors.centerIn: parent; theme: theme
            clock: win.clockShort; updateAsk: lp.ask
        }
    }

    // mock clock strings so the dashboard is deterministic
    readonly property string clockShort: "09:41"
    readonly property string clockDate:  "WED, 22 JUL"

    // ---- a pill-shaped host for an open menu (bg surface + padded content area) ----
    component MenuHost: Item {
        id: host
        property int pillW: 520
        property int pillH: 470
        default property alias content: inner.data
        width: pillW
        height: pillH
        PillSurface {
            anchors.fill: parent
            anchors.leftMargin: -34
            anchors.rightMargin: -34
            theme: theme
            radius: theme.radiusPanel
            wing: 34
            fillColor: theme.bg
        }
        Item { id: inner; anchors.fill: parent; anchors.margins: theme.pad }
    }

    // ======================= gallery states =======================
    // SHOT_ONLY (env) renders just the states whose name contains this substring,
    // skipping the rest instantly — a fast single-target loop while iterating on one
    // pane. Empty = render everything (the full regression pass; run this when done).
    property string only: (Quickshell.env("SHOT_ONLY") || "")
    property int _shot: -1
    property var _states: [
        { name: "resting",       comp: cResting },
        { name: "resting-rec",   comp: cRestingRec },
        { name: "resting-due",   comp: cRestingDue },
        { name: "resting-meeting", comp: cRestingMeeting },
        { name: "clock-styles",  comp: cClockStyles },
        { name: "deadlines",     comp: cDeadlines },
        { name: "dashboard",     comp: cDashboard },
        { name: "menu-network",  comp: cNet },
        { name: "menu-volume",   comp: cVol },
        { name: "menu-bluetooth", comp: cBt },
        { name: "menu-battery",  comp: cBatt },
        { name: "menu-clipboard", comp: cClip },
        { name: "menu-calendar", comp: cCal },
        { name: "menu-finance", comp: cFin },
        { name: "menu-finance-add", comp: cFinAdd },
        { name: "menu-finance-wishlist", comp: cFinWish },
        { name: "menu-finance-forecast", comp: cFinFore },
        { name: "menu-finance-plan", comp: cFinPlan },
        { name: "menu-finance-register", comp: cFinReg },
        { name: "menu-finance-category", comp: cFinCat },
        { name: "menu-games",    comp: cGames },
        { name: "menu-tetris",   comp: cTetris },
        { name: "menu-tetris-share", comp: cTetrisShare },
        { name: "menu-blockblast", comp: cBlockBlast },
        { name: "menu-blockblast-combo", comp: cBlockBlastCombo },
        { name: "menu-blockblast-share", comp: cBlockBlastShare },
        { name: "menu-brickbreaker", comp: cBrick },
        { name: "menu-snake",    comp: cSnake },
        { name: "menu-minesweeper", comp: cMine },
        { name: "menu-invaders", comp: cInvaders },
        { name: "menu-invaders-draft", comp: cInvadersDraft },
        { name: "menu-invaders-path", comp: cInvadersPath },
        { name: "menu-invaders-laser", comp: cInvadersLaser },
        { name: "menu-invaders-vapor", comp: cInvadersVapor },
        { name: "menu-habits",   comp: cHabits },
        { name: "menu-habits-dialog", comp: cHabitsDialog },
        { name: "menu-habits-dialog-bool", comp: cHabitsDialogBool },
        { name: "menu-habits-edit", comp: cHabitsEdit },
        { name: "menu-habits-freeze", comp: cHabitsFreeze },
        { name: "menu-habits-datepicker", comp: cHabitsDatepicker },
        { name: "datefield", comp: cDateFieldView },
        { name: "menu-habits-frozenweek", comp: cHabitsFrozen },
        { name: "settings",      comp: cSettings },
        { name: "settings-productivity", comp: cSettingsProd },
        { name: "menu-emoji",    comp: cEmoji },
        { name: "menu-emoji-search", comp: cEmojiSearch },
        { name: "resting-updates", comp: cRestingUpdates },
        { name: "dashboard-updates", comp: cDashUpdates },
        { name: "notif-updates", comp: cNotifUpdates },
        { name: "menu-updates",  comp: cUpdates },
        { name: "menu-updates-hold", comp: cUpdatesHold },
        { name: "menu-updates-run", comp: cUpdatesRun },
        { name: "menu-updates-ask", comp: cUpdatesAsk },
        { name: "menu-updates-key", comp: cUpdatesKey },
        { name: "menu-updates-done", comp: cUpdatesDone },
        { name: "menu-updates-failed", comp: cUpdatesFailed },
        { name: "disk-overview", comp: cDiskOverview },
        { name: "disk-projects", comp: cDiskProjects },
        { name: "disk-caches", comp: cDiskCaches },
        { name: "disk-games-veiled", comp: cDiskGames },
        { name: "disk-files", comp: cDiskFiles },
        { name: "disk-review", comp: cDiskReview },
        { name: "disk-done", comp: cDiskDone },
        { name: "menu-done",     comp: cDone },
        { name: "menu-done-loading", comp: cDoneLoading },
        { name: "menu-notifhistory", comp: cNotifHist },
        { name: "notif-stack",   comp: cNotifStack },
        { name: "power-hush",    comp: cPowerHush },
        { name: "power-blaze",   comp: cPowerBlaze },
        { name: "power-ledger",  comp: cPowerLedger },
        { name: "power-split",   comp: cPowerSplit }
    ]

    Loader { id: stage; anchors.centerIn: parent }

    function _next() {
        win._shot++;
        if (win._shot >= win._states.length) { Qt.quit(); return; }
        // SHOT_ONLY: skip non-matching states with no grab delay (keeps the same
        // _shot index, so filenames match a full run — e.g. pill-17-menu-tetris.png)
        if (win.only && win._states[win._shot].name.indexOf(win.only) < 0) { Qt.callLater(win._next); return; }
        stage.sourceComponent = win._states[win._shot].comp;
        grabTimer.restart();
    }
    Timer { id: startTimer; interval: 900; running: true; onTriggered: win._next() }
    Timer {
        id: grabTimer; interval: 800; repeat: false     // room for entrance animations
        onTriggered: {
            var it = stage.item;
            var s = win._states[win._shot];
            if (!it) { Qt.callLater(win._next); return; }
            it.grabToImage(function (res) {
                res.saveToFile(win.outDir + "/pill-" + win._shot + "-" + s.name + ".png");
                Qt.callLater(win._next);
            }, Qt.size(Math.ceil(it.width * 2), Math.ceil(it.height * 2)));
        }
    }

    // ---------------- resting collapsed pill ----------------
    Component {
        id: cResting
        Item {
            width: 168; height: 30
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort; hasUnread: true
                notifGroups: notifs.grouped; iconsMax: 4
            }
        }
    }
    // resting with a live screen-recording (solid + red pulse dot + unread)
    Component {
        id: cRestingRec
        Item {
            width: 150; height: 30
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bg
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort; solid: true; recordingOn: true; cameraOn: true
                // a screencast auto-enters DND → app strip hidden, generic dot shown
                dnd: true; hasUnread: true; notifGroups: notifs.grouped; iconsMax: 4
            }
        }
    }

    // resting pill with an org-deadline under-line (overdue + due-today counts).
    // Taller pill, 2px-smaller clock, "⚑ N LATE · M TODAY" beneath it.
    Component {
        id: cRestingDue
        Item {
            width: 360; height: 48
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort
                lateCount: org.lateCount; todayCount: org.todayCount
                // combined with an imminent meeting to show the full under-line
                meetingMins: 7
            }
        }
    }
    // resting pill with only an imminent-meeting notice (no deadlines) —
    // "⚑-free" under-line: just the calendar icon + "N MIN TO MEETING".
    Component {
        id: cRestingMeeting
        Item {
            width: 200; height: 48
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            CollapsedPill {
                anchors.centerIn: parent; theme: theme
                clock: win.clockShort
                meetingMins: 3
            }
        }
    }
    // every collapsed-clock design (Settings → Appearance → Clock and Agenda),
    // each shown resting (clock only) and with a sample agenda under-line. Each pill
    // is sized by the SAME dynamic rule init.qml uses for the real resting pill —
    // width = max(56, content + 23), height = max(28|48, content + 7) — so the
    // screenshot shows whether every style actually fits (no overflow, no cramping).
    // A dashed keyline traces each pill so any clipping is obvious.
    Component {
        id: cClockStyles
        // one sized pill hosting a CollapsedPill, mirroring init's resting bindings
        component StylePill: Item {
            id: sp
            property string styleId: "1a"
            property bool due: false
            width: Math.max(56, cp.implicitWidth + 23)
            height: Math.max(sp.due ? 48 : 28, cp.implicitHeight + 7)
            PillSurface {
                anchors.fill: parent; theme: theme
                radius: Math.min(theme.radiusPanel, height / 2); wing: 12
                fillColor: theme.bgTranslucent
            }
            // keyline exactly on the pill bounds — content spilling past it = overflow
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Math.min(theme.radiusPanel, height / 2)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
            }
            CollapsedPill {
                id: cp
                anchors.centerIn: parent; theme: theme
                styleOverride: sp.styleId
                clock: "09:41"
                lateCount: sp.due ? 1 : 0
                todayCount: sp.due ? 1 : 0
                meetingMins: sp.due ? 10 : -1
            }
        }
        Rectangle {
            width: 720
            color: theme.desk
            implicitHeight: stylesCol.height + 32
            Column {
                id: stylesCol
                x: 16; y: 16
                width: parent.width - 32
                spacing: 14
                Repeater {
                    model: theme.clockStyles
                    delegate: Row {
                        required property var modelData
                        spacing: 20
                        Text {
                            width: 168
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.id + " · " + modelData.name
                            color: theme.textDim
                            font.family: theme.family
                            font.pixelSize: 13
                        }
                        StylePill {
                            anchors.verticalCenter: parent.verticalCenter
                            styleId: modelData.id
                        }
                        StylePill {
                            anchors.verticalCenter: parent.verticalCenter
                            styleId: modelData.id
                            due: true
                        }
                    }
                }
            }
        }
    }

    // the floating agenda list (right-click / under-line target): org deadlines + events
    Component {
        id: cDeadlines
        Item {
            width: 420; height: 980
            AgendaMenu {
                // bodyMax raised so the whole list (deadlines + events) shows in the
                // still; live it stays capped and scrolls.
                anchors.fill: parent; theme: theme; org: org; cal: cal
                bodyMax: 1200
                open: true; px: 8; py: 8
            }
        }
    }

    // ---------------- hovered dashboard (two rows) ----------------
    Component {
        id: cDashboard
        Item {
            id: dash
            width: 640; height: 150
            PillSurface {
                anchors.fill: parent; anchors.leftMargin: -34; anchors.rightMargin: -34
                theme: theme; radius: theme.radiusPanel; wing: 34; fillColor: theme.bg
            }
            // Row 1: datetime + desktop dots (left) | taskbar (right)
            Item {
                x: theme.pad + 8; y: 20
                width: dash.width - (theme.pad + 8) * 2; height: 36
                Column {
                    anchors.left: parent.left; anchors.top: parent.top
                    anchors.topMargin: -10; spacing: 9
                    Item {
                        implicitWidth: dtColMock.implicitWidth; implicitHeight: dtColMock.implicitHeight
                        Column {
                            id: dtColMock
                            spacing: 1
                            Text { id: clockTimeMock; text: win.clockShort; color: theme.text; font.family: theme.serif; font.pixelSize: 34; lineHeight: 0.9 }
                            Text { text: win.clockDate; color: theme.textDim; font.family: theme.mono
                                   font.pixelSize: theme.fsSmall; font.letterSpacing: theme.labelSpacing
                                   font.capitalization: Font.AllUppercase; lineHeight: 0.95 }
                        }
                        // two tiny game buttons stacked beside the clock (mirrors init.qml):
                        // S-tetromino (Tetris) over plus/T (Block Blast)
                        Column {
                            anchors.left: dtColMock.right; anchors.leftMargin: 12
                            anchors.verticalCenter: clockTimeMock.verticalCenter
                            spacing: 4
                            Rectangle {
                                width: 26; height: 26; radius: theme.radiusSmall; color: "transparent"
                                Item {
                                    id: tetGlyphMock
                                    anchors.centerIn: parent; width: 15; height: 10
                                    readonly property int u: 5
                                    Repeater {
                                        model: [[1,0],[2,0],[0,1],[1,1]]
                                        delegate: Rectangle {
                                            required property var modelData
                                            x: modelData[0] * tetGlyphMock.u; y: modelData[1] * tetGlyphMock.u
                                            width: tetGlyphMock.u - 1; height: tetGlyphMock.u - 1; radius: 1; color: theme.accent
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: 26; height: 26; radius: theme.radiusSmall; color: "transparent"
                                Item {
                                    id: blockGlyphMock
                                    anchors.centerIn: parent; width: 15; height: 10
                                    readonly property int u: 5
                                    Repeater {
                                        model: [[1,0],[0,1],[1,1],[2,1]]
                                        delegate: Rectangle {
                                            required property var modelData
                                            x: modelData[0] * blockGlyphMock.u; y: modelData[1] * blockGlyphMock.u
                                            width: blockGlyphMock.u - 1; height: blockGlyphMock.u - 1; radius: 1; color: theme.accent
                                        }
                                    }
                                }
                            }
                        }
                    }
                    DesktopDots {
                        theme: theme
                        desktops: [{ id: "1", name: "one" }, { id: "2", name: "two" },
                                   { id: "3", name: "three" }, { id: "4", name: "four" }]
                        activeIdx: 1
                    }
                }
                Taskbar {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    theme: theme
                    activeWindow: "w-code"
                    groups: [
                        { key: "pin:firefox", icon: "firefox", entry: null, wins: [{ uuid: "w-ff" }], desks: [], onAll: false, pinned: true },
                        { key: "win:code", icon: "visual-studio-code", entry: null,
                          wins: [{ uuid: "w-code" }, { uuid: "w-code2" }], desks: [], onAll: false, pinned: false },
                        { key: "win:kitty", icon: "kitty", entry: null, wins: [{ uuid: "w-kitty" }], desks: [], onAll: false, pinned: false },
                        { key: "pin:telegram", icon: "telegram", entry: null, wins: [], desks: [], onAll: false, pinned: true }
                    ]
                }
            }
            // divider
            Rectangle { x: theme.pad + 8 + 60; y: 86; width: dash.width - (theme.pad + 8) - x; height: 1; color: theme.divider }
            // Row 2: launcher glyph (left) | status icons (right)
            Item {
                x: theme.pad + 8; y: 100
                width: dash.width - (theme.pad + 8) * 2; height: 42
                Rectangle {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: 42; height: 42; radius: 12; color: theme.accentSoft
                    MSym { anchors.centerIn: parent; icon: "grid_view"; size: 22; fill: 1; weight: 500; color: theme.accent }
                }
                StatusIcons {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    theme: theme; notifs: notifs; netState: netState; open: true; menu: 0
                }
            }
        }
    }

    // ---------------- menus ----------------
    Component { id: cNet;  MenuHost { NetworkMenu   { anchors.fill: parent; theme: theme; netState: netState } } }
    Component { id: cVol;  MenuHost { VolumeMenu    { anchors.fill: parent; theme: theme } } }
    Component { id: cBt;   MenuHost { BluetoothMenu { anchors.fill: parent; theme: theme } } }
    Component { id: cBatt; MenuHost { BatteryMenu   { anchors.fill: parent; theme: theme; brightness: brightness } } }
    Component { id: cClip; MenuHost { pillH: 670; ClipboardMenu { anchors.fill: parent; theme: theme; clip: clip; memos: memos } } }
    Component { id: cCal;  MenuHost { pillW: 760; CalendarMenu  { anchors.fill: parent; theme: theme; org: org; fin: fin; cal: cal } } }
    Component { id: cFin;  MenuHost { pillW: 760; FinanceMenu   { anchors.fill: parent; theme: theme; fin: fin } } }
    Component { id: cTetris; MenuHost { pillW: 480; pillH: 556; TetrisMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    // Tetris with the screenshot share card up (shareMode toggled after load; no grab
    // Process runs — this just previews the pretty card layout).
    Component { id: cTetrisShare; MenuHost { pillW: 480; pillH: 556;
        TetrisMenu { id: tsh; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: { tsh.shotName = "tetris-20260806-101500.png"; tsh.shareMode = true; } }
    } }
    Component { id: cBlockBlast; MenuHost { pillW: 480; pillH: 556; BlockBlastMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    // Block Blast mid-combo-flare (fires popCombo ~450ms before the 800ms grab, so
    // the "3× COMBO" flare is caught at full pop). Preview only — no real drop.
    Component { id: cBlockBlastCombo; MenuHost { pillW: 480; pillH: 556;
        BlockBlastMenu { id: bcm; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 350; onTriggered: bcm.popCombo(3) }
    } }
    Component { id: cBlockBlastShare; MenuHost { pillW: 480; pillH: 556;
        BlockBlastMenu { id: bsh; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: { bsh.shotName = "blockblast-20260807-101500.png"; bsh.shareMode = true; } }
    } }
    // the Games picker (menu 11) — six cards with seeded best scores
    Component { id: cGames; MenuHost { pillW: 520; pillH: 524; GamesMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    // Brick Breaker between rounds (seeded round-12 wall; opens paused → unpaused
    // so the aim-ready field shows instead of the veil). Preview only.
    Component { id: cBrick; MenuHost { pillW: 576; pillH: 416;
        BrickBreakerMenu { id: brk; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: brk.paused = false }
    } }
    // Snake — unpaused after load so the field (snake + digesting lump + apple) is
    // visible rather than under the PAUSED veil. Preview only.
    Component { id: cSnake; MenuHost { pillW: 560; pillH: 400;
        SnakeMenu { id: snk; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: snk.paused = false }
    } }
    // Minesweeper — reveal a couple of cells after load so the field shows numbers /
    // flood-filled area rather than a blank grid. Preview only.
    Component { id: cMine; MenuHost { pillW: 560; pillH: 420;
        MinesweeperMenu { id: mine; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: { mine.reveal(20); mine.toggleFlag(0); } }
    } }
    // Chicken Invaders mid-wave (seeded wave-4 run; unpaused so the ~800ms grab
    // window catches the sweeping flock + autofire bullets). Preview only.
    Component { id: cInvaders; MenuHost { pillW: 772; pillH: 556;
        InvadersMenu { id: inv; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: inv.paused = false }
        // in-flight bullets don't reach the flock before the grab — inject a few
        // damage numbers so the still shows them mid-flight
        Timer { running: true; interval: 550; onTriggered: {
            inv.spawnDmg(inv.chickX(13), inv.chickY(13) - 10, 1);
            inv.spawnDmg(inv.chickX(15), inv.chickY(15) - 10, 1);
        } }
    } }
    // …its between-wave upgrade draft (three random bullet/ship cards)
    Component { id: cInvadersDraft; MenuHost { pillW: 772; pillH: 556;
        InvadersMenu { id: invd; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: invd.rollDraft() }
    } }
    // …the level-0 "arm your ship" path draft (fresh run, no seed)
    Component { id: cInvadersPath; MenuHost { pillW: 772; pillH: 556;
        QtObject { id: freshSet; property var invaders: ({}) }
        InvadersMenu { anchors.fill: parent; theme: theme; settings: freshSet }
    } }
    // …the laser path mid-beam (seeded run; the beam is forced on just before the
    // grab so the still catches it lit)
    Component { id: cInvadersLaser; MenuHost { pillW: 772; pillH: 556;
        QtObject {
            id: laserSet
            property var invaders: ({
                "wave": 5, "score": 520, "hp": 4, "maxHp": 4,
                "path": "laser", "lv": { "lwidth": 2, "luptime": 1, "plating": 1 },
                "picks": 5, "draft": false, "over": false,
                "best": { "score": 1210, "wave": 9 }
            })
        }
        InvadersMenu { id: invl; anchors.fill: parent; theme: theme; settings: laserSet }
        Timer { running: true; interval: 60; onTriggered: invl.paused = false }
        Timer { running: true; interval: 500; onTriggered: { invl.laserX = invl.shipX; invl.laserT = 400; invl.laserHits = ({}); } }
    } }
    // …the vapor path with two orbs mid-flight (injected so the still shows them)
    Component { id: cInvadersVapor; MenuHost { pillW: 772; pillH: 556;
        QtObject {
            id: vaporSet
            property var invaders: ({
                "wave": 5, "score": 470, "hp": 3, "maxHp": 3,
                "path": "vapor", "lv": { "vsize": 2, "vdmg": 1 },
                "picks": 4, "draft": false, "over": false,
                "best": { "score": 1210, "wave": 9 }
            })
        }
        InvadersMenu { id: invv; anchors.fill: parent; theme: theme; settings: vaporSet }
        Timer { running: true; interval: 60; onTriggered: invv.paused = false }
        Timer { running: true; interval: 350; onTriggered: invv.blobs = [
            { "x": invv.shipX, "y": invv.shipY - 130 },
            { "x": invv.shipX - 70, "y": invv.shipY - 290 }
        ] }
    } }
    // the launcher's Settings page (Org Agenda page shown: toggle + directory field)
    // the habit tracker (menu 19): the jungle over MockHabits' pinned report,
    // plus the per-habit dialog (books group → member switcher + history) and
    // the freeze dialog. The breeze clock runs live; the grab just catches one
    // sway frame.
    Component { id: cHabits; MenuHost { pillW: 860; pillH: 580; HabitMenu { anchors.fill: parent; theme: theme; habits: mockHabits } } }
    Component { id: cHabitsDialog; MenuHost { pillW: 860; pillH: 580;
        HabitMenu { id: habMenu; anchors.fill: parent; theme: theme; habits: mockHabits }
        Timer { running: true; interval: 60; onTriggered: habMenu.openHabit(mockHabits.report.rows[3]) }
    } }
    // bool habit (workout) dialog: done/missed as PillCheckboxes, no text value
    Component { id: cHabitsDialogBool; MenuHost { pillW: 860; pillH: 580;
        HabitMenu { id: habMenuB; anchors.fill: parent; theme: theme; habits: mockHabits }
        Timer { running: true; interval: 60; onTriggered: habMenuB.openHabit(mockHabits.report.rows[2]) }
    } }
    // the definition editor (Edit habit) prefilled from the workout directive
    Component { id: cHabitsEdit; MenuHost { pillW: 860; pillH: 580;
        HabitMenu { id: habMenuE; anchors.fill: parent; theme: theme; habits: mockHabits }
        Timer { running: true; interval: 60; onTriggered: habMenuE.editHabitId = "workout" }
    } }
    Component { id: cHabitsFreeze; MenuHost { pillW: 860; pillH: 580;
        HabitMenu { id: habMenuF; anchors.fill: parent; theme: theme; habits: mockHabits }
        Timer { running: true; interval: 60; onTriggered: habMenuF.freezeOpen = true }
    } }
    // standalone DateField exercise view: the reusable date input in a bare
    // form — rows around and BELOW the field, with the popover OPEN. Any
    // layout displacement caused by opening the calendar (the bug class where
    // the popup joined the Column flow) shows immediately against the fixed
    // reference rows.
    Component { id: cDateFieldView; MenuHost { pillW: 560; pillH: 470;
        Item {
            id: dfHost
            anchors.fill: parent
            Column {
                x: 20; y: 16
                spacing: 12
                Text { text: "DateField"; color: theme.text; font.family: theme.serif; font.pixelSize: 19 }
                Row {
                    spacing: 10
                    DateField { id: dfA; theme: theme; overlay: dfHost; label: "from"; text: "2026-09-12"; fieldWidth: 130 }
                    DateField { theme: theme; overlay: dfHost; label: "to"; fieldWidth: 130 }
                    HabitField { theme: theme; label: "note"; fieldWidth: 110; placeholder: "vacation" }
                }
                Row {
                    spacing: 10
                    DateField { theme: theme; overlay: dfHost; label: "locked"; text: "2026-09-01"; editable: false; fieldWidth: 130 }
                    HabitField { theme: theme; label: "value"; fieldWidth: 110; placeholder: "6:00" }
                }
                Rectangle { width: 380; height: 1; color: theme.divider }
                Text {
                    text: "reference rows — must not move while the popover is open"
                    color: theme.faint; font.family: theme.mono; font.pixelSize: theme.fsSmall
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: 8
                        Rectangle { width: 36; height: 22; radius: 6; color: theme.row; border.width: 1; border.color: theme.border }
                    }
                }
            }
            Timer { running: true; interval: 120; onTriggered: dfA.open = true }
        }
    } }
    // the freeze dialog with the "from" date-picker popover dropped open — proves
    // the reusable DateField calendar renders above the dialog content
    Component { id: cHabitsDatepicker; MenuHost { pillW: 860; pillH: 580;
        HabitMenu { id: habMenuD; anchors.fill: parent; theme: theme; habits: mockHabits }
        Timer {
            running: true; interval: 60
            onTriggered: {
                habMenuD.freezeOpen = true;
                openTimer.start();
            }
        }
        Timer {
            id: openTimer; interval: 120
            // reach into the freeze dialog's first DateField and open its calendar
            onTriggered: {
                var fd = _findDateField(habMenuD);
                if (fd) fd.open = true;
            }
            function _findDateField(obj) {
                if (!obj || !obj.children) return null;
                for (var i = 0; i < obj.children.length; i++) {
                    var c = obj.children[i];
                    if (c && c.hasOwnProperty("editable") && c.hasOwnProperty("open")) return c;
                    var deep = _findDateField(c);
                    if (deep) return deep;
                }
                return null;
            }
        }
    } }
    // scrolled to the W33 vacation week: snowed tiles/trees, the dead books
    // tree (W32) and green summer weeks below it
    Component { id: cHabitsFrozen; MenuHost { pillW: 860; pillH: 580;
        HabitMenu { id: habMenuS; anchors.fill: parent; theme: theme; habits: mockHabits }
        Timer { running: true; interval: 120; onTriggered: habMenuS.scrollToWeek(4) }
    } }
    Component { id: cSettings; MenuHost { pillW: 860; pillH: 580; SettingsMenu { anchors.fill: parent; theme: theme; acc: null; settings: mockSettings; themeSettings: mockThemeSettings; page: 0 } } }
    // the Productivity settings page (project dirs + author emails)
    Component { id: cSettingsProd; MenuHost { pillW: 860; pillH: 580; SettingsMenu { anchors.fill: parent; theme: theme; acc: null; settings: mockSettings; themeSettings: mockThemeSettings; page: 4 } } }
    // the emoji picker (menu 16) opened on its Favorites tab (mockSettings seeds a
    // few favourites), plus a search variant (Timer types a query post-load)
    Component { id: cEmoji; MenuHost { pillW: 600; pillH: 470; EmojiMenu { anchors.fill: parent; theme: theme; settings: mockSettings } } }
    Component { id: cEmojiSearch; MenuHost { pillW: 600; pillH: 470;
        EmojiMenu { id: emo; anchors.fill: parent; theme: theme; settings: mockSettings }
        Timer { running: true; interval: 60; onTriggered: emo.query = "heart" }
    } }
    // ---- the Disk manager window (not a menu: a real toplevel; DiskView is its content) ----
    Component { id: cDiskOverview; DiskHost { variant: "overview" } }
    Component { id: cDiskProjects; DiskHost { variant: "projects" } }
    Component { id: cDiskCaches;   DiskHost { variant: "caches" } }
    Component { id: cDiskGames;    DiskHost { variant: "games" } }
    Component { id: cDiskFiles;    DiskHost { variant: "files" } }
    Component { id: cDiskReview;   DiskHost { variant: "review" } }
    Component { id: cDiskDone;     DiskHost { variant: "done" } }
    // ---- system updates (menu 20 + the resting lip + the status icon) ----
    Component { id: cUpdates;       UpdHost { variant: "pending" } }
    Component { id: cUpdatesHold;   UpdHost { variant: "hold" } }
    Component { id: cUpdatesRun;    UpdHost { variant: "running" } }
    Component { id: cUpdatesAsk;    UpdHost { variant: "ask" } }
    Component { id: cUpdatesKey;    UpdHost { variant: "key" } }
    Component { id: cUpdatesDone;   UpdHost { variant: "done" } }
    Component { id: cUpdatesFailed; UpdHost { variant: "failed" } }
    // the update cards exactly as init.qml's updateNotify builds them for
    // Notifications.postLocal (critical = stays; non-default actions = buttons)
    Component {
        id: cNotifUpdates
        Item {
            width: 440; height: nuCol.implicitHeight + 20
            Column {
                id: nuCol
                anchors.centerIn: parent
                spacing: 10
                Repeater {
                    model: [
                        { id: "1", appName: "Updates", appIcon: "system-software-update", urgency: 2,
                          summary: "2 security updates", body: "openssl, firefox have a published fix. Updating today is advised.",
                          image: "", hints: ({}), hasInlineReply: false, inlineReplyPlaceholder: "",
                          actions: [{ identifier: "default", text: "Open", invoke: function() {} },
                                    { identifier: "local-0", text: "View", invoke: function() {} },
                                    { identifier: "local-1", text: "Update", invoke: function() {} }] },
                        { id: "1", appName: "Updates", appIcon: "system-software-update", urgency: 2,
                          summary: "Update is waiting for you", body: ":: Replace jack2 with extra/pipewire-jack? [Y/n]  Nothing has been changed yet.",
                          image: "", hints: ({}), hasInlineReply: false, inlineReplyPlaceholder: "",
                          actions: [{ identifier: "default", text: "Open", invoke: function() {} },
                                    { identifier: "local-0", text: "Yes, replace", invoke: function() {} },
                                    { identifier: "local-1", text: "No, keep jack2", invoke: function() {} }] },
                        { id: "1", appName: "Updates", appIcon: "system-software-update", urgency: 1,
                          summary: "47 updates are worth installing", body: "linux, systemd, mesa and more. Needs one reboot.",
                          image: "", hints: ({}), hasInlineReply: false, inlineReplyPlaceholder: "",
                          actions: [{ identifier: "default", text: "Open", invoke: function() {} },
                                    { identifier: "local-0", text: "View", invoke: function() {} }] }
                    ]
                    delegate: NotificationView {
                        required property var modelData
                        width: 420
                        theme: theme; notifs: notifs; notification: modelData
                        showProgress: modelData.urgency !== 2
                    }
                }
            }
        }
    }
    // every lip mood on a strip of "wallpaper", so the faint ones can be judged
    Component {
        id: cRestingUpdates
        Rectangle {
            width: 760; height: 300
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#34434a" }
                GradientStop { position: 0.55; color: "#6a5847" }
                GradientStop { position: 1; color: "#2c2931" }
            }
            Grid {
                anchors.fill: parent; anchors.margins: 0
                columns: 3; columnSpacing: 40; rowSpacing: 50
                leftPadding: 25
                LipPill { mood: "none" }
                LipPill { mood: "optional" }
                LipPill { mood: "recommended" }
                LipPill { mood: "required" }
                LipPill { mood: "hold" }
                LipPill { mood: "running"; progress: 0.38 }
                LipPill { mood: "failed"; progress: 0.62 }
                LipPill { mood: "asking"; ask: true }
                LipPill { mood: "restart" }
            }
        }
    }
    // the status-icon strip in each update mood (leftmost glyph)
    Component {
        id: cDashUpdates
        Rectangle {
            width: 330; height: 330; color: theme.bg
            Column {
                anchors.centerIn: parent; spacing: 6
                Repeater {
                    model: ["optional", "recommended", "required", "hold", "running", "asking", "restart", "failed"]
                    delegate: StatusIcons {
                        id: si
                        required property var modelData
                        theme: theme; notifs: notifs; netState: netState
                        upd: QtObject {
                            property bool enabled: true
                            property string mood: si.modelData
                            property var counts: ({ required: 2, total: 12 })
                        }
                    }
                }
            }
        }
    }

    // the Done work-history page (menu 15) over the seeded MockDone
    Component { id: cDone; MenuHost { pillW: 820; pillH: 560; DoneMenu { anchors.fill: parent; theme: theme; done: mockDone } } }
    // the Done page mid-load (skeleton chapters + busy stripe)
    Component { id: cDoneLoading; MenuHost { pillW: 820; pillH: 420; DoneMenu { anchors.fill: parent; theme: theme; done: MockDone { loading: true } } } }
    Component {
        id: cFinAdd
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("add")
            }
        }
    }
    Component {
        id: cFinWish
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("wishlist")
            }
        }
    }
    Component {
        id: cFinFore
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("forecast")
            }
        }
    }
    Component {
        id: cFinPlan
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("plan")
            }
        }
    }
    Component {
        id: cFinReg
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: openMode("register")
            }
        }
    }
    Component {
        id: cFinCat
        MenuHost {
            pillW: 760
            FinanceMenu {
                anchors.fill: parent; theme: theme; fin: fin
                Component.onCompleted: { openMode("register"); registerFilter = "category"; loadRegisterView(); }
            }
        }
    }
    Component { id: cNotifHist; MenuHost { NotificationHistory { anchors.fill: parent; theme: theme; notifs: notifs } } }
    Component {
        id: cNotifStack
        Item {
            width: st.implicitWidth; height: st.implicitHeight
            NotificationStack { id: st; anchors.centerIn: parent; theme: theme; notifs: notifs }
        }
    }

    // ---------------- power-confirmation designs (extracted PowerConfirm.qml) ----------------
    component PowerCanvas: Item {
        property string variant: "1a"
        property string action: "shutdown"
        property string msg: "Really?"
        width: 1280; height: 800
        PowerConfirm {
            anchors.fill: parent; theme: theme; active: true
            action: parent.action; msg: parent.msg; variant: parent.variant; clock: win.clockShort
        }
    }
    Component { id: cPowerHush;   PowerCanvas { variant: "1a"; action: "shutdown"; msg: "Really?" } }
    Component { id: cPowerBlaze;  PowerCanvas { variant: "1b"; action: "reboot";   msg: "No shit!" } }
    Component { id: cPowerLedger; PowerCanvas { variant: "1c"; action: "logout";   msg: "Are you serious?" } }
    Component { id: cPowerSplit;  PowerCanvas { variant: "1d"; action: "shutdown"; msg: "No kidding?" } }
}
