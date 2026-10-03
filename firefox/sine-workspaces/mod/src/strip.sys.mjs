// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — the nav-bar workspace strip.
//
// Injects a centered row of workspace chips into #nav-bar (icon + live tab count,
// workspace name as tooltip, active chip highlighted). Left-click switches; right
// -click opens a small menu (Unload all tabs / Manage workspaces).

import Store from "./store.sys.mjs";

const STRIP_ID = "sine-workspaces-strip";
const MENU_ID = "sine-workspaces-menu";
const MANAGE_URL = "chrome://sine-workspaces/content/manage/manage.html";

export class WorkspacesStrip {
  constructor(win, controller) {
    this.win = win;
    this.doc = win.document;
    this.controller = controller;
    this.strip = null;
    this.menuTargetWs = null;
    this._unsub = null;
    this._observer = null;
    this._reattachQueued = false;
  }

  build() {
    const existing = this.doc.getElementById(STRIP_ID);
    if (existing?.isConnected) {
      this.strip = existing;
      return;
    }

    // The strip element is created once and reused; placement happens separately
    // so we can re-attach it if the sidebar/toolbar is rebuilt.
    this.strip = this.doc.createXULElement("hbox");
    this.strip.id = STRIP_ID;
    this.strip.setAttribute("align", "center");

    this.#buildMenu();
    this._unsub = this.controller.onChange(() => this.render());
    this.render();

    // Attach into the DOM, then keep watching so it survives update hiccups:
    // on a real session the sidebar/pinned-tabs container can be built AFTER this
    // runs, or torn down and recreated (Natsumi/Firefox do this across updates),
    // which is how the strip kept "disappearing". The observer re-attaches it
    // whenever it ends up detached.
    this.#place();
    this.#watch();
  }

  // Insert the strip into its preferred home: inside the vertical-tabs list,
  // directly above the pinned-tabs section, so the chips always sit atop the
  // sidebar's own tab area — deliberately NOT the nav-bar, which Natsumi
  // rearranges/breaks on Firefox updates. Returns true once attached.
  #place() {
    if (!this.strip || this.strip.isConnected) return this.strip?.isConnected;

    const tabsHost = this.doc.getElementById("tabbrowser-tabs");
    const pinned = this.doc.getElementById("pinned-tabs-container");
    if (tabsHost && pinned && pinned.parentNode === tabsHost) {
      // #tabbrowser-tabs already holds several non-tab children (drop indicators,
      // promo card, splitter), so one more sibling is fine.
      tabsHost.insertBefore(this.strip, pinned);
      return true;
    }

