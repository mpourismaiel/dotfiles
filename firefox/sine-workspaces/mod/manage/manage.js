/*
 * sine-workspaces — Manage page.
 * Runs in a privileged chrome:// document. Reuses the mod's Store/Containers/Rules
 * modules (loaded in the system global so their IOUtils/Services refs resolve).
 */
"use strict";

const { default: Store } = ChromeUtils.importESModule(
  "chrome://sine/content/sine-workspaces/src/store.sys.mjs"
);
const { default: Containers } = ChromeUtils.importESModule(
  "chrome://sine/content/sine-workspaces/src/containers.sys.mjs"
);
const { default: Rules } = ChromeUtils.importESModule(
  "chrome://sine/content/sine-workspaces/src/rules.sys.mjs"
);

let state = null; // working copy of config
let containers = [];
let openPickerId = null; // workspace id whose emoji picker is open
let pickerQuery = ""; // emoji picker search text
let dragIndex = null; // index being dragged
let testUrl = ""; // live rule-tester input

// Curated, searchable icon set. `k` = search keywords.
const EMOJIS = [
  { e: "🌐", k: "web globe world internet" }, { e: "🏠", k: "home house" },
  { e: "💼", k: "work briefcase business" }, { e: "📚", k: "books study library learn" },
  { e: "🎮", k: "games gaming play" }, { e: "🎵", k: "music audio song" },
  { e: "🛒", k: "shopping cart buy store" }, { e: "💬", k: "chat talk message" },
  { e: "📧", k: "email mail" }, { e: "🔧", k: "tools settings config" },
  { e: "🎨", k: "art design paint" }, { e: "🐛", k: "bug debug issue" },
  { e: "⭐", k: "star favorite" }, { e: "🔒", k: "lock secure private" },
  { e: "📁", k: "folder files" }, { e: "💡", k: "idea light" },
  { e: "🚀", k: "rocket launch startup" }, { e: "🧪", k: "lab test science experiment" },
  { e: "🖥️", k: "desktop monitor computer" }, { e: "📝", k: "notes write edit" },
  { e: "📊", k: "chart stats analytics graph" }, { e: "💰", k: "money finance cash" },
  { e: "🎯", k: "target goal focus" }, { e: "🔍", k: "search find" },
  { e: "🧠", k: "brain think ai" }, { e: "☁️", k: "cloud" },
  { e: "⚙️", k: "gear settings config" }, { e: "📷", k: "camera photo" },
  { e: "🎬", k: "film movie video" }, { e: "🍿", k: "popcorn cinema movie" },
  { e: "✈️", k: "travel plane flight" }, { e: "🏦", k: "bank finance" },
  { e: "🐙", k: "github octopus git" }, { e: "🦊", k: "firefox fox" },
  { e: "🌙", k: "moon night dark" }, { e: "☀️", k: "sun day light" },
  { e: "🔥", k: "fire hot trending" }, { e: "💎", k: "gem diamond premium" },
  { e: "🌸", k: "flower blossom" }, { e: "🍀", k: "clover luck" },
  { e: "🐧", k: "penguin linux" }, { e: "🤖", k: "robot bot ai" },
  { e: "👾", k: "game alien invader" }, { e: "🎓", k: "school graduate education" },
  { e: "🏋️", k: "gym fitness workout" }, { e: "🧭", k: "compass explore navigate" },
  { e: "📌", k: "pin" }, { e: "❤️", k: "heart love" },
  { e: "💻", k: "laptop code dev" }, { e: "📱", k: "phone mobile" },
  { e: "🗓️", k: "calendar schedule" }, { e: "⏰", k: "clock time alarm" },
  { e: "📦", k: "package box shipping" }, { e: "🔔", k: "bell notification" },
  { e: "🏷️", k: "tag label" }, { e: "🗂️", k: "files folders organize" },
  { e: "🧰", k: "toolbox tools" }, { e: "🛠️", k: "tools build" },
  { e: "🔑", k: "key password" }, { e: "🛡️", k: "shield security" },
  { e: "📈", k: "growth chart up stats" }, { e: "📉", k: "chart down loss" },
  { e: "🧾", k: "receipt invoice bill" }, { e: "💳", k: "card payment credit" },
  { e: "🎧", k: "headphones audio music" }, { e: "🎙️", k: "mic podcast record" },
  { e: "📺", k: "tv stream video" }, { e: "🕹️", k: "joystick game arcade" },
  { e: "🌍", k: "earth world global" }, { e: "🗺️", k: "map travel" },
  { e: "🏢", k: "office building company" }, { e: "🏥", k: "hospital health medical" },
  { e: "🍔", k: "food burger eat" }, { e: "☕", k: "coffee cafe java" },
  { e: "🍺", k: "beer drink" }, { e: "⚽", k: "soccer sports football" },
  { e: "🏀", k: "basketball sports" }, { e: "🎸", k: "guitar music" },
  { e: "🎹", k: "piano music keys" }, { e: "🖌️", k: "brush paint design" },
  { e: "✏️", k: "pencil write edit" }, { e: "📖", k: "book read" },
  { e: "🗃️", k: "archive files box" }, { e: "🔗", k: "link url chain" },
  { e: "⚡", k: "lightning fast power" }, { e: "🎉", k: "party celebrate" },
  { e: "🐳", k: "whale docker" }, { e: "🐍", k: "snake python" },
  { e: "🧩", k: "puzzle extension mod" }, { e: "🎲", k: "dice random game" },
];

