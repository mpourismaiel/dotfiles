// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — URL rule matching (glob / regex).
//
// A rule lives in its workspace's `rules` list:
//   { type: "glob" | "regex", pattern: string, containerId?: number | "none" | null }
// A match sends the tab to that workspace, in the rule's container — a
// container id, "none" for no container, or null/absent for the workspace's
// default container. Rules are evaluated once, on tab creation, and only for
// tabs the user has not manually assigned.

const Rules = {
  _globToRegExp(glob) {
    // Escape regex metachars, then turn * into .* and ? into a single char.
    let out = "";
    for (const ch of glob) {
      if (ch === "*") out += ".*";
      else if (ch === "?") out += ".";
      else out += ch.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
    return new RegExp("^" + out + "$", "iu");
  },

  matches(rule, url) {
    if (!rule || !url) return false;
    try {
      if (rule.type === "regex") {
        return new RegExp(rule.pattern, "iu").test(url);
      }
      return this._globToRegExp(rule.pattern).test(url);
    } catch (_e) {
      return false;
    }
  },

  /**
   * Returns { workspace, rule } for the first matching rule, honoring workspace
   * order then rule order. Returns null if nothing matches.
   */
  match(workspaces, url) {
    for (const ws of workspaces) {
      for (const rule of ws.rules || []) {
        if (this.matches(rule, url)) return { workspace: ws, rule };
      }
    }
    return null;
  },

  /** The id of the first workspace whose rules match the URL, or null. */
  firstMatch(workspaces, url) {
    return this.match(workspaces, url)?.workspace.id ?? null;
  },

  /**
   * The container a match puts its tab in: a userContextId, 0 for "no
   * container", or null when neither the rule nor its workspace names one.
   */
  containerFor(hit) {
    const c = hit?.rule?.containerId;
    if (c === "none" || c === 0 || c === "0") return 0;
    if (c != null && c !== "") return Number(c);
    const def = hit?.workspace?.containerId;
    return def ? Number(def) : null;
  },
};

export default Rules;
