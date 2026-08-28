pragma ComponentBehavior: Bound
// GamesMenu.qml — the little arcade: a list of the games bundled with the pill
// (menu 11), opened from the game-controller button right of the virtual-desktop
// dots on the expanded dashboard. Picking a row hands off to that game's own pane
// (Tetris = menu 9, Block Blast = menu 10) via playRequested, which init.qml wires
// to openTetris / openBlockBlast. Add a new game by dropping a row into `games`.
//
// This is only the launcher/picker — each game keeps its own menu, keyboard grab
// and persisted state; this pane grabs nothing and just routes the click.
import QtQuick

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — best scores live under settings.<game>
    signal closeRequested()
    signal playRequested(int gameMenu)      // 9 = Tetris, 10 = Block Blast, 12 = Brick Breaker, 14 = Snake, 17 = Minesweeper

    // one entry per game. `glyph` is a 3×2 cell mask drawn as little squares (the
    // same identity the old clock-side buttons used); `best` reads each game's
    // persisted high score so the row can show it.
    readonly property var games: [
        {
            "menu": 9,
            "name": "Tetris",
            "desc": "Stack the falling tetrominoes, clear full lines.",
            "best": (root.settings.tetris && root.settings.tetris.high) || 0,
            "glyph": [[1, 0], [2, 0], [0, 1], [1, 1]]     // S-tetromino
        },
        {
            "menu": 10,
            "name": "Block Blast",
            "desc": "Drop blocks to fill rows and columns.",
            "best": (root.settings.blockBlast && root.settings.blockBlast.best) || 0,
            "glyph": [[1, 0], [0, 1], [1, 1], [2, 1]]     // plus/T piece
        },
        {
            "menu": 12,
            "name": "Brick Breaker",
            "desc": "Aim, launch the balls, smash the bricks.",
            "best": (root.settings.brickBreaker && root.settings.brickBreaker.best) || 0,
            "glyph": [[0, 0], [1, 0], [2, 0], [1, 1]]     // wall + ball
        },
        {
            "menu": 14,
            "name": "Snake",
            "desc": "Eat apples, grow the tail, don't bite yourself.",
            "best": (root.settings.snake && root.settings.snake.best) || 0,
            "glyph": [[0, 1], [1, 1], [2, 1], [2, 0]]     // snake bend
        },
        {
            "menu": 17,
            "name": "Minesweeper",
            "desc": "Uncover the field, flag the mines, don't blow up.",
            // best is the fastest Beginner clear (seconds); 0 until first win
            "best": (root.settings.minesweeper && root.settings.minesweeper.best && root.settings.minesweeper.best[0]) || 0,
            "glyph": [[0, 0], [2, 0], [0, 1], [2, 1]]     // scattered mines
        }
    ]

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Games"
            onBack: root.closeRequested()
        }

        // one card per game
        Repeater {
            model: root.games
            delegate: Rectangle {
                id: card
                required property var modelData

                // keyboard nav (MenuKbNav): Enter plays the game
                readonly property bool kbFocusable: true
                property bool kbFocused: false
                function keyClick() { root.playRequested(card.modelData.menu); }

                width: parent ? parent.width : 0
                height: 66
                radius: root.theme.radiusBtn
                color: (cardMa.containsMouse || card.kbFocused) ? root.theme.rowHi : root.theme.row

                // glyph tile — the game's little block mask on an accent-soft square
                Rectangle {
                    id: tile
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: root.theme.radiusSmall
                    color: root.theme.accentSoft

                    Item {
                        anchors.centerIn: parent
                        width: 15
                        height: 10
                        readonly property int u: 5
                        Repeater {
                            model: card.modelData.glyph
                            delegate: Rectangle {
                                required property var modelData
                                x: modelData[0] * parent.u
                                y: modelData[1] * parent.u
                                width: parent.u - 1
                                height: parent.u - 1
                                radius: 1
                                color: root.theme.accent
                            }
                        }
                    }
                }

                // name over description
                Column {
                    anchors.left: tile.right
                    anchors.leftMargin: 14
                    anchors.right: bestCol.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        text: card.modelData.name
                        color: root.theme.text
                        font.family: root.theme.serif
                        font.pixelSize: root.theme.fsLarge + 3
                    }
                    Text {
                        width: parent.width
                        text: card.modelData.desc
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        elide: Text.ElideRight
                    }
                }

                // best score (right) — hidden until the game has been played once
                Column {
                    id: bestCol
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    visible: card.modelData.best > 0

                    Text {
                        anchors.right: parent.right
                        text: "BEST"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall - 1
                        font.letterSpacing: root.theme.labelSpacing
                    }
                    Text {
                        anchors.right: parent.right
                        text: card.modelData.best
                        color: root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsLarge
                    }
                }

                MouseArea {
                    id: cardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.playRequested(card.modelData.menu)
                }

                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }
        }
    }
}
