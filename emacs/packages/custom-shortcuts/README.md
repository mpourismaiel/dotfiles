# custom-shortcuts

The larger, non-trivial **custom shortcuts** and the helper commands they call
(project-root default directory, opening a Ghostel terminal with `` C-` ``,
...) — kept out of the main keybindings module (`mp-keys.el`) so that module
stays a quick, scannable list.

Ported from the Doom-era package (extracted from config.org's
*Keybindings › Custom Shortcuts* section). The `mp/move-lines-*` /
line-moving helpers moved to `emacs/lisp/mp-core.el`; `SPC o e` / `SPC o E`
leader bindings for `mp/ghostel-open` / `mp/ghostel-new` live in
`emacs/lisp/mp-keys.el`.

## Loading

`mp-tools.el` loads it in place with `(mp/require-package "custom-shortcuts")`.