const $ = (sel) => document.querySelector(sel);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k === "value") node.value = v;
    else if (k === "html") node.innerHTML = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined && v !== false) node.setAttribute(k, v);
  }
  for (const c of children) if (c != null) node.append(c);
  return node;
}

let statusTimer = null;
function setStatus(msg) {
  const s = $("#status");
  if (!s) return;
  s.textContent = msg;
  clearTimeout(statusTimer);
  if (msg) statusTimer = setTimeout(() => (s.textContent = ""), 2500);
}

// ---- top bars ------------------------------------------------------------

function header() {
  return el(
    "header",
    {},
    el("h1", {}, "Workspaces"),
    el(
      "div",
      { class: "actions" },
      el("button", { onclick: addWorkspace }, "＋ Add workspace"),
      el("button", { class: "primary", onclick: save }, "Save"),
      el("span", { id: "status", "aria-live": "polite" })
    )
  );
}

function toolbar() {
  // Badge color control.
  const useAccent = !state.badgeColor;
  const colorInput = el("input", {
    type: "color",
    value: state.badgeColor || "#e5484d",
    disabled: useAccent,
    oninput: (e) => {
      state.badgeColor = e.target.value;
      render();
    },
  });
  const accentToggle = el("label", { class: "inline" },
    el("input", {
      type: "checkbox",
      checked: useAccent,
      onchange: (e) => {
        state.badgeColor = e.target.checked ? "" : (colorInput.value || "#e5484d");
        render();
      },
    }),
    "Use theme accent"
  );

  // Live rule tester.
  const testInput = el("input", {
    type: "text",
    class: "test-input",
    value: testUrl,
    placeholder: "Paste a URL to test your rules…",
    oninput: (e) => {
      testUrl = e.target.value;
      updateTestResult();
    },
  });

  return el(
    "div",
    { class: "toolbar" },
    el("div", { class: "tool-group" },
      el("span", { class: "tool-label" }, "Badge color"),
      el("span", { class: "swatch", id: "badgeSwatch" }),
      colorInput,
      accentToggle
    ),
    el("div", { class: "tool-group grow" },
      el("span", { class: "tool-label" }, "Rule tester"),
      testInput,
      el("span", { class: "test-result", id: "testResult" })
    )
  );
}

function updateTestResult() {
  const r = $("#testResult");
  if (!r) return;
  const url = testUrl.trim();
  if (!url) { r.textContent = ""; r.className = "test-result"; return; }
  const id = Rules.firstMatch(state.workspaces, url);
  if (id) {
    const ws = state.workspaces.find((w) => w.id === id);
    r.textContent = `→ ${ws?.icon || ""} ${ws?.name || id}`;
    r.className = "test-result match";
  } else {
    r.textContent = "→ no rule matches (stays in the active workspace)";
    r.className = "test-result nomatch";
  }
}

// ---- workspace cards -----------------------------------------------------

function render() {
  const app = $("#app");
  app.textContent = "";
  app.append(header(), toolbar());

  const list = el("div", { id: "list" });
  state.workspaces.forEach((ws, index) => list.append(card(ws, index)));
  app.append(list);

  // reflect badge swatch + test result after (re)build
  const sw = $("#badgeSwatch");
  if (sw) sw.style.background = state.badgeColor || "var(--accent)";
  updateTestResult();
}

