// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — script API (driven by the `ffws` CLI in ../../bin/).
//
// A file mailbox in the profile, so nothing listens on the network:
//   <profile>/sine-workspaces-ipc/requests/<id>.json   ← CLI writes (tmp + rename)
//   <profile>/sine-workspaces-ipc/responses/<id>.json  → mod answers
//   <profile>/sine-workspaces-ipc/alive.json           → {pid, version}, for discovery
// One poller per browser process: Sine imports each window's .uc.mjs graph
// into that window's own global, so workspaces.uc.mjs loads THIS module with
// ChromeUtils.importESModule (a process-wide singleton) and every window
// registers its WorkspacesController here. Its Store is therefore the system
// instance (shared with the Manage page), kept fresh via the config nonce.
//
// Requests: {id, cmd: "ping" | "state" | "apply", ops?, dryRun?, focus?, window?}
// "apply" validates every op first and changes nothing if any op is invalid;
// `dryRun` stops after validation and returns the plan. `focus` (default
// false) is the only way a request may select a tab or switch workspace —
// without it everything happens in the background (lazy tabs, no selection).
// The op reference lives in README.md § "Script API".
//
// Pref `sine-workspaces.api.enabled` (default true) turns the mailbox off.

import Store from "./store.sys.mjs";
import Containers from "./containers.sys.mjs";
import { setInterval } from "resource://gre/modules/Timer.sys.mjs";

const API_VERSION = 1;
const IPC_DIR = PathUtils.join(PathUtils.profileDir, "sine-workspaces-ipc");
const REQ_DIR = PathUtils.join(IPC_DIR, "requests");
const RES_DIR = PathUtils.join(IPC_DIR, "responses");
const ENABLED_PREF = "sine-workspaces.api.enabled";
const POLL_MS = 250;
const GROUP_COLORS = ["blue", "purple", "cyan", "orange", "yellow", "pink", "green", "gray", "red"];

// Tab ids are minted per browser session (prefix) so a plan made before a
// restart fails cleanly instead of hitting whatever tab reused a number.
const SESSION = Date.now().toString(36);
let uidSeq = 0;

class ApiError extends Error {}

const controllers = new Set();
let started = false;
let busy = false;

// ---- lookups ---------------------------------------------------------------

function windows() {
  return [...controllers].filter((c) => !c.win.closed);
}

function frontController() {
  const recent = Services.wm.getMostRecentWindow("navigator:browser");
  const list = windows();
  return list.find((c) => c.win === recent) || list[0] || null;
}

// (Node.ownerGlobal isn't visible through the Xray this system module sees
// window content through; ownerDocument.defaultView is.)
function winOf(node) {
  return node?.ownerDocument?.defaultView || null;
}

function controllerFor(tab) {
  return windows().find((c) => c.win === winOf(tab)) || null;
}

function uidOf(tab) {
  let id = tab.getAttribute("sine-ws-uid");
  if (!id) {
    id = `${SESSION}-${++uidSeq}`;
    tab.setAttribute("sine-ws-uid", id);
  }
  return id;
}

function allTabs() {
  return windows().flatMap((c) => [...c.gBrowser.tabs]);
}

function allGroups() {
  return windows().flatMap((c) => {
    try {
      return [...(c.gBrowser.tabGroups || [])];
    } catch (_e) {
      return [];
    }
  });
}

function urlOf(tab) {
  const b = tab.linkedBrowser;
  const spec = b?.currentURI?.spec || "";
  return spec === "about:blank" && b?.userTypedValue ? b.userTypedValue : spec;
}

function containerOf(tab) {
  return parseInt(tab.getAttribute("usercontextid") || "0", 10);
}

// ---- state -----------------------------------------------------------------

function tabJson(tab, index) {
  return {
    id: uidOf(tab),
    title: tab.label,
    url: urlOf(tab),
    workspace: Store.getTabWorkspace(tab) || Store.defaultId,
    container: containerOf(tab),
    group: tab.group?.id ?? null,
    pinned: tab.pinned,
    selected: tab.selected,
    loaded: !tab.hasAttribute("pending") && !tab.hasAttribute("discarded"),
    lastAccessed: tab.lastAccessed ? new Date(tab.lastAccessed).toISOString() : null,
    index,
  };
}

