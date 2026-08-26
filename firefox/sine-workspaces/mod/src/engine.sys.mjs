// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — per-window workspace controller.
//
// One instance per browser window. Owns tab visibility for that window: it hides
// tabs (pinned + normal + grouped) that don't belong to the active workspace and
// shows the ones that do. It also routes new tabs, evaluates URL rules on tab
// creation, and applies per-workspace container defaults.

import Store from "./store.sys.mjs";
import Rules from "./rules.sys.mjs";
import Containers from "./containers.sys.mjs";

const BLANK = new Set(["about:newtab", "about:blank", "about:home", "", "chrome://browser/content/blanktab.html"]);

export class WorkspacesController {
  constructor(win) {
    this.win = win;
    this.gBrowser = win.gBrowser;
    this.activeId = null;
    this.lastActiveByWs = new Map(); // wsId -> tab (remembered active tab)
    this.listeners = new Set();
    this._pendingRule = new WeakSet(); // brand-new tabs awaiting one-shot rule eval
    this._switching = false;
    this._boundHandlers = {};
    this._tabsProgress = null;
  }

  // ---- lifecycle -----------------------------------------------------------

  init() {
    // Choose the initial active workspace from the restored selected tab.
    const selTag = Store.getTabWorkspace(this.gBrowser.selectedTab);
    this.activeId = selTag && Store.hasWorkspace(selTag) ? selTag : Store.defaultId;

    // Tag any untagged tabs (fresh profile / imported session) with the default.
    for (const tab of this.gBrowser.tabs) {
      if (!Store.getTabWorkspace(tab)) Store.setTabWorkspace(tab, Store.defaultId);
    }

    this.#wire();
    this.applyVisibility();
    this.emit();
  }

  destroy() {
    const c = this.gBrowser.tabContainer;
    c.removeEventListener("TabOpen", this._boundHandlers.open);
    c.removeEventListener("TabClose", this._boundHandlers.close);
    c.removeEventListener("TabSelect", this._boundHandlers.select);
    if (this._tabsProgress) this.gBrowser.removeTabsProgressListener(this._tabsProgress);
    this.listeners.clear();
  }

  #wire() {
    const c = this.gBrowser.tabContainer;
    this._boundHandlers.open = (e) => this.#onTabOpen(e.target);
    this._boundHandlers.close = (e) => this.#onTabClose(e.target);
    this._boundHandlers.select = (e) => this.#onTabSelect(e.target);
    c.addEventListener("TabOpen", this._boundHandlers.open);
    c.addEventListener("TabClose", this._boundHandlers.close);
    c.addEventListener("TabSelect", this._boundHandlers.select);