    // Fallback (no vertical tabs / anchor not ready): the old nav-bar placement,
    // right-aligned before the right-hand toolbar cluster.
    const host =
      this.doc.getElementById("nav-bar-customization-target") ||
      this.doc.getElementById("nav-bar");
    if (!host) return false;
    const kids = [...host.children];
    const anchor =
      kids.find((c) => c.id === "downloads-button") ||
      kids.find((c) => c.id === "fxa-toolbar-menu-button") ||
      kids.find((c) => c.id === "unified-extensions-button") ||
      kids.find((c) => c.id === "urlbar-container");
    if (anchor) host.insertBefore(this.strip, anchor);
    else host.appendChild(this.strip);
    return true;
  }

  // Watch the chrome document so the strip re-attaches itself if it is ever
  // detached (sidebar/toolbar rebuild) or if its preferred anchor appears late.
  // Also hops out of the nav-bar fallback into the sidebar once that's available.
  #watch() {
    if (this._observer) return;
    const reattach = () => {
      if (this._reattachQueued) return;
      this._reattachQueued = true;
      this.win.requestAnimationFrame(() => {
        this._reattachQueued = false;
        if (!this.strip) return;
        const tabsHost = this.doc.getElementById("tabbrowser-tabs");
        const pinned = this.doc.getElementById("pinned-tabs-container");
        const sidebarReady = tabsHost && pinned && pinned.parentNode === tabsHost;
        // Re-place when detached, or when still parked in the nav-bar fallback
        // but the sidebar anchor has since become available.
        const parkedInFallback =
          this.strip.isConnected && this.strip.parentNode !== tabsHost;
        if (!this.strip.isConnected || (sidebarReady && parkedInFallback)) {
          if (sidebarReady && parkedInFallback) this.strip.remove();
          this.#place();
        }
      });
    };
    this._observer = new this.win.MutationObserver(reattach);
    this._observer.observe(this.doc.documentElement, {
      childList: true,
      subtree: true,
    });
  }

  destroy() {
    if (this._unsub) this._unsub();
    this._observer?.disconnect();
    this._observer = null;
    this.strip?.remove();
    this.doc.getElementById(MENU_ID)?.remove();
  }

  #buildMenu() {
    if (this.doc.getElementById(MENU_ID)) return;
    const popupset =
      this.doc.getElementById("mainPopupSet") || this.doc.documentElement;
    const menu = this.doc.createXULElement("menupopup");
    menu.id = MENU_ID;

    const unload = this.doc.createXULElement("menuitem");
    unload.setAttribute("label", "Unload all tabs");
    unload.addEventListener("command", () => {
      if (this.menuTargetWs) this.controller.unloadWorkspace(this.menuTargetWs);
    });

    const manage = this.doc.createXULElement("menuitem");
    manage.setAttribute("label", "Manage workspaces…");
    manage.addEventListener("command", () => this.openManage());

    menu.append(unload, manage);
    popupset.appendChild(menu);
  }

  openManage() {
    const gBrowser = this.win.gBrowser;
    // Reuse an existing Manage tab if one is open.
    for (const tab of gBrowser.tabs) {
      if (tab.linkedBrowser?.currentURI?.spec === MANAGE_URL) {
        gBrowser.selectedTab = tab;
        return;
      }
    }
    gBrowser.selectedTab = gBrowser.addTrustedTab
      ? gBrowser.addTrustedTab(MANAGE_URL)
      : gBrowser.addTab(MANAGE_URL, {
          triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal(),
        });
  }

  render() {
    if (!this.strip) return;
    while (this.strip.firstChild) this.strip.firstChild.remove();

    // Global badge background color (empty → theme accent via the CSS fallback).
    const badgeColor = Store.config?.badgeColor || "";
    if (badgeColor) this.strip.style.setProperty("--sine-badge-bg", badgeColor);
    else this.strip.style.removeProperty("--sine-badge-bg");

    for (const ws of Store.workspaces) {
      // A plain hbox (not toolbarbutton) so the label isn't suppressed by the
      // toolbar's icons-only display mode.
      const chip = this.doc.createXULElement("hbox");
      chip.className = "sine-ws-chip";
      chip.setAttribute("align", "center");
      chip.setAttribute("tooltiptext", ws.name);
      if (ws.id === this.controller.activeId) chip.setAttribute("active", "true");
      if (ws.color) chip.style.setProperty("--sine-ws-color", ws.color);

      const icon = this.doc.createXULElement("label");
      icon.className = "sine-ws-chip-icon";
      icon.setAttribute("value", ws.icon);
      chip.append(icon);

      // Tab count as a small badge at the top-right of the icon (hidden when 0).
      const n = this.controller.count(ws.id);
      if (n > 0) {
        const count = this.doc.createXULElement("label");
        count.className = "sine-ws-chip-count";
        count.setAttribute("value", String(n));
        chip.append(count);
      }

      chip.addEventListener("click", (e) => {
        if (e.button === 0) this.controller.switchTo(ws.id);
      });
      chip.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        this.menuTargetWs = ws.id;
        this.doc
          .getElementById(MENU_ID)
          .openPopup(chip, "after_start", 0, 0, true, false);
      });
      this.strip.appendChild(chip);
    }
  }
}
