# agent-shell-extras

Local integrations layered on top of the `agent-shell` package, kept together in
one place:

- **Per-project Claude config dir** — resolve/attach a `.claude` config
  directory per project.
- **Desktop notifications** — native notifications for agent-shell events.
- **Default model** — the default model `setq`.
- **Faces** — custom faces for the agent-shell UI.

Ported from the Doom package of the same name (originally extracted from
config.org's *Plugins › Agent Shell* section).

## Notes

- Everything targets the external `agent-shell` / `acp` packages (declared
  elsewhere in the config) and is loaded after them via the same
  `use-package` / `with-eval-after-load` wrappers that were used before.
- Workspace lookups use perspective.el (`persp-names`, `perspectives-hash`,
  `persp-buffers`) plus `mp/workspace-current-name` instead of Doom's
  `+workspace-*` API.

## Loading

The config loads it in place with `(mp/require-package "agent-shell-extras")`.
