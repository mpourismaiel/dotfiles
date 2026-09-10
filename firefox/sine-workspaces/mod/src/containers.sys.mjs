// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — Multi-Account Containers helpers.
//
// A workspace may declare a default containerId (userContextId). When set, new
// blank tabs opened while that workspace is active are (re)opened in it. This is
// only a DEFAULT: Firefox Multi-Account Containers' own per-site assignments run
// as a webRequest listener and will still reopen the tab into its assigned
// container, which is exactly the "MAC wins" behavior the user asked for.

// ContextualIdentityService moved from resource://gre/modules/ to moz-src:/// in
// Firefox 155 (the old alias was dropped). Import defensively so a single moved
// path can't throw at module top-level and take the whole mod down with it: try
// the current location first, fall back to the legacy one, tolerate neither.
const ContextualIdentityService = (() => {
  const paths = [
    "moz-src:///toolkit/components/contextualidentity/ContextualIdentityService.sys.mjs",
    "resource://gre/modules/ContextualIdentityService.sys.mjs",
  ];
  for (const path of paths) {
    try {
      return ChromeUtils.importESModule(path).ContextualIdentityService;
    } catch (_e) {
      /* try the next known location */
    }
  }
  console.warn("[sine-workspaces] ContextualIdentityService unavailable — container defaults disabled");
  return null;
})();

const Containers = {
  /** All user-visible containers: [{ userContextId, name, color, icon }]. */
  list() {
    if (!ContextualIdentityService) return [];
    try {
      return ContextualIdentityService.getPublicIdentities().map((identity) => ({
        userContextId: identity.userContextId,
        name: ContextualIdentityService.getUserContextLabel(identity.userContextId),
        color: identity.color,
        icon: identity.icon,
      }));
    } catch (_e) {
      return [];
    }
  },

  exists(userContextId) {
    if (!userContextId) return false;
    return this.list().some((c) => c.userContextId === Number(userContextId));
  },
};

export default Containers;
