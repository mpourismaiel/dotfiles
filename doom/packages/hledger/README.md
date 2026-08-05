# hledger — plain-text personal finance

Personal finance with [hledger](https://hledger.org) (plain-text double-entry
accounting), edited in `ledger-mode` with hledger as the binary, plus
report / quick-add commands under `SPC o l`.

Previously a literate `hledger.org`; now a plain package (`hledger.el`).

## Journals

Live in `~/Documents/finance`:

- `main.journal` — entry point: commodity styles (EUR, IRT), account
  declarations, and includes. Every command reads through this file.
- `YYYY-month.journal` — one file per month, picked up by main.journal's
  `include ????-*.journal` glob. New months are born by
  `mp/hledger-open-current-month`.
- `forecast.journal` — periodic rules; inert unless a report runs with
  `--forecast`.
- `wishlist.journal` — things to buy; **not** included in main.journal, so it
  never touches real balances. Queried by `mp/hledger-wishlist`.

## Notes

- Editing uses `ledger-mode` (Doom's `:lang ledger` module, enabled in
  `init.el`) with hledger as the binary — font-lock, `TAB` alignment, account
  completion and the evil `[[` / `]]` motions all work.
- Two stock `ledger-mode` commands are ledger-CLI-only and are avoided:
  `ledger-add-transaction` (replaced by `mp/hledger-add-transaction`) and
  `ledger-reconcile`.
- On-the-fly checking comes from `flycheck-hledger` (declared in config.org's
  packages section); the stock `ledger` flycheck checker is disabled here.

## Loading

`config.org` loads it with `(mp/require-package "hledger")`.