function state() {
  const front = frontController();
  return {
    version: API_VERSION,
    workspaces: Store.workspaces.map((ws) => ({
      id: ws.id,
      name: ws.name,
      icon: ws.icon,
      container: ws.containerId ? Number(ws.containerId) : 0,
      rules: ws.rules,
    })),
    containers: Containers.list().map((c) => ({ id: c.userContextId, name: c.name, color: c.color, icon: c.icon })),
    windows: windows().map((c, wi) => ({
      index: wi,
      front: c === front,
      activeWorkspace: c.activeId,
      tabs: [...c.gBrowser.tabs].filter((t) => !t.closing).map(tabJson),
      groups: (() => {
        try {
          return [...(c.gBrowser.tabGroups || [])].map((g) => ({
            id: g.id,
            label: g.label || g.name || "",
            color: g.color,
            collapsed: !!g.collapsed,
            workspace: c.groupWorkspace(g),
            tabs: [...g.tabs].map(uidOf),
          }));
        } catch (_e) {
          return [];
        }
      })(),
    })),
  };
}

// ---- resolution (shared by validation and execution) -----------------------

function resolveWorkspace(x) {
  if (x == null || x === "") return null;
  const ws =
    Store.getWorkspace(String(x)) ||
    Store.workspaces.find((w) => w.name.toLowerCase() === String(x).toLowerCase());
  if (!ws) throw new ApiError(`unknown workspace "${x}"`);
  return ws.id;
}

// → undefined (not given), 0 (no container) or a userContextId.
function resolveContainer(x) {
  if (x === undefined || x === null || x === "") return undefined;
  if (x === 0 || x === "0" || String(x).toLowerCase() === "none") return 0;
  const list = Containers.list();
  const c =
    list.find((ct) => ct.userContextId === Number(x)) ||
    list.find((ct) => ct.name.toLowerCase() === String(x).toLowerCase());
  if (!c) throw new ApiError(`unknown container "${x}"`);
  return c.userContextId;
}

function containerDefault(wsId) {
  const def = Store.getWorkspace(wsId)?.containerId;
  return def && Containers.exists(def) ? Number(def) : 0;
}

// Tab refs: "id" or {id, url} — with a url, the tab must still show it (the
// plan is stale otherwise).
function resolveTabs(refs, gone) {
  if (!Array.isArray(refs) || !refs.length) throw new ApiError("`tabs` must be a non-empty list");
  const tabs = allTabs();
  return refs.map((ref) => {
    const id = typeof ref === "object" ? ref?.id : ref;
    const tab = tabs.find((t) => t.getAttribute("sine-ws-uid") === String(id) && !t.closing);
    if (!tab || gone.has(tab)) throw new ApiError(`unknown or closed tab "${id}" (ids come from \`state\` in this browser session)`);
    if (typeof ref === "object" && ref.url && urlOf(tab) !== ref.url) {
      throw new ApiError(`tab "${id}" changed: expected ${ref.url}, now ${urlOf(tab)}`);
    }
    return tab;
  });
}

// Group refs: an id from `state`, "$ref" of a group created earlier in the
// same request, or an exact label that matches one group.
function resolveGroup(x, refs) {
  if (typeof x === "string" && x.startsWith("$")) {
    if (!refs.has(x)) throw new ApiError(`group ref ${x} is used before the op that creates it`);
    return refs.get(x);
  }
  const groups = allGroups();
  const byId = groups.find((g) => g.id === String(x));
  if (byId) return { group: byId, wsId: controllerFor(byId.tabs[0])?.groupWorkspace(byId) };
  const byLabel = groups.filter((g) => (g.label || g.name || "") === String(x));
  if (byLabel.length === 1) {
    const g = byLabel[0];
    return { group: g, wsId: controllerFor(g.tabs[0])?.groupWorkspace(g) };
  }
  if (byLabel.length > 1) throw new ApiError(`group label "${x}" is ambiguous — use its id`);
  throw new ApiError(`unknown group "${x}"`);
}

function checkColor(color) {
  if (color != null && !GROUP_COLORS.includes(color)) {
    throw new ApiError(`color must be one of ${GROUP_COLORS.join(", ")}`);
  }
}

function sameWindow(tabs) {
  const w = winOf(tabs[0]);
  if (tabs.some((t) => winOf(t) !== w)) throw new ApiError("tabs must all be in one window");
  return controllerFor(tabs[0]);
}

