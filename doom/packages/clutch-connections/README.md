# clutch-connections

Loads database connections for the [`clutch`](https://github.com/) SQL client
and installs them as `clutch-connection-alist` (applied once clutch loads).

Connections are stored as **full clutch connection objects** (JSON) and are
authored in an interactive edit buffer — no hand-writing URI strings.

## Managing connections (from Emacs)

`mp/clutch-connections` is the dispatcher: it lists saved connections with
password-free annotations (`backend  host:port/db  (user …)`) plus a pinned
**＋ New connection…** entry. Selecting a connection offers **Connect / Edit /
Copy URI / Rename / Delete**.

Create and Edit open a **JSONC edit buffer** (`mp/clutch-connection-edit-mode`):

- Prefilled with the common keys and inline `//` comments documenting allowed
  values, default ports, and doc links — no doc diving.
- Optional keys (`sslmode`, `ssh-host`, `schema`, `url`, timeouts, …) appear as
  commented examples; uncomment the ones you need.
- Empty values are dropped on save; numbers (`port`, timeouts) must be unquoted.

Buffer keys:

| key       | action                                                        |
|-----------|---------------------------------------------------------------|
| `C-c C-c` | validate & save, then close                                   |
| `C-c C-k` | cancel                                                        |
| `C-c C-i` | `mp/clutch-import-connection-string` — fill fields from a URL |

`C-c C-i` prompts in the echo area for a `postgresql://` / `mysql://` /
`sqlite://` string (including `?sslmode=…` query params) and rewrites the
buffer fields from it, keeping the name you already typed.

Other commands: `mp/clutch-connection-connect` (open/connect a query console),
`mp/clutch-connection-delete`, `-rename`, `-copy-uri` (copies credentials —
beware), and `mp/clutch-apply-connections` (re-read the store into
`clutch-connection-alist`).

Suggested binding (add to config.org next to `SPC o s`):

```elisp
(map! :leader :desc "Clutch connections" "o S" #'mp/clutch-connections)
```

### Connection keys

The edit buffer covers the common keys; the authoritative reference is the
`clutch-connection-alist` docstring in clutch. Highlights:

- `backend` (required): `pg`, `mysql`, `sqlite`, `mongodb`, `oracle`,
  `sqlserver`.
- `host` `port` `user` `password` `database`.
- `sslmode` (PostgreSQL): `disable` / `prefer` / `require` / `verify-full`.
- `ssl-mode` (MySQL): `disabled` forces plaintext. `tls`: convenience shortcut.
- `ssh-host`: local SSH tunnel via a `~/.ssh/config` host — clutch runs
  `ssh -N -L …` automatically at connect time.
- `url`: JDBC URL for `oracle` / `sqlserver` / MongoDB-SQL backends.
- `schema`, `sql-product`, `display-name`, `auth-database`, `props`, timeouts.

Connecting (`Connect`, or `mp/clutch-connection-connect`) hands the saved name
to `clutch-query-console`, so SSH tunnels, TLS, JDBC URLs, MongoDB and
auth-source password resolution all work through clutch's normal path.

### SSL / TLS (PostgreSQL)

`verify-full` validates the server certificate (and hostname) against Emacs's
GnuTLS **system CA bundle** (`gnutls-trustfiles`, e.g.
`/etc/ssl/certs/ca-certificates.crt`). No cert files to configure when the
server chains to a public/system-trusted CA — same as most GUI clients. clutch
has **no per-connection root-CA (`sslrootcert`) option**: for a private CA, add
it to the system trust store or customize `gnutls-trustfiles`.

## Storage backends

`mp/clutch-connections-backend` selects where the store lives:

- **`secret-service`** (default) — the freedesktop Secret Service (KWallet /
  gnome-keyring) via Emacs `secrets.el`. The keyring is **unlocked once at
  login**, so there is **no per-save password prompt**. All connections are
  stored as one keyring item (label `Clutch DB connections`) in the default
  collection (override with `mp/clutch-connections-ss-collection`).

  Note: on this machine the `org.freedesktop.secrets` D-Bus name is currently
  owned by **gnome-keyring**, not KWallet (both auto-unlock at login, so it
  works either way). To force KWallet to serve it, disable gnome-keyring's
  Secret Service component so `ksecretd`/`kwalletd6` can claim the name.

- **`gpg`** — EasyPG-encrypted `~/.config/doom/connections.json.gpg`. Encrypted
  at rest, but prompts for a passphrase on every save unless you point it at a
  GPG key so `gpg-agent` caches the unlock
  (`mp/clutch-connections-gpg-recipient`).

### Tradeoff

`secret-service` trades a bit of at-rest isolation for convenience: while the
keyring is unlocked (your whole session), any process running as you can read
the secrets through the Secret Service API. `gpg` with a passphrase keeps each
secret sealed until you explicitly unlock it.

`connections.json` and `connections.json.gpg` are git-ignored. **Do not commit
either** — the plaintext is an obvious leak, and an encrypted file in a public
repo is still an offline-crackable secret.

## Loading

`config.org` loads it in place with `(mp/require-package "clutch-connections")`.
