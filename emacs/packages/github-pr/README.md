# github-pr — GitHub PR review comments

Read a pull request's **review-comment threads** (the inline "conversations")
plus the general PR discussion into an editable Org buffer, with the
newest-active conversation floated to the top so nothing gets lost when a PR has
dozens of threads. Reply by adding a level-2 heading with an **empty author and
no properties**, type your response, then submit a reviewed preview
(`C-c C-c`, streamed, y/n confirmed).

Previously a literate `github-pr.org`; now a plain package.

## Files

| file                   | role                                                        |
|------------------------|-------------------------------------------------------------|
| `github-pr.el`         | Emacs commands (`github-pr`, `github-pr-submit`)            |
| `github_pr.py`         | sidecar that talks to the `gh` CLI                          |
| `test_github_pr.py`    | offline unit tests for the pure sidecar functions           |

`github-pr.el` locates `github_pr.py` next to itself, so the whole directory is
deployed together to `~/.config/emacs-vanilla/packages/github-pr/`.

## Auth

All GitHub access goes through the `gh` CLI, which owns authentication and
account selection — there is no credential handling here. If `gh auth status`
shows you logged in, you are ready; switch accounts with `gh auth switch`.

## Tests

`test_github_pr.py` is offline (no `gh`, no network):

```sh
python3 ~/.config/emacs-vanilla/packages/github-pr/test_github_pr.py
```

Note: the org file never tangled this test (an embedded `#+`-keyword line in a
fixture made Org skip the block), so it was carried over verbatim during the
conversion.

## Loading

`lisp/mp-tools.el` loads it with `(mp/require-package "github-pr")`.