function urlEntries(urls) {
  if (!Array.isArray(urls) || !urls.length) throw new ApiError("`urls` must be a non-empty list");
  return urls.map((u) => {
    const e = typeof u === "string" ? { url: u } : { url: u?.url, title: u?.title };
    if (!e.url || typeof e.url !== "string") throw new ApiError("every url needs a `url` string");
    return e;
  });
}

// ---- ops -------------------------------------------------------------------
//
// Each op has `plan(op, ctx)` → {describe, run}. plan() resolves and checks
// everything (throwing ApiError) but changes nothing; run() performs it and
// returns a result. Groups created by an op are registered in ctx.refs during
// planning (as a placeholder) so later ops can point at them.

const OPS = {
  open(op, ctx) {
    const entries = urlEntries(op.urls);
    let target = null;
    if (op.group != null) target = resolveGroup(op.group, ctx.refs);
    if (op.newGroup) checkColor(op.newGroup.color);
    let wsId = resolveWorkspace(op.workspace);
    if (target) {
      if (wsId && target.wsId && wsId !== target.wsId) {
        throw new ApiError(`group "${op.group}" is in workspace "${target.wsId}", not "${wsId}"`);
      }
      wsId = wsId || target.wsId;
    }
    const c = target?.group ? controllerFor(target.group.tabs[0]) : ctx.controller;
    wsId = wsId || c.activeId;
    const container = resolveContainer(op.container);
    const userContextId = container === undefined ? containerDefault(wsId) : container;
    const lazy = op.load !== true;
    const placeholder = {};
    if (op.newGroup?.ref) ctx.refs.set(op.newGroup.ref, { placeholder, wsId });
    return {
      describe:
        `open ${entries.length} tab(s) in workspace "${wsId}"` +
        (userContextId ? `, container ${userContextId}` : "") +
        (op.group != null ? `, in folder ${op.group}` : "") +
        (op.newGroup ? `, in new folder "${op.newGroup.label || ""}"` : "") +
        (lazy ? " (unloaded)" : ""),
      run: () => {
        const group = target?.group || target?.placeholder?.group || null;
        const tabs = c.openTabs(entries, { wsId, userContextId, group, lazy });
        if (op.newGroup && tabs.length) {
          const g = c.gBrowser.addTabGroup(tabs, { label: op.newGroup.label || "", color: op.newGroup.color || null });
          placeholder.group = g;
        }
        ctx.touched = tabs[0] || ctx.touched;
        return { tabs: tabs.map(uidOf), group: placeholder.group?.id ?? group?.id ?? null };
      },
    };
  },

  group(op, ctx) {
    const tabs = resolveTabs(op.tabs, ctx.gone);
    const c = sameWindow(tabs);
    if (tabs.some((t) => t.pinned)) throw new ApiError("pinned tabs can't be grouped");
    checkColor(op.color);
    const wsId = resolveWorkspace(op.workspace);
    const placeholder = {};
    if (op.ref) ctx.refs.set(op.ref, { placeholder, wsId: wsId || Store.getTabWorkspace(tabs[0]) });
    return {
      describe: `create folder "${op.label || ""}" from ${tabs.length} tab(s)` + (wsId ? ` in workspace "${wsId}"` : ""),
      run: () => {
        if (wsId) c.moveTabsToWorkspace(tabs, wsId);
        const first = tabs.reduce((a, b) => (a.index < b.index ? a : b));
        const g = c.gBrowser.addTabGroup(tabs, {
          label: op.label || "",
          color: op.color || null,
          insertBefore: first.group ? null : first,
        });
        placeholder.group = g;
        ctx.touched = tabs[0];
        return { group: g?.id ?? null };
      },
    };
  },

  move(op, ctx) {
    const tabs = resolveTabs(op.tabs, ctx.gone);
    const c = sameWindow(tabs);
    const wsId = resolveWorkspace(op.workspace);
    const ungroup = op.group === null;
    const target = op.group != null ? resolveGroup(op.group, ctx.refs) : null;
    if (target && wsId && target.wsId && target.wsId !== wsId) {
      throw new ApiError(`group "${op.group}" is in workspace "${target.wsId}", not "${wsId}"`);
    }
    if (target && tabs.some((t) => t.pinned)) throw new ApiError("pinned tabs can't be grouped");
    if (op.position != null && op.position !== "end") throw new ApiError('`position` may only be "end"');
    if (!wsId && !target && !ungroup && op.position == null) throw new ApiError("move needs workspace, group or position");
    return {
      describe:
        `move ${tabs.length} tab(s)` +
        (wsId ? ` to workspace "${wsId}"` : "") +
        (target ? ` into folder ${op.group}` : "") +
        (ungroup ? " out of their folder" : "") +
        (op.position === "end" ? " (to the end, in this order)" : ""),
      run: () => {
        if (wsId) c.moveTabsToWorkspace(tabs, wsId);
        if (ungroup) for (const t of tabs) if (t.group) c.gBrowser.ungroupTab(t);
        const group = target?.group || target?.placeholder?.group || null;
        if (group) group.addTabs(tabs); // TabGrouped retags to the folder's workspace
        else if (op.position === "end") for (const t of tabs) c.moveToWorkspaceEnd(t);
        ctx.touched = tabs[0];
        return { tabs: tabs.map(uidOf) };
      },
    };
  },

  close(op, ctx) {
    const tabs = resolveTabs(op.tabs, ctx.gone);
    for (const t of tabs) ctx.gone.add(t);
    return {
      describe: `close ${tabs.length} tab(s): ${tabs.map((t) => urlOf(t)).join(", ")}`,
      run: () => {
        for (const t of tabs) winOf(t).gBrowser.removeTab(t, { animate: false });
        return { closed: tabs.length };
      },
    };
  },

  unload(op, ctx) {
    const tabs = resolveTabs(op.tabs, ctx.gone);
    return {
      describe: `unload ${tabs.length} tab(s) (the selected tab is skipped)`,
      run: () => {
        let n = 0;
        for (const t of tabs) {
          if (t.selected) continue;
          try {
            winOf(t).gBrowser.discardBrowser(t);
            n++;
          } catch (_e) {
            /* already unloaded */
          }
        }
        return { unloaded: n };
      },
    };
  },

  container(op, ctx) {
    const tabs = resolveTabs(op.tabs, ctx.gone);
    const userContextId = resolveContainer(op.container);
    if (userContextId === undefined) throw new ApiError("container op needs `container`");
    for (const t of tabs) if (containerOf(t) !== userContextId) ctx.gone.add(t);
    return {
      describe: `reopen ${tabs.length} tab(s) in container ${userContextId} (loses their back/forward history)`,
      run: () => {
        const out = [];
        for (const t of tabs) {
          if (containerOf(t) === userContextId) {
            out.push(uidOf(t));
            continue;
          }
          const n = controllerFor(t)?.reopenInContainer(t, userContextId);
          if (n) out.push(uidOf(n));
        }
        return { tabs: out };
      },
    };
  },

  editGroup(op, ctx) {
    const target = resolveGroup(op.group, ctx.refs);
    checkColor(op.color);
    return {
      describe: `edit folder ${op.group}` +
        (op.label != null ? ` label="${op.label}"` : "") +
        (op.color != null ? ` color=${op.color}` : "") +
        (op.collapsed != null ? ` collapsed=${!!op.collapsed}` : ""),
      run: () => {
        const g = target.group || target.placeholder?.group;
        if (!g) throw new ApiError(`folder ${op.group} was not created`);
        if (op.label != null) g.label = String(op.label);
        if (op.color != null) g.color = op.color;
        if (op.collapsed != null) g.collapsed = !!op.collapsed;
        return { group: g.id };
      },
    };
  },

  ungroup(op, ctx) {
    const target = resolveGroup(op.group, ctx.refs);
    return {
      describe: `dissolve folder ${op.group} (its tabs stay open)`,
      run: () => {
        const g = target.group || target.placeholder?.group;
        if (g) g.ungroupTabs();
        return {};
      },
    };
  },

  createWorkspace(op) {
    const name = String(op.name || "").trim();
    if (!name) throw new ApiError("createWorkspace needs `name`");
    if (Store.workspaces.some((w) => w.name.toLowerCase() === name.toLowerCase())) {
      throw new ApiError(`workspace "${name}" already exists`);
    }
    const container = resolveContainer(op.container);
    return {
      describe: `create workspace "${name}"`,
      run: async () => {
        const id = op.id ? String(op.id) : Services.uuid.generateUUID().toString().slice(1, -1);
        Store.config.workspaces.push({
          id,
          name,
          icon: op.icon || "◆",
          color: "",
          containerId: container || null,
          rules: [],
        });
        await Store.save();
        Store.bumpNonce();
        return { workspace: id };
      },
    };
  },
};

