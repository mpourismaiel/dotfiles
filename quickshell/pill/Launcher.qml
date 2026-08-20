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
// expression (or one prefixed with =) shows a result row: its Copy pill copies +
// closes, while clicking the rest substitutes the number back into the field for
// chaining (Up undoes it). A ≥2-term sum also lists a per-term breakdown (each ×/÷
// group resolved before the +/− joins), with a hover tooltip. Right-click an app
// for its desktop actions and a favourite toggle. Favourites + grid mode are
// persisted by the parent (see init.qml).
//
// The resting app list is supplied by the parent (built once from
// DesktopEntries and kept alive across opens), so opening is instant.
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
// NOTE: the KRunner search backend (org.kde.milou) + its Kirigami icon renderer
// are NOT imported here. They live in LauncherSearch.qml, loaded through a Loader
// (`searchLoader` below), so that on a machine without KDE's QML modules the
// failed import takes down only that Loader — not the whole launcher/pill. When
// the backend is absent the launcher falls back to local app-name filtering.

Item {
    id: root
    required property var theme
    required property var apps        // [DesktopEntry], pre-sorted by the parent
    required property var settings    // JsonAdapter { bool grid; var favorites }
    required property var notifs      // notification state (the DND toggle drives it)
    property var fin                  // FinanceState (the privacy toggle drives it)
    // NOTE: Settings (accounts + appearance + feature toggles) moved out of the
    // launcher; it now opens from the gear on the expanded dashboard (init.qml,
    // menu 13). The launcher's bottom-left toggle row keeps only DND + privacy.
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
    function open() { search.text = ""; currentIndex = 0; calcPrevFormula = ""; calcSubstituted = ""; calcHoverTerm = null; search.forceActiveFocus(); }
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
    
    // ---- KRunner search (org.kde.milou), loaded out-of-line + graceful fallback ----
    // The rich search backend lives in LauncherSearch.qml behind `searchLoader`.
    // On KDE it loads and `searchBackend` is true — searching shows the full
    // KRunner results (Applications, System Settings, Power, Locations, web
    // shortcuts, calculator, …). Without KDE's QML modules the Loader fails to
    // instantiate its item, `searchBackend` is false, and we fall back to
    // filtering the local DesktopEntry list by name (`localResults`) so the
    // launcher still searches — just apps, not the whole KRunner plugin set.
    readonly property bool searchBackend: searchLoader.item !== null
    readonly property var localResults: (searching && !searchBackend)
        ? apps.filter(a => (a.name || "").toLowerCase().indexOf(q) >= 0)
        : []
    // number of rows the current search shows (KRunner count, or local matches)
    readonly property int resultCount: !searching ? 0
        : (searchBackend ? searchLoader.item.count : localResults.length)
    
    // ---- keyboard selection (arrow-key navigation) ----
    // The live view is the resting grid/list (over `model`) or, while searching,
    // the KRunner results list; navigation clamps to whichever is showing and
    // resets whenever the visible set changes (new query, or grid/list toggle).
    property int currentIndex: 0
    readonly property int navCount: searching ? resultCount : model.length
    onQChanged: currentIndex = 0
    onShowGridChanged: currentIndex = 0
    function setSel(i) {
        const n = navCount;
        currentIndex = n === 0 ? 0 : Math.max(0, Math.min(n - 1, i));
        if (n === 0) return;
        // while searching: the KRunner list if the backend loaded, else the
        // fallback (local) list which reuses the resting `list` view.
        if (searching && searchBackend) searchLoader.item.positionAt(currentIndex);
        else if (searching) list.positionViewAtIndex(currentIndex, ListView.Contain);
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
            if (navCount === 0) return;
            if (searchBackend) {
                if (searchLoader.item.runIndex(currentIndex)) root.launched();
            } else {
                const r = localResults;
                r[Math.max(0, Math.min(r.length - 1, currentIndex))].execute();
                root.launched();
            }
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
    // prettify a sub-expression for display: ASCII * / become × ÷, whitespace
    // collapses. Only cosmetic — never fed back to the evaluator.
    function prettyExpr(s) {
        return String(s).replace(/\*/g, " × ").replace(/\//g, " ÷ ").replace(/\s+/g, " ").trim();
    }

    // ---- calculator: per-term breakdown ----
    // Split a summable expression into its top-level additive terms so each ×/÷
    // group is resolved on its own "before" the +/− that joins them (matching how
    // people read "a*b + c*d - e"). Returns [{ op, src, value, running }] where
    // `value` carries the term's additive sign and `running` is the subtotal up to
    // and including that term; returns [] when there's nothing worth breaking down
    // (a single term) or the expression won't parse/evaluate cleanly.
    property var calcTerms: (calcResult !== null) ? breakdownCalc(search.text.trim()) : []
    function breakdownCalc(expr) {
        let e = expr.trim();
        if (e.length > 0 && e[0] === "=") e = e.slice(1).trim();
        if (e.length === 0) return [];
        if (!/^[0-9.,+\-*/%()\s]+$/.test(e)) return [];
        e = e.replace(/,/g, "");
        // walk the string, splitting on +/- that sit at paren-depth 0 and act as a
        // binary operator (i.e. follow a value: a digit, ')' , '.' or '%'); a +/-
        // in any other spot is a unary sign that belongs to the term.
        let parts = [];                       // { op, src }
        let depth = 0, start = 0, op = "+", prev = "";
        for (let i = 0; i < e.length; i++) {
            const c = e[i];
            if (c === "(") depth++;
            else if (c === ")") depth--;
            else if (depth === 0 && (c === "+" || c === "-") && /[0-9.)%]/.test(prev)) {
                parts.push({ op: op, src: e.slice(start, i).trim() });
                op = c; start = i + 1;
            }
            if (!/\s/.test(c)) prev = c;
        }
        parts.push({ op: op, src: e.slice(start).trim() });
        if (parts.length < 2) return [];      // one term — nothing to break down
        let out = [], running = 0;
        for (const p of parts) {
            if (p.src.length === 0) return []; // dangling operator → give up
            let v;
            try { v = Function('"use strict"; return (' + p.src + ');')(); }
            catch (err) { return []; }
            if (typeof v !== "number" || !isFinite(v)) return [];
            const signed = (p.op === "-") ? -v : v;
            running = parseFloat((running + signed).toFixed(8));
            out.push({ op: p.op, src: p.src, value: signed, running: running });
        }
        return out;
    }

    // ---- calculator: "use this result" chaining ----
    // Clicking the result row substitutes the number back into the search field so
    // the user can keep operating on it (15680 → 15680*1.1). We stash the formula
    // that produced it; pressing Up while the field still holds that exact result
    // restores the original formula (an undo for an accidental substitution).
    property string calcPrevFormula: ""
    property string calcSubstituted: ""
    function useResult() {
        if (calcResult === null) return;
        calcPrevFormula = search.text;
        calcSubstituted = String(calcResult);
        search.text = calcSubstituted;
        search.cursorPosition = search.text.length;
    }
    function restoreFormula() {
        if (calcPrevFormula.length === 0 || search.text !== calcSubstituted) return false;
        search.text = calcPrevFormula;
        search.cursorPosition = search.text.length;
        calcPrevFormula = "";
        calcSubstituted = "";
        return true;
    }
    // term the pointer is over in the breakdown, and its top in `body` coords, so a
    // tooltip can float free of the (clipped) breakdown list. null = nothing hovered.
    property var calcHoverTerm: null
    property real calcHoverY: 0

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
            // Up first undoes a "use result" substitution (see restoreFormula),
            // otherwise it steps up the results list.
            Keys.onUpPressed: { if (!root.restoreFormula()) root.moveVert(-1); }
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
    
        // privacy eye: an open eye normally, a closed eye (accent = "on") while
        // amounts are masked — auto-on during screen shares (see FinanceState).
        // Shown whenever the privacy state exists (always, since FinanceState is
        // instantiated regardless of the Finance feature): the toggle masks the
        // calendar and org agenda too, not just finance, so a user with Finance
        // OFF must still be able to reach it (previously it was gated behind
        // Finance being enabled, so it never appeared for them).
        MSym {
            visible: !!root.fin
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
    
        // calculator result (top, when the query evaluates). Clicking anywhere but
        // the Copy pill *substitutes* the number back into the search field so the
        // user can keep operating on it (see useResult / restoreFormula).
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

            // whole-card click first, so the Copy pill (declared after) sits on top
            MouseArea {
                id: calcMa

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.useResult()
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "= " + root.fmtNum(root.calcResult)
                color: root.theme.accent
                font.family: root.theme.serif
                font.pixelSize: root.theme.fsLarge + 3
            }

            // Copy pill — its own hit area (over calcMa) so copy stays a click away
            // even though the rest of the card now substitutes instead of copying.
            Rectangle {
                id: copyPill
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                width: copyRow.implicitWidth + 18
                radius: root.theme.radiusBtn
                color: copyMa.containsMouse ? root.theme.accentSoft : "transparent"

                Row {
                    id: copyRow
                    anchors.centerIn: parent
                    spacing: 5

                    MSym {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "content_copy"
                        size: 14
                        color: copyMa.containsMouse ? root.theme.accent : root.theme.faint
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Copy"
                        color: copyMa.containsMouse ? root.theme.accent : root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                }

                MouseArea {
                    id: copyMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.copy(root.calcResult);
                        root.launched();
                    }
                }
            }

        }

        // ---- per-term breakdown (each ×/÷ group resolved before the +/− joins) ----
        // Shown under the result whenever the sum has ≥2 additive terms. Hovering a
        // row floats a tooltip (calcTip) with the running subtotal at that point.
        Rectangle {
            id: calcBreakdown

            readonly property int rowH: 24
            readonly property int maxRows: 7

            anchors.top: calcCard.bottom
            anchors.topMargin: visible ? 6 : 0
            anchors.left: parent.left
            anchors.right: parent.right
            visible: root.calcTerms.length >= 2
            height: visible ? Math.min(root.calcTerms.length, maxRows) * rowH + 12 : 0
            radius: root.theme.radiusRow
            color: root.theme.bgElevated
            border.color: root.theme.border
            border.width: 1
            clip: true

            ListView {
                id: breakdownList
                anchors.fill: parent
                anchors.margins: 6
                model: root.calcTerms
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: root.calcTerms.length > calcBreakdown.maxRows

                delegate: Item {
                    id: termRow
                    required property var modelData
                    required property int index
                    width: breakdownList.width
                    height: calcBreakdown.rowH

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 2
                        radius: root.theme.radiusBtn
                        color: termMa.containsMouse ? root.theme.rowHi : "transparent"
                    }

                    // running index (1., 2., …) + the term as written (× ÷ prettified)
                    Text {
                        id: termExpr
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: termVal.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: (termRow.index + 1) + ".  " + root.prettyExpr(termRow.modelData.src)
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall + 1
                    }

                    // signed contribution of this term (+ 4,680 / − 7,200)
                    Text {
                        id: termVal
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: (termRow.modelData.value < 0 ? "− " : "+ ")
                              + root.fmtNum(Math.abs(termRow.modelData.value))
                        color: termRow.modelData.value < 0 ? root.theme.faint : root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall + 1
                    }

                    MouseArea {
                        id: termMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: {
                            const p = termRow.mapToItem(body, 0, 0);
                            root.calcHoverY = p.y;
                            root.calcHoverTerm = termRow.modelData;
                        }
                        onExited: if (root.calcHoverTerm === termRow.modelData) root.calcHoverTerm = null;
                    }
                }
            }
        }

        Item {
            id: viewHost

            anchors.top: calcBreakdown.bottom
            anchors.topMargin: calcCard.visible ? root.theme.gap : 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
    
            // ---- resting list view (favourites / all apps, when grid is off) ----
            // While searching *with* the KRunner backend this hides and the results
            // list (searchLoader) takes over; when the backend is absent it stays
            // visible and shows the local name-filtered fallback (see localResults).
            ListView {
                id: list
    
                anchors.fill: parent
                visible: !root.showGrid && (!root.searching || !root.searchBackend)
                model: (root.searching && !root.searchBackend) ? root.localResults : root.model
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
    
            // ---- KRunner results (shown while searching, if the backend loaded) ----
            // The results list lives in LauncherSearch.qml, pulled in through this
            // Loader so a missing org.kde.milou/kirigami module fails just here (item
            // stays null → `searchBackend` false → the local fallback list above
            // shows instead). setSource passes the theme/query bindings + a back-ref
            // at creation so the file's required properties resolve.
            Loader {
                id: searchLoader

                anchors.fill: parent
                visible: root.searching && root.searchBackend
                Component.onCompleted: setSource("LauncherSearch.qml", {
                    "theme": Qt.binding(() => root.theme),
                    "launcher": root,
                    "query": Qt.binding(() => root.searching ? search.text.trim() : "")
                })
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
                visible: root.apps.length === 0 || (root.searching ? (root.resultCount === 0 && root.calcResult === null) : root.model.length === 0)
                text: root.apps.length === 0 ? "Loading applications…" : root.searching ? "No results" : "No applications"
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }

        }

        // breakdown tooltip — floats over the list, free of its clip, at the hovered
        // row. Shows the term's exact value and the running subtotal up to it.
        Rectangle {
            id: calcTip
            visible: root.calcHoverTerm !== null
            z: 100
            anchors.right: parent.right
            anchors.rightMargin: 14
            // sit just above the hovered row, clamped into the body
            y: Math.max(0, root.calcHoverY - height - 4)
            width: tipCol.implicitWidth + 20
            height: tipCol.implicitHeight + 14
            radius: root.theme.radiusRow
            color: root.theme.rowHi
            border.color: root.theme.border
            border.width: 1

            Column {
                id: tipCol
                anchors.centerIn: parent
                spacing: 3

                Text {
                    text: root.calcHoverTerm
                          ? root.prettyExpr(root.calcHoverTerm.src) + "  =  " + root.fmtNum(root.calcHoverTerm.value)
                          : ""
                    color: root.theme.text
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                }
                Text {
                    text: root.calcHoverTerm ? "running total  " + root.fmtNum(root.calcHoverTerm.running) : ""
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                }
            }
        }

    }
}
