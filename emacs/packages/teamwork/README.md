# teamwork — Teamwork.com from Org

Work with [Teamwork.com](https://teamwork.com) from editable Org buffers. Three
buffer kinds share the same pull → edit → review-diff → streamed-apply flow:

- **Timesheet** (`teamwork-timesheet`) — the project / task-list / task tree plus
  your time logs for a date range; edit logs, then submit.
- **Management** (`teamwork-management`) — the same tree with *no time filter*,
  for creating / renaming / **deleting** task-lists, tasks and subtasks, and
  editing task **properties** — `:TW_TAGS:`, `:TW_DUE:` (date), `:TW_PRIORITY:`
  (low/medium/high) and `:TW_ASSIGNEE:` (by name) — plus a **description** as
  plain text under the drawer. `C-c C-p` sets a property with completion over the
  available values (project people, existing tags, the priority list, a calendar
  for the due date). Removing a heading deletes it in Teamwork on submit (children
  cascade); the preview lists every deletion. Deletion is management-only —
  timesheet mode never deletes tasks/lists.
- **Comments** (`teamwork-comments`) — the comments of the task under point, in a
  new buffer you can edit, add to and delete from.

Tasks nest to any depth: a heading demoted below a task (`****` or deeper) is a
subtask, and subtasks take logs, renames, labels and `[d]` completion like any
task. Label a task with a `:TW_TAGS: bug, backend` property line (comma
separated; empty clears, a missing line leaves labels untouched).

Which projects appear is a **per-account filter** (`teamwork-filter`), persisted
in prefs — switching accounts no longer resets it. Delete a project heading to
stop fetching it (a local preference — it is never deleted in Teamwork).

Every buffer shows **cached data instantly** while a fresh copy is fetched in the
background; a header-line banner marks it stale, the buffer is replaced when
fresh data arrives (edits discarded), and submit is refused while stale/errored
so a diff is never computed against out-of-date data. `C-c C-r` forces a refresh.

Credentials live in the system keyring. Previously a literate `teamwork.org`;
now a plain package.

## Files

| file                 | role                                                       |
|----------------------|------------------------------------------------------------|
| `teamwork.el`        | Emacs commands (`teamwork-timesheet`, `teamwork-submit`, …) |
| `timesheet.py`       | sidecar that talks to the Teamwork REST API                |
| `teamwork-setup.sh`  | one-time credential setup (keyring)                        |
| `test_timesheet.py`  | offline unit tests for the sidecar                         |

`teamwork.el` locates `timesheet.py` next to itself, so the whole directory is
deployed together to `~/.config/emacs-vanilla/packages/teamwork/`.

## Setup

Run once per account (prompts for a label, site URL and API key, validates
against the live API, stores in the system keyring — never on disk):

```sh
~/.config/emacs-vanilla/packages/teamwork/teamwork-setup.sh
# or, from Emacs:  M-x teamwork-account-add
```

Multiple accounts are supported (each a separate keyring item, told apart by
name; `--print` lists them, `--remove NAME` deletes one). With more than one
account the commands ask which to use, and the pulled buffer records its choice
in a `#+TEAMWORK_ACCOUNT` header so submit targets the same account.

## Loading

`lisp/mp-tools.el` loads it with `(mp/require-package "teamwork")`.
