# Doom packages

Self-contained features that used to live inline in `config.org`. Each one is a
real package directory (`.el` + a `README.md`, plus any sidecar scripts) instead
of a giant literate-config section, so `config.org` can stay lean and just
*configure* and *load* them rather than *define* them.

## Layout

```
packages/
  deploy.sh            health-check + sync into the live config
  <name>/
    <name>.el          the package (Emacs Lisp)
    README.md          what it is / how to use it (not deployed)
    ...                optional sidecars (.py, .sh, ...)
```

## How it loads

`config.org` never points at this repo directory directly. `deploy.sh` copies
each package into the running Doom config at `~/.config/doom/packages/<name>/`,
and `config.org` loads it from there with the `mp/require-package` helper:

```elisp
(mp/require-package "svg-header")
```

The call sits at the same spot in `config.org` where the code used to be inline,
so load order / timing is unchanged. If a package hasn't been deployed yet the
helper just logs a message — a missing deploy can never break config load.

## Deploying

`deploy.sh` is run automatically after you tangle `config.org` (an
`org-babel-tangle` advice in config.org's Overview section fires it). You can
also run it by hand:

```sh
doom/packages/deploy.sh
```

It **health-checks first and deploys nothing if anything fails**. The checks are
reader/parser-only, so they need neither Doom nor the packages' own runtime deps:

| files  | check                                   |
|--------|-----------------------------------------|
| `*.el` | Emacs `check-parens` (balanced parens)  |
| `*.py` | `python3 -m py_compile` (syntax)        |
| `*.sh` | `bash -n` (syntax)                      |

Deploy target is `${DOOMDIR:-~/.config/doom}/packages/`.

## First run

The tangle-time auto-deploy is installed by loading the *new* `config.el`, so it
isn't active during the very first tangle that produces it. Run `deploy.sh`
once by hand (or `SPC h r r` to reload, which installs the advice); every tangle
after that deploys on its own.
