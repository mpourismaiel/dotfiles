#!/usr/bin/env -S ags --run-file
const ShortcutsDisplay = (
  await import(
    `file:///home/${Utils.USER}/.config/ags/windows/shortcut-helper.js`
  )
).ShortcutsDisplay;

ShortcutsDisplay.setValue({
  title: "Submap: Groups",
  shortcuts: [
    { title: "Toggle group mode", combo: "Super+G" },
    { title: "Change active client in group", combo: "Super+Tab" },
    {
      title: "Change active client in group (backwards)",
      combo: "Super+Shift+Tab",
    },
    { title: "Toggle active group's lock", combo: "Super+L" },
    {
      title: "Move client in and out of group in direction",
      combo: "Super+Arrow Key",
    },
  ],
});
