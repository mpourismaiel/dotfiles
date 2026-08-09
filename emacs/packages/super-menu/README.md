# super-menu

A single `consult`-driven **super menu** that gathers the actions otherwise
scattered across the config (buffers, files, project ops, ...) behind one
discoverable entry point, with history-sorted custom sources.

Ported from the Doom config's *Plugins › Consult › Super menu* section to the
vanilla Emacs config (perspective.el workspaces, stock file commands).

## Usage

`SPC SPC` (`mp/super-menu`).

## Notes

- Depends on `consult` (and, opportunistically, `fd` for file listing).

## Loading

Loaded from `emacs/packages/super-menu/`; the `SPC SPC` binding lives in
`lisp/mp-keys.el`.
