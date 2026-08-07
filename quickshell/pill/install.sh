#!/usr/bin/env bash
# install.sh — one-shot installer for the Quickshell "pill" shell on Arch Linux.
#
# What it does, in order:
#   1. installs the runtime + core dependencies from the official repos,
#   2. installs the icon font (Material Symbols) from the AUR (needs an AUR
#      helper — yay/paru — or it tells you the one package to add by hand),
#   3. drops the two display fonts Arch doesn't package (DM Serif Display, and
#      optionally Newsreader + Instrument Serif) into ~/.local/share/fonts,
#   4. copies the pill into ~/.config/quickshell/pill (the live config location),
#   5. on KDE, offers to install the pill's suggested global shortcuts,
#   6. prints how to start it.
#
# It is safe to re-run: every step is idempotent (pacman --needed, font files are
# overwritten, the copy just refreshes ~/.config/quickshell/pill).
#
# Usage:
#   ./install.sh                 core install (everything the pill needs to run)
#   ./install.sh --with-optional add the per-feature tools (finance, voice,
#                                screenshots, org-agenda, screen recording, …)
#   ./install.sh --no-copy       install deps only, don't touch ~/.config
#
# NOT for the repo maintainer's own machine — that one deploys with deploy.sh.
# This is for a fresh machine / another user cloning the repo.
set -euo pipefail

SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/pill"
FONTDIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

WITH_OPTIONAL=0
DO_COPY=1
for a in "$@"; do
    case "$a" in
        --with-optional) WITH_OPTIONAL=1 ;;
        --no-copy)       DO_COPY=0 ;;
        -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
    esac
done

