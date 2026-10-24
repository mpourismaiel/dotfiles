// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — per-window workspace controller.
//
// One instance per browser window. Owns tab visibility for that window: it hides
// tabs (pinned + normal + grouped) that don't belong to the active workspace and
// shows the ones that do. It also routes new tabs: URL rules on tab creation
// pick a workspace + container, otherwise the active workspace's default
// container applies. A new tab that is in front of you (an external link from
// Slack/Telegram, or a selected tab a rule moves) takes you to its workspace;
// background tabs move quietly.
//
// Tab groups (folders) are workspace-bound: every tab in a group carries the
// group's workspace. A tab joining a group (drag, "Move to group") is retagged
// to that group's workspace, and moving a grouped tab to another workspace
// takes it out of the group — so a folder never straddles workspaces and its
// tabs show wherever the folder shows.

import Store from "./store.sys.mjs";
import Rules from "./rules.sys.mjs";
import Containers from "./containers.sys.mjs";

// Genuine "fresh tab" pages. A bare about:blank / "" is deliberately excluded:
// Firefox's real new tab is about:newtab/home, so a bare about:blank with no
// typed URL is a special trusted tab (e.g. Customize Toolbar) we must not touch.
const NEWTAB = new Set(["about:newtab", "about:home", "chrome://browser/content/blanktab.html"]);

export class WorkspacesController {
  constructor(win) {
    this.win = win;
    this.gBrowser = win.gBrowser;
    this.activeId = null;
    this.lastActiveByWs = new Map(); // wsId -> tab (remembered active tab)
    this.listeners = new Set();
    this._pendingRule = new WeakSet(); // brand-new tabs awaiting one-shot rule eval
    this._adopt = null; // { wsId, manual } for the next tab WE open (see #openTab)
    this._switching = false;
    this._boundHandlers = {};
    this._tabsProgress = null;
  }

  // ---- lifecycle -----------------------------------------------------------

  init() {
    // Heal folders that already straddle workspaces (tabs moved into another
    // workspace's group before groups were workspace-bound) so their stray
    // tabs show up in the folder instead of staying hidden.
    this.#normalizeGroups();

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
    c.removeEventListener("TabGrouped", this._boundHandlers.grouped);
    if (this._tabsProgress) this.gBrowser.removeTabsProgressListener(this._tabsProgress);
    this.listeners.clear();
  }

  #wire() {
    const c = this.gBrowser.tabContainer;
    this._boundHandlers.open = (e) => this.#onTabOpen(e.target, e.detail);
    this._boundHandlers.close = (e) => this.#onTabClose(e.target);
    this._boundHandlers.select = (e) => this.#onTabSelect(e.target);
    // Firefox dispatches TabGrouped on the GROUP (bubbling) with the tab in
    // `detail` — see tab.js #updateOnTabGrouped.
    this._boundHandlers.grouped = (e) => this.#onTabGrouped(e.detail);
    c.addEventListener("TabOpen", this._boundHandlers.open);
    c.addEventListener("TabClose", this._boundHandlers.close);
    c.addEventListener("TabSelect", this._boundHandlers.select);
    c.addEventListener("TabGrouped", this._boundHandlers.grouped);

    // Rule fallback for new tabs whose URL wasn't known when they opened (a
    // Ctrl+T tab the user then types into): evaluate once, on the first real
    // top-level URL. New-tab pages don't count — they'd use the one shot up.
    this._tabsProgress = {
      onLocationChange: (browser, webProgress, _request, location, _flags) => {
        if (!webProgress?.isTopLevel) return;
        const tab = this.gBrowser.getTabForBrowser(browser);
        if (!tab || !this._pendingRule.has(tab)) return;
        const spec = location?.spec || "";
        if (!spec || spec === "about:blank" || NEWTAB.has(spec)) return;
        this._pendingRule.delete(tab); // creation-only: evaluate exactly once
        if (Store.isManual(tab)) return;
        const hit = Rules.match(Store.workspaces, spec);
        if (!hit) return;
        // The page has committed, so reopening it in the rule's container
        // reloads it — fine for the first navigation of a fresh tab.
        this.#route(tab, {
          wsId: hit.workspace.id,
          containerId: Rules.containerFor(hit),
          url: spec,
          follow: tab.selected,
        });
        this.emit();
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
      .sort((a, b) => (b.pinned - a.pinned) || (a.index - b.index));
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

  // ---- tab groups ----------------------------------------------------------

