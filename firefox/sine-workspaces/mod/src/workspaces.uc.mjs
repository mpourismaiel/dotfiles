// ==UserScript==
// @include   chrome://browser/content/browser.xhtml
// @loadOrder 20
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — per-window entry point.
//
// Wires the store, the per-window controller, the nav-bar strip and the keyboard
// shortcuts together, and keeps them in sync when the Manage page edits config.

import Store from "./store.sys.mjs";
import { WorkspacesController } from "./engine.sys.mjs";
import { WorkspacesStrip } from "./strip.sys.mjs";
import { WorkspacesShortcuts } from "./shortcuts.sys.mjs";
import { WorkspaceTabMenu } from "./tabmenu.sys.mjs";

(() => {
  const win = window;
  if (win.__sineWorkspaces) return;
  win.__sineWorkspaces = true;

  const whenReady = (fn) => {
    if (win.gBrowserInit?.delayedStartupFinished) {
      fn();
      return;
    }
    const obs = (subject, topic) => {
      if (subject === win) {
        Services.obs.removeObserver(obs, topic);
        fn();
      }
    };
    Services.obs.addObserver(obs, "browser-delayed-startup-finished");
  };

  whenReady(async () => {
    try {
      await Store.ensureLoaded();

      const controller = new WorkspacesController(win);
      controller.init();

      const strip = new WorkspacesStrip(win, controller);
      try {
        strip.build();
      } catch (e) {
        console.error("[sine-workspaces] strip build failed (engine still active):", e);
      }

      const shortcuts = new WorkspacesShortcuts(win, controller);
      shortcuts.attach();

      const tabMenu = new WorkspaceTabMenu(win, controller);
      try {
        tabMenu.build();
      } catch (e) {
        console.error("[sine-workspaces] tab menu build failed:", e);
      }

      const unobserve = Store.observeConfigChange(async () => {
        await Store.reload();
        controller.onConfigReloaded();
        strip.render();
      });

      win.__sineWorkspacesAPI = { controller, strip, shortcuts, tabMenu };
      console.log(
        `[sine-workspaces] ready — ${Store.workspaces.length} workspaces, active=${controller.activeId}`
      );

      // Optional dev self-test (pref-gated) — logs behavior for terminal verification.
      if (Services.prefs.getBoolPref("sine-workspaces.selftest", false)) {
        const { runSelfTest } = await import("./selftest.sys.mjs");
        win.setTimeout(() => runSelfTest(win, controller, strip), 1500);
      }
      // Dev: open a fresh Manage tab on startup (pref-gated) for screenshotting.
      if (Services.prefs.getBoolPref("sine-workspaces.debug-open-manage", false)) {
        win.setTimeout(() => strip.openManage(), 1800);
      }

      const cleanup = () => {
        try {
          unobserve();
          shortcuts.detach();
          tabMenu.destroy();
          strip.destroy();
          controller.destroy();
        } catch (e) {
          console.warn("[sine-workspaces] cleanup error:", e);
        }
      };
      if (typeof win.addUnloadListener === "function") win.addUnloadListener(cleanup);
      else win.addEventListener("unload", cleanup, { once: true });
    } catch (e) {
      console.error("[sine-workspaces] init failed:", e);
    }
  });
})();
