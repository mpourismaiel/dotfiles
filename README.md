# Dotfiles

A long-lived, slightly messy dotfiles repo. I used AwesomeWM, then Hyprland, and
now **KDE Plasma 6 on Wayland** — hence the odd folder layout and the branches in
history.

## The pill 👉 [`quickshell/pill`](quickshell/pill)

The one thing worth your time. A [Quickshell](https://quickshell.org) shell that
replaces KDE's panels with a single pill at the top-center of every monitor — it
morphs between a clock, a hover dashboard, and click-open menus (network, volume,
bluetooth, battery, calendar, finance, clipboard, notifications) with a built-in
app launcher, and it doubles as the notification daemon.

- **Install:** [`quickshell/INSTALL.md`](quickshell/INSTALL.md) — one-command
  script for Arch, full dependency list, and what degrades off KDE.
- **Internals:** [`quickshell/pill/README.md`](quickshell/pill/README.md).

There's also `quickshell/emaqs`, a small bottom-edge Emacs-Doom workspace pill —
only useful if you live in Emacs.

## Everything else

Personal config with nothing special going on, kept here mostly to sync it:

- **`zsh` / `starship`** — prompt + shell functions I use daily.
- **`mpv`** — stock `mpv.conf`/`input.conf`; the good parts are other people's
  scripts: [uosc](https://github.com/tomasklaen/uosc) (UI),
  [thumbfast](https://github.com/po5/thumbfast) (hover thumbnails), and the
  [Eisa01/mpv-scripts](https://github.com/Eisa01/mpv-scripts) suite (history,
  bookmarks, copy/paste, undo). Assembled from a config repo I can no longer
  find — those three are the credit.
- **`doom`** — my Emacs Doom config. Literate, LLM-assisted, very personal.

I hope you're not using my config. 🙂