say()  { printf '\n\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$1" >&2; exit 1; }

command -v pacman >/dev/null || die "this installer targets Arch Linux (pacman not found).
See ../INSTALL.md for the dependency list to install by hand on other distros."

# --- 1. core packages (official repos) ---------------------------------------
# quickshell     — the runtime (provides the `qs` command)
# qt6-*          — QML engine + Shapes/Effects/DBus used across the pill
# milou/kirigami — KDE KRunner search backend for the launcher (see note below)
# plasma-workspace/kwin — the pill is a KDE Plasma 6 / KWin (Wayland) shell
# the rest are the tools the pill shells out to for its always-on features.
CORE_PKGS=(
    quickshell
    qt6-declarative qt6-base qt6-tools qt6-multimedia qt6-5compat
    milou kirigami
    plasma-workspace kwin
    glib2 wl-clipboard libnotify cliphist networkmanager brightnessctl
    pipewire wireplumber libsecret xdg-utils python python-gobject
    ttf-ibm-plex
)

# --- optional, per-feature tools ---------------------------------------------
OPTIONAL_PKGS=(
    spectacle             # screenshots (default grabber)
    imagemagick           # crop/export captured images
    gpu-screen-recorder   # screen recording
    hledger git           # finance menu + its git-backed journals
    emacs                 # org-agenda / deadlines (needs a running emacs daemon)
)

say "Installing core packages from the official repos"
sudo pacman -S --needed "${CORE_PKGS[@]}"

if [ "$WITH_OPTIONAL" -eq 1 ]; then
    say "Installing optional per-feature packages"
    sudo pacman -S --needed "${OPTIONAL_PKGS[@]}"
fi

# --- 2. icon font from the AUR (essential: every glyph in the UI uses it) -----
AUR_FONT=ttf-material-symbols-variable-git
if pacman -Qq "$AUR_FONT" >/dev/null 2>&1; then
    say "Icon font already installed ($AUR_FONT)"
else
    helper=""
    for h in yay paru; do command -v "$h" >/dev/null && { helper="$h"; break; }; done
    if [ -n "$helper" ]; then
        say "Installing the icon font from the AUR ($AUR_FONT via $helper)"
        "$helper" -S --needed "$AUR_FONT"
    else
        warn "No AUR helper (yay/paru) found. The icon font is essential — the pill
         renders empty boxes without it. Install it by hand, e.g.:
             git clone https://aur.archlinux.org/$AUR_FONT.git
             cd $AUR_FONT && makepkg -si"
    fi
fi

# --- 3. display fonts Arch doesn't package (Google Fonts, OFL) ----------------
# DM Serif Display is used for the clock/titles (core). Newsreader + Instrument
# Serif are only used by the fancy power-confirm screens (optional).
say "Installing display fonts into $FONTDIR"
mkdir -p "$FONTDIR"
GF=https://github.com/google/fonts/raw/main/ofl
fetch() { # fetch <url> <dest-name>
    if command -v curl >/dev/null; then curl -fsSL "$1" -o "$FONTDIR/$2"
    elif command -v wget >/dev/null; then wget -qO "$FONTDIR/$2" "$1"
    else warn "neither curl nor wget found — skipping font $2"; return 1; fi
    echo "  fetched $2"
}
fetch "$GF/dmserifdisplay/DMSerifDisplay-Regular.ttf" DMSerifDisplay-Regular.ttf || true
fetch "$GF/dmserifdisplay/DMSerifDisplay-Italic.ttf"  DMSerifDisplay-Italic.ttf  || true
if [ "$WITH_OPTIONAL" -eq 1 ]; then
    fetch "$GF/newsreader/Newsreader%5Bopsz,wght%5D.ttf"          "Newsreader.ttf"          || true
    fetch "$GF/newsreader/Newsreader-Italic%5Bopsz,wght%5D.ttf"   "Newsreader-Italic.ttf"   || true
    fetch "$GF/instrumentserif/InstrumentSerif-Regular.ttf"       "InstrumentSerif-Regular.ttf" || true
    fetch "$GF/instrumentserif/InstrumentSerif-Italic.ttf"        "InstrumentSerif-Italic.ttf"  || true
fi
command -v fc-cache >/dev/null && fc-cache -f "$FONTDIR" >/dev/null 2>&1 || true

# --- 4. copy the pill into the live config -----------------------------------
if [ "$DO_COPY" -eq 1 ]; then
    say "Copying the pill into $DEST"
    mkdir -p "$DEST"
    for f in "$SRC"/*; do
        b=$(basename "$f")
        # skip dev-only tooling and docs — they never belong in the live config.
        # kde-shortcuts.kksrc is handled separately below (paths get rewritten to
        # this user before it lands in the config dir), so skip the raw copy here.
        case "$b" in install.sh|deploy.sh|check.sh|README.md|CLAUDE.md|INSTALL.md|kde-shortcuts.kksrc) continue ;; esac
        [ -f "$f" ] || continue
        cp -p "$f" "$DEST/$b"
    done
    chmod +x "$DEST"/*.sh 2>/dev/null || true
    echo "  copied $(ls "$DEST" | wc -l) files"
fi

# --- 4b. optional: KDE global shortcuts --------------------------------------
# The repo ships a set of global-shortcut bindings the pill is designed around
# (Meta+V clipboard history, Print screenshot, Meta+S open, volume/brightness
# keys, …), exported from KDE as kde-shortcuts.kksrc. Those bindings are what
# make the pill feel like a first-class shell. On KDE we OFFER to install them,
# after rewriting the maintainer's hard-coded paths to this user's config. They
# are optional and easy to change or remove afterwards in System Settings.
KKSRC_IN="$SRC/kde-shortcuts.kksrc"
is_kde=0
case "${XDG_CURRENT_DESKTOP:-}" in *KDE*|*kde*) is_kde=1 ;; esac
command -v plasmashell >/dev/null 2>&1 && is_kde=1
SHORTCUTS_DONE=0
if [ "$is_kde" -eq 1 ] && [ -f "$KKSRC_IN" ]; then
    do_shortcuts=0
    if [ -t 0 ]; then
        printf '\n\033[1;36m==>\033[0m %s' \
            "KDE detected. Install the pill's suggested global shortcuts (Meta+V clipboard, Print screenshot, Meta+S open, volume/brightness keys, …)? [y/N] "
        read -r ans || ans=""
        case "$ans" in y|Y|yes|YES|Yes) do_shortcuts=1 ;; esac
    else
        warn "KDE detected but input is not a terminal — skipping the optional
         global shortcuts. Re-run this installer interactively to add them."
    fi
    if [ "$do_shortcuts" -eq 1 ]; then
        mkdir -p "$DEST"
        KKSRC_OUT="$DEST/kde-shortcuts.kksrc"
        # rewrite the maintainer's paths (absolute and ~) to this user's config,
        # then any remaining home references, so the Exec lines point at the copy
        # of the pill this installer just placed.
        sed -e "s#/home/mahdi/.config/quickshell/pill#$DEST#g" \
            -e "s#~/.config/quickshell/pill#$DEST#g" \
            -e "s#/home/mahdi#$HOME#g" \
            "$KKSRC_IN" > "$KKSRC_OUT"
        SHORTCUTS_DONE=1
        say "Prepared the shortcut bindings for you at:
    $KKSRC_OUT

KDE has no reliable command-line importer, so activating them is a single
one-time click:
    System Settings → Keyboard → Shortcuts → the ⋮ (or 'Import') menu → Import…
    then pick the file above.

Every binding is just a suggestion — change or remove any of them afterwards in
that same Shortcuts screen."
    fi
fi

# --- 5. done -----------------------------------------------------------------
cat <<EOF

$(say "Done." >/dev/null; printf '\033[1;32m==> Done.\033[0m')

Start the pill (from your Wayland/KDE session) with:

    $DEST/run-pill.sh

To launch it automatically at login, add that command to
System Settings → Autostart, or drop a .desktop file in ~/.config/autostart.

Notes:
  • This is a KDE Plasma 6 / KWin (Wayland) shell. On other compositors it
    still loads, but KWin-specific features (taskbar, virtual-desktop dots,
    brightness, power menu, launcher *search*) degrade — see ../INSTALL.md.
  • Optional features (voice transcription, Google Calendar, finance) each
    need extra one-time setup; see quickshell/pill/README.md and CAPTURE.md.
$( [ "$SHORTCUTS_DONE" -eq 1 ] && printf '  • Import the prepared global shortcuts: System Settings → Keyboard →\n    Shortcuts → Import… → %s\n' "$DEST/kde-shortcuts.kksrc" )
EOF
