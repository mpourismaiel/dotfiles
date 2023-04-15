const { listenToTab } = require("./tabs");
const { showModal, hideModal } = require("./modal");
const { getShortcuts, setShortcuts } = require("./shortcuts");
const { formValues, stopPropagation, preventDefault } = require("./forms");

const shortcutAddButton = document.querySelector("#shortcuts-add");
const addShortcutModal = document.querySelector("#add-shortcut-modal");
const addShortcutModalForm = document.querySelector("#add-shortcut-form");
const addShortcutModalRelatedForm = document.querySelector(
  "#add-shortcut-form-related"
);

shortcutAddButton.addEventListener("click", showModal(addShortcutModal));
addShortcutModal.addEventListener("click", stopPropagation());

listenToTab("add-shortcut", "link", () => {
  const shortcutsSelector = document.querySelector("#shortcut-related");
  shortcutsSelector.innerHTML = [
    '<option disabled value=""></option>',
    ...getShortcuts().map(
      ({ title, link }) => `<option value="${link}">${title}</option>`
    ),
  ];
  shortcutsSelector.value = "";
});

const addShortcut =
  (mode = "") =>
  () => {
    const formName =
      mode === "related" ? "add-shortcut-form-related" : "add-shortcut-form";

    const emptyFields = Object.keys(formValues[formName].values).filter(
      (key) => key !== "icon" && formValues[formName].values[key] === ""
    );
    if (emptyFields.length > 0) {
      emptyFields.forEach((field) => {
        const input = document.querySelector(`#${formName} [name="${field}"]`);
        input.classList.add("error");
      });
      return;
    }

    if (mode === "related") {
      const shortcuts = getShortcuts();
      const shortcut = shortcuts.find(
        (shortcut) =>
          shortcut.link ===
          formValues["add-shortcut-form-related"].values.parent
      );

      if (!shortcut) {
        throw new Error("Shortcut not found");
      }

      shortcut.children.push(formValues["add-shortcut-form-related"].values);
      setShortcuts(shortcuts);
    } else {
      setShortcuts([
        ...getShortcuts(),
        { ...formValues["add-shortcut-form"].values, children: [] },
      ]);
    }

    formValues["add-shortcut-form-related"].reset();
    formValues["add-shortcut-form"].reset();
    hideModal(addShortcutModal)();
  };

addShortcutModalForm.addEventListener("submit", preventDefault(addShortcut()));
addShortcutModalRelatedForm.addEventListener(
  "submit",
  preventDefault(addShortcut("related"))
);
