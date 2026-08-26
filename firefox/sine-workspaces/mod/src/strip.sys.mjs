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
  }

  build() {
    // Toolbar items live inside #nav-bar-customization-target, not directly under
    // #nav-bar, so we inject there. (Natsumi single-toolbar also relocates the
    // urlbar, so we anchor only against nodes that are real children of the host.)
    const host =
      this.doc.getElementById("nav-bar-customization-target") ||
      this.doc.getElementById("nav-bar");
    if (!host || this.doc.getElementById(STRIP_ID)) return;

    const strip = this.doc.createXULElement("hbox");
    strip.id = STRIP_ID;
    strip.setAttribute("align", "center");

    // Right-align: place the strip just before the right-hand toolbar cluster so
    // the flexible spring/spacer in front of it pushes the chips to the right.
    const kids = [...host.children];
    const anchor =
      kids.find((c) => c.id === "downloads-button") ||
      kids.find((c) => c.id === "fxa-toolbar-menu-button") ||
      kids.find((c) => c.id === "unified-extensions-button") ||
      kids.find((c) => c.id === "urlbar-container");
    if (anchor) host.insertBefore(strip, anchor);
    else host.appendChild(strip);
    this.strip = strip;

    this.#buildMenu();
    this._unsub = this.controller.onChange(() => this.render());
    this.render();
  }

  destroy() {
    if (this._unsub) this._unsub();
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
