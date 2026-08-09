# Vanilla Emacs config (Doom migration)

Full port of the Doom Emacs setup in `../doom/` to vanilla Emacs 30.2 with
elpaca. Deployed to `~/.config/emacs-vanilla/`, launched with
`emacs --init-directory=~/.config/emacs-vanilla`. The Doom install stays
untouched and bootable throughout the transition.

## Layout

```
early-init.el      GC/UI pre-init
init.el            elpaca bootstrap + module loading
lisp/mp-core.el    defaults, paths, NVM/exec-path, private data, helpful
lisp/mp-evil.el    evil + full flotilla (snipe/surround/easymotion/...) + mc
lisp/mp-keys.el    general.el leader engine + the whole Doom binding tree
lisp/mp-completion.el  vertico/consult/embark/orderless/prescient/corfu/cape
lisp/mp-ui.el      doom-themes + dobri-c07, modeline, popper, visual polish
lisp/mp-treesit.el grammars, treesit-fold, fold-by-level, evil text objects
lisp/mp-lsp.el     lsp-bridge DEFAULT + eglot fallback + flycheck + apheleia
lisp/mp-workspaces.el  perspective, projectile, bundles, persistence, splash
lisp/mp-org.el     org + evil-org + org-appear + localleader
lisp/mp-langs.el   python pipenv guards, gdscript+dape, twee, misc languages
lisp/mp-tools.el   magit, ghostel, color-rg, clutch, docker, envrc, dirvish
lisp/mp-ai.el      agent-shell + eca (ghost-text completion + rewrite)
packages/          ported custom packages (svg-header, super-menu, teamwork, ...)
themes/            dobri-c07 (+ any future custom themes)
var/               runtime state (never synced by deploy)
```

Custom features remain self-contained packages under `packages/`, loaded with
`mp/require-package` from the module that owns them. Config files configure;
features live in packages.

## First launch

1. Deploy: `./deploy.sh` (or `__ignore__/scripts/deploy-vanilla.sh` from the
   repo). This also seeds `private.el` + `connections.json` into the target
   once, copied from the old Doom config dir.
2. Create the lsp-bridge backend venv (one-time):
   ```sh
   python -m venv ~/.config/emacs-vanilla/var/lsp-bridge-venv
   ~/.config/emacs-vanilla/var/lsp-bridge-venv/bin/pip install \
     epc orjson sexpdata six setuptools paramiko rapidfuzz watchdog packaging
   ```
   Without it, lsp-bridge stays off and corfu/eglot serve as fallback.
   lsp-bridge also needs the language SERVERS on PATH (it launches them
   itself). For the usual suspects:
   ```sh
   npm i -g typescript typescript-language-server pyright \
            vscode-langservers-extracted yaml-language-server \
            bash-language-server graphql-language-service-cli
   ```
   `M-x mp/lsp-doctor` in any code buffer reports exactly what's missing
   (venv / bridge / backend process / server binary). Real completions
   (e.g. `p.` → `a` with its type) only appear when everything is green —
   until then you're seeing the dumb word-matching fallback.
3. Launch: `emacs --init-directory=~/.config/emacs-vanilla`. First start pulls
   every package via elpaca (network, a few minutes). Watch `*elpaca-log*`.
4. If icons look wrong: `M-x nerd-icons-install-fonts`.
5. Terminal: `M-x ghostel-download-module` if the native module didn't
   auto-download.
6. Tree-sitter grammars auto-install on first use of each language.
7. ECA: start a session with `SPC d e`, `/login` → `anthropic` once per machine
   (server config in `~/.config/eca/` is shared external state, unchanged).
8. Godot: LSP/DAP need the Godot editor running (ports 6005/6006); gdscript
   buffers use eglot over TCP, everything else uses lsp-bridge.

## Lockfile

After a good sync on one machine: `M-x elpaca-write-lock-file` →
`emacs/lockfile/lock.eld`, commit it. Fresh machines then restore the exact
package revisions (init.el points elpaca at the lockfile when present).

## LSP architecture

lsp-bridge (own completion UI, async Python backend) is the DEFAULT in
supported prog buffers; corfu is suppressed there. eglot covers gdscript (TCP).
Everything else (org, conf, twee, ...) uses corfu. `SPC t b` toggles bridge OFF
per buffer (restoring corfu/eglot) — inverted from the Doom-era setup where
bridge was opt-in. Diagnostics: bridge's own in bridge buffers, flycheck
elsewhere (incl. hledger journals). Formatting: apheleia on save (prettier for
JS/TS/web, gdformat for GDScript); `SPC f !` saves without formatting.

## Intentional differences from the Doom keymap manifest

Dropped (dead in live Doom already):
- forge bindings under `SPC g` (forge was never installed), docsets `SPC s k/K`
  (dash-docs never installed), `+eval/test` (`SPC t t/a` now run
  `projectile-test-project` / were void functions before).
- `SPC i s` yasnippet + `C-TAB` aya-create (snippets feature removed entirely),
  `SPC t m` minimap (removed), `SPC o e/E` eshell → now open Ghostel,
  `SPC h d *` Doom help, `SPC h r e/f/p/t` Doom reloads (`SPC h r r` reloads
  init), `SPC q d` daemon restart, `SPC n Y` rich-text org export.

Note: `SPC h` now reuses the stock `help-map` wholesale (as Doom did), with the
custom entries (h b bindings tree, h r r, h t theme, helpful remaps) applied to
help-map itself — so they work from `C-h` too.

Replaced engines (same keys, new implementation):
- Scratch: `SPC x`, `SPC b x/X`, `SPC p x/X` → built-in `scratch-buffer`
  (no per-project persistent scratch).
- Sessions: `SPC q s/S/l/L`, `SPC TAB s/l` → workspace persistence
  (perspective state files; also autosaved on exit + every 5 min and
  auto-restored at startup — new behavior).
- LSP keys (`SPC c r/a/o/j`, `gd/gD/gr/K`, `]e/[e`, `SPC e *`) → dispatchers
  routing to lsp-bridge / eglot / flycheck depending on the buffer.
  `SPC c S` (lsp-treemacs) and `SPC c l` (lsp command map) dropped with lsp-mode.
  `SPC m g f s` → consult-imenu (was consult-lsp-file-symbols).
- `SPC s t/T` → built-in `dictionary-search`; `SPC s o/O` → web search prompt.
- `g Q` format region → apheleia; `g R` eval buffer → quickrun/elisp eval.
- vc: `SPC g s`/`SPC g r` → diff-hl stage/revert hunk; `SPC g S/U` →
  `magit-stage-file`/`magit-unstage-file`; git links via git-link.
- `SPC w d` now runs `mp/close-window-preserve-buffer` — the Doom config
  *intended* this but its `after! workspaces` block never fired (latent bug),
  so live Doom actually ran `evil-window-delete`. Fixed as intended.
- Dashboard → minimal splash buffer (workspace, project, branch, recent files);
  fresh splits (`SPC w v/s`) open it.

## Live-unverified (needs a real launch by the user)

elpaca first bootstrap; theme + svg-header + workspace-hud rendering;
lsp-bridge against real servers; ghostel native module; eca session +
partial-accepts; Godot TCP eglot; teamwork/github-pr/clutch live sidecars;
workspace persistence across real restarts; org agenda paths.

## Rollback

Keep using Doom (`~/.config/emacs` untouched). Delete
`~/.config/emacs-vanilla/` to reset the vanilla install; repo `emacs/` is the
source of truth.
