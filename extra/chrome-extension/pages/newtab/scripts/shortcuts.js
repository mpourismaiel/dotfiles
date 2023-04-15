const sortable = require("sortablejs");

const handlebars = require("./handlebars");
const store = require("./store");
const { shortcutsDefault } = require("./constants");

const shortcutsContainer = document.querySelector("#shortcuts");
const shortcutsEdit = document.querySelector("#shortcuts-edit");

const {
  get: getShortcuts,
  set: setShortcuts,
  subscribe: subscribeShortcuts,
} = store(shortcutsDefault, "shortcuts");

let isEditing = false;

subscribeShortcuts((shortcuts) => {
  shortcutsContainer.innerHTML = "";
  isEditing = false;
  shortcuts.forEach(({ title, link, icon, children }, i) => {
    shortcutsContainer.innerHTML += handlebars.templates.shortcut({
      id: i,
      title,
      icon:
        icon || "https://s2.googleusercontent.com/s2/favicons?domain=" + link,
      children,
      hasChildren: children && children.length > 0,
      link: link.replace(/^https?:\/\//, ""),
    });
  });

  Array.from(shortcutsContainer.querySelectorAll(".shortcut")).forEach(
    (shortcut, i) => {
      shortcut
        .querySelector(".edit-actions .delete")
        .addEventListener("click", () => {
          setShortcuts(getShortcuts().filter((_, j) => i !== j));
        });
    }
  );
});

shortcutsEdit.addEventListener("click", () => {
  const shortcuts = Array.from(
    shortcutsContainer.querySelectorAll(".shortcut")
  );

  if (!isEditing) {
    isEditing = true;
    shortcuts.forEach((shortcut) => shortcut.classList.add("editing"));
    return;
  }

  isEditing = false;
  shortcuts.forEach((shortcut) => shortcut.classList.remove("editing"));
});

const changeOrder = (arr, m, n) => {
  const newArr = [...arr];
  const [item] = newArr.splice(m, 1);
  newArr.splice(n, 0, item);
  return newArr;
};

sortable.create(shortcutsContainer, {
  animation: 150,
  ghostClass: "ghost-draggable",
  onEnd: (e) => {
    setShortcuts(changeOrder(getShortcuts(), e.oldIndex, e.newIndex));
  },
});

module.exports = { getShortcuts, setShortcuts, subscribeShortcuts };
