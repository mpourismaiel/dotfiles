// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — "Move to workspace" submenu in the native tab context menu.
//
// Firefox blocks dragging tabs out of the tab strip onto the toolbar, so this is
// the way to move tabs between workspaces: right-click a tab (or a multi-selection)
// → Move to workspace → pick one.

import Store from "./store.sys.mjs";

const MENU_ID = "sine-ws-move-menu";

export class WorkspaceTabMenu {
  constructor(win, controller) {
    this.win = win;
    this.doc = win.document;
    this.controller = controller;
    this.menu = null;
    this.popup = null;
    this._onShowing = null;
    this._ctx = null;
  }

  build() {
    const ctx = this.doc.getElementById("tabContextMenu");
    if (!ctx || this.doc.getElementById(MENU_ID)) return;
    this._ctx = ctx;

    const menu = this.doc.createXULElement("menu");
    menu.id = MENU_ID;
    menu.setAttribute("label", "Move to workspace");

    const popup = this.doc.createXULElement("menupopup");
    popup.id = "sine-ws-move-popup";
    menu.appendChild(popup);

    // Place it right after Firefox's own "Move Tab" submenu when present.
    const anchor = this.doc.getElementById("context_moveTabOptions");
    if (anchor && anchor.parentNode === ctx) ctx.insertBefore(menu, anchor.nextSibling);
    else ctx.appendChild(menu);

    this.menu = menu;
    this.popup = popup;

    // Rebuild the submenu each time the context menu opens (workspaces and the
    // target tab change between invocations).
    this._onShowing = (e) => {
      if (e.target === ctx) this.#populate();
    };
    ctx.addEventListener("popupshowing", this._onShowing);
  }

  #targetTabs() {
    const gBrowser = this.win.gBrowser;
    const ctxTab = this.win.TabContextMenu?.contextTab || gBrowser.selectedTab;
    const sel = gBrowser.selectedTabs || [];
    // Acting on a tab inside a multi-selection moves the whole selection.
    if (ctxTab && ctxTab.multiselected && sel.length > 1) return [...sel];
    return ctxTab ? [ctxTab] : [];
  }

  #populate() {
    if (!this.popup) return;
    while (this.popup.firstChild) this.popup.firstChild.remove();

    const tabs = this.#targetTabs();
    this.menu.setAttribute(
      "label",
      tabs.length > 1 ? `Move ${tabs.length} tabs to workspace` : "Move to workspace"
    );
    // Hide the whole submenu if there's nothing to move (shouldn't happen).
    this.menu.hidden = tabs.length === 0;

    const currentWs = tabs.length
      ? Store.getTabWorkspace(tabs[0]) || Store.defaultId
      : null;

    for (const ws of Store.workspaces) {
      const item = this.doc.createXULElement("menuitem");
      item.setAttribute("type", "radio");
      item.setAttribute("name", "sine-ws-move");
      item.setAttribute("label", `${ws.icon}  ${ws.name}`);
      if (ws.id === currentWs) item.setAttribute("checked", "true");
      item.addEventListener("command", () =>
        this.controller.moveTabsToWorkspace(tabs, ws.id)
      );
      this.popup.appendChild(item);
    }
  }

  destroy() {
    if (this._ctx && this._onShowing) {
      this._ctx.removeEventListener("popupshowing", this._onShowing);
    }
    this.menu?.remove();
  }
}
