// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — keyboard shortcuts.
//
//   Ctrl+1 … Ctrl+9        → activate the Nth tab in the ACTIVE workspace
//                            (counting pinned tabs first, then normal; 9 = last).
//   Ctrl+Shift+1 … +9      → switch to the Nth workspace.
//
// We intercept in the capturing phase so we shadow Firefox's native Ctrl+1..8
// "select tab N" bindings.

import Store from "./store.sys.mjs";

export class WorkspacesShortcuts {
  constructor(win, controller) {
    this.win = win;
    this.controller = controller;
    this._handler = (e) => this.#onKeyDown(e);
  }

  attach() {
    this.win.addEventListener("keydown", this._handler, true);
  }

  detach() {
    this.win.removeEventListener("keydown", this._handler, true);
  }

  #onKeyDown(e) {
    if (!e.ctrlKey || e.altKey || e.metaKey || e.repeat) return;
    // Match the physical digit key via e.code, not e.key: with Shift held e.key
    // is the shifted symbol ("!"…"(" on a US layout), so keying off e.key made
    // Ctrl+Shift+1…9 (switch workspace) never fire. e.code stays "Digit1"…
    // "Digit9" / "Numpad1"…"Numpad9" regardless of modifiers or layout.
    const m = /^(?:Digit|Numpad)([1-9])$/.exec(e.code || "");
    if (!m) return;
    const n = Number(m[1]);

    e.preventDefault();
    e.stopImmediatePropagation();

    if (e.shiftKey) {
      const ws = Store.workspaces[n - 1];
      if (ws) this.controller.switchTo(ws.id);
      return;
    }

    // Ctrl+9 → last tab (mirrors Firefox), otherwise the Nth tab.
    const tabs = this.controller.orderedTabs(this.controller.activeId);
    if (!tabs.length) return;
    const tab = n === 9 ? tabs[tabs.length - 1] : tabs[n - 1];
    if (tab) this.win.gBrowser.selectedTab = tab;
  }
}
