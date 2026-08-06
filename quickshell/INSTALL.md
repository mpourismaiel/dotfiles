# Installing the pill

The **pill** is a [Quickshell](https://quickshell.org) desktop shell: one pill at
the top-center of every monitor that morphs between a clock, a hover dashboard, a
click-open control panel (network / volume / bluetooth / battery / calendar /
finance / clipboard / notifications) and an app launcher. It is also the
machine's freedesktop notification daemon.

It is built for **KDE Plasma 6 on Wayland (KWin)**. That is the supported target
and where every feature works. It still *runs* on other Wayland compositors, but
several features degrade — see [Running without KDE](#running-without-kde).

---

## Quick install (Arch Linux)

```bash
git clone <this-repo> awesome
cd awesome/quickshell/pill
./install.sh                 # core install
# ./install.sh --with-optional   # also install finance / voice / screenshot / org tools
```

The script installs the runtime and dependencies, pulls the fonts, and copies the
pill into `~/.config/quickshell/pill`. Then start it:

```bash
~/.config/quickshell/pill/run-pill.sh
```

To start it at login, add that command to **System Settings → Autostart** (or drop
a `.desktop` file in `~/.config/autostart`).

> The installer needs an **AUR helper** (`yay` or `paru`) for the one icon font
> that Arch doesn't package (`ttf-material-symbols-variable-git`). Without the
> icon font the UI renders empty boxes where glyphs should be, so install it one
> way or another. Everything else comes from the official repos.

---

## Manual install

If you'd rather install by hand (or you're not on Arch), here is the full
dependency list. Package names are Arch's; translate as needed for your distro.

### Runtime + core (required)

| Package(s) | Why |
| --- | --- |
| `quickshell` | the runtime — provides the `qs` command |
| `qt6-declarative qt6-base qt6-tools qt6-multimedia qt6-5compat` | QML engine, Shapes/Effects, DBus, webcam overlay |
| `plasma-workspace kwin` | it's a KDE Plasma 6 / KWin shell (taskbar, virtual desktops, brightness, power all go through KWin/Plasma DBus) |
| `milou kirigami` | KDE KRunner search backend used by the launcher (optional at runtime — see below) |
| `glib2` | `gdbus` (KWin / virtual-desktop / keyboard-layout DBus calls) |
| `wl-clipboard cliphist` | clipboard history menu |
| `libnotify` | `notify-send` |
| `networkmanager` | Wi-Fi / wired menu (`nmcli`) |
| `brightnessctl` | brightness media keys |
| `pipewire wireplumber` | volume menu + per-app streams |
| `libsecret xdg-utils` | keyring + opening links |
| `python python-gobject` | the Python "bridges" (window list, clipboard, calendar, …) |

### Fonts (required)

| Font | Source |
| --- | --- |
| IBM Plex Sans / IBM Plex Mono | `ttf-ibm-plex` (official repo) |
| Material Symbols Rounded | `ttf-material-symbols-variable-git` (AUR) — **all UI glyphs** |
| DM Serif Display | Google Fonts (OFL) — clock/titles. `install.sh` downloads it to `~/.local/share/fonts`; or grab it from [fonts.google.com](https://fonts.google.com/specimen/DM+Serif+Display) |

### Optional, per feature

| Feature | Needs |
| --- | --- |
| Screenshots | `spectacle` (default grabber) + `imagemagick` (crop/export) |
| Screen recording | `gpu-screen-recorder` |
| Finance menu | `hledger` + `git` (git-backed journals) — off by default; enable in the launcher **Settings** page |
| Org agenda / deadlines | `emacs` running as a daemon (`emacsclient`) — off by default; enable in **Settings** |
| Voice memos / transcription | see [`pill/setup-transcribe.sh`](pill/setup-transcribe.sh) (own venv: `faster-whisper`, optional `anthropic` for Claude polish) |
| Google / Proton calendar | `python-gobject` + KDE Online Accounts, or the pill's own OAuth flow — see [`pill/README.md`](pill/README.md) |
| Power-confirm fancy fonts | Newsreader + Instrument Serif (Google Fonts) — only for the `1a`–`1d` confirm screens; `install.sh --with-optional` fetches them |

Then copy the pill into place and run it:

```bash
cp -r pill ~/.config/quickshell/pill          # (or run pill/install.sh --no-copy first, then this)
~/.config/quickshell/pill/run-pill.sh
```

---

## Running without KDE

The pill is a KDE Plasma 6 / KWin shell, so a lot of it is wired to KWin and
Plasma over DBus. On a non-KDE Wayland compositor it **still loads and is usable**
— notifications, clock/calendar, volume, bluetooth, the app launcher (grid +
favourites + calculator), clipboard, and the menus all work — but these
KWin/Plasma-specific pieces degrade:

| Feature | Without KDE |
| --- | --- |
| **Launcher search** | KRunner search (`org.kde.milou`) is unavailable → the launcher falls back to **local app-name filtering**. The launcher itself still opens and launches apps. |
| **Taskbar** | empty — the window list comes from a KWin script (KWin exposes no window-list Wayland protocol). |
| **Virtual-desktop dots** | inert — desktop list/switch is a KWin DBus call. |
| **Brightness slider / keys** | empty — uses KDE's `org.kde.ScreenBrightness`. |
| **Power menu (logout/reboot/shutdown)** | buttons no-op — they call `org.kde.Shutdown`. |
| **Keyboard-layout burst** | empty — reads `org.kde.keyboard`. |
| **KDE Online Accounts calendars** | unavailable — but the pill's own Google OAuth and Proton/ICS calendars still work. |

The important part: **a missing KDE piece degrades that one feature — it never
takes the whole pill down.** In particular the launcher's KDE search backend is
isolated in `pill/LauncherSearch.qml` and loaded through a `Loader`, so if
`org.kde.milou` / `org.kde.kirigami` aren't installed, only search falls back to
local filtering instead of the QML import bricking the entire shell.

If you want the launcher's full KRunner search on a non-KDE session, install just
`milou` and `kirigami` (they pull a bit of the Plasma search stack but don't
require you to *run* Plasma).

---

## Updating

Re-running `./install.sh` refreshes `~/.config/quickshell/pill` (Quickshell
hot-reloads on file change, so a running pill picks up the new copy on its own).
