# clutch-connections

Loads database connections for the [`clutch`](https://github.com/) SQL client
from `~/.config/doom/connections.json` and installs them as
`clutch-connection-alist` (applied once clutch loads).

Each JSON entry maps a name to either a connection **URI string**
(`postgresql://`, `mysql://`, `sqlite://`) or an explicit **plist/object**;
both are normalized to clutch's plist format.

Extracted verbatim from config.org's *Plugins › Clutch › Connections JSON*
sub-section. The small `use-package! clutch` config (timeouts) and the
`SPC o s` keybinding stay inline in config.org.

## Usage

- `mp/clutch-apply-connections` re-reads the JSON file on demand.
- `connections.json` is symlinked into `~/.config/doom/` from this repo.

## Loading

`config.org` loads it in place with `(mp/require-package "clutch-connections")`.
