// ==UserScript==
// @ignorecache
// ==/UserScript==
//
// sine-workspaces — URL rule matching (glob / regex).
//
// A rule is { type: "glob" | "regex", pattern: string }. Rules are evaluated
// once, on tab creation, and only for tabs the user has not manually assigned.

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
   * Returns the id of the first workspace whose rules match the URL, honoring
   * workspace order. Returns null if nothing matches.
   */
  firstMatch(workspaces, url) {
    for (const ws of workspaces) {
      for (const rule of ws.rules || []) {
        if (this.matches(rule, url)) return ws.id;
      }
    }
    return null;
  },
};

export default Rules;