function card(ws, index) {
  const c = el("div", {
    class: "card",
    ondragover: (e) => {
      if (dragIndex === null) return;
      e.preventDefault();
      c.classList.add("drop-target");
    },
    ondragleave: () => c.classList.remove("drop-target"),
    ondrop: (e) => {
      e.preventDefault();
      c.classList.remove("drop-target");
      if (dragIndex !== null && dragIndex !== index) moveTo(dragIndex, index);
      dragIndex = null;
    },
  });

  const handle = el("div", {
    class: "drag-handle",
    title: "Drag to reorder",
    draggable: "true",
    ondragstart: (e) => {
      dragIndex = index;
      e.dataTransfer.effectAllowed = "move";
      c.classList.add("dragging");
    },
    ondragend: () => {
      dragIndex = null;
      c.classList.remove("dragging");
    },
  }, "⠿");

  const iconBtn = el("button", {
    class: "icon-btn",
    title: "Pick an icon",
    onclick: () => {
      openPickerId = openPickerId === ws.id ? null : ws.id;
      pickerQuery = "";
      render();
    },
  }, ws.icon);

  const nameInput = el("input", {
    class: "name-input",
    value: ws.name,
    placeholder: "Workspace name",
    oninput: (e) => (ws.name = e.target.value),
  });

  const containerSelect = el("select", {
    onchange: (e) => (ws.containerId = e.target.value ? Number(e.target.value) : null),
  }, el("option", { value: "" }, "No container"));
  for (const ct of containers) {
    const opt = el("option", { value: String(ct.userContextId) }, ct.name);
    if (Number(ws.containerId) === ct.userContextId) opt.selected = true;
    containerSelect.append(opt);
  }

  c.append(
    el("div", { class: "row head" },
      handle,
      iconBtn,
      nameInput,
      el("label", { class: "muted" }, "Container"),
      containerSelect,
      el("button", {
        class: "icon danger",
        title: "Delete workspace",
        disabled: state.workspaces.length <= 1,
        onclick: () => removeWorkspace(index),
      }, "🗑")
    )
  );

  if (openPickerId === ws.id) c.append(emojiPicker(ws));
  c.append(rulesBlock(ws));
  return c;
}

function emojiPicker(ws) {
  const pop = el("div", { class: "emoji-pop" });
  const search = el("input", {
    class: "emoji-search",
    value: pickerQuery,
    placeholder: "Search icons… (e.g. code, money, music)",
    oninput: (e) => {
      pickerQuery = e.target.value;
      grid.textContent = "";
      fillGrid();
    },
  });
  const grid = el("div", { class: "emoji-grid" });

  function fillGrid() {
    const q = pickerQuery.trim().toLowerCase();
    const items = q
      ? EMOJIS.filter((x) => x.k.includes(q) || x.e === q)
      : EMOJIS;
    for (const x of items) {
      grid.append(
        el("button", {
          class: "emoji-cell",
          title: x.k,
          onclick: () => {
            ws.icon = x.e;
            openPickerId = null;
            render();
          },
        }, x.e)
      );
    }
    if (!items.length) grid.append(el("div", { class: "muted pad" }, "No matches"));
  }
  fillGrid();

  pop.append(search, grid);
  return pop;
}

function rulesBlock(ws) {
  const rules = el("div", { class: "rules" }, el("h3", {}, "URL rules"));
  (ws.rules || []).forEach((rule, ri) => {
    const typeSel = el("select", { onchange: (e) => (rule.type = e.target.value) });
    for (const t of ["glob", "regex"]) {
      const opt = el("option", { value: t }, t);
      if (rule.type === t) opt.selected = true;
      typeSel.append(opt);
    }
    rules.append(
      el("div", { class: "rule-row" },
        typeSel,
        el("input", {
          class: "pattern-input",
          value: rule.pattern,
          placeholder: rule.type === "regex" ? "^https://…$" : "*://*.example.com/*",
          oninput: (e) => {
            rule.pattern = e.target.value;
            updateTestResult();
          },
        }),
        el("button", {
          class: "icon danger",
          title: "Remove rule",
          onclick: () => { ws.rules.splice(ri, 1); render(); },
        }, "✕")
      )
    );
  });
  rules.append(
    el("button", { class: "small", onclick: () => { ws.rules = ws.rules || []; ws.rules.push({ type: "glob", pattern: "" }); render(); } }, "＋ Add rule")
  );
  return rules;
}

// ---- mutations -----------------------------------------------------------

function moveTo(from, to) {
  const [item] = state.workspaces.splice(from, 1);
  state.workspaces.splice(to, 0, item);
  render();
}

function removeWorkspace(index) {
  state.workspaces.splice(index, 1);
  render();
}

function addWorkspace() {
  state.workspaces.push({
    id: crypto.randomUUID(),
    name: "New workspace",
    icon: "◆",
    color: "",
    containerId: null,
    rules: [],
  });
  render();
}

async function save() {
  for (const ws of state.workspaces) {
    ws.name = (ws.name || "").trim() || ws.id;
    ws.icon = (ws.icon || "•").trim() || "•";
    ws.rules = (ws.rules || []).filter((r) => (r.pattern || "").trim() !== "");
  }
  Store._config = state;
  await Store.save();
  Store.bumpNonce();
  setStatus("Saved ✓");
}

(async function init() {
  await Store.load();
  state = structuredClone(Store.config);
  containers = Containers.list();
  render();
})();
