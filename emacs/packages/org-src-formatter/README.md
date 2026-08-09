# org-src-formatter

Run a per-language external formatter on **every recognised src block** in an
Org buffer. Ships formatters for `qml` (qmlformat), `python` (ruff),
`sh`/`bash` (shfmt); missing tools are skipped gracefully.

## Usage

`M-x my/org-format-src-blocks`, or wire it into a file's save:

```org
# Local Variables:
# eval: (add-hook 'before-save-hook #'my/org-format-src-blocks nil t)
# End:
```

Extend by adding to `my/org-src-formatters` (`lang -> (EXT PROGRAM ARGS...)`,
tools must edit the temp file in place).

## Loading

Loaded in place with `(mp/require-package "org-src-formatter")`.
