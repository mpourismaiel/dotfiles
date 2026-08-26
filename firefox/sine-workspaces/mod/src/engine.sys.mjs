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
    // Choose the initial active workspace. Normally it's the restored selected
    // tab's workspace. But on a cold start triggered by an external link (a
    // Slack message, etc.), Firefox creates and selects that tab before this
    // controller exists, so it carries no workspace tag. Falling back to the
    // default here would yank the user out of the workspace they left — and hide
    // it — which reads as "the link just opened an empty new tab". So when the
    // selected tab is untagged, restore the last workspace the user was on.
    const selTag = Store.getTabWorkspace(this.gBrowser.selectedTab);
    if (selTag && Store.hasWorkspace(selTag)) {
      this.activeId = selTag;
    } else {
      const last = Store.getLastActiveId();
      this.activeId = last && Store.hasWorkspace(last) ? last : Store.defaultId;
    }

    // Tag any untagged tabs (fresh profile / imported session / a brand-new
    // external tab created before we wired up) into the ACTIVE workspace, so
    // they stay visible instead of being hidden away in the default one.
    for (const tab of this.gBrowser.tabs) {
      if (!Store.getTabWorkspace(tab)) Store.setTabWorkspace(tab, this.activeId);
    }
    Store.setLastActiveId(this.activeId);

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
    this.#refreshSuccessor();
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
      Store.setLastActiveId(wsId);
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
    // Position the new tab within its workspace. A blank tab (Ctrl+T / new-tab
    // button) goes to the END; a tab opened FROM a link (middle-click, "open in
    // new tab" — Firefox sets openerTab) goes right after the tab it came from.
    // Deferred so it runs after Firefox finishes inserting the tab. openerTab is
    // captured now because Firefox can clear it as related tabs chain.
    const opener = tab.openerTab || null;
    this.win.setTimeout(() => this.#placeNewTab(tab, opener), 0);
    this.emit();
  }

  // Place a freshly-opened tab within its workspace. Skips pinned and grouped
  // tabs (respect the group). Link-opened tabs (an opener) go next to the opener;
  // blank tabs go to the end of the workspace.
  #placeNewTab(tab, opener) {
    try {
      if (!tab || tab.closing || tab.pinned || tab.group) return;
      if (!this.gBrowser.tabs.includes(tab)) return;
      if (opener && !opener.closing && this.gBrowser.tabs.includes(opener)) {
        this.#placeAfterOpener(tab, opener);
      } else {
        this.#moveToWorkspaceEnd(tab);
      }
    } catch (e) {
      console.warn("[sine-workspaces] placeNewTab failed:", e);
    }
  }

  // A link-opened tab sits immediately after the tab it came from. If that tab
  // is pinned, the link tab can't live among the pinned tabs, so it's prepended
  // to the workspace's non-pinned tabs instead.
  #placeAfterOpener(tab, opener) {
    const wsId = Store.getTabWorkspace(tab) || Store.defaultId;
    if (opener.pinned) {
      const normals = this.#tabsFor(wsId).filter((t) => t !== tab && !t.pinned);
      if (!normals.length) return; // tab is the only non-pinned one — already fine
      const first = normals[0]; // #tabsFor sorts by _tPos ascending
      if (tab._tPos > first._tPos) this.gBrowser.moveTabTo(tab, { tabIndex: first._tPos });
    } else {
      const target = tab._tPos > opener._tPos ? opener._tPos + 1 : opener._tPos;
      if (tab._tPos !== target) this.gBrowser.moveTabTo(tab, { tabIndex: target });
    }
  }

  // Move a freshly-opened blank tab so it sits just after the last (non-pinned)
  // tab of its workspace. No-op when there are no other normal tabs (Firefox
  // already appends at the end).
  #moveToWorkspaceEnd(tab) {
    const wsId = Store.getTabWorkspace(tab) || Store.defaultId;
    const peers = this.#tabsFor(wsId).filter((t) => t !== tab && !t.pinned);
    if (!peers.length) return;
    const last = peers[peers.length - 1]; // #tabsFor sorts by _tPos ascending
    const target = tab._tPos > last._tPos ? last._tPos + 1 : last._tPos;
    if (tab._tPos !== target) this.gBrowser.moveTabTo(tab, { tabIndex: target });
  }

  #applyContainerDefault(tab, userContextId) {
    if (!tab || tab.closing || !this.gBrowser.tabs.includes(tab)) return;
    const current = parseInt(tab.getAttribute("usercontextid") || "0", 10);
    if (current === userContextId) return;
    const browser = tab.linkedBrowser;
    // A tab opened for a real URL (external link from Slack/Telegram, a
    // link with target=_blank, etc.) reports currentURI="about:blank" for the
    // first tick — the load hasn't committed yet — but already carries its
    // destination in userTypedValue (and, a moment later, a live document
    // load). Reopening it in the container would discard that pending load and
    // leave an empty new tab, so bail out. Only genuinely blank new tabs
    // (Ctrl+T, with no pending navigation) get reopened into the container.
    if (browser?.userTypedValue || browser?.webProgress?.isLoadingDocument) return;
    const spec = browser?.currentURI?.spec ?? "";
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
    // If the active tab is closing, choose its replacement ourselves — the
    // closest still-loaded tab in the workspace — rather than leaving whatever
    // positional neighbor Firefox selects, which may be an unloaded tab.
    // If the active tab of the current workspace is closing, re-pick per cascade.
    // (Firefox usually beats us to it via the successor tab we keep set — see
    // #refreshSuccessor — but this covers the cases where it doesn't, e.g. the
    // workspace just went empty.)
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

  // Keep the selected tab's "successor" pointed at the closest still-loaded tab
  // in its workspace. Firefox selects a closing tab's successor first of all
  // (tabbrowser._findTabToBlurTo), so this makes closing the active tab land on
  // the nearest loaded neighbor (a pinned tab counts) instead of whatever
  // positional — possibly unloaded — tab Firefox would otherwise pick. Falls
  // back to the closest tab of any load state; clears the successor if the tab
  // is alone in its workspace (so an empty workspace is handled by #onTabClose).
  #refreshSuccessor() {
    try {
      const tab = this.gBrowser.selectedTab;
      if (!tab || tab.closing) return;
      const wsId = Store.getTabWorkspace(tab) || Store.defaultId;
      const peers = this.#tabsFor(wsId).filter((t) => t !== tab && !t.closing);
      let succ = this.#closest(peers.filter((t) => this.#isLoaded(t)), tab._tPos);
      if (!succ) succ = this.#closest(peers, tab._tPos);
      this.gBrowser.setSuccessor(tab, succ || null);
    } catch (e) {
      console.warn("[sine-workspaces] refreshSuccessor failed:", e);
    }
  }

  #onTabSelect(tab) {
    if (this._switching) return;
    // Selecting a tab that lives in another workspace switches to that workspace.
    const wid = Store.getTabWorkspace(tab) || Store.defaultId;
    if (wid !== this.activeId && Store.hasWorkspace(wid)) {
      this.lastActiveByWs.set(wid, tab);
      this.activeId = wid;
      Store.setLastActiveId(wid);
      this.applyVisibility();
      this.emit();
    } else {
      this.lastActiveByWs.set(this.activeId, tab);
      this.#refreshSuccessor();
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

  // Move one or more tabs (e.g. dropped on a workspace chip) into a workspace.
  // Marks them manual (sticky). If the active tab is among them and the target
  // isn't the active workspace, picks a replacement active tab first so the
  // moved tabs can be safely hidden.
  moveTabsToWorkspace(tabs, wsId) {
    if (!Store.hasWorkspace(wsId)) return;
    const list = [...new Set(tabs)].filter(
      (t) => t && !t.closing && this.gBrowser.tabs.includes(t)
    );
    if (!list.length) return;

    const movedActive = list.includes(this.gBrowser.selectedTab);
    const refIndex = this.gBrowser.selectedTab?._tPos ?? 0;

    for (const tab of list) {
      Store.setTabWorkspace(tab, wsId);
      Store.setManual(tab, true);
    }

    if (movedActive && wsId !== this.activeId) {
      this.#pickAndSelect(this.activeId, refIndex);
    }

    for (const tab of list) this.#setTabHidden(tab, wsId !== this.activeId);
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
