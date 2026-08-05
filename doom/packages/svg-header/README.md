# svg-header

A tall, custom **header line** rendered with SVG so it can be a fixed pixel
height regardless of font metrics. Shows the buffer file name + major mode,
`breadcrumb` project/imenu crumbs, VCS state and diagnostics.

Extracted verbatim from config.org's *Appearance › Header Line* section.

## Notes

- Depends on `breadcrumb` (declared in config.org's packages section) and the
  built-in `svg`, `subr-x`, `seq` libraries.
- Tunables are `defvar`s at the top of `svg-header.el`
  (`mp/header-line-height`, padding, the foreground faces it borrows, ...).

## Loading

`config.org` loads it in place with `(mp/require-package "svg-header")`.
