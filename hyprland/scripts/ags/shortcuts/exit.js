#!/usr/bin/env -S ags --run-file
const ShortcutsDisplay = (
  await import(
    `file:///home/${Utils.USER}/.config/ags/windows/shortcut-helper.js`
  )
).ShortcutsDisplay;

ShortcutsDisplay.setValue(null);