  // A group's workspace = the workspace of its first tagged tab (ignoring
  // `exclude`, the tab that is just joining). Null for a group with no other
  // tagged tabs — e.g. a brand-new group, which then takes its tabs' workspace.
  #groupWorkspace(group, exclude = null) {
    if (!group) return null;
    for (const t of group.tabs || []) {
      if (t === exclude || t.closing) continue;
      const wid = Store.getTabWorkspace(t);
      if (wid && Store.hasWorkspace(wid)) return wid;
    }
    return null;
  }

  // Retag any tab whose workspace differs from its group's.
  #normalizeGroups() {
    let groups = [];
    try {
      groups = this.gBrowser.tabGroups || [];
    } catch (_e) {
      return;
    }
    for (const group of groups) {
      const wid = this.#groupWorkspace(group);
      if (!wid) continue;
      for (const t of group.tabs || []) {
        if (Store.getTabWorkspace(t) && Store.getTabWorkspace(t) !== wid) {
          Store.setTabWorkspace(t, wid);
        }
      }
    }
  }

  // A tab joined a group: it now lives in that group's workspace. Untagged tabs
  // (still opening) are left to #onTabOpen, which reads the group itself.
  #onTabGrouped(tab) {
    if (!tab || tab.closing || !this.gBrowser.tabs.includes(tab)) return;
    const tag = Store.getTabWorkspace(tab);
    if (!tag) return;
    const wid = this.#groupWorkspace(tab.group, tab);
    if (wid && wid !== tag) this.moveTabsToWorkspace([tab], wid);
  }

  // Take tabs that are leaving for another workspace out of their group,
  // unless the whole group is going with them.
  #detachFromGroups(tabs, wsId) {
    const moving = new Set(tabs);
    for (const tab of tabs) {
      const group = tab.group;
      if (!group || this.#groupWorkspace(group, tab) === wsId) continue;
      if ((group.tabs || []).every((t) => moving.has(t))) continue;
      try {
        this.gBrowser.ungroupTab(tab);
      } catch (e) {
        console.warn("[sine-workspaces] ungroupTab failed:", e);
      }
    }
  }

  // ---- switching -----------------------------------------------------------

  switchTo(wsId) {
    if (!Store.hasWorkspace(wsId) || this._switching) return;
    if (wsId === this.activeId) return;

    const prevSel = this.gBrowser.selectedTab;
    const prevIndex = prevSel?.index ?? 0;
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
      Math.abs(t.index - refIndex) < Math.abs(best.index - refIndex) ? t : best
    );
  }

  // ---- tab lifecycle -------------------------------------------------------

  #onTabOpen(tab, detail) {
    // A tab we opened ourselves (#openTab: the API, container reopens) comes
    // pre-routed — tag it and skip rules / container defaults / placement.
    const adopt = this._adopt;
    if (adopt) {
      this._adopt = null;
      Store.setTabWorkspace(tab, adopt.wsId);
      Store.setManual(tab, adopt.manual);
      return;
    }
    // Restored / duplicated tabs already carry a persisted tag — keep it.
    if (Store.getTabWorkspace(tab)) return;

    // A tab opened inside a folder (e.g. a link from a grouped tab) belongs to
    // the folder's workspace.
    Store.setTabWorkspace(tab, this.#groupWorkspace(tab.group, tab) || this.activeId);
    Store.setManual(tab, false);
    this._pendingRule.add(tab);

    // Captured now because Firefox can clear openerTab as related tabs chain.
    const opener = tab.openerTab || null;
    const external = !!detail?.fromExternal;
    // Deferred so it runs after Firefox finishes inserting the tab and has
    // put the destination URL in userTypedValue.
    this.win.setTimeout(() => this.#routeNewTab(tab, opener, external), 0);
    this.emit();
  }

  // Decide where a fresh tab lives. Its URL is known now for links (external
  // or from a page): the first matching rule picks workspace + container.
  // With no match it stays in its workspace (the active one, or its folder's)
  // and — unless it was opened FROM a page, which inherits that page's
  // container — gets the workspace's default container. External links always
  // take you to wherever they land; so does a selected tab a rule moves.
  // For external links the container is authoritative (none if neither rule
  // nor workspace names one): Firefox otherwise guesses one from tabs already
  // open on the same host (URILoadingHelper.guessUserContextId).
  #routeNewTab(tab, opener, external) {
    try {
      if (!tab || tab.closing || !this.gBrowser.tabs.includes(tab)) return;
      const browser = tab.linkedBrowser;
      const pending = browser?.userTypedValue || "";
      const spec = browser?.currentURI?.spec ?? "";
      const url = pending || (spec !== "about:blank" && !NEWTAB.has(spec) ? spec : "");

      let wsId = Store.getTabWorkspace(tab) || this.activeId;
      let containerId = null;
      let matched = false;
      if (url) {
        this._pendingRule.delete(tab); // the one-shot rule evaluation is now
        const hit = Store.isManual(tab) ? null : Rules.match(Store.workspaces, url);
        if (hit) {
          matched = true;
          wsId = hit.workspace.id;
          containerId = Rules.containerFor(hit);
        }
      }
      if (!matched && !opener) {
        const def = Store.getWorkspace(wsId)?.containerId;
        containerId = def ? Number(def) : null;
      }
      // A reopen needs a destination that hasn't committed yet: the typed /
      // external URL, or a genuine new-tab page. A bare about:blank with no
      // destination is a special trusted tab (Customize Toolbar, view-source)
      // and is left alone.
      const reopenUrl = pending || (NEWTAB.has(spec) ? "about:newtab" : "");

      const t = this.#route(tab, {
        wsId,
        containerId: external ? containerId ?? 0 : containerId,
        force: external,
        url: reopenUrl,
        follow: external || (matched && tab.selected),
      });
      this.#placeNewTab(t, opener);
      this.emit();
    } catch (e) {
      console.warn("[sine-workspaces] routeNewTab failed:", e);
    }
  }

  // Put a tab in workspace `wsId` and (if it has none yet) container
  // `containerId`. A tab's container can't change in place, so that reopens
  // `url` in a new tab at the same spot and closes the old one. A tab that
  // already has a container (a Multi-Account-Containers site assignment, an
  // explicit "open in container") keeps it — that also rules out reopen
  // ping-pong with MAC — unless `force` (external links: containerId is then
  // exact, 0 meaning none). `follow` selects the tab and switches to its
  // workspace; otherwise a tab landing in another workspace is hidden.
  // Returns the (possibly new) tab.
  #route(tab, { wsId, containerId, url, follow, force = false }) {
    let t = tab;
    const current = parseInt(tab.getAttribute("usercontextid") || "0", 10);
    const wanted = force
      ? containerId !== current && (containerId === 0 || Containers.exists(containerId))
      : containerId > 0 && current === 0 && Containers.exists(containerId);
    if (wanted && url) {
      t = this.#reopen(tab, url, { userContextId: containerId, wsId, manual: false }) || tab;
    }
    if (Store.getTabWorkspace(t) !== wsId) {
      this.#detachFromGroups([t], wsId);
      Store.setTabWorkspace(t, wsId);
    }
    if (follow) {
      if (!t.selected) this.gBrowser.selectedTab = t; // #onTabSelect switches
      else if (wsId !== this.activeId) this.#activate(wsId, t);
    } else {
      this.#setTabHidden(t, wsId !== this.activeId);
    }
    this.#updateGroups();
    return t;
  }

  // Replace `tab` with a fresh one loading `url` in another container: same
  // position, same folder, same selection. Returns the new tab (null on error).
  #reopen(tab, url, { userContextId, wsId, manual }) {
    const newTab = this.#openTab(url, {
      wsId,
      manual,
      userContextId,
      tabIndex: tab.index + 1,
      tabGroup: tab.group || undefined,
      inBackground: !tab.selected,
    });
    if (!newTab) return null;
    if (tab.selected) this.gBrowser.selectedTab = newTab;
    this.gBrowser.removeTab(tab);
    return newTab;
  }

  // Open a tab that is already routed: tagged `wsId` (and `manual`) before
  // TabOpen handlers run, so rules / container defaults / placement skip it.
  // Remaining options go to gBrowser.addTab (userContextId, tabIndex,
  // tabGroup, createLazyBrowser, lazyTabTitle, inBackground, ...).
  #openTab(url, { wsId, manual = false, ...opts }) {
    this._adopt = { wsId, manual };
    try {
      return this.#addTab(url, { skipAnimation: true, ...opts });
    } finally {
      this._adopt = null;
    }
  }

  // Place a freshly-opened tab within its workspace. Skips pinned and grouped
  // tabs (respect the group). A link-opened tab goes next to its opener when
  // both share a workspace; otherwise (blank tabs, rule-moved tabs) it goes to
  // the end of its workspace.
  #placeNewTab(tab, opener) {
    try {
      if (!tab || tab.closing || tab.pinned || tab.group) return;
      if (!this.gBrowser.tabs.includes(tab)) return;
      const wsOf = (t) => Store.getTabWorkspace(t) || Store.defaultId;
      if (opener && !opener.closing && this.gBrowser.tabs.includes(opener) && wsOf(opener) === wsOf(tab)) {
        this.#placeAfterOpener(tab, opener);
      } else {
        this.moveToWorkspaceEnd(tab);
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
      const first = normals[0]; // #tabsFor sorts by index ascending
      if (tab.index > first.index) this.gBrowser.moveTabTo(tab, { tabIndex: first.index });
    } else {
      const target = tab.index > opener.index ? opener.index + 1 : opener.index;
      if (tab.index !== target) this.gBrowser.moveTabTo(tab, { tabIndex: target });
    }
  }

  // Move a tab so it sits just after the last (non-pinned) tab of its
  // workspace. No-op when there are no other normal tabs (Firefox already
  // appends at the end). Public: the script API uses it to order tabs.
  moveToWorkspaceEnd(tab) {
    const wsId = Store.getTabWorkspace(tab) || Store.defaultId;
    const peers = this.#tabsFor(wsId).filter((t) => t !== tab && !t.pinned);
    if (!peers.length) return;
    const last = peers[peers.length - 1]; // #tabsFor sorts by index ascending
    const target = tab.index > last.index ? last.index + 1 : last.index;
    if (tab.index !== target) {
      this.gBrowser.moveTabTo(tab, { tabIndex: target, forceUngrouped: !tab.group });
    }
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
          this.#pickAndSelect(this.activeId, tab.index);
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
      let succ = this.#closest(peers.filter((t) => this.#isLoaded(t)), tab.index);
      if (!succ) succ = this.#closest(peers, tab.index);
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
      this.#activate(wid, tab);
    } else {
      this.lastActiveByWs.set(this.activeId, tab);
      this.#refreshSuccessor();
    }
  }

  // Make `wsId` the active workspace with `tab` (already selected) in front.
  #activate(wsId, tab) {
    this.lastActiveByWs.set(wsId, tab);
    this.activeId = wsId;
    Store.setLastActiveId(wsId);
    this.applyVisibility();
    this.emit();
  }

  // ---- assignment / creation ----------------------------------------------

  // Move a tab into a workspace. `manual` marks it sticky (rules stop touching it).
  assignTab(tab, wsId, manual = true) {
    if (!Store.hasWorkspace(wsId)) return;
    this.#detachFromGroups([tab], wsId);
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
    const refIndex = this.gBrowser.selectedTab?.index ?? 0;

    this.#detachFromGroups(list, wsId);
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

  // ---- script API (api.sys.mjs) ------------------------------------------

  groupWorkspace(group) {
    return this.#groupWorkspace(group);
  }

  // Open URLs straight into a workspace (+ container, + folder) without
  // touching selection. `lazy` tabs don't load until clicked. Returns the tabs.
  openTabs(entries, { wsId, userContextId = 0, group = null, lazy = true }) {
    const tabs = [];
    for (const { url, title } of entries) {
      const lazyOk = lazy && !/^about:/i.test(url);
      const tab = this.#openTab(url, {
        wsId,
        manual: true,
        userContextId,
        tabGroup: group || undefined,
        inBackground: true,
        createLazyBrowser: lazyOk,
        lazyTabTitle: lazyOk ? title || url : undefined,
      });
      if (!tab) continue;
      if (!group) this.moveToWorkspaceEnd(tab);
      this.#setTabHidden(tab, wsId !== this.activeId);
      tabs.push(tab);
    }
    this.#updateGroups();
    return tabs;
  }

  // Move a tab to another container (reopens it: back/forward history is lost).
  reopenInContainer(tab, userContextId) {
    const browser = tab.linkedBrowser;
    const url = browser?.currentURI?.spec || browser?.userTypedValue || "about:newtab";
    const wsId = Store.getTabWorkspace(tab) || Store.defaultId;
    const t = this.#reopen(tab, url, { userContextId, wsId, manual: Store.isManual(tab) });
    if (t) this.#setTabHidden(t, wsId !== this.activeId);
    return t;
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
    this.#normalizeGroups();
    this.applyVisibility();
    this.emit();
  }
}
