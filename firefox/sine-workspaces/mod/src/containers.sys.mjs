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

const { ContextualIdentityService } = ChromeUtils.importESModule(
  "resource://gre/modules/ContextualIdentityService.sys.mjs"
);

const Containers = {
  /** All user-visible containers: [{ userContextId, name, color, icon }]. */
  list() {
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
