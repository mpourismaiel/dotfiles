# clutch-connections

Loads database connections for the [`clutch`](https://github.com/) SQL client
and installs them as `clutch-connection-alist` (applied once clutch loads).

Connections live in an **EasyPG-encrypted** file
`~/.config/doom/connections.json.gpg`. A legacy plaintext
`~/.config/doom/connections.json` is still read as a fallback (with a nag to
migrate), so nothing breaks mid-transition.

Each JSON entry maps a name to either a connection **URI string**
(`postgresql://`, `mysql://`, `sqlite://`) or an explicit **plist/object**;
both are normalized to clutch's plist format.

## Security

- The store is a GPG file, so secrets are encrypted at rest. Emacs decrypts it
  transparently on read and re-encrypts on write via EasyPG.
- By default it uses **symmetric** encryption (passphrase prompt). To encrypt
  to your GPG key instead — so `gpg-agent` unlocks it without retyping —
  set:

  ```elisp
  (setq mp/clutch-connections-gpg-recipient "mpourismaiel@gmail.com")
  ```

- Both `connections.json` and `connections.json.gpg` are git-ignored. **Do not
  commit either** — the plaintext is an obvious leak, and an encrypted file in
  a public repo is still an offline-crackable secret.

## Managing connections (from Emacs)

All commands drive the minibuffer, so vertico/consult render them with live,
password-free annotations (`backend  host:port/db  (user …)`):

- `mp/clutch-connections` — dispatcher: pick a connection (then Edit / Copy URI
  / Rename / Delete) or choose **＋ New connection…**.
- `mp/clutch-connection-create`
- `mp/clutch-connection-edit`
- `mp/clutch-connection-delete`
- `mp/clutch-connection-rename`
- `mp/clutch-connection-copy-uri`  (copies credentials — beware)
- `mp/clutch-apply-connections` — re-read the file into `clutch-connection-alist`.

Every write re-encrypts the `.gpg` file and re-applies the connections.

Suggested binding (add to config.org next to `SPC o s`):

```elisp
(map! :leader :desc "Clutch connections" "o S" #'mp/clutch-connections)
```

## Migrating an existing plaintext file

If you still have `~/.config/doom/connections.json`:

```
M-x mp/clutch-migrate-to-gpg
```

It encrypts the contents into `connections.json.gpg` and offers to securely
`shred` the plaintext. **After migrating, rotate any credentials that were ever
committed to git** — see `scrub-secrets.sh` at the repo root.

## Loading

`config.org` loads it in place with `(mp/require-package "clutch-connections")`.
