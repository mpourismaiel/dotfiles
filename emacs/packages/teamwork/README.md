# teamwork — Teamwork.com from Org

Work with [Teamwork.com](https://teamwork.com) from editable Org buffers. Two
buffer kinds share the same pull → edit → review-diff → streamed-apply flow:

- **Timesheet** (`teamwork-timesheet`) — the project / task-list / task tree plus
  your time logs for a date range; edit logs, then submit.
- **Management** (`teamwork-management`) — the same tree with *no time filter*,
  for creating / renaming / **deleting** task-lists, tasks and subtasks, and
  editing task **properties** — `:LABELS:`, `:DUE:` (date), `:URGENCY:`
  (low/medium/high) and `:ASSIGNEE:` (by name) — plus a **description** as plain
  text under the drawer. A task's **done state is an Org `TODO`/`DONE` keyword on
  its heading** (the buffer declares `#+TODO: TODO | DONE`), so Org fontifies and
  strikes completed tasks itself; edit the keyword on the heading directly (type
  over `TODO`/`DONE`) to complete or reopen the task on submit — Org's own
  `C-c C-t` (`org-todo`) is intentionally **disabled** here. `C-c C-p` sets a property
  with completion over the available values (project people, existing tags, the
  priority list, a calendar for the due date), or jump straight to one with a
  dedicated combo — `C-c C-b` labels, `C-c C-u` urgency, `C-c C-d` due date,
  `C-c C-a` assignee (the last three are management-only; `C-c C-b` also works in
  the timesheet). Completion for labels / urgency / assignee is seeded with the
  values already used on the loaded tasks (plus the account's tags and the
  project's people for those two), so common values are one keystroke away, and
  you can still type a custom one. `C-c C-o` loads the selected tasks' comments
  on demand (see **Comments** below). By
  default management shows only **open** work — completed tasks and completed
  task lists are hidden (a clean "what's left" view); the header's **Tasks** and
  **Lists** buttons (persisted per account) reveal them — a completed task shows
  as an Org `DONE` heading, a completed task list dimmed with a checkmark — so a
  done task/list can be found and reopened. Removing a heading
  deletes it in Teamwork on submit (children cascade); the preview lists every
  deletion. Deletion is management-only — timesheet mode never deletes tasks/lists.
  (Hidden completed items are kept out of the fetched snapshot too, so they are
  never mistaken for deletions.) Because a heading carries its `TASK_ID`, **cutting
  a task heading and pasting it under a different task list — or under another task,
  or back out to the top level — moves it in Teamwork** rather than reading as a
  delete + create, so its logs, comments and history travel with it. Subtasks
  follow their parent automatically, so only the heading you actually moved is
  relocated. Moving is management-only.

  Properties carry no prefix: the drawer keys are `TASK_ID` (never edit — it
  identifies the task), `LABELS`, `DUE`, `URGENCY`, `ASSIGNEE` (the done state is
  the heading's `TODO`/`DONE` keyword, not a drawer key). `LABELS`
  and `URGENCY` are deliberately *not* named `TAGS`/`PRIORITY`, which Org reserves
  as special property names (Org would return the headline's tags / priority cookie
  instead of the drawer value).
- **Comments** — each task's comments live **inline** in the management buffer
  under a `# Comments` line, but are **loaded on demand** so the pull stays fast
  on big projects. A task with comments on the server shows a hint with the count:

  ```
  # Comments (3 — select + C-c C-o to load)
  ```

  Put point on a task (or **select a region** spanning several tasks) and press
  `C-c C-o` (`teamwork-load-comments`): the comments for the selected existing
  tasks are fetched and spliced in, rewriting only those sections — the rest of
  the buffer, and any unsaved edits, are untouched. New (id-less) tasks in the
  selection are skipped. Once loaded, each existing comment is a
  `- author, YYYY-MM-DD HH:MM, `id`` header with its text below; edit the text of
  **your own** comment to change it (editing someone else's is refused), or add a
  bodied `-` block to post a new comment:

  ```
  # Comments
  - Ann Lee, 2026-06-10 09:30, `1234`
  looks good to me
  -
  my brand-new reply
  ```

Tasks nest to any depth: a heading demoted below a task (`****` or deeper) is a
subtask, and subtasks take logs, renames, labels and `[d]` completion like any
task. Label a task with a `:LABELS: bug, backend` property line (comma
separated; empty clears, a missing line leaves labels untouched).

- **View filters** — narrow the *already-loaded* buffer to the tasks you care
  about, in place, with **no round-trip and no text change**. `C-c C-v t`
  (`teamwork-view-filter-tag`) hides every task whose subtree doesn't carry the
  chosen tag; `C-c C-v n` (`teamwork-view-filter-title`) filters on a
  case-insensitive substring of the task title. A matching task keeps its whole
  subtree (its subtasks come along) and its list / project headings stay as
  scaffolding — everything else is hidden. Filters **stack (AND)**: filter on
  `bounty`, then on `mux`, and you're left with tasks carrying **both** tags.
  `C-c C-v r` (`teamwork-view-filter-reset`) clears them and reveals the whole
  buffer. Because filtering only hides text with overlays (it never edits the
  buffer), all your local edits — added / renamed / deleted tasks, changed
  labels — are kept through filtering and fully restored on reset; a refetch
  also clears the filters. These are distinct from the project `teamwork-filter`
  below, which picks *which projects are fetched*.

Which projects appear is a **per-account filter** (`teamwork-filter`), persisted
in prefs — switching accounts no longer resets it. Delete a project heading to
stop fetching it (a local preference — it is never deleted in Teamwork); it is
added to the account's hidden list. To bring one back, **click its chip in the
header** and refetch. The hidden list and the completed-item view flags live in
the account prefs (not in the buffer) and reach the header via the sidecar's
`manage-state` command, so the management buffer keeps only its routing markers
(`#+TITLE`, `#+TEAMWORK_MANAGE`, `#+TEAMWORK_ACCOUNT`) — no how-to comment block.

Every buffer shows **cached data instantly** while a fresh copy is fetched in the
background; the buffer is replaced when fresh data arrives (edits discarded), and
submit is refused while stale/errored so a diff is never computed against
out-of-date data. `C-c C-r` forces a refresh.

The **header line is an interactive control strip** (a tall SVG when the config's
`svg-header` package is loaded, otherwise a clickable text row): a freshness pill
(READY/STALE/ERROR), a help line, a **Refetch** button (applies hidden-list
changes), clickable **hidden-project chips** (click to restore), and — in
management — **Lists/Tasks** buttons that toggle the completed-item view.

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
