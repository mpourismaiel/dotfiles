# super-menu

A single `consult`-driven **super menu** that gathers the actions otherwise
scattered across the config (buffers, files, project ops, ...) behind one
discoverable entry point, with history-sorted custom sources.

Extracted verbatim from config.org's *Plugins › Consult › Super menu* section.

## Usage

`SPC SPC` (`mp/super-menu`).

## Notes

- Depends on `consult` (and, opportunistically, `fd` for file listing).

## Loading

`config.org` loads it in place with `(mp/require-package "super-menu")`.
