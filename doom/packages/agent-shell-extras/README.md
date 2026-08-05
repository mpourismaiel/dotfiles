# agent-shell-extras

Local integrations layered on top of the `agent-shell` package, kept together in
one place:

- **Per-project Claude config dir** — resolve/attach a `.claude` config
  directory per project.
- **Desktop notifications** — native notifications for agent-shell events.
- **Default model** — the default model `setq`.
- **Faces** — custom faces for the agent-shell UI.

Extracted verbatim from config.org's *Plugins › Agent Shell* section (all four
sub-sections concatenated in order).

## Notes

- Everything targets the external `agent-shell` / `acp` packages (declared in
  config.org's packages section) and is loaded after them via the same
  `use-package!` / `with-eval-after-load` wrappers that were inline before.

## Loading

`config.org` loads it in place with `(mp/require-package "agent-shell-extras")`.
