# overview-ruler

A minimap-style **overview ruler** rendered with SVG down the side of the
buffer, marking git changes, diagnostics, merge conflicts and the current
viewport — a lightweight VS Code minimap.

It only appears over `prog-mode` file buffers; for Org, dired, magit, help,
etc. the ruler window is taken down automatically.

Lanes: git changes on the left (green add / red delete / amber change),
diagnostics on the right (red error / amber warning / blue info), merge
conflicts span the full width (purple), and the current viewport is the
translucent outlined box.

## Usage

Toggle with `SPC t o` (`mp/overview-ruler-mode`). **Click** any indicator to
jump the source window's point to that line.

## Loading

`config.org` loads it in place with `(mp/require-package "overview-ruler")`.
