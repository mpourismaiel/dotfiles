// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — persistent store + per-tab workspace tagging.
//
// This is a background (.sys.mjs) singleton shared across all browser windows.
// It owns:
//   - the workspaces.json config (definitions: name/icon/container/rules),
//   - per-tab workspace membership (via SessionStore custom tab values, so it
//     survives restart through normal session restore),
//   - a tiny change-notification channel so the Manage page can poke live windows.

// SessionStore's module URL moved in Firefox 156 (resource:///modules/… →
// moz-src:///browser/components/…). Importing a missing path throws at module
// eval, which would take the whole mod down (strip + engine), so try the known
// locations in order — newest first — and fall back across Firefox versions.
const SessionStore = (() => {
  const paths = [
    "moz-src:///browser/components/sessionstore/SessionStore.sys.mjs", // Firefox 156+
    "resource:///modules/sessionstore/SessionStore.sys.mjs", // Firefox ≤155
  ];
  for (const path of paths) {
    try {
      return ChromeUtils.importESModule(path).SessionStore;
    } catch (_e) {
      /* try the next known location */
    }
  }
  throw new Error(
    "[sine-workspaces] SessionStore module not found at any known path: " +
      paths.join(", ")
  );
})();

const MOD_DIR = ["chrome", "sine-mods", "sine-workspaces", "config"];
const CONFIG_PATH = PathUtils.join(PathUtils.profileDir, ...MOD_DIR, "workspaces.json");
const DEFAULT_PATH = PathUtils.join(PathUtils.profileDir, ...MOD_DIR, "workspaces.default.json");

// SessionStore custom-tab-value keys.
const TAG_KEY = "sine-workspaces-id";
const MANUAL_KEY = "sine-workspaces-manual";

// Pref used purely as a cross-window "config changed" signal (Manage page bumps it).
const NONCE_PREF = "sine-workspaces.config-nonce";

// Last workspace the user was on (any window), persisted across restarts. Used at
// startup to restore the active workspace when a window opens onto a fresh
// external / command-line tab that carries no workspace tag yet.
const LAST_ACTIVE_PREF = "sine-workspaces.last-active";

const Store = {
  _config: null,
  _loaded: false,
  _loadPromise: null,

  /** Loads once; concurrent windows share the same promise. */
  ensureLoaded() {
    return (this._loadPromise ??= this.load());
  },

  /** Loads workspaces.json, seeding from the bundled default on first run. */
  async load() {
    let raw;
    try {
      raw = await IOUtils.readJSON(CONFIG_PATH);
    } catch (_e) {
      try {
        raw = await IOUtils.readJSON(DEFAULT_PATH);
      } catch (_e2) {
        raw = { version: 1, workspaces: [] };
      }
      // Persist the seed so the user has an editable copy.
      try {
        await IOUtils.writeJSON(CONFIG_PATH, raw);
      } catch (e) {
        console.warn("[sine-workspaces] could not seed config:", e);
      }
    }
    this._config = this._normalize(raw);
    this._loaded = true;
    return this._config;
  },

  /** Reloads config from disk (used after the Manage page writes changes). */
  async reload() {
    try {
      this._config = this._normalize(await IOUtils.readJSON(CONFIG_PATH));
    } catch (e) {
      console.warn("[sine-workspaces] reload failed:", e);
    }
    return this._config;
  },

  async save() {
    if (!this._config) return;
    try {
      await IOUtils.writeJSON(CONFIG_PATH, this._config);
    } catch (e) {
      console.warn("[sine-workspaces] save failed:", e);
    }
  },

  _normalize(raw) {
    const cfg = raw && typeof raw === "object" ? raw : {};
    cfg.version = cfg.version || 1;
    cfg.badgeColor = typeof cfg.badgeColor === "string" ? cfg.badgeColor : "";
    cfg.workspaces = Array.isArray(cfg.workspaces) ? cfg.workspaces : [];
    if (!cfg.workspaces.length) {
      cfg.workspaces.push({ id: "default", name: "Default", icon: "🌐", color: "", containerId: null, rules: [] });
    }
    for (const ws of cfg.workspaces) {
      ws.id = String(ws.id || crypto.randomUUID());
      ws.name = ws.name || ws.id;
      ws.icon = ws.icon || "•";
      ws.color = ws.color || "";
      ws.containerId = ws.containerId ?? null;
      ws.rules = Array.isArray(ws.rules) ? ws.rules : [];
    }
    return cfg;
  },

  get config() {
    return this._config;
  },

  get workspaces() {
    return this._config?.workspaces ?? [];
  },

  get defaultId() {
    return this.workspaces[0]?.id ?? "default";
  },

  getWorkspace(id) {
    return this.workspaces.find((w) => w.id === id) || null;
  },

  hasWorkspace(id) {
    return !!this.getWorkspace(id);
  },

  // ---- per-tab membership (persisted via SessionStore) --------------------

  getTabWorkspace(tab) {
    try {
      return SessionStore.getCustomTabValue(tab, TAG_KEY) || null;
    } catch (_e) {
      return null;
    }
  },

  setTabWorkspace(tab, id) {
    try {
      SessionStore.setCustomTabValue(tab, TAG_KEY, String(id));
    } catch (e) {
      console.warn("[sine-workspaces] setTabWorkspace failed:", e);
    }
  },

  isManual(tab) {
    try {
      return SessionStore.getCustomTabValue(tab, MANUAL_KEY) === "1";
    } catch (_e) {
      return false;
    }
  },

  setManual(tab, manual) {
    try {
      SessionStore.setCustomTabValue(tab, MANUAL_KEY, manual ? "1" : "0");
    } catch (_e) {
      /* ignore */
    }
  },

  // ---- last-active workspace (persisted across restarts) ------------------

  getLastActiveId() {
    try {
      return Services.prefs.getStringPref(LAST_ACTIVE_PREF, "") || null;
    } catch (_e) {
      return null;
    }
  },

  setLastActiveId(id) {
    try {
      Services.prefs.setStringPref(LAST_ACTIVE_PREF, String(id || ""));
    } catch (_e) {
      /* ignore */
    }
  },

  // ---- cross-window change signal -----------------------------------------

  bumpNonce() {
    try {
      Services.prefs.setIntPref(NONCE_PREF, Services.prefs.getIntPref(NONCE_PREF, 0) + 1);
    } catch (_e) {
      /* ignore */
    }
  },

  observeConfigChange(callback) {
    const observer = {
      observe: () => callback(),
    };
    Services.prefs.addObserver(NONCE_PREF, observer);
    return () => Services.prefs.removeObserver(NONCE_PREF, observer);
  },
};

export default Store;
