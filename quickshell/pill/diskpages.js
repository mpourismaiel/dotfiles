// diskpages.js — turns the sections of a disk scan (diskscan.py) into the one
// shape DiskBuckets.qml draws: a lead sentence, a few headline figures and groups
// of rows. Pure functions; `D` is the DiskState (for formatting and the scan).
//
//   page  = { title, lead, stats: [{label, value, tone}], groups: [group], note }
//   group = { title, note, bytes, rows: [row], offer: [ids] }
//   row   = { id, path, label, sub, bytes, when, tier, note, veil, chips: [{text,tone}], open }
//
// A row with an `id` is a removable item the scan registered; a row with only a
// `path` can still be put in the plan (the bridge makes an item for it on demand).
.pragma library

function num(n) { return ("" + n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
function plural(n, w) { return num(n) + " " + w + (n === 1 ? "" : "s"); }
function base(p) { var i = p.lastIndexOf("/"); return i >= 0 ? p.substring(i + 1) : p; }
function dirOf(p) { var i = p.lastIndexOf("/"); return i > 0 ? p.substring(0, i) : "/"; }
function sum(a, k) { var s = 0; for (var i = 0; i < a.length; i++) s += a[i][k] || 0; return s; }
function ids(rows) { var o = []; for (var i = 0; i < rows.length; i++) if (rows[i].id) o.push(rows[i].id); return o; }

var KIND = { video: "videos", audio: "audio", image: "images", archive: "archives", installer: "installers", diskimage: "disk images",
             document: "documents", model: "model weights", dump: "database dumps", folder: "folders", other: "other files" };

function videos(D, s) {
    var v = (s.home || {}).videos;
    if (!v) return null;
    var dirs = v.dirs.map(function (d) {
        return { label: base(d.path), sub: D.tilde(dirOf(d.path)) + " · " + plural(d.count, "video"), bytes: d.bytes, when: d.newest, veil: true, open: d.path };
    });
    var files = v.files.map(function (f) {
        return { path: f.path, label: base(f.path), sub: D.tilde(dirOf(f.path)), bytes: f.bytes, when: f.mtime, tier: "data", veil: true };
    });
    return {
        title: "Videos",
        lead: "Video files outside games, projects and caches. Game folders are full of video too — those are counted under Games.",
        stats: [{ label: plural(v.count, "video"), value: D.fmtBytes(v.bytes) }, { label: "folders holding them", value: "" + v.dirs.length }],
        groups: [{ title: "Where they are", note: "open a folder in Files to go through it", rows: dirs.slice(0, 25) },
                 { title: "Largest files", note: "", rows: files }]
    };
}

function games(D, s) {
    var g = s.games;
    if (!g) return null;
    var groups = [], stats = [{ label: plural(g.count, "game"), value: D.fmtBytes(g.bytes) }];
    if (g.steam) {
        var st = g.steam;
        stats.push({ label: "Steam · " + plural(st.games.length, "game"), value: D.fmtBytes(st.bytes) });
        if (st.never) stats.push({ label: "installed, never played", value: "" + st.never, tone: "warn" });
        groups.push({ title: "Steam", note: D.tilde(st.root), bytes: st.bytes, rows: st.games.map(function (r) {
            return { id: r.id, label: r.name, sub: r.played ? "last played " + D.fmtAge(r.played) : "never played", bytes: r.bytes, when: r.played || r.updated,
                     tier: "cost", veil: true, chips: r.played ? [] : [{ text: "never played", tone: "warn" }], open: r.path };
        }) });
        var ex = [];
        st.extras.forEach(function (e) {
            ex.push({ id: e.id, label: e.label, sub: e.orphans ? plural(e.orphans, "folder") + " for games that are not installed · " + D.fmtBytes(e.orphan_bytes) : "all for installed games",
                      bytes: e.bytes, tier: e.key === "shadercache" ? "free" : "state" });
        });
        st.tools.forEach(function (t) {
            ex.push({ id: t.id || "", label: t.name, sub: t.custom ? ("custom Proton build" + (t.used ? " · in use" : " · no game is set to use it")) : "installed through Steam", bytes: t.bytes,
                      tier: "cost", open: t.path, chips: (t.custom && !t.used) ? [{ text: "unreferenced", tone: "safe" }] : [] });
        });
        if (ex.length) groups.push({ title: "Steam compatibility tools and caches", note: "", bytes: sum(ex, "bytes"), rows: ex });
    }
    if (g.other.length) {
        stats.push({ label: plural(g.other.length, "game") + " outside launchers", value: D.fmtBytes(sum(g.other, "bytes")) });
        groups.push({ title: "Games outside launchers", note: g.libraries.map(function (p) { return D.tilde(p); }).join(" · "), bytes: sum(g.other, "bytes"),
                      rows: g.other.map(function (r) {
            var chips = [];
            if (r.versions > 1) chips.push({ text: r.versions + " versions kept", tone: "warn" });
            return { id: r.id, label: r.name, sub: r.engine + " · " + D.tilde(dirOf(r.path)), bytes: r.bytes, when: r.newest, tier: "data", veil: true, chips: chips, open: r.path };
        }) });
    }
    if (g.misc.length)
        groups.push({ title: "Runners, prefixes and emulators", note: "", bytes: sum(g.misc, "bytes"), rows: g.misc.map(function (r) {
            return { path: r.path, label: r.label, sub: D.tilde(r.path), bytes: r.bytes, when: r.newest, tier: "state", open: r.path };
        }) });
    return { title: "Games", lead: "Steam games come back with a download. Games kept as plain folders do not — nothing can fetch those again.", stats: stats, groups: groups };
}

function downloads(D, s) {
    var d = s.downloads;
    if (!d) return null;
    var groups = [];
    if (d.dups.length)
        groups.push({ title: "Exact duplicates", note: "same content twice — the copy with the longer path is offered", bytes: d.dup_bytes, rows: [].concat.apply([], d.dups.map(function (g) {
            return g.extra.map(function (p, i) {
                return { id: g.ids[i], label: base(p), sub: "same as " + D.tilde(g.keep), bytes: g.size, tier: "data", veil: true, chips: [{ text: "duplicate", tone: "safe" }] };
            });
        })) });
    if (d.archives.length)
        groups.push({ title: "Archives already unpacked", note: "a folder with the same name sits next to each", bytes: sum(d.archives, "bytes"), rows: d.archives.map(function (a) {
            return { id: a.id, label: a.name, sub: "unpacked at " + D.tilde(a.unpacked), bytes: a.bytes, tier: "data", veil: true, chips: [{ text: "unpacked", tone: "safe" }] };
        }) });
    groups.push({ title: "Everything in " + D.tilde(d.root), note: "largest first", bytes: d.bytes, rows: d.rows.filter(function (r) { return r.bytes >= 1048576; }).map(function (r) {
        var chips = [];
        if (r.claimed) chips.push({ text: "game library → Games", tone: "plain" });
        if (r.secret) chips.push({ text: "looks like a key — never offered", tone: "stop" });
        return { id: r.id, label: r.name, sub: (r.dir ? "folder" : (KIND[r.kind] || r.kind)) + " · downloaded " + D.fmtAge(r.mtime), bytes: r.bytes, when: r.mtime, tier: "data",
                 veil: true, chips: chips, open: r.dir ? r.path : "" };
    }) });
    var stats = [{ label: plural(d.count, "entry").replace("entrys", "entries"), value: D.fmtBytes(d.bytes) },
                 { label: "older than a year", value: D.fmtBytes(d.ages.older) }];
    if (d.dup_bytes) stats.push({ label: "in duplicates", value: D.fmtBytes(d.dup_bytes), tone: "safe" });
    return { title: "Downloads", lead: "Nothing here can be fetched again for you, so everything goes to the Trash rather than being deleted."
             + (d.secrets ? " " + plural(d.secrets, "file") + " look like keys or backup codes and are never offered." : ""), stats: stats, groups: groups };
}

function caches(D, s) {
    var c = s.caches;
    if (!c) return null;
    function row(r) {
        var chips = [];
        if (r.heavy) chips.push({ text: "large downloads", tone: "warn" });
        if (r.reclaim < r.bytes * 0.8) chips.push({ text: "only " + D.fmtBytes(r.reclaim) + " frees up", tone: "warn" });
        if (r.stale) chips.push({ text: "untouched", tone: "safe" });
        return { id: r.id, label: r.label, sub: D.tilde(r.path), bytes: r.bytes, when: r.newest, tier: r.tier, note: r.note, chips: chips, open: r.path };
    }
    var th = s.thumbnails, groups = [];
    groups.push({ title: "Known caches", note: "cleaned with the tool's own command where it has one", bytes: sum(c.known, "bytes"), rows: c.known.map(row) });
    if (c.other.length) groups.push({ title: "Other folders in the cache directory", note: "not recognised — judged by age only", bytes: sum(c.other, "bytes"), rows: c.other.map(row) });
    if (c.tools.length) groups.push({ title: "Large tool data (not cache)", note: "shown so you know where the space is — never offered", bytes: sum(c.tools, "bytes"), rows: c.tools.map(function (r) {
        return { label: r.label, sub: D.tilde(r.path), bytes: r.bytes, when: r.newest, tier: "state", note: r.note, open: r.path };
    }) });
    var stats = [{ label: "in caches", value: D.fmtBytes(c.bytes) }];
    if (th) stats.push({ label: "thumbnails (own page)", value: D.fmtBytes(th.bytes) });
    return { title: "Caches", lead: "Caches refill by themselves. The question is only what refilling costs: nothing, a rebuild, or a download.", stats: stats, groups: groups };
}

function packages(D, s) {
    var p = s.packages;
    if (!p) return null;
    return { title: "Packages", lead: "Old package versions, AUR build folders, orphans, logs and the Trash. Anything needing administrator rights opens in a terminal with the command shown first.",
             stats: [{ label: "reclaimable here", value: D.fmtBytes(p.bytes) }],
             groups: p.groups.map(function (g) {
                 return { title: g.title, note: g.note, bytes: g.bytes, rows: g.rows.map(function (r) {
                     return { id: r.id, label: r.label, sub: r.note, bytes: r.bytes, tier: r.tier, mono: true };
                 }) };
             }) };
}

function docker(D, s) {
    var d = s.docker;
    if (!d) return null;
    if (!d.available) return { title: "Docker", lead: d.reason, stats: [], groups: [] };
    var t = d.totals, c = d.counts, groups = [];
    groups.push({ title: "What can be pruned", note: "each runs Docker's own prune command", bytes: sum(d.rows, "bytes"), rows: d.rows.map(function (r) {
        return { id: r.id, label: r.label, sub: r.sub + " · " + r.note, bytes: r.bytes, tier: r.tier };
    }) });
    if (d.compose.length)
        groups.push({ title: "Compose projects", note: "which folder each belongs to", rows: d.compose.map(function (p) {
            return { label: p.name, sub: (p.dir ? D.tilde(p.dir) : "folder unknown") + " · " + plural(p.containers, "container") + (p.running ? ", " + p.running + " running" : ""),
                     tier: "state", chips: p.orphaned ? [{ text: "folder is gone", tone: "warn" }] : [], open: p.orphaned ? "" : p.dir };
        }) });
    var stats = [{ label: plural(c.images, "image") + " · " + c.dangling + " dangling", value: D.fmtBytes(t.images) }, { label: "build cache", value: D.fmtBytes(t.cache) },
                 { label: plural(c.volumes, "volume"), value: D.fmtBytes(t.volumes) }, { label: plural(c.containers, "container") + " · " + c.running + " running", value: D.fmtBytes(t.containers) }];
    return { title: "Docker", lead: "Sizes come from the Docker daemon. Named volumes that nothing uses (" + c.named_unused + ", " + D.fmtBytes(c.named_unused_bytes) + ") are never offered: they are usually databases.",
             stats: stats, groups: groups };
}

function thumbnails(D, s) {
    var t = s.thumbnails;
    if (!t) return null;
    var st = t.state, rows = [];
    if (t.ids.dead) rows.push({ id: t.ids.dead, label: "Thumbnails of files that are gone or changed", sub: plural(st.orphan.count, "orphan") + " · " + st.stale.count + " outdated — each one is checked again right before it is removed",
                                bytes: t.dead_bytes, tier: "free", chips: [{ text: "not needed", tone: "safe" }] });
    if (t.ids.all) rows.push({ id: t.ids.all, label: "Every thumbnail", sub: "previews are drawn again as you browse — folders open slower the first time", bytes: t.bytes, tier: "free" });
    var groups = [{ title: "What can go", note: D.tilde(t.root), bytes: t.bytes, rows: rows }];
    if (t.where.length) groups.push({ title: "Where the vanished files used to be", note: "the folders these dead previews pointed at", rows: t.where.map(function (w) {
        return { label: D.tilde(w.path), sub: plural(w.count, "preview"), bytes: w.bytes, tier: "free", veil: true };
    }) });
    groups.push({ title: "By size class", note: "", rows: t.buckets.map(function (b) { return { label: b.name, sub: plural(b.count, "file"), bytes: b.bytes, tier: "free" }; }) });
    if (t.extra.length) groups.push({ title: "Other preview caches", note: "", rows: t.extra.map(function (e) {
        return { path: e.path, label: e.label, sub: D.tilde(e.path), bytes: e.bytes, when: e.newest, tier: "free", open: e.path };
    }) });
    return { title: "Thumbnails", lead: "A thumbnail is not needed when the file it shows is gone, or changed after the preview was made. Previews for unplugged drives are left alone.",
             stats: [{ label: plural(t.count, "thumbnail"), value: D.fmtBytes(t.bytes) }, { label: "not needed", value: D.fmtBytes(t.dead_bytes), tone: "safe" },
                     { label: "still valid", value: D.fmtBytes(st.ok.bytes) }, { label: "source not mounted", value: num(st.away.count) }],
             groups: groups };
}

function bins(D, s) {
    var b = s.bins;
    if (!b) return null;
    return { title: "Programs", lead: "Programs installed by hand, outside the package manager. In system folders only files that no package owns are listed.",
             stats: [{ label: "in your own program folders", value: D.fmtBytes(b.bytes) }],
             groups: b.groups.map(function (g) {
                 return { title: D.tilde(g.path), note: (g.note || "") + (g.repo ? "a git repository" : ""), bytes: g.bytes, rows: g.rows.map(function (r) {
                     var chips = [];
                     if (r.shadow) chips.push({ text: "also installed as a package", tone: "safe" });
                     if (r.appimage) chips.push({ text: "AppImage", tone: "plain" });
                     return { id: r.id, label: r.name, sub: (r.dir ? "folder" : "file") + " · changed " + D.fmtAge(r.mtime), bytes: r.bytes, when: r.mtime, tier: "data", chips: chips, open: r.dir ? r.path : "" };
                 }) };
             }) };
}

function system(D, s) {
    var y = s.system, h = s.home;
    if (!y) return null;
    var groups = [{ title: "System folders", note: y.denied ? "some folders need administrator rights to measure fully" : "", bytes: y.bytes, rows: y.rows.map(function (r) {
        return { label: r.path, sub: r.denied ? "partly unreadable" : "", bytes: r.bytes, tier: "state", open: r.path, mono: true };
    }) }];
    if (y.kernels.length) groups.push({ title: "Kernel modules", note: "", rows: y.kernels.map(function (k) {
        return { label: k.name, sub: k.running ? "the running kernel" : (k.owned ? "installed kernel" : "no package owns this — a leftover"), bytes: k.bytes, tier: "state",
                 chips: (!k.running && !k.owned) ? [{ text: "leftover", tone: "warn" }] : [] };
    }) });
    if (h && h.top) groups.push({ title: "Your home folder", note: plural(h.files, "file"), bytes: h.bytes, rows: h.top.slice(0, 30).map(function (r) {
        return { label: "~/" + r.name, sub: r.kids.slice(0, 3).map(function (k) { return k.name + " " + D.fmtBytes(k.bytes); }).join(" · "), bytes: r.bytes, when: r.newest, tier: "data", open: r.path, mono: true };
    }) });
    return { title: "System", lead: "The operating system and the top of your home folder. Nothing here is offered for removal — it is the map.", stats: [{ label: "system folders", value: D.fmtBytes(y.bytes) }], groups: groups };
}

function reports(D) {
    return { title: "Reports", lead: "One report per cleanup: what went, what it weighed, what was skipped and why. Kept in " + D.tilde(D.reportsDir) + ".",
             stats: [{ label: "cleanups so far", value: "" + D.reports.length }],
             groups: [{ title: "Past cleanups", note: "", rows: D.reports.map(function (r) {
                 return { label: D.fmtDate(r.at) + " — " + r.done + " of " + plural(r.items, "item"), sub: r.titles.join(" · "), bytes: r.bytes, when: r.at, tier: "free", file: r.path };
             }) }] };
}

function build(page, D) {
    var s = D.sections || {};
    var f = { videos: videos, games: games, downloads: downloads, caches: caches, packages: packages, docker: docker, thumbnails: thumbnails, bins: bins, system: system };
    if (page === "reports") return reports(D);
    return f[page] ? f[page](D, s) : null;
}

// sidebar figure for a page
function pageBytes(page, D) {
    var s = D.sections || {};
    switch (page) {
    case "projects": return s.projects ? s.projects.totals.bytes : -1;
    case "videos": return s.home && s.home.videos ? s.home.videos.bytes : -1;
    case "games": return s.games ? s.games.bytes : -1;
    case "downloads": return s.downloads ? s.downloads.bytes : -1;
    case "caches": return s.caches ? s.caches.bytes : -1;
    case "packages": return s.packages ? s.packages.bytes : -1;
    case "docker": return s.docker && s.docker.available ? s.docker.bytes : -1;
    case "thumbnails": return s.thumbnails ? s.thumbnails.bytes : -1;
    case "bins": return s.bins ? s.bins.bytes : -1;
    case "system": return s.system ? s.system.bytes : -1;
    }
    return -1;
}
