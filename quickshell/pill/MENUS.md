# pill/MENUS.md — authoritative menu-index map

The expanded pill hosts one pane at a time, selected by `win.menu` (an int in
`init.qml`). This file is the source of truth for that numbering so it stops
drifting across code, comments, and notes. When you add or renumber a pane,
update **both** this table and the `property int menu` comment in `init.qml`.

The dispatch lives in `init.qml`:
- `property int menu` declaration + comment (the canonical list).
- `menuLoader.sourceComponent` — the `win.menu === N ? cX : …` ternary chain.
- `Component { id: cX; … }` definitions near the bottom of `init.qml`.

## Panes

| menu | Component | Source file | Opened from |
|-----:|-----------|-------------|-------------|
| 0 | cNet | NetworkMenu.qml | status icon (network) |
| 1 | cVol | VolumeMenu.qml | status icon (volume) |
| 2 | cBt | BluetoothMenu.qml | status icon (bluetooth) |
| 3 | cBatt | BatteryMenu.qml | status icon (battery) |
| 4 | cNotif | NotificationHistory.qml | **default pane** / notif history key |
| 5 | cClip | ClipboardMenu.qml | clipboard IPC / key |
| 6 | cCal | CalendarMenu.qml | datetime click |
| 7 | cVoice | VoiceMemoMenu.qml | voice-memo config |
| 8 | cFin | FinanceMenu.qml | wallet button |
| 9 | cTetris | TetrisMenu.qml | Games menu |
| 10 | cBlockBlast | BlockBlastMenu.qml | Games menu |
| 11 | cGames | GamesMenu.qml | game-controller button (right of desktop dots) |
| 12 | cBrickBreaker | BrickBreakerMenu.qml | Games menu |
| 13 | cSettings | SettingsMenu.qml | gear (right of Done button) |
| 14 | cSnake | SnakeMenu.qml | Games menu |
| 15 | cDone | DoneMenu.qml | Done button (git + agenda work history) |
| 16 | cEmoji | EmojiMenu.qml | smiley button |
| 17 | cMine | MinesweeperMenu.qml | Games menu (mouse-only) |
| 18 | cInvaders | InvadersMenu.qml | Games menu (Chicken Invaders roguelike) |

Notes:
- **4 is the default** — the fallback branch of the dispatch ternary is `cNotif`.
- Games (9, 10, 12, 14, 17, 18) are launched *through* the Games picker (menu 11,
  `GamesMenu.qml`), which routes clicks via `playRequested(gameMenu)` →
  `openTetris` / `openBlockBlast` / etc. in `init.qml`. Add a new game by
  dropping a row into `GamesMenu.games` **and** wiring its pane here — and give
  it a screenshot-harness stage (`../screenshots/`, see CLAUDE.md rule 6).
- Panes that grab the keyboard: 4, 5, 9, 12, 14, 16, 18 (see `grabsKeyboard` in
  `init.qml`). Game panes with a custom size: 9/10 (tetris), 12 (brick), 14
  (snake), plus 11 (games list), 13 (settings), 15 (done), 16 (emoji), 17
  (minesweeper), 18 (invaders).
- Minesweeper (17) is mouse-only — it stays out of `grabsKeyboard` (like Block
  Blast) but is in `gamePane` (park-draggable by the header grip).
- The Games picker (11) sizes to its card count (`gamesHeight`) — it outgrew the
  generic `openHeight` at six games.
- The next free index is **19**.
