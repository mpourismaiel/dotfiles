# org-src-formatter

Run a per-language external formatter on **every recognised src block** in an
Org buffer. Ships formatters for `qml` (qmlformat), `python` (ruff),
`sh`/`bash` (shfmt); missing tools are skipped gracefully.

Extracted verbatim from config.org's *Should be plugins › Org src block
formatter* section.

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

`config.org` loads it in place with `(mp/require-package "org-src-formatter")`.
