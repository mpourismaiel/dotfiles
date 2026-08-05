# dashboard-widgets

The custom **startup dashboard**: layout and faces, project helpers, rendering
helpers and the widgets that make up the splash screen.

Extracted verbatim from config.org's *Plugins › Dashboard* section (the *Layout
And Faces*, *Project Helpers*, *Rendering Helpers* and *Dashboard Widgets*
sub-sections, concatenated in order).

## Notes

- Guards itself with `(when (modulep! :ui dashboard) ...)`, so it is inert
  unless Doom's `:ui dashboard` module is enabled.

## Loading

`config.org` loads it in place with `(mp/require-package "dashboard-widgets")`.