    // One-shot URL-rule evaluation on a new tab's first committed top-level URL.
    this._tabsProgress = {
      onLocationChange: (browser, webProgress, _request, location, _flags) => {
        if (!webProgress?.isTopLevel) return;
        const tab = this.gBrowser.getTabForBrowser(browser);
        if (!tab || !this._pendingRule.has(tab)) return;
        this._pendingRule.delete(tab); // creation-only: evaluate exactly once
        if (Store.isManual(tab)) return;
        const wsId = Rules.firstMatch(Store.workspaces, location?.spec || "");
        if (wsId && wsId !== Store.getTabWorkspace(tab)) this.assignTab(tab, wsId, false);
      },
    };
    this.gBrowser.addTabsProgressListener(this._tabsProgress);
  }

  // ---- observers -----------------------------------------------------------

  onChange(cb) {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  emit() {
    for (const cb of this.listeners) {
      try {
        cb(this);
      } catch (e) {
        console.warn("[sine-workspaces] listener error:", e);
      }
    }
  }

  // ---- queries -------------------------------------------------------------

  #isLoaded(tab) {
    return !tab.hasAttribute("pending") && !tab.hasAttribute("discarded");
  }

  #tabsFor(wsId) {
    // Pinned first, then by tab position — the order the shortcuts count from.
    return [...this.gBrowser.tabs]
      .filter((t) => !t.closing && (Store.getTabWorkspace(t) || Store.defaultId) === wsId)
      .sort((a, b) => (b.pinned - a.pinned) || (a._tPos - b._tPos));
  }

  count(wsId) {
    return this.#tabsFor(wsId).length;
  }

  // Public, ordered (pinned-first) view of a workspace's tabs — used by shortcuts.
  orderedTabs(wsId) {
    return this.#tabsFor(wsId);
  }

  // ---- visibility ----------------------------------------------------------

  // Hide/show a tab. Firefox's gBrowser.hideTab REFUSES pinned tabs, so we drive
  // visibility with our own attribute (CSS hides it — works for pinned too) and
  // additionally call hideTab for normal tabs to get proper internal semantics
  // (excluded from Ctrl+Tab, alltabs menu, etc.).
  #setTabHidden(tab, hidden) {
    if (hidden) {
      if (tab.selected) return; // never hide the active tab
      tab.setAttribute("sine-ws-hidden", "true");
      if (!tab.pinned) {
        try { this.gBrowser.hideTab(tab); } catch (_e) { /* ignore */ }
      }
    } else {
      tab.removeAttribute("sine-ws-hidden");
      if (!tab.pinned) {
        try { this.gBrowser.showTab(tab); } catch (_e) { /* ignore */ }
      }
    }
  }

  applyVisibility() {
    for (const tab of this.gBrowser.tabs) {
      const wid = Store.getTabWorkspace(tab) || Store.defaultId;
      this.#setTabHidden(tab, wid !== this.activeId);
    }
    this.#updateGroups();
  }

  #updateGroups() {
    let groups = [];
    try {
      groups = this.gBrowser.tabGroups || [];
    } catch (_e) {
      return;
    }
    for (const group of groups) {
      try {
        const allHidden = [...group.tabs].every(
          (t) => t.hidden || t.hasAttribute("sine-ws-hidden")
        );
        group.hidden = allHidden;
      } catch (_e) {
        /* best-effort */
      }
    }
  }

  // ---- switching -----------------------------------------------------------

  switchTo(wsId) {
    if (!Store.hasWorkspace(wsId) || this._switching) return;
    if (wsId === this.activeId) return;

    const prevSel = this.gBrowser.selectedTab;
    const prevIndex = prevSel?._tPos ?? 0;
    if (prevSel && Store.getTabWorkspace(prevSel) === this.activeId) {
      this.lastActiveByWs.set(this.activeId, prevSel);
    }

    this._switching = true;
    try {
      this.activeId = wsId;
      // Show the target workspace's tabs first so we can safely select one.
      for (const tab of this.#tabsFor(wsId)) this.#setTabHidden(tab, false);
      this.#pickAndSelect(wsId, prevIndex);
      // Now hide everything that isn't in the active workspace.
      for (const tab of this.gBrowser.tabs) {
        const wid = Store.getTabWorkspace(tab) || Store.defaultId;
        if (wid !== this.activeId) this.#setTabHidden(tab, true);
      }
      this.#updateGroups();
    } finally {
      this._switching = false;
    }
    this.emit();
  }

  // The active-tab resolution cascade (see grill answers #5 and #6).
  #pickAndSelect(wsId, refIndex) {
    const inWs = this.#tabsFor(wsId);

    // 0. Empty workspace → open a fresh tab in it (q6). Must come before the
    //    "all-unloaded → jump elsewhere" branch, which is only for non-empty ones.
    if (inWs.length === 0) {
      const fresh = this.newTabInWorkspace(wsId, { select: false });
      if (fresh) this.gBrowser.selectedTab = fresh;
      return;
    }

    // 1. Remembered last-active tab, if still valid.
    let target = this.lastActiveByWs.get(wsId);
    if (!this.#valid(target, wsId)) target = null;

    // 2. Closest loaded tab in the workspace.
    if (!target) target = this.#closest(inWs.filter((t) => this.#isLoaded(t)), refIndex);

    // 3. Closest tab in the workspace even if unloaded — selecting loads it.
    //    (This is the common case right after a restart, when session-restore
    //    brings tabs back lazy/discarded. We always land IN the target workspace.)
    if (!target) target = this.#closest(inWs, refIndex);

    // 4. Absolute fallback (shouldn't happen for a non-empty ws): fresh tab.
    if (!target) target = this.newTabInWorkspace(wsId, { select: false });

    if (target) this.gBrowser.selectedTab = target;
  }

  #valid(tab, wsId) {
    return (
      tab &&
      !tab.closing &&
      this.gBrowser.tabs.includes(tab) &&
      (Store.getTabWorkspace(tab) || Store.defaultId) === wsId
    );
  }

  #closest(tabs, refIndex) {
    if (!tabs.length) return null;
    return tabs.reduce((best, t) =>
      Math.abs(t._tPos - refIndex) < Math.abs(best._tPos - refIndex) ? t : best
    );
  }

  // ---- tab lifecycle -------------------------------------------------------

  #onTabOpen(tab) {
    // Restored / duplicated tabs already carry a persisted tag — keep it.
    if (Store.getTabWorkspace(tab)) return;

    Store.setTabWorkspace(tab, this.activeId);
    Store.setManual(tab, false);
    this._pendingRule.add(tab);

    // Apply the active workspace's default container to genuinely blank new tabs.
    const ws = Store.getWorkspace(this.activeId);
    if (ws?.containerId && Containers.exists(ws.containerId)) {
      this.win.setTimeout(() => this.#applyContainerDefault(tab, Number(ws.containerId)), 0);
    }
    this.emit();
  }

  #applyContainerDefault(tab, userContextId) {
    if (!tab || tab.closing || !this.gBrowser.tabs.includes(tab)) return;
    const current = parseInt(tab.getAttribute("usercontextid") || "0", 10);
    if (current === userContextId) return;
    const spec = tab.linkedBrowser?.currentURI?.spec ?? "";
    if (!BLANK.has(spec)) return; // only reopen blank tabs — never lose page state

    const index = tab._tPos + 1;
    const newTab = this.#addTab("about:newtab", { userContextId, index });
    if (!newTab) return;
    Store.setTabWorkspace(newTab, this.activeId);
    Store.setManual(newTab, false);
    const wasSelected = tab.selected;
    this.gBrowser.removeTab(tab);
    if (wasSelected) this.gBrowser.selectedTab = newTab;
  }

  #onTabClose(tab) {
    this.lastActiveByWs.forEach((v, k) => {
      if (v === tab) this.lastActiveByWs.delete(k);
    });
    // If the active tab of the current workspace is closing, re-pick per cascade.
    if (tab.selected && (Store.getTabWorkspace(tab) || Store.defaultId) === this.activeId) {
      this.win.setTimeout(() => {
        const sel = this.gBrowser.selectedTab;
        if (!sel || (Store.getTabWorkspace(sel) || Store.defaultId) !== this.activeId) {
          this.#pickAndSelect(this.activeId, tab._tPos);
          this.applyVisibility();
        }
        this.emit();
      }, 0);
    } else {
      this.emit();
    }
  }

  #onTabSelect(tab) {
    if (this._switching) return;
    // Selecting a tab that lives in another workspace switches to that workspace.
    const wid = Store.getTabWorkspace(tab) || Store.defaultId;
    if (wid !== this.activeId && Store.hasWorkspace(wid)) {
      this.lastActiveByWs.set(wid, tab);
      this.activeId = wid;
      this.applyVisibility();
      this.emit();
    } else {
      this.lastActiveByWs.set(this.activeId, tab);
    }
  }

  // ---- assignment / creation ----------------------------------------------

  // Move a tab into a workspace. `manual` marks it sticky (rules stop touching it).
  assignTab(tab, wsId, manual = true) {
    if (!Store.hasWorkspace(wsId)) return;
    Store.setTabWorkspace(tab, wsId);
    if (manual) Store.setManual(tab, true);
    this.#setTabHidden(tab, wsId !== this.activeId);
    this.#updateGroups();
    this.emit();
  }

  newTabInWorkspace(wsId, { select = true } = {}) {
    const ws = Store.getWorkspace(wsId);
    const opts = {};
    if (ws?.containerId && Containers.exists(ws.containerId)) {
      opts.userContextId = Number(ws.containerId);
    }
    const tab = this.#addTab("about:newtab", opts);
    if (!tab) return null;
    Store.setTabWorkspace(tab, wsId);
    Store.setManual(tab, false);
    if (select) {
      this.#setTabHidden(tab, false);
      this.gBrowser.selectedTab = tab;
    }
    this.emit();
    return tab;
  }

  #addTab(url, opts = {}) {
    try {
      const params = {
        triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal(),
        ...opts,
      };
      return this.gBrowser.addTab(url, params);
    } catch (e) {
      console.warn("[sine-workspaces] addTab failed:", e);
      return null;
    }
  }

  // Unload (discard) every tab in a workspace — used by the strip context menu.
  unloadWorkspace(wsId) {
    for (const tab of this.#tabsFor(wsId)) {
      if (tab.selected || tab.pinned) continue;
      try {
        this.gBrowser.discardBrowser(tab);
      } catch (_e) {
        /* ignore */
      }
    }
    this.emit();
  }

  // Called when the config changes on disk (Manage page edits).
  onConfigReloaded() {
    if (!Store.hasWorkspace(this.activeId)) this.activeId = Store.defaultId;
    this.applyVisibility();
    this.emit();
  }
}
