# teamwork — Teamwork.com timesheet

Log time to [Teamwork.com](https://teamwork.com) from an editable Org buffer.
Pull the project / task-list / task tree plus your time logs for a date range,
edit, then submit a reviewed diff (streamed, ordered, with retry + abort).
Delete a project heading to stop fetching it (a local preference — it is never
deleted in Teamwork). Credentials live in the system keyring.

Previously a literate `teamwork.org`; now a plain package.

## Files

| file                 | role                                                       |
|----------------------|------------------------------------------------------------|
| `teamwork.el`        | Emacs commands (`mp/teamwork-timesheet`, `mp/teamwork-submit`) |
| `timesheet.py`       | sidecar that talks to the Teamwork REST API                |
| `teamwork-setup.sh`  | one-time credential setup (keyring)                        |
| `test_timesheet.py`  | offline unit tests for the sidecar                         |

`teamwork.el` locates `timesheet.py` next to itself, so the whole directory is
deployed together to `~/.config/doom/packages/teamwork/`.

## Setup

Run once per account (prompts for a label, site URL and API key, validates
against the live API, stores in the system keyring — never on disk):

```sh
~/.config/doom/packages/teamwork/teamwork-setup.sh
# or, from Emacs:  M-x teamwork-account-add
```

Multiple accounts are supported (each a separate keyring item, told apart by
name; `--print` lists them, `--remove NAME` deletes one). With more than one
account the commands ask which to use, and the pulled buffer records its choice
in a `#+TEAMWORK_ACCOUNT` header so submit targets the same account.

## Loading

`config.org` loads it with `(mp/require-package "teamwork")`.
