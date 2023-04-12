const store = require("./store");
const { shortcutsDefault } = require("./constants");

const shortcutsContainer = document.querySelector("#shortcuts");
const shortcutTemplate = document.querySelector("#shortcut-template");
const shortcutTemplateWithChildren = document.querySelector(
  "#shortcut-template-with-children"
);

const {
  get: getShortcuts,
  set: setShortcuts,
  subscribe: subscribeShortcuts,
} = store(shortcutsDefault, "shortcuts");

subscribeShortcuts((shortcuts) => {
  shortcutsContainer.innerHTML = "";
  shortcuts.forEach(({ title, link, icon, children }) => {
    if (children.length > 0) {
      shortcutsContainer.innerHTML += shortcutTemplateWithChildren.innerHTML
        .replace(/%title%/g, title)
        .replace(/%link%/g, link.replace(/^https?:\/\//, ""))
        .replace(/%icon%/g, icon)
        .replace(
          /%children%/g,
          children
            .map(
              (child) =>
                `<a href="${child.link}"><img src="./icons/chevron-right.svg" class="icon" /><span>${child.title}</span></a>`
            )
            .join("")
        );
    } else {
      shortcutsContainer.innerHTML += shortcutTemplate.innerHTML
        .replace(/%title%/g, title)
        .replace(/%link%/g, link.replace(/^https?:\/\//, ""))
        .replace(/%icon%/g, icon);
    }
  });
});

module.exports = { getShortcuts, setShortcuts, subscribeShortcuts };