async function apply(req) {
  const ops = Array.isArray(req.ops) ? req.ops : [];
  if (!ops.length) throw new ApiError("`ops` must be a non-empty list");
  const controller =
    req.window != null ? windows()[Number(req.window)] : frontController();
  if (!controller) throw new ApiError("no browser window");
  const ctx = { controller, refs: new Map(), gone: new Set(), touched: null };

  // 1. Plan everything; any invalid op aborts the whole request untouched.
  const planned = [];
  const errors = [];
  ops.forEach((op, i) => {
    try {
      const fn = OPS[op?.op];
      if (!fn) throw new ApiError(`unknown op "${op?.op}" (known: ${Object.keys(OPS).join(", ")})`);
      planned.push({ i, op: op.op, ...fn(op, ctx) });
    } catch (e) {
      errors.push({ op: i, error: e instanceof ApiError ? e.message : String(e) });
    }
  });
  const plan = planned.map((p) => ({ op: p.i, describe: p.describe }));
  if (errors.length) return { ok: false, errors, plan };
  if (req.dryRun) return { ok: true, dryRun: true, plan };

  // 2. Run in order. A failure stops the run; earlier ops stay applied.
  const results = [];
  for (const p of planned) {
    try {
      results.push({ op: p.i, ...(await p.run()) });
    } catch (e) {
      return { ok: false, errors: [{ op: p.i, error: String(e?.message || e) }], results, plan };
    }
  }
  for (const c of windows()) c.emit();

  // 3. Only now, and only when asked, bring something to the front.
  if (req.focus && ctx.touched && !ctx.touched.closing) {
    const w = winOf(ctx.touched);
    w.gBrowser.selectedTab = ctx.touched; // switches to its workspace
    w.focus();
  }
  return { ok: true, results, plan };
}

