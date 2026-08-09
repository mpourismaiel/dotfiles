# svg-header

A tall, custom **header line** rendered with SVG so it can be a fixed pixel
height regardless of font metrics. Shows the buffer file name + major mode,
`breadcrumb` project/imenu crumbs, VCS state and diagnostics.

Vanilla Emacs port of the Doom package of the same name (originally extracted
from Doom's config.org *Appearance › Header Line* section).

## Notes

- Depends on `breadcrumb` (declared via `use-package` in `svg-header.el`;
  installed automatically since `use-package-always-ensure` is on) and the
  built-in `svg`, `subr-x`, `seq`, `cl-lib` libraries.
- Tunables are `defvar`s at the top of `svg-header.el`
  (`mp/header-line-height`, padding, the foreground faces it borrows, ...).

## Loading

The vanilla config loads it in place with a plain `load` of
`emacs/packages/svg-header/svg-header.el`.
