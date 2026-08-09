# project-scripts

Pick and run an executable script from the project's `__ignore__/scripts/`
directory in a Ghostel terminal buffer named `*project:NAME*`. Scripts that have
run at least once this session are marked with a `✓` in the picker; a live
script's terminal is reused instead of respawned.

Ported from the Doom-era package (originally extracted from config.org's
*Should be plugins › Project Scripts runner* section).

## Usage

`SPC p S` (`my/run-project-script`) — the leader bind lives in `mp-keys.el`.

## Notes

- Uses **Ghostel** (`ghostel`, `ghostel-send-string`, ...) as the terminal.
- Requires **projectile** for project-root detection.

## Loading

`init.el` loads it in place with `(mp/require-package "project-scripts")`.
