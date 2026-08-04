pragma ComponentBehavior: Bound
// Launcher.qml — KDE-style application launcher.
//
// Layout: a search field (focused on open) + a grid/list toggle, then the
// results. Empty query shows favourites (if any) else all apps, in grid or list
// per the persisted toggle. A non-empty query shows the full Plasma/KRunner
// search via an org.kde.milou ResultsModel (Applications, System Settings,
// Power, Locations, web shortcuts, … — whatever plugins are enabled in System
// Settings → Search), grouped by category; running a row calls back into
// KRunner. The search box also doubles as a calculator — an arithmetic
// expression (or one prefixed with =) shows a result row that copies on
// click/Enter. Right-click an app for its desktop actions and a favourite
// toggle. Favourites + grid mode are persisted by the parent (see init.qml).
//
// The resting app list is supplied by the parent (built once from
// DesktopEntries and kept alive across opens), so opening is instant.
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
// KRunner search backend (same one Plasma's launcher/KRunner use) + its icon
// renderer, which resolves both themed icon names and QIcon decorations.
import org.kde.milou as Milou
import org.kde.kirigami as Kirigami

Item {
    id: root
    required property var theme
    required property var apps        // [DesktopEntry], pre-sorted by the parent
    required property var settings    // JsonAdapter { bool grid; var favorites }
    required property var notifs      // notification state (the DND toggle drives it)
    property var fin                  // FinanceState (the privacy toggle drives it)
    property var acc                  // AccountsState (the settings page manages calendar accounts)
    // the settings gear (toggle row) opens the calendar-account manager over the body
    property bool settingsOpen: false
    signal launched()
    signal closeRequested()
    // right-click on an app row/tile/result: ask the parent to show the app
    // context menu (AppMenu) at (x, y) — in *this* Launcher's coordinates — so it
    // can render above the pill and drop out of it without being clipped.
    signal appMenuRequested(var app, bool fav, bool pinned, real x, real y)
    // shutdown / reboot / logout ask for a full-screen confirmation first; the
    // parent shows it and only runs `cmd` if the user picks "yes".
    signal confirmPower(string action, var cmd)
    
    // called by the parent when the launcher opens: clear + focus the search
    function open() { search.text = ""; currentIndex = 0; search.forceActiveFocus(); }
    // called when the launcher closes: drop the search field's active focus so the
    // (kept-instantiated) launcher stops holding the layer surface's keyboard grab,
    // letting the focused window get the keyboard back. The parent sets the window's
    // WlrKeyboardFocus to None in tandem.
    function close() { search.focus = false; }
    
    // ---- query ----
    readonly property string q: search.text.trim().toLowerCase()
    readonly property bool searching: q.length > 0
    
    readonly property var favApps: {
        const ids = settings.favorites || [];
        if (ids.length === 0) return [];
        const byId = {};
        for (const a of apps) byId[a.id] = a;
        return ids.map(id => byId[id]).filter(Boolean);
    }
    // resting model: favourites (if any) else all apps. Search results don't come
    // from here — while searching we show the KRunner results list below instead.
    readonly property var model: favApps.length > 0 ? favApps : apps
    // grid only on the resting view; searching is always the results list
    readonly property bool showGrid: !searching && settings.grid
    
    // ---- KRunner search (org.kde.milou ResultsModel) ----
    // The exact backend Plasma's launcher / KRunner / Overview use: it runs every
    // search plugin the user has enabled (Applications, System Settings, Power,
    // Locations, Places, Windows, web shortcuts, calculator, …) and streams
    // grouped, ranked matches. We bind the raw query in and render the model
    // directly; running a row calls back into KRunner so each match launches/opens
    // exactly as it would there. `count` comes off the bound ListView (the model
    // itself doesn't expose one).
    Milou.ResultsModel {
        id: krunner
        queryString: root.searching ? search.text.trim() : ""
    }
    
    // ---- keyboard selection (arrow-key navigation) ----
    // The live view is the resting grid/list (over `model`) or, while searching,
    // the KRunner results list; navigation clamps to whichever is showing and
    // resets whenever the visible set changes (new query, or grid/list toggle).
    property int currentIndex: 0
    readonly property int navCount: searching ? resultsList.count : model.length
    onQChanged: currentIndex = 0
    onShowGridChanged: currentIndex = 0
    function setSel(i) {
        const n = navCount;
        currentIndex = n === 0 ? 0 : Math.max(0, Math.min(n - 1, i));
        if (n === 0) return;
        if (searching) resultsList.positionViewAtIndex(currentIndex, ListView.Contain);
        else if (showGrid) grid.positionViewAtIndex(currentIndex, GridView.Contain);
        else list.positionViewAtIndex(currentIndex, ListView.Contain);
    }
    // up/down step one row (or one grid row); left/right step one column. In the
    // grid every arrow navigates; in a list up/down navigate, and left/right only
    // navigate when the search is empty (otherwise they move the text cursor).
    function moveVert(d) { setSel(currentIndex + d * (showGrid ? grid.cols : 1)); }
    function moveHoriz(d) { setSel(currentIndex + d); }
    function activateCurrent() {
        if (calcResult !== null) { copy(calcResult); root.launched(); return; }
        if (searching) {
            if (navCount > 0 && krunner.run(krunner.index(currentIndex, 0))) root.launched();
            return;
        }
        const n = model.length;
        if (n === 0) return;
        model[Math.max(0, Math.min(n - 1, currentIndex))].execute();
        root.launched();
    }
    
    function isFav(a) { return (settings.favorites || []).indexOf(a.id) >= 0; }
    function toggleFav(a) {
        const f = (settings.favorites || []).slice();
        const i = f.indexOf(a.id);
        if (i >= 0) f.splice(i, 1); else f.push(a.id);
        settings.favorites = f;
    }
    
    // taskbar pin state + toggle (shared settings.pinned; offered from the app menu).
    function isPinned(a) { return a ? (settings.pinned || []).indexOf(a.id) >= 0 : false; }
    function togglePin(a) {
        if (!a) return;
        const f = (settings.pinned || []).slice();
        const i = f.indexOf(a.id);
        if (i >= 0) f.splice(i, 1); else f.push(a.id);
        settings.pinned = f;
    }
    
    // resolve a KRunner search result row to one of our DesktopEntries so its
    // right-click gets the same app menu as the resting list/grid. KRunner results
    // aren't DesktopEntry objects; the Applications runner uses the entry's name, so
    // match by display name against `apps`. Non-app results (settings, calculator,
    // locations, …) don't match → no menu.
    function entryForResult(m) {
        if (!m) return null;
        const name = m.display;
        const list = apps || [];
        for (let i = 0; i < list.length; i++)
            if (list[i].name === name) return list[i];
        return null;
    }
    
    // ---- calculator: evaluate a safe arithmetic expression ----
    readonly property var calcResult: searching ? evalCalc(search.text.trim()) : null
    function evalCalc(expr) {
        let forced = false;
        let e = expr.trim();
        if (e.length > 0 && e[0] === "=") { forced = true; e = e.slice(1).trim(); }
        if (e.length === 0) return null;
        if (!/^[0-9.,+\-*/%()\s]+$/.test(e)) return null;     // digits + operators only
        if (!forced && !/[-+*/%]/.test(e)) return null;       // plain numbers don't count
        e = e.replace(/,/g, "");
        try {
            const r = Function('"use strict"; return (' + e + ');')();
            if (typeof r === "number" && isFinite(r))
                return Number.isInteger(r) ? r : parseFloat(r.toFixed(8));
        } catch (err) {}
        return null;
    }
    // group the integer part with thousands separators for *display* (12345.6 ->
    // "12,345.6"); the raw number is still what copy() puts on the clipboard, so a
    // pasted result stays a plain, re-computable value. Exponential forms (1e21)
    // and non-numbers pass through untouched.
    function fmtNum(n) {
        if (typeof n !== "number" || !isFinite(n)) return String(n);
        const s = Math.abs(n).toString();
        if (s.indexOf("e") >= 0 || s.indexOf("E") >= 0) return (n < 0 ? "-" : "") + s;
        const dot = s.indexOf(".");
        const intp = (dot < 0 ? s : s.slice(0, dot)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return (n < 0 ? "-" : "") + intp + (dot < 0 ? "" : s.slice(dot));
    }
    
    Process { id: copyProc }
    function copy(s) { copyProc.command = ["wl-copy", "--", String(s)]; copyProc.startDetached(); }
    
    Process { id: powerProc }
    function exec(cmd) { powerProc.command = cmd; powerProc.startDetached(); }
    
    // ================= search row =================
    MSym {                                       // back chevron — closes the launcher
        id: backChevron
        anchors.left: parent.left
        anchors.verticalCenter: searchBox.verticalCenter
        icon: "chevron_left"
        size: 20
        color: backChevMa.containsMouse ? root.theme.text : root.theme.faint
        MouseArea {
            id: backChevMa
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
        }
    }
    Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.left: backChevron.right
        anchors.leftMargin: 8
        anchors.right: parent.right
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
            anchors.right: gridToggle.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: TextInput.AlignVCenter
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
            clip: true
            selectByMouse: true
            selectionColor: root.theme.accentDim
            Keys.onEscapePressed: root.closeRequested()
            Keys.onReturnPressed: root.activateCurrent()
            Keys.onEnterPressed: root.activateCurrent()
            // arrow-key navigation over the list/grid (see moveVert/moveHoriz):
            // up/down always navigate; left/right navigate in the grid, or in a
            // list only when the query is empty — otherwise they move the cursor.
            Keys.onUpPressed: root.moveVert(-1)
            Keys.onDownPressed: root.moveVert(1)
            Keys.onLeftPressed: e => {
                if (!root.showGrid && root.q.length > 0) { e.accepted = false; return; }
                root.moveHoriz(-1);
            }
            Keys.onRightPressed: e => {
                if (!root.showGrid && root.q.length > 0) { e.accepted = false; return; }
                root.moveHoriz(1);
            }
    
            Text {                               // placeholder
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: search.text.length === 0
                textFormat: Text.StyledText
                text: 'Search apps  ·  <font face="' + root.theme.serif + '"><i>type a sum to calculate</i></font>'
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
                elide: Text.ElideRight
            }
        }
        Rectangle {                              // grid / list toggle
            id: gridToggle
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30
            radius: root.theme.radiusBtn
            color: root.theme.accentSoft
            MSym {
                anchors.centerIn: parent
                icon: root.settings.grid ? "view_list" : "grid_view"
                size: 19
                fill: 1
                weight: 500
                color: root.theme.accent
            }
            MouseArea {
                id: gridMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settings.grid = !root.settings.grid
            }
        }
    }
    // ================= toggle buttons (bottom-left) =================
    Row {
        id: toggleBar
    
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 12
    
        // do-not-disturb: a bell while notifications pop, a slashed bell (and the
        // accent colour, the "on" cue) while DND silences them into history only.
        MSym {
            icon: root.notifs.dnd ? "notifications_off" : "notifications"
            size: 18
            fill: root.notifs.dnd ? 1 : 0
            color: root.notifs.dnd ? root.theme.accent : (dndMa.containsMouse ? root.theme.text : root.theme.faint)
    
            MouseArea {
                id: dndMa
    
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.notifs.dnd = !root.notifs.dnd
            }
    
        }
    
        // finance privacy: an open eye normally, a closed eye (accent = "on") while
        // amounts are masked — auto-on during screen shares (see FinanceState).
        // Hidden unless the Finance feature is enabled (Settings).
        MSym {
            visible: root.fin && root.fin.enabled
            icon: root.fin && root.fin.privacy ? "visibility_off" : "visibility"
            size: 18
            fill: root.fin && root.fin.privacy ? 1 : 0
            color: root.fin && root.fin.privacy ? root.theme.accent : (finPrivMa.containsMouse ? root.theme.text : root.theme.faint)
    
            MouseArea {
                id: finPrivMa
    
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.fin) root.fin.togglePrivacy()
            }
    
        }
    
        // settings gear — opens the calendar-account manager (KDE + pill accounts)
        MSym {
            icon: "settings"
            size: 18
            fill: root.settingsOpen ? 1 : 0
            color: root.settingsOpen ? root.theme.accent : (setMa.containsMouse ? root.theme.text : root.theme.faint)
    
            MouseArea {
                id: setMa
    
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsOpen = !root.settingsOpen
            }
    
        }
    
    }
    // ================= power buttons (bottom-right) =================
    Row {
        id: powerBar
    
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 12
    
        Repeater {
            // `confirm` entries pop the full-screen confirmation first (`action` is
            // the word shown on it); lock fires immediately.
            model: [{
                "ic": "lock",
                "col": root.theme.accent,
                "action": "",
                "confirm": false,
                "cmd": ["loginctl", "lock-session"]
            }, {
                "ic": "switch_account",
                "col": root.theme.good,
                "action": "logout",
                "confirm": true,
                "cmd": ["gdbus", "call", "--session", "--dest", "org.kde.Shutdown", "--object-path", "/Shutdown", "--method", "org.kde.Shutdown.logout"]
            }, {
                "ic": "restart_alt",
                "col": "#d98a3a",
                "action": "reboot",
                "confirm": true,
                "cmd": ["gdbus", "call", "--session", "--dest", "org.kde.Shutdown", "--object-path", "/Shutdown", "--method", "org.kde.Shutdown.logoutAndReboot"]
            }, {
                "ic": "power_settings_new",
                "col": root.theme.accent,
                "action": "shutdown",
                "confirm": true,
                "cmd": ["gdbus", "call", "--session", "--dest", "org.kde.Shutdown", "--object-path", "/Shutdown", "--method", "org.kde.Shutdown.logoutAndShutdown"]
            }]
    
            delegate: MSym {
                required property var modelData
    
                icon: modelData.ic
                size: 18
                opacity: pma.containsMouse ? 1 : 0.82
                color: modelData.col
    
                MouseArea {
                    id: pma
    
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.confirm ? root.confirmPower(modelData.action, modelData.cmd) : root.exec(modelData.cmd)
                }
    
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.theme.animFast
                    }
    
                }
    
            }
    
        }
    
    }
    // ================= body =================
    Item {
        id: body
    
        anchors.top: searchBox.bottom
        anchors.topMargin: root.theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: powerBar.top
        anchors.bottomMargin: root.theme.gap
    
        // calculator result (top, when the query evaluates)
        Rectangle {
            id: calcCard
    
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? root.theme.rowHeight : 0
            visible: root.calcResult !== null
            radius: root.theme.radiusRow
            color: calcMa.containsMouse ? root.theme.rowHi : root.theme.bgElevated
            border.color: root.theme.border
            border.width: 1
    
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "= " + root.fmtNum(root.calcResult)
                color: root.theme.accent
                font.family: root.theme.serif
                font.pixelSize: root.theme.fsLarge + 3
            }
    
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
    
                MSym {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "content_copy"
                    size: 14
                    color: root.theme.faint
                }
    
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Copy"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
    
            }
    
            MouseArea {
                id: calcMa
    
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.copy(root.calcResult);
                    root.launched();
                }
            }
    
        }
    
        Item {
            id: viewHost
    
            anchors.top: calcCard.bottom
            anchors.topMargin: calcCard.visible ? root.theme.gap : 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
    
            // ---- resting list view (favourites / all apps, when grid is off) ----
            // While searching this hides and the KRunner results list below takes
            // over; the resting list is a plain DesktopEntry list (star + context).
            ListView {
                id: list
    
                anchors.fill: parent
                visible: !root.showGrid && !root.searching
                model: root.model
                clip: true
                spacing: 2
                cacheBuffer: 600
                boundsBehavior: Flickable.StopAtBounds
    
                delegate: Rectangle {
                    id: appRow
    
                    required property var modelData
                    required property int index
    
                    width: list.width
                    height: root.theme.rowHeight
                    radius: root.theme.radiusRow
                    // keyboard-selected row gets the accent tint; hover is the softer bg
                    color: appRow.index === root.currentIndex ? root.theme.accentDim : rowMa.containsMouse ? root.theme.rowHi : "transparent"
    
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: favStar.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
    
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 24
                            asynchronous: true
                            source: Quickshell.iconPath(appRow.modelData.icon, "application-x-executable")
                        }
    
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24 - 10
                            elide: Text.ElideRight
                            text: appRow.modelData.name
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
    
                    }
                    // favourite marker (filled when favourite, on hover otherwise)
    
                    MSym {
                        id: favStar
    
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.isFav(appRow.modelData) || rowMa.containsMouse
                        icon: "star"
                        size: 16
                        fill: root.isFav(appRow.modelData) ? 1 : 0
                        weight: 500
                        color: root.isFav(appRow.modelData) ? root.theme.accent : root.theme.faint
    
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleFav(appRow.modelData)
                        }
    
                    }
    
                    MouseArea {
                        id: rowMa
    
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                const p = mapToItem(root, mouse.x, mouse.y);
                                root.appMenuRequested(appRow.modelData, root.isFav(appRow.modelData), root.isPinned(appRow.modelData), p.x, p.y);
                            } else {
                                appRow.modelData.execute();
                                root.launched();
                            }
                        }
                    }
    
                }
    
            }
    
            // ---- KRunner results list (shown while searching) ----
            // A flat, category-grouped ListView bound straight to the Milou model;
            // the section header is the KRunner category ("Applications", "System
            // Settings", "Locations", …). Each row shows the match's own icon (a
            // themed name or a QIcon, both via Kirigami.Icon), its title and subtext;
            // clicking or pressing Enter runs it back through KRunner.
            ListView {
                id: resultsList
    
                anchors.fill: parent
                visible: root.searching
                model: krunner
                clip: true
                spacing: 2
                cacheBuffer: 600
                boundsBehavior: Flickable.StopAtBounds
                section.property: "category"
                section.criteria: ViewSection.FullString
    
                section.delegate: Item {
                    id: secHeader
    
                    required property string section
    
                    width: resultsList.width
                    height: 30
    
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: secHeader.section
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
    
                }
    
                delegate: Rectangle {
                    id: resRow
    
                    required property var model
                    required property int index
    
                    width: resultsList.width
                    height: root.theme.rowHeight
                    radius: root.theme.radiusRow
                    color: resRow.index === root.currentIndex ? root.theme.accentDim : resMa.containsMouse ? root.theme.rowHi : "transparent"
    
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
    
                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 24
                            implicitHeight: 24
                            source: resRow.model.decoration
                        }
    
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24 - 10
                            spacing: 1
    
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: resRow.model.display
                                color: root.theme.text
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsNormal
                            }
    
                            Text {
                                width: parent.width
                                visible: text.length > 0
                                height: visible ? implicitHeight : 0
                                elide: Text.ElideRight
                                text: resRow.model.subtext || ""
                                color: root.theme.textDim
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsSmall
                            }
    
                        }
    
                    }
    
                    MouseArea {
                        id: resMa
    
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                // only app results resolve to a DesktopEntry; others get no menu
                                const e = root.entryForResult(resRow.model);
                                if (e) {
                                    const p = mapToItem(root, mouse.x, mouse.y);
                                    root.appMenuRequested(e, root.isFav(e), root.isPinned(e), p.x, p.y);
                                }
                                return ;
                            }
                            if (krunner.run(krunner.index(resRow.index, 0)))
                                root.launched();
    
                        }
                    }
    
                }
    
            }
    
            // ---- grid view (resting view when grid mode is on) ----
            // When the grid is showing *favourites* (canReorder), tiles can be
            // dragged to reorder: the drag reorders the DelegateModel's items group
            // live (stable delegates, animated displace), mirrored into `dragOrder`,
            // and committed to settings.favorites on release. A plain click still
            // launches; right-click opens the context menu. The all-apps grid
            // (favApps empty) is not reorderable — there'd be nothing to persist.
            GridView {
                id: grid
    
                readonly property int cols: Math.max(3, Math.floor(width / 108))
                readonly property bool canReorder: root.showGrid && root.favApps.length > 0
                property var dragOrder: [] // ids, mirrored from the live drag
                property bool reordered: false // a drag actually moved something
    
                anchors.fill: parent
                visible: root.showGrid
                clip: true
                cacheBuffer: 800
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / cols)
                cellHeight: 92
    
                moveDisplaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: root.theme.animFast
                    }
    
                }
    
                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: root.theme.animFast
                    }
    
                }
    
                model: DelegateModel {
                    id: gridModel
    
                    model: root.model
    
                    delegate: MouseArea {
                        id: tile
    
                        required property var modelData
                        required property int index
                        readonly property int visualIndex: DelegateModel.itemsIndex
    
                        width: grid.cellWidth
                        height: grid.cellHeight
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: grid.canReorder ? tileBg : undefined
                        drag.axis: Drag.XAndYAxis
                        onPressed: {
                            if (grid.canReorder) {
                                grid.dragOrder = root.favApps.map((a) => {
                                    return a.id;
                                });
                                grid.reordered = false;
                            }
                        }
                        onReleased: {
                            if (grid.canReorder && grid.reordered)
                                root.settings.favorites = grid.dragOrder;
    
                        }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                const p = mapToItem(root, mouse.x, mouse.y);
                                root.appMenuRequested(tile.modelData, root.isFav(tile.modelData), root.isPinned(tile.modelData), p.x, p.y);
                            } else {
                                tile.modelData.execute();
                                root.launched();
                            }
                        }
    
                        // reorder as a tile is dragged over
                        DropArea {
                            anchors.fill: parent
                            enabled: grid.canReorder
                            onEntered: (drag) => {
                                const from = drag.source.visualIndex;
                                const to = tile.visualIndex;
                                if (from === to)
                                    return ;
    
                                gridModel.items.move(from, to);
                                const o = grid.dragOrder.slice();
                                o.splice(to, 0, o.splice(from, 1)[0]);
                                grid.dragOrder = o;
                                grid.reordered = true;
                            }
                        }
    
                        Rectangle {
                            id: tileBg
    
                            width: tile.width - 8
                            height: tile.height - 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            radius: root.theme.radiusTile
                            // keyboard-selected tile gets the accent tint; hover is softer
                            color: tile.index === root.currentIndex ? root.theme.accentDim : tile.containsMouse ? root.theme.rowHi : "transparent"
                            border.width: tile.index === root.currentIndex ? 1 : 0
                            border.color: root.theme.accent
                            z: tileBg.Drag.active ? 2 : 0
                            Drag.active: tile.drag.active
                            Drag.source: tile
                            Drag.hotSpot.x: width / 2
                            Drag.hotSpot.y: height / 2
    
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 6
    
                                IconImage {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    implicitSize: 40
                                    asynchronous: true
                                    source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                                }
    
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                    text: tile.modelData.name
                                    color: root.theme.text
                                    font.family: root.theme.family
                                    font.pixelSize: root.theme.fsSmall
                                }
    
                            }
                            // favourite marker
    
                            MSym {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 7
                                visible: root.isFav(tile.modelData) || tile.containsMouse
                                icon: "star"
                                size: 15
                                fill: root.isFav(tile.modelData) ? 1 : 0
                                weight: 500
                                color: root.isFav(tile.modelData) ? root.theme.accent : root.theme.faint
    
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleFav(tile.modelData)
                                }
    
                            }
    
                            states: State {
                                when: tileBg.Drag.active
    
                                ParentChange {
                                    target: tileBg
                                    parent: grid
                                }
    
                                AnchorChanges {
                                    target: tileBg
                                    anchors.horizontalCenter: undefined
                                    anchors.verticalCenter: undefined
                                }
    
                            }
    
                        }
    
                    }
    
                }
    
            }
    
            // empty state
            Text {
                anchors.centerIn: parent
                visible: root.apps.length === 0 || (root.searching ? (resultsList.count === 0 && root.calcResult === null) : root.model.length === 0)
                text: root.apps.length === 0 ? "Loading applications…" : root.searching ? "No results" : "No applications"
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }
    
        }
    
    }
    // ================= settings overlay (accounts + feature toggles) =================
    Item {
        id: accountsOverlay
    
        anchors.fill: parent
        visible: root.settingsOpen
        z: 100
    
        // swallow clicks/hover so nothing in the launcher body underneath reacts
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    
        SettingsMenu {
            anchors.fill: parent
            theme: root.theme
            acc: root.acc
            settings: root.settings
            onCloseRequested: root.settingsOpen = false
        }
    }
    // manage keyboard focus + refresh as the overlay toggles
    Connections {
        target: root
        function onSettingsOpenChanged() {
            if (root.settingsOpen) {
                search.focus = false;
                if (root.acc)
                    root.acc.load();
            } else {
                search.forceActiveFocus();
            }
        }
    }
}
