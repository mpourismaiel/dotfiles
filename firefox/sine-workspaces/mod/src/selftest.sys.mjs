// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — dev self-test. Only runs when the pref
// `sine-workspaces.selftest` is true. Exercises the strip + engine end-to-end
// and logs each step, so behavior can be verified from the terminal without a
// screenshot. Not loaded in normal use.

import Store from "./store.sys.mjs";

const P = "[sine-workspaces:selftest]";

function visibleCount(gBrowser) {
  return [...gBrowser.tabs].filter(
    (t) => !t.hidden && !t.hasAttribute("sine-ws-hidden")
  ).length;
}

function snapshot(controller) {
  const counts = {};
  for (const ws of Store.workspaces) counts[ws.id] = controller.count(ws.id);
  return {
    active: controller.activeId,
    totalTabs: controller.gBrowser.tabs.length,
    visible: visibleCount(controller.gBrowser),
    counts,
  };
}

export function runSelfTest(win, controller, strip) {
  try {
    const doc = win.document;
    const el = doc.getElementById("sine-workspaces-strip");
    const navbar = doc.getElementById("nav-bar");

    // 1. Strip placement.
    if (!el) {
      console.error(`${P} FAIL: strip element not found in DOM`);
    } else {
      const host = doc.getElementById("nav-bar-customization-target") || navbar;
      const kids = [...host.children].map((c) => c.id || c.tagName);
      console.log(
        `${P} strip OK — host=${host.id}, chips=${el.children.length}, ` +
          `prev=${el.previousElementSibling?.id}, next=${el.nextElementSibling?.id}`
      );
      console.log(`${P} host order: ${kids.join(", ")}`);
      console.log(
        `${P} chip labels: ${[...el.children].map((c) => c.getAttribute("label")).join(" | ")}`
      );
    }

    // 2. Initial state.
    console.log(`${P} initial ${JSON.stringify(snapshot(controller))}`);

    const wss = Store.workspaces;
    if (wss.length < 2) {
      console.log(`${P} only one workspace; skipping switch test`);
      return;
    }

    // 3. Switch to the 2nd workspace (empty → cascade should open a fresh tab).
    const targetId = wss[1].id;
    controller.switchTo(targetId);
    const afterSwitch = snapshot(controller);
    console.log(`${P} after switchTo(${targetId}) ${JSON.stringify(afterSwitch)}`);
    const ok1 =
      afterSwitch.active === targetId &&
      afterSwitch.visible === afterSwitch.counts[targetId] &&
      afterSwitch.visible >= 1;
    console.log(`${P} switch+isolation ${ok1 ? "PASS" : "FAIL"}`);

    // 4. Switch back to the first workspace; its tabs should reappear.
    const firstId = wss[0].id;
    controller.switchTo(firstId);
    const afterBack = snapshot(controller);
    console.log(`${P} after switchTo(${firstId}) ${JSON.stringify(afterBack)}`);
    const ok2 =
      afterBack.active === firstId &&
      afterBack.visible === afterBack.counts[firstId];
    console.log(`${P} switch-back ${ok2 ? "PASS" : "FAIL"}`);

    // 5. Pinned-tab isolation: pin a tab in the first workspace, switch away,
    //    and confirm it is hidden (this is the case gBrowser.hideTab can't do).
    let ok3 = true;
    const firstTabs = controller.orderedTabs(firstId);
    const pin = firstTabs.find((t) => !t.pinned);
    if (pin) {
      win.gBrowser.pinTab(pin);
      const p = pin.parentNode;
      console.log(
        `${P} pinned ancestry: parent=#${p?.id || "?"}.${p?.className || ""} ` +
          `grandparent=#${p?.parentNode?.id || "?"}`
      );
      controller.switchTo(targetId);
      const hidden = pin.hasAttribute("sine-ws-hidden");
      ok3 = hidden;
      console.log(`${P} pinned-tab hidden after switch: ${hidden} ${ok3 ? "PASS" : "FAIL"}`);
      controller.switchTo(firstId);
      win.gBrowser.unpinTab(pin);
    } else {
      console.log(`${P} pinned-tab test skipped (no eligible tab)`);
    }

    // 6. Unloaded-tab switch (issue #1): discard the target workspace's tabs
    //    while we're away, then switch to it — must land there with a tab active,
    //    NOT bounce to another workspace.
    controller.switchTo(firstId);
    for (const tt of controller.orderedTabs(targetId)) {
      if (!tt.selected) {
        try { win.gBrowser.discardBrowser(tt); } catch (_e) { /* ignore */ }
      }
    }
    controller.switchTo(targetId);
    const s6 = snapshot(controller);
    const ok4 = s6.active === targetId && s6.visible >= 1;
    console.log(`${P} unloaded-switch ${JSON.stringify(s6)} ${ok4 ? "PASS" : "FAIL"}`);
    controller.switchTo(firstId);

    // 7. Pinned grid (issues #3/#4): pin 3 tabs, verify container display + sizes.
    const container = win.document.getElementById("pinned-tabs-container");
    while (
      controller.orderedTabs(firstId).filter((t) => !t.pinned).length < 3
    ) {
      controller.newTabInWorkspace(firstId, { select: false });
    }
    const toPin = controller.orderedTabs(firstId).filter((t) => !t.pinned).slice(0, 3);
    toPin.forEach((t) => win.gBrowser.pinTab(t));
    const cs = container ? win.getComputedStyle(container) : null;
    const rects = toPin.map((t) => {
      const r = t.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height) };
    });
    const tcs = toPin[0] ? win.getComputedStyle(toPin[0]) : null;
    console.log(
      `${P} pinned grid: container.display=${cs?.display} flexWrap=${cs?.flexWrap} ` +
        `containerWidth=${Math.round(container?.getBoundingClientRect().width || 0)} ` +
        `tabRects=${JSON.stringify(rects)} ` +
        `tabComputed{width=${tcs?.width} minWidth=${tcs?.minWidth} maxWidth=${tcs?.maxWidth} ` +
        `flexBasis=${tcs?.flexBasis} display=${tcs?.display}}`
    );
    // Container-hide check: unpin all, confirm container computes to display:none.
    toPin.forEach((t) => win.gBrowser.unpinTab(t));
    const csEmpty = container ? win.getComputedStyle(container).display : "?";
    console.log(`${P} pinned container when empty: display=${csEmpty} (want none)`);

    console.log(`${P} DONE ${ok1 && ok2 && ok3 && ok4 ? "ALL PASS" : "SOME FAIL"}`);
  } catch (e) {
    console.error(`${P} threw:`, e);
  }
}
