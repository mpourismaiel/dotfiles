pragma ComponentBehavior: Bound
// EmojiMenu.qml — the pill's emoji picker (menu 16), opened from the smiley
// button between the games and Done buttons on the expanded dashboard (and via
// the `emoji` IPC command). A search field + a category tab strip sit on top;
// below is a keyboard-navigable grid of every emoji (bundled, categorized data
// in emojidata.js). Enter (or click) copies the highlighted emoji to the
// clipboard via wl-copy and closes the pane. Right-click any emoji for a small
// menu to add/remove it from Favorites (persisted in settings.emojiFavorites).
//
// By default the Favorites tab shows first if the user has any; otherwise the
// first real category. Keyboard nav mirrors the launcher: the search field keeps
// focus and its arrow keys drive the grid selection (all four arrows navigate,
// since the view is always a grid), Enter copies, Escape closes.
import QtQuick
import Quickshell.Io
import "emojidata.js" as EmojiData

Item {
    id: root
    required property var theme
    required property var settings          // shared JsonAdapter — favourites live under settings.emojiFavorites
    signal closeRequested()

    // ---- data ----------------------------------------------------------------
    readonly property var cats: EmojiData.CATEGORIES     // [{name,label,tab,emojis:[[ch,name,kw],…]}]

    // favourite emoji chars (persisted). Read-through so the view reacts to edits.
    readonly property var favs: root.settings.emojiFavorites || []
    function isFav(ch) { return root.favs.indexOf(ch) >= 0; }

    // char → [ch,name,kw] lookup, so the Favorites tab (which stores only chars)
    // can render names/keywords, and tooltips work everywhere.
    readonly property var byChar: {
        const m = {};
        for (let ci = 0; ci < root.cats.length; ci++) {
            const es = root.cats[ci].emojis;
            for (let i = 0; i < es.length; i++) m[es[i][0]] = es[i];
        }
        return m;
    }

    // tab strip: a synthetic Favorites tab (only when there are any) then every
    // category. `tab` indexes into this. A default of 0 therefore lands on
    // Favorites when present, else the first category — exactly the requested
    // default.
    readonly property bool hasFav: root.favs.length > 0
    property int tab: 0
    readonly property var tabs: {
        const t = [];
        if (root.hasFav)
            t.push({ "name": "Favorites", "label": "Favorites", "tab": "⭐", "fav": true });
        for (let i = 0; i < root.cats.length; i++) t.push(root.cats[i]);
        return t;
    }

    // ---- query ----------------------------------------------------------------
    property string query: ""
    readonly property string q: root.query.trim().toLowerCase()
    readonly property bool searching: root.q.length > 0

    // the rows shown in the grid — filtered search results across every category,
    // or the active tab's emojis. Each row is [ch, name, kw].
    readonly property var view: {
        if (root.searching) {
            const out = [];
            const needle = root.q;
            for (let ci = 0; ci < root.cats.length; ci++) {
                const es = root.cats[ci].emojis;
                for (let i = 0; i < es.length; i++)
                    if (es[i][2].indexOf(needle) >= 0 || es[i][1].indexOf(needle) >= 0)
                        out.push(es[i]);
            }
            return out;
        }
        const active = root.tabs[root.tab];
        if (!active) return [];
        if (active.fav)
            return root.favs.map(ch => root.byChar[ch] || [ch, "", ""]);
        return active.emojis;
    }

    // add/remove a favourite. Reassign the array (never mutate) so the JsonAdapter
    // flushes, mirroring the launcher's pinned/favorites handling. As the synthetic
    // Favorites tab appears/disappears it shifts every category by one, so nudge
    // `tab` to keep the currently-viewed category in place.
    function toggleFav(ch) {
        const cur = (root.settings.emojiFavorites || []).slice();
        const i = cur.indexOf(ch);
        const hadFav = cur.length > 0;
        if (i >= 0) cur.splice(i, 1); else cur.push(ch);
        const nowFav = cur.length > 0;
        root.settings.emojiFavorites = cur;
        if (!hadFav && nowFav) root.tab = root.tab + 1;
        else if (hadFav && !nowFav && root.tab > 0) root.tab = root.tab - 1;
    }

    // ---- clipboard ------------------------------------------------------------
    Process { id: copyProc }
    function copy(s) { copyProc.command = ["wl-copy", "--", String(s)]; copyProc.startDetached(); }

    // ---- keyboard selection (mirrors Launcher.setSel/moveVert/moveHoriz) ------
    property int sel: 0
    onQChanged: root.sel = 0
    onTabChanged: root.sel = 0
    function setSel(i) {
        const n = root.view.length;
        root.sel = n === 0 ? 0 : Math.max(0, Math.min(n - 1, i));
        if (n > 0) grid.positionViewAtIndex(root.sel, GridView.Contain);
    }
    function moveVert(d) { root.setSel(root.sel + d * grid.cols); }
    function moveHoriz(d) { root.setSel(root.sel + d); }
    function activate() {
        const v = root.view;
        if (v.length === 0) return;
        const e = v[Math.max(0, Math.min(v.length - 1, root.sel))];
        root.copy(e[0]);
        root.closeRequested();
    }

    Component.onCompleted: search.forceActiveFocus()

    // ---- header ---------------------------------------------------------------
    MenuHeader {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        theme: root.theme
        title: "Emoji"
        onBack: root.closeRequested()
    }

    // search field (left) + category tab strip (right), on one baseline
    Item {
        id: topRow
        anchors.top: header.bottom
        anchors.topMargin: root.theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40

        // category tabs — one per Favorites/category, each a representative emoji
        // glyph. Active (and not searching) is filled; clicking a tab clears the
        // search and returns focus to the field for continued keyboard nav.
        Row {
            id: tabStrip
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Repeater {
                model: root.tabs
                delegate: Rectangle {
                    id: tabBtn
                    required property int index
                    required property var modelData
                    readonly property bool active: !root.searching && root.tab === index
                    width: 30
                    height: 30
                    radius: root.theme.radiusBtn
                    color: (tabMa.containsMouse || active) ? root.theme.accentSoft : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: tabBtn.modelData.tab
                        font.pixelSize: 17
                        opacity: tabBtn.active ? 1 : 0.75
                    }

                    // active underline
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 14
                        height: 2
                        radius: 1
                        color: root.theme.accent
                        visible: tabBtn.active
                    }

                    MouseArea {
                        id: tabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.query = "";
                            search.text = "";
                            root.tab = tabBtn.index;
                            search.forceActiveFocus();
                        }
                    }

                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }

        Rectangle {
            id: searchBox
            anchors.left: parent.left
            anchors.right: tabStrip.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 40
            radius: root.theme.radiusRow
            color: root.theme.row
            border.color: search.activeFocus ? root.theme.accent : root.theme.border
            border.width: 1

            MSym {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                icon: "search"
                size: 18
                color: search.activeFocus ? root.theme.accent : root.theme.faint
            }
            TextInput {
                id: search
                objectName: "pillKbInput"
                anchors.left: searchIcon.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
                clip: true
                selectByMouse: true
                selectionColor: root.theme.accentDim
                onTextChanged: root.query = text

                Keys.onEscapePressed: root.closeRequested()
                Keys.onReturnPressed: root.activate()
                Keys.onEnterPressed: root.activate()
                // the view is always a grid, so every arrow navigates it (the
                // launcher does the same in grid mode) — the text cursor is not
                // needed inside a short search term.
                Keys.onUpPressed: root.moveVert(-1)
                Keys.onDownPressed: root.moveVert(1)
                Keys.onLeftPressed: root.moveHoriz(-1)
                Keys.onRightPressed: root.moveHoriz(1)

                Text {                              // placeholder
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: "Search emoji"
                    color: root.theme.faint
                    font.family: search.font.family
                    font.pixelSize: search.font.pixelSize
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- emoji grid -----------------------------------------------------------
    GridView {
        id: grid
        anchors.top: topRow.bottom
        anchors.topMargin: root.theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        cellWidth: 46
        cellHeight: 46
        // actual number of columns — used by moveVert to step a full row
        readonly property int cols: Math.max(1, Math.floor(width / cellWidth))
        boundsBehavior: Flickable.StopAtBounds
        model: root.view
        cacheBuffer: 400

        // empty-state hint (Favorites tab with no favourites, or a search miss)
        Text {
            anchors.centerIn: parent
            visible: root.view.length === 0
            width: parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.searching
                ? "No emoji matches “" + root.query.trim() + "”"
                : "No favourites yet — right-click any emoji to add one."
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
        }

        delegate: Item {
            id: cell
            required property int index
            required property var modelData          // [ch, name, kw]
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: root.theme.radiusSmall
                color: (cellMa.containsMouse || cell.index === root.sel) ? root.theme.rowHi : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData[0]
                    font.pixelSize: 24
                }

                // little corner star on favourited emoji (redundant inside the
                // Favorites tab, so hidden there)
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 1
                    anchors.rightMargin: 2
                    text: "⭐"
                    font.pixelSize: 9
                    visible: root.isFav(cell.modelData[0])
                        && !(root.tabs[root.tab] && root.tabs[root.tab].fav)
                }

                MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPositionChanged: root.sel = cell.index
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            const p = mapToItem(root, mouse.x, mouse.y);
                            root.showCtx(cell.modelData[0], p.x, p.y);
                        } else {
                            root.copy(cell.modelData[0]);
                            root.closeRequested();
                        }
                    }
                }

                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }
        }
    }

    // ---- right-click favourites menu -----------------------------------------
    // Hosted inside this pane (positioned in root coordinates, clamped to stay in
    // bounds), so it never leaves the menu's own clip region.
    property string ctxChar: ""
    property real ctxX: 0
    property real ctxY: 0
    function showCtx(ch, x, y) { root.ctxChar = ch; root.ctxX = x; root.ctxY = y; }
    function hideCtx() { root.ctxChar = ""; }

    MouseArea {                                     // outside-click dismiss
        anchors.fill: parent
        visible: root.ctxChar !== ""
        z: 99
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.hideCtx()
    }

    Rectangle {
        id: ctx
        z: 100
        visible: root.ctxChar !== ""
        width: 190
        height: ctxRow.height + 10
        radius: root.theme.radiusBtn
        color: root.theme.row
        border.color: root.theme.border
        border.width: 1
        x: Math.max(0, Math.min(root.ctxX, root.width - width))
        y: Math.max(0, Math.min(root.ctxY, root.height - height))

        Row {
            id: ctxRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            height: 30

            Rectangle {
                width: parent.width
                height: 30
                radius: root.theme.radiusSmall
                color: ctxMa.containsMouse ? root.theme.rowHi : "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ctxChar
                        font.pixelSize: 16
                    }
                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "star"
                        size: 16
                        fill: root.isFav(root.ctxChar) ? 1 : 0
                        color: root.theme.accent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isFav(root.ctxChar) ? "Remove from favorites" : "Add to favorites"
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                }

                MouseArea {
                    id: ctxMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.toggleFav(root.ctxChar);
                        root.hideCtx();
                        search.forceActiveFocus();
                    }
                }

                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }
        }
    }
}