// ---- mailbox ---------------------------------------------------------------

async function handle(req) {
  await Store.ensureLoaded();
  switch (req?.cmd) {
    case "ping":
      return { ok: true, version: API_VERSION, windows: windows().length };
    case "state":
      return { ok: true, ...state() };
    case "apply":
      return apply(req);
    default:
      throw new ApiError(`unknown cmd "${req?.cmd}" (ping, state, apply)`);
  }
}

async function respond(id, body) {
  const out = PathUtils.join(RES_DIR, `${id}.json`);
  const tmp = `${out}.tmp`;
  await IOUtils.writeJSON(tmp, { id, ...body });
  await IOUtils.move(tmp, out);
}

async function poll() {
  if (busy || !Services.prefs.getBoolPref(ENABLED_PREF, true) || !windows().length) return;
  busy = true;
  try {
    const files = (await IOUtils.getChildren(REQ_DIR)).filter((f) => f.endsWith(".json")).sort();
    for (const file of files) {
      const id = PathUtils.filename(file).replace(/\.json$/, "");
      let req = null;
      try {
        req = await IOUtils.readJSON(file);
      } catch (e) {
        await IOUtils.remove(file, { ignoreAbsent: true });
        await respond(id, { ok: false, errors: [{ error: `bad request JSON: ${e.message}` }] });
        continue;
      }
      await IOUtils.remove(file, { ignoreAbsent: true });
      let body;
      try {
        body = await handle(req);
      } catch (e) {
        body = { ok: false, errors: [{ error: e instanceof ApiError ? e.message : String(e) }] };
        if (!(e instanceof ApiError)) console.error("[sine-workspaces] api error:", e);
      }
      await respond(id, body);
    }
  } catch (e) {
    if (e?.name !== "NotFoundError") {
      console.warn("[sine-workspaces] api poll failed:", e);
    }
  } finally {
    busy = false;
  }
}

async function start() {
  if (started) return;
  started = true;
  try {
    await IOUtils.makeDirectory(REQ_DIR, { ignoreExisting: true, permissions: 0o700 });
    await IOUtils.makeDirectory(RES_DIR, { ignoreExisting: true, permissions: 0o700 });
    await IOUtils.writeJSON(PathUtils.join(IPC_DIR, "alive.json"), {
      pid: Services.appinfo.processID,
      version: API_VERSION,
      startedAt: new Date().toISOString(),
    });
  } catch (e) {
    console.warn("[sine-workspaces] api mailbox setup failed:", e);
    return;
  }
  Store.observeConfigChange(() => Store.reload());
  setInterval(poll, POLL_MS);
}

const Api = {
  register(controller) {
    controllers.add(controller);
    start();
  },
  unregister(controller) {
    controllers.delete(controller);
  },
};

export default Api;
