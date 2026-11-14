pragma ComponentBehavior: Bound
// UpdatesMenu.qml — the Updates page (menu 20), a two-column logbook over
// UpdateState. LEFT: every twice-daily check and every update run, newest first
// (a live run pins itself to the top). RIGHT: whatever the selected entry is —
//   · the latest check → the pending list: sources (one row per package manager,
//     with toggles), the FULL package list (scrolls, never folded) and Update;
//   · a live run → the phase rail, pacman's question as a card with answer
//     buttons (shown verbatim, default marked, destructive answers outlined, a
//     Terminal hand-off always offered), and the live log;
//   · a past run → what happened: result, restart needed, .pacnew files,
//     warnings / the error with its remedy, the log tail and its files;
//   · an older check → its counts.
// Pure view: every action is an UpdateState call; restart / source toggles /
// external opens are signals init.qml wires up.
import QtQuick

Item {
    id: root
    required property var theme
    required property var upd                 // UpdateState
    property string initialId: ""             // entry to select on open ("" = newest)
    signal closeRequested()
    signal sourceToggled(string key, bool on)
    signal restartRequested(string level)

    // ---- selection ----------------------------------------------------------
    property string selId: ""
    readonly property var entries: {
        var out = [];
        var r = root.upd.run;
        if (r && root.upd.active)
            out.push({ kind: "live", id: r.id, at: r.startedAt || 0 });
        var h = root.upd.history || [];
        for (var i = 0; i < h.length; i++)
            if (!(r && root.upd.active && h[i].id === r.id)) out.push(h[i]);
        return out;
    }
    readonly property var sel: {
        for (var i = 0; i < entries.length; i++)
            if (entries[i].id === root.selId) return entries[i];
        return entries.length ? entries[0] : null;
    }
    readonly property string latestCheckId: {
        for (var i = 0; i < entries.length; i++)
            if (entries[i].kind === "check") return entries[i].id;
        return "";
    }
    readonly property string view: !sel ? "pending"
        : sel.kind === "live" ? "live"
        : sel.kind === "update" ? "run"
        : (sel.id === latestCheckId ? "pending" : "check")

    Component.onCompleted: {
        if (root.initialId !== "") root.selId = root.initialId;
        else if (root.upd.active && root.upd.run) root.selId = root.upd.run.id;
        root._lastRun = (root.upd.run && root.upd.active) ? root.upd.run.id : "";
    }
    // a run that starts (or ends) while the page is open takes the selection
    property string _lastRun: ""
    Connections {
        target: root.upd
        function onRunChanged() {
            var id = (root.upd.run && root.upd.active) ? root.upd.run.id : "";
            if (id !== "" && id !== root._lastRun) root.selId = id;
            root._lastRun = id;
        }
    }
    onSelChanged: if (sel && sel.kind === "update" && sel.status === "failed") root.upd.markFailedSeen()

    // ---- formatting ---------------------------------------------------------
    function _d(at) { return new Date((at || 0) * 1000); }
    function _hm(at) { return Qt.formatDateTime(root._d(at), "HH:mm"); }
    function _hmMs(ms) { return ms > 0 ? Qt.formatDateTime(new Date(ms), "HH:mm") : "—"; }
    function _dayLabel(at) {
        var d = root._d(at), n = new Date();
        var a = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        var b = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime();
        var diff = Math.round((b - a) / 86400000);
        return diff === 0 ? "Today" : diff === 1 ? "Yesterday" : Qt.formatDateTime(d, "d MMM");
    }
    function _hex(c) {
        function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s; }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }
    function _acc(s) { return '<font color="' + root._hex(root.theme.accent) + '">' + s + '</font>'; }
    function _plural(n, one, many) { return n + " " + (n === 1 ? one : many); }
    function _tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function entryIcon(e) {
        if (e.kind === "live") return root.upd.asking ? "help" : "progress_activity";
        if (e.kind === "update")
            return e.status === "done" ? "check_circle" : e.status === "stopped" ? "cancel" : "error";
        return e.level === "required" ? "shield" : e.level === "recommended" ? "deployed_code_update"
             : e.total > 0 ? "radio_button_unchecked" : "check";
    }
    function entryColor(e) {
        var t = root.theme;
        if (e.kind === "live") return root.upd.asking ? t.money : t.accent;
        if (e.kind === "update")
            return e.status === "done" ? t.success : e.status === "stopped" ? t.faint : t.danger;
        return e.level === "required" ? t.accent
             : e.level === "recommended" ? root._tint(t.accent, 0.6) : t.faint;
    }
    function entryTitle(e) {
        if (e.kind === "live") {
            var r = root.upd.run;
            if (root.upd.asking) return "Needs an answer";
            if (r.status === "auth") return "Waiting for password";
            if (r.phase === "install") return "Installing " + r.pkgIndex + " / " + r.pkgTotal;
            if (r.phase === "download") return "Downloading " + r.dlDone + " / " + r.dlTotal;
            if (r.phase === "hooks") return "Running hooks";
            if (r.phase === "flatpak") return "Updating flatpak";
            return "Preparing";
        }
        if (e.kind === "update") {
            if (e.status === "done") return root._plural(e.updated, "package", "packages") + " · " + root.upd.fmtDuration(e.seconds);
            if (e.status === "stopped") return "Stopped by you";
            return e.pkgIndex > 0 ? ("Stopped at " + e.pkgIndex + " of " + e.pkgTotal) : "Did not install";
        }
        if (!e.total) return "Up to date";
        return e.total + " pending" + (e.required ? ", " + e.required + " required" : "");
    }
    function entrySub(e) {
        if (e.kind === "live") {
            var r = root.upd.run;
            if (root.upd.asking && r.prompt) return r.prompt.label.toLowerCase();
            return r.current || "";
        }
        if (e.kind === "update") {
            if (e.status === "done")
                return e.restart ? root.upd.restartPhrase(e.restart).toLowerCase() + " needed" : "no restart needed";
            if (e.status === "failed")
                return e.errorKind === "conflict" ? "file conflict" : e.errorKind === "lock" ? "database locked"
                     : e.errorKind === "mirror" ? "download failed" : e.errorKind === "disk" ? "disk full" : "see log";
            return "nothing was changed";
        }
        var parts = [];
        if (e.bytes) parts.push(root.upd.fmtBytes(e.bytes));
        if (e.restart) parts.push(root.upd.restartPhrase(e.restart).toLowerCase());
        if (!parts.length && e.total) parts.push(e.level);
        return parts.join(" · ");
    }
    readonly property var timeline: {
        var rows = [], last = "";
        for (var i = 0; i < entries.length; i++) {
            var lbl = root._dayLabel(entries[i].at);
            if (lbl !== last) { rows.push({ type: "day", label: lbl }); last = lbl; }
            rows.push({ type: "entry", e: entries[i] });
        }
        return rows;
    }

    // ---- small shared pieces ------------------------------------------------
    component Lbl: Text {
        color: root.theme.faint
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall - 1
        font.letterSpacing: root.theme.labelSpacing
        font.capitalization: Font.AllUppercase
    }
    // kind: "primary" (filled accent) · "ghost" (outlined) · "danger" (outlined accent)
    component Btn: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property string kind: "ghost"
        property string note: ""            // small caps suffix, e.g. "default"
        property bool on: true              // enabled
        signal clicked()
        readonly property bool kbFocusable: btn.on && btn.visible
        property bool kbFocused: false
        function keyClick() { if (btn.on) btn.clicked(); }
        implicitHeight: 30
        implicitWidth: brow.implicitWidth + 24
        height: implicitHeight
        width: implicitWidth
        radius: root.theme.radiusBtn
        opacity: btn.on ? 1 : 0.4
        color: btn.kind === "primary" ? (bma.containsMouse && btn.on ? Qt.lighter(root.theme.accent, 1.12) : root.theme.accent)
             : (bma.containsMouse && btn.on) || btn.kbFocused ? root.theme.rowHi : "transparent"
        border.width: btn.kind === "primary" ? 0 : 1
        border.color: btn.kind === "danger" ? root.theme.accent : root.theme.borderStrong
        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        Row {
            id: brow
            anchors.centerIn: parent
            spacing: 6
            MSym {
                anchors.verticalCenter: parent.verticalCenter
                visible: btn.icon !== ""
                icon: btn.icon; size: 16
                color: btn.kind === "primary" ? "#ffffff" : btn.kind === "danger" ? root.theme.accent : root.theme.text
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: btn.kind === "primary" ? "#ffffff" : btn.kind === "danger" ? root.theme.accent : root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal - 1
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: btn.note !== ""
                text: btn.note
                color: btn.kind === "primary" ? "#ffffff" : root.theme.textDim
                opacity: 0.8
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall - 2
                font.letterSpacing: 1
                font.capitalization: Font.AllUppercase
            }
        }
        MouseArea {
            id: bma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.on ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.on) btn.clicked()
        }
    }
    // tone: "" neutral · "a" accent · "m" money · "e" event
    component Tag: Rectangle {
        id: tag
        property string text: ""
        property string tone: ""
        readonly property color ink: tone === "a" ? root.theme.accent : tone === "m" ? root.theme.money
                                   : tone === "e" ? root.theme.event : root.theme.textDim
        implicitWidth: tagT.implicitWidth + 12
        implicitHeight: 16
        width: implicitWidth; height: implicitHeight
        radius: 6
        color: tone === "a" ? root.theme.accentSoft : "transparent"
        border.width: 1
        border.color: tone === "" ? root.theme.borderStrong : root._tint(tag.ink, 0.5)
        Text {
            id: tagT
            anchors.centerIn: parent
            text: tag.text
            color: tag.ink
            font.family: root.theme.mono
            font.pixelSize: 9
            font.letterSpacing: 1
            font.capitalization: Font.AllUppercase
        }
    }
    component Spinner: MSym {
        id: spin
        icon: "progress_activity"
        RotationAnimation on rotation { from: 0; to: 360; duration: 1100; loops: Animation.Infinite; running: spin.visible }
    }
    // a framed note: tone "m" (gold) or "a" (accent)
    component Banner: Rectangle {
        id: ban
        property string tone: "m"
        property string icon: "info"
        property string title: ""
        property string body: ""
        default property alias actions: banActs.data
        readonly property color ink: tone === "a" ? root.theme.accent : root.theme.money
        width: parent ? parent.width : 0
        implicitHeight: banCol.implicitHeight + 20
        height: implicitHeight
        radius: root.theme.radiusRow
        color: root._tint(ban.ink, 0.08)
        border.width: 1
        border.color: root._tint(ban.ink, 0.45)
        MSym { id: banIc; x: 11; y: 10; icon: ban.icon; size: 18; color: ban.ink }
        Column {
            id: banCol
            x: 38; y: 10
            width: parent.width - 49
            spacing: 3
            Text {
                width: parent.width
                text: ban.title
                color: root.theme.text
                font.family: root.theme.family; font.pixelSize: root.theme.fsNormal; font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                visible: ban.body !== ""
                text: ban.body
                color: root.theme.textDim
                font.family: root.theme.family; font.pixelSize: root.theme.fsNormal - 1
                wrapMode: Text.WordWrap
            }
            Row { id: banActs; spacing: 8; topPadding: 5 }
        }
    }
    // a dark "terminal" box of mono lines; the last line is lit
    component Term: Rectangle {
        id: term
        property var lines: []
        property string live: ""            // an unterminated line (a question) shown with a cursor
        property int maxLines: 8
        readonly property var shown: {
            var l = (term.lines || []).slice(-(term.live !== "" ? term.maxLines - 1 : term.maxLines));
            return l;
        }
        width: parent ? parent.width : 0
        implicitHeight: termCol.implicitHeight + 20
        height: implicitHeight
        radius: root.theme.radiusRow
        color: root.theme.desk
        border.width: 1
        border.color: root.theme.border
        clip: true
        Column {
            id: termCol
            x: 12; y: 10
            width: parent.width - 24
            spacing: 3
            Repeater {
                model: term.shown
                delegate: Text {
                    required property var modelData
                    required property int index
                    width: termCol.width
                    text: modelData
                    elide: Text.ElideRight
                    color: (index === term.shown.length - 1 && term.live === "") ? root.theme.text
                         : ("" + modelData).indexOf("warning:") === 0 ? root.theme.money
                         : ("" + modelData).indexOf("error:") === 0 ? root.theme.danger
                         : root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                }
            }
            Row {
                visible: term.live !== ""
                spacing: 5
                Text {
                    width: Math.min(implicitWidth, termCol.width - 14)
                    text: term.live
                    elide: Text.ElideRight
                    color: root.theme.text
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                }
                Rectangle {
                    width: 7; height: 12; color: root.theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite; running: term.live !== ""
                        PropertyAction { value: 1 } PauseAnimation { duration: 500 }
                        PropertyAction { value: 0 } PauseAnimation { duration: 500 }
                    }
                }
            }
            Text {
                visible: term.shown.length === 0 && term.live === ""
                text: "no output yet"
                color: root.theme.faint
                font.family: root.theme.mono; font.pixelSize: root.theme.fsSmall
            }
        }
    }
    // the phase rail: one segment per phase, lit as the run moves through them
    component Rail: Row {
        id: rail
        property var phases: []
        property bool asking: false
        property real frac: 0               // progress inside the active phase
        width: parent ? parent.width : 0
        spacing: 3
        Repeater {
            model: rail.phases
            delegate: Column {
                id: seg
                required property var modelData
                readonly property bool act: modelData.state === "active"
                width: (rail.width - rail.spacing * Math.max(0, rail.phases.length - 1)) / Math.max(1, rail.phases.length)
                spacing: 6
                Rectangle {
                    width: parent.width; height: 2; radius: 1
                    color: seg.modelData.state === "done" ? root.theme.success : root.theme.track
                    Rectangle {
                        visible: seg.act
                        height: parent.height; radius: 1
                        width: (rail.asking || rail.frac <= 0) ? parent.width : parent.width * Math.min(1, rail.frac)
                        color: rail.asking ? root.theme.money : root.theme.accent
                    }
                }
                Lbl {
                    text: seg.modelData.label
                    color: seg.act ? (rail.asking ? root.theme.money : root.theme.text)
                         : seg.modelData.state === "done" ? root.theme.textDim : root.theme.faint
                }
                Text {
                    width: parent.width
                    text: seg.modelData.detail || (seg.modelData.state === "done" ? "done" : "—")
                    elide: Text.ElideRight
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall - 1
                }
            }
        }
    }
    // path + Open log / Show in folder — the same on every run view
    component Files: Item {
        id: files
        property string runId: ""
        property string path: ""
        default property alias extra: filesExtra.data
        width: parent ? parent.width : 0
        implicitHeight: 30
        height: implicitHeight
        Text {
            anchors.left: parent.left
            anchors.right: filesRow.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: files.path
            elide: Text.ElideMiddle
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
        }
        Row {
            id: filesRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Row { id: filesExtra; spacing: 8 }
            Btn { label: "Open log"; icon: "edit_note"; onClicked: root.upd.openLog(files.runId) }
            Btn { label: "Show in folder"; icon: "folder_open"; onClicked: root.upd.showFolder(files.runId) }
        }
    }
    function _home(p) {
        var s = "" + (p || "");
        var m = s.match(/^\/home\/[^\/]+/);
        return m ? "~" + s.substring(m[0].length) : s;
    }

    // ---- header -------------------------------------------------------------
    MenuHeader {
        id: header
        theme: root.theme
        title: "Updates"
        onBack: root.closeRequested()

        Lbl {
            anchors.verticalCenter: parent.verticalCenter
            text: root.upd.checking ? "checking…"
                : root.upd.checkedAt > 0 ? ("checked " + root._hmMs(root.upd.checkedAt) + " · next " + root._hmMs(root.upd.nextAt))
                : "not checked yet"
        }
        Rectangle {
            id: checkChip
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.upd.checkNow(); }
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: checkLbl.implicitWidth + 20
            radius: root.theme.radiusSmall
            color: (checkMa.containsMouse || kbFocused) ? root.theme.accentSoft : "transparent"
            border.width: 1
            border.color: root.theme.border
            opacity: (root.upd.checking || root.upd.active) ? 0.4 : 1
            Lbl {
                id: checkLbl
                anchors.centerIn: parent
                text: "check now"
                color: checkMa.containsMouse ? root.theme.text : root.theme.textDim
            }
            MouseArea {
                id: checkMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!root.upd.checking && !root.upd.active) root.upd.checkNow()
            }
        }
    }
    BusyStripe {
        anchors.top: header.bottom
        anchors.topMargin: 7
        anchors.left: parent.left
        anchors.right: parent.right
        height: 3
        theme: root.theme
        active: root.upd.checking
    }

    // ---- left: the logbook --------------------------------------------------
    Flickable {
        id: tl
        anchors.top: header.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 236
        contentHeight: tlCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: tlCol
            width: tl.width
            spacing: 2
            Repeater {
                model: root.timeline
                delegate: Item {
                    id: trow
                    required property var modelData
                    readonly property bool isDay: modelData.type === "day"
                    readonly property var e: modelData.e || null
                    readonly property bool selected: !isDay && root.sel && e.id === root.sel.id
                    readonly property bool kbFocusable: !isDay
                    property bool kbFocused: false
                    function keyClick() { if (!isDay) root.selId = e.id; }
                    width: tlCol.width
                    height: isDay ? 26 : erow.implicitHeight + 14
                    Lbl {
                        visible: trow.isDay
                        anchors.left: parent.left; anchors.leftMargin: 2
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                        text: trow.isDay ? trow.modelData.label : ""
                    }
                    Rectangle {
                        visible: !trow.isDay
                        anchors.fill: parent
                        radius: root.theme.radiusRow
                        color: trow.selected ? root.theme.rowHi
                             : (ema.containsMouse || trow.kbFocused) ? root.theme.row : "transparent"
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                    Row {
                        id: erow
                        visible: !trow.isDay
                        x: 8; y: 7
                        width: parent.width - 16
                        spacing: 9
                        Item {
                            width: 18; height: 18
                            Spinner {
                                anchors.centerIn: parent
                                visible: !trow.isDay && trow.e.kind === "live" && !root.upd.asking
                                size: 16; color: root.theme.accent
                            }
                            MSym {
                                anchors.centerIn: parent
                                visible: !trow.isDay && !(trow.e.kind === "live" && !root.upd.asking)
                                icon: trow.isDay ? "" : root.entryIcon(trow.e)
                                size: 16
                                // outline glyphs: the solid knock-out variants (help / error /
                                // check_circle) smear at this size
                                fill: 0
                                color: trow.isDay ? "transparent" : root.entryColor(trow.e)
                            }
                        }
                        Column {
                            width: parent.width - 27
                            spacing: 1
                            Text {
                                text: trow.isDay ? "" : (root._hm(trow.e.at) + " · " + (trow.e.kind === "check" ? "check" : "update"))
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall - 1
                            }
                            Text {
                                width: parent.width
                                text: trow.isDay ? "" : root.entryTitle(trow.e)
                                elide: Text.ElideRight
                                color: root.theme.text
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsNormal - 1
                            }
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: trow.isDay ? "" : root.entrySub(trow.e)
                                elide: Text.ElideRight
                                color: root.theme.textDim
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsSmall
                            }
                        }
                    }
                    MouseArea {
                        id: ema
                        anchors.fill: parent
                        enabled: !trow.isDay
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selId = trow.e.id
                    }
                }
            }
            Text {
                visible: root.entries.length === 0
                width: parent.width - 8
                x: 4
                topPadding: 8
                text: root.upd.ready ? "Nothing logged yet. The first check runs shortly after the pill starts."
                                     : "Starting…"
                wrapMode: Text.WordWrap
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal - 1
            }
        }
    }
    Rectangle {
        id: divider
        anchors.top: tl.top
        anchors.bottom: parent.bottom
        anchors.left: tl.right
        anchors.leftMargin: 12
        width: 1
        color: root.theme.divider
    }

    // ---- right: the selected entry -----------------------------------------
    Loader {
        id: detail
        anchors.top: tl.top
        anchors.bottom: parent.bottom
        anchors.left: divider.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        sourceComponent: root.view === "live" ? cLive : root.view === "run" ? cRun
                       : root.view === "check" ? cCheck : cPending
    }

    // ======================= pending (latest check) =======================
    Component {
        id: cPending
        Item {
            id: pend
            readonly property var c: root.upd.counts
            readonly property var enabledKeys: {
                var k = [];
                var rows = root.upd.sourceRows || [];
                for (var i = 0; i < rows.length; i++) if (rows[i].enabled) k.push(rows[i].key);
                return k;
            }
            readonly property var rows: {
                var out = [], groups = { required: [], recommended: [], optional: [], off: [] };
                var p = root.upd.packages || [];
                for (var i = 0; i < p.length; i++) {
                    if (pend.enabledKeys.indexOf(p[i].source) < 0) groups.off.push(p[i]);
                    else groups[p[i].cls || "optional"].push(p[i]);
                }
                var defs = [["required", "Required · security", true], ["recommended", "Recommended · core system", false],
                            ["optional", "Optional", false], ["off", "Not included · other sources", false]];
                for (var g = 0; g < defs.length; g++) {
                    var list = groups[defs[g][0]];
                    if (!list.length) continue;
                    out.push({ type: "head", label: defs[g][1] + " · " + list.length, hot: defs[g][2] });
                    for (var j = 0; j < list.length; j++) out.push({ type: "pkg", p: list[j], off: defs[g][0] === "off" });
                }
                return out;
            }
            function headline() {
                if (!root.upd.ready) return "Starting…";
                if (root.upd.checkedAt <= 0) return root.upd.checking ? "Checking for the first time…" : "Not checked yet.";
                if (!c.total) return "Everything is up to date.";
                var parts = [];
                if (c.required) parts.push(root._acc(c.required + " required"));
                if (c.recommended) parts.push(c.recommended + " recommended");
                if (c.optional) parts.push(c.optional + " optional");
                return parts.join(", ") + ".";
            }
            function footLine() {
                var parts = [];
                var b = root.upd.fmtBytes(root.upd.downloadBytes);
                if (b) parts.push(b + " download");
                if (root.upd.daysBehind >= 1) parts.push(Math.round(root.upd.daysBehind) + " days behind");
                var rows = root.upd.sourceRows || [];
                var src = [];
                for (var i = 0; i < rows.length; i++) if (rows[i].enabled && rows[i].count) src.push(rows[i].key + " " + rows[i].count);
                if (src.length) parts.push(src.join(" + "));
                return parts.join(" · ");
            }

            Column {
                id: pendTop
                width: parent.width
                spacing: 10

                Banner {
                    visible: root.upd.restartLevel !== ""
                    tone: "m"; icon: "restart_alt"
                    title: root.upd.restartLevel === "reboot" ? "Reboot to finish the last update."
                         : root.upd.restartLevel === "relogin" ? "Log out and back in to finish the last update."
                         : "Restart the pill to finish the last update."
                    body: {
                        var rs = (root.upd.pendingRestart && root.upd.pendingRestart.reasons) || [];
                        var n = [];
                        for (var i = 0; i < rs.length && i < 5; i++) n.push(rs[i].name);
                        return n.length ? "Updated: " + n.join(", ") + (rs.length > 5 ? " + more" : "") : "";
                    }
                    Btn {
                        visible: root.upd.restartLevel !== "pill"
                        kind: "primary"; icon: "restart_alt"
                        label: root.upd.restartLevel === "reboot" ? "Reboot" : "Log out"
                        onClicked: root.restartRequested(root.upd.restartLevel)
                    }
                    Btn { label: "Already done"; onClicked: root.upd.ackRestart() }
                }
                Repeater {
                    model: root.upd.hold
                    delegate: Banner {
                        required property var modelData
                        tone: "m"; icon: "newspaper"
                        title: "Read before updating: " + modelData.title
                        body: "Arch news from " + Qt.formatDateTime(root._d(modelData.at), "d MMM") + ", newer than your last full upgrade."
                        Btn { label: "Read note"; icon: "open_in_new"; onClicked: Qt.openUrlExternally(modelData.link) }
                        Btn { label: "Mark all read"; onClicked: root.upd.ackNews() }
                    }
                }
                Banner {
                    visible: root.upd.error !== ""
                    tone: "a"; icon: "error"
                    title: "The last check did not finish."
                    body: root.upd.error
                    Btn { label: "Check again"; onClicked: root.upd.checkNow() }
                }

                Text {
                    width: parent.width
                    text: pend.headline()
                    textFormat: Text.StyledText
                    wrapMode: Text.WordWrap
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: root.theme.fsLarge + 8
                }

                Column {
                    width: parent.width
                    spacing: 0
                    Lbl { text: "Sources · every package manager found on this machine"; bottomPadding: 4 }
                    Repeater {
                        model: root.upd.sourceRows
                        delegate: Item {
                            id: srow
                            required property var modelData
                            width: parent.width
                            height: 30
                            opacity: modelData.available ? 1 : 0.55
                            MSym {
                                id: sIc
                                anchors.verticalCenter: parent.verticalCenter
                                icon: srow.modelData.icon; size: 16
                                color: srow.modelData.enabled ? root.theme.textDim : root.theme.faint
                            }
                            Text {
                                id: sNm
                                anchors.left: sIc.right; anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 96
                                text: srow.modelData.label
                                elide: Text.ElideRight
                                color: srow.modelData.enabled ? root.theme.text : root.theme.faint
                                font.family: root.theme.mono; font.pixelSize: root.theme.fsNormal - 1
                            }
                            Text {
                                anchors.left: sNm.right; anchors.leftMargin: 10
                                anchors.right: sCt.left; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: srow.modelData.desc
                                elide: Text.ElideRight
                                color: srow.modelData.failed ? root.theme.danger : root.theme.textDim
                                font.family: root.theme.family; font.pixelSize: root.theme.fsSmall
                            }
                            Text {
                                id: sCt
                                anchors.right: sAct.left; anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: srow.modelData.available ? srow.modelData.count : "—"
                                color: srow.modelData.enabled ? root.theme.text : root.theme.faint
                                font.family: root.theme.serif; font.pixelSize: root.theme.fsLarge + 1
                            }
                            Item {
                                id: sAct
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 76; height: 24
                                PillToggle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: srow.modelData.togglable
                                    theme: root.theme
                                    checked: srow.modelData.enabled
                                    onToggled: (v) => root.sourceToggled(srow.modelData.key, v)
                                }
                                Btn {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: srow.modelData.key === "aur" && srow.modelData.available && srow.modelData.count > 0
                                    implicitHeight: 24
                                    label: "Terminal"
                                    onClicked: root.upd.terminal("aur")
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1
                                color: root.theme.divider
                            }
                        }
                    }
                }
            }

            // the FULL list — scrolls, never folded
            Rectangle {
                anchors.top: pendTop.bottom
                anchors.topMargin: 10
                anchors.bottom: pendFoot.top
                anchors.bottomMargin: 10
                width: parent.width
                visible: pend.rows.length > 0
                radius: root.theme.radiusRow
                color: "transparent"
                border.width: 1
                border.color: root.theme.border
                ListView {
                    id: plist
                    anchors.fill: parent
                    anchors.margins: 1
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: pend.rows
                    delegate: Item {
                        id: prow
                        required property var modelData
                        readonly property bool head: modelData.type === "head"
                        readonly property var p: modelData.p || ({})
                        width: plist.width
                        height: head ? 28 : 22
                        Row {
                            visible: prow.head
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                            width: parent.width
                            spacing: 8
                            Lbl {
                                id: hl
                                text: prow.head ? prow.modelData.label : ""
                                color: (prow.head && prow.modelData.hot) ? root.theme.accent : root.theme.faint
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - hl.width - 8; height: 1
                                color: root.theme.divider
                            }
                        }
                        Text {
                            id: pn
                            visible: !prow.head
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width * 0.42)
                            text: prow.head ? "" : (prow.p.title && prow.p.source === "flatpak" ? prow.p.title : prow.p.name)
                            elide: Text.ElideRight
                            color: prow.modelData.off ? root.theme.textDim : root.theme.text
                            font.family: root.theme.mono; font.pixelSize: root.theme.fsNormal - 1
                        }
                        Rectangle {
                            visible: !prow.head
                            anchors.left: pn.right; anchors.leftMargin: 8
                            anchors.right: pv.left; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 4
                            height: 1
                            color: root.theme.divider
                        }
                        Row {
                            id: pv
                            visible: !prow.head
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: prow.head ? "" : ((prow.p.old ? prow.p.old + " → " : "") + (prow.p.new || ""))
                                color: root.theme.textDim
                                font.family: root.theme.mono; font.pixelSize: root.theme.fsSmall
                            }
                            Tag {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !prow.head && !!prow.p.advisory
                                tone: "a"
                                text: prow.p.advisory ? ("security · " + prow.p.advisory.severity) : ""
                            }
                            Tag {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !prow.head && !!prow.p.restart
                                tone: prow.p.restart === "reboot" ? "m" : prow.p.restart === "relogin" ? "e" : ""
                                text: prow.p.restart === "reboot" ? "reboot" : prow.p.restart === "relogin" ? "re-login"
                                    : prow.p.restart === "pill" ? "pill restarts" : ""
                            }
                            Tag {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !prow.head && prow.modelData.off === true
                                text: prow.p.source || ""
                            }
                        }
                    }
                }
            }

            Item {
                id: pendFoot
                anchors.bottom: parent.bottom
                width: parent.width
                height: 40
                Rectangle { width: parent.width; height: 1; color: root.theme.divider }
                Column {
                    anchors.left: parent.left
                    anchors.right: pendBtns.left
                    anchors.rightMargin: 12
                    anchors.bottom: parent.bottom
                    spacing: 1
                    Row {
                        spacing: 5
                        MSym {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pend.c.total > 0 && root.upd.restart !== ""
                            icon: "restart_alt"; size: 14; color: root.theme.money
                        }
                        Text {
                            text: !pend.c.total ? "Nothing to install."
                                : root.upd.restart === "reboot" ? "Needs a reboot afterwards"
                                : root.upd.restart === "relogin" ? "Needs a re-login afterwards"
                                : root.upd.restart === "pill" ? "The pill restarts afterwards" : "No restart needed"
                            color: root.theme.text
                            font.family: root.theme.family; font.pixelSize: root.theme.fsNormal - 1; font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        width: parent.width
                        text: pend.footLine()
                        elide: Text.ElideRight
                        color: root.theme.textDim
                        font.family: root.theme.family; font.pixelSize: root.theme.fsSmall
                    }
                }
                Row {
                    id: pendBtns
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 8
                    Btn {
                        label: "Terminal"; icon: "terminal"
                        visible: pend.c.total > 0
                        onClicked: root.upd.terminal("repo")
                    }
                    Btn {
                        kind: "primary"
                        label: "Update " + pend.c.total
                        on: pend.c.total > 0 && !root.upd.active && !root.upd.checking
                        onClicked: root.upd.start()
                    }
                }
            }
        }
    }

    // ============================ live run ============================
    Component {
        id: cLive
        Item {
            id: lv
            readonly property var r: root.upd.run || ({})
            readonly property var q: r.prompt || null
            readonly property real frac: r.phase === "install" && r.pkgTotal ? r.pkgIndex / r.pkgTotal
                                       : r.phase === "download" && r.dlTotal ? r.dlDone / r.dlTotal
                                       : r.phase === "hooks" && r.hookTotal ? r.hookIndex / r.hookTotal : 0

            Flickable {
                anchors.top: parent.top
                anchors.bottom: liveFoot.top
                anchors.bottomMargin: 10
                width: parent.width
                contentHeight: liveCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: liveCol
                    width: parent.width
                    spacing: 12

                    Rail {
                        phases: lv.r.phases || []
                        asking: root.upd.asking
                        frac: lv.frac
                    }

                    Banner {
                        visible: lv.r.status === "auth"
                        tone: "m"; icon: "key"
                        title: "Waiting for your password."
                        body: "The system password dialog is open. Nothing has been changed yet; closing it cancels the update."
                    }

                    // ---- pacman's question, as a card ----
                    Rectangle {
                        id: qc
                        visible: !!lv.q
                        readonly property bool hot: !!lv.q && lv.q.tone === "danger"
                        readonly property color ink: hot ? root.theme.accent : root.theme.money
                        width: parent.width
                        implicitHeight: qcCol.implicitHeight + 26
                        height: visible ? implicitHeight : 0
                        radius: root.theme.radiusRow
                        color: root._tint(qc.ink, hot ? 0.12 : 0.07)
                        border.width: 1
                        border.color: root._tint(qc.ink, 0.5)
                        Column {
                            id: qcCol
                            x: 14; y: 12
                            width: parent.width - 28
                            spacing: 8
                            Lbl {
                                text: lv.q ? ("Question " + lv.q.n + " · " + lv.q.label) : ""
                                color: qc.ink
                            }
                            Text {
                                width: parent.width
                                text: lv.q ? lv.q.title : ""
                                wrapMode: Text.WordWrap
                                color: root.theme.text
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge + 4
                            }
                            Rectangle {       // pacman's own words, verbatim
                                width: parent.width
                                implicitHeight: rawT.implicitHeight + 14
                                height: implicitHeight
                                radius: 8
                                color: root.theme.desk
                                border.width: 1
                                border.color: root.theme.border
                                Text {
                                    id: rawT
                                    x: 10; y: 7
                                    width: parent.width - 20
                                    text: lv.q ? lv.q.raw : ""
                                    wrapMode: Text.WrapAnywhere
                                    color: root.theme.text
                                    font.family: root.theme.mono
                                    font.pixelSize: root.theme.fsSmall
                                }
                            }
                            Grid {
                                visible: !!lv.q && lv.q.kv.length > 0
                                columns: 2
                                columnSpacing: 12
                                rowSpacing: 3
                                Repeater {
                                    model: lv.q ? [].concat.apply([], lv.q.kv) : []
                                    delegate: Text {
                                        required property var modelData
                                        required property int index
                                        readonly property bool key: index % 2 === 0
                                        width: key ? implicitWidth : Math.min(implicitWidth, qcCol.width - 110)
                                        text: modelData
                                        wrapMode: key ? Text.NoWrap : Text.WrapAnywhere
                                        color: key ? root.theme.faint
                                             : (lv.q && lv.q.checkOk === false && ("" + modelData).indexOf("not in") === 0) ? root.theme.accent
                                             : (lv.q && lv.q.checkOk === true && ("" + modelData).indexOf("in the installed") === 0) ? root.theme.success
                                             : root.theme.text
                                        font.family: root.theme.mono
                                        font.pixelSize: key ? root.theme.fsSmall - 1 : root.theme.fsSmall
                                        font.letterSpacing: key ? 1.2 : 0
                                        font.capitalization: key ? Font.AllUppercase : Font.MixedCase
                                    }
                                }
                            }
                            Text {
                                visible: !!lv.q && lv.q.options.length === 0
                                width: parent.width
                                text: "This needs typed input the pill cannot give. Continue in a terminal."
                                wrapMode: Text.WordWrap
                                color: root.theme.textDim
                                font.family: root.theme.family; font.pixelSize: root.theme.fsNormal - 1
                            }
                            Flow {
                                width: parent.width
                                spacing: 8
                                topPadding: 3
                                Repeater {
                                    model: lv.q ? lv.q.options : []
                                    delegate: Btn {
                                        required property var modelData
                                        // the safe default is the filled button; a destructive answer never is
                                        kind: modelData.danger ? "danger" : modelData.default ? "primary" : "ghost"
                                        label: modelData.label
                                        note: modelData.default ? "default" : ""
                                        onClicked: root.upd.answer(modelData.id)
                                    }
                                }
                                Btn { label: "Terminal"; icon: "terminal"; onClicked: root.upd.terminal("repo") }
                                Btn { visible: !!lv.r.canStop; label: "Stop update"; onClicked: root.upd.stop() }
                            }
                        }
                    }

                    Text {
                        visible: !lv.q && lv.r.status === "running"
                        width: parent.width
                        text: {
                            var c = lv.r.current || "";
                            if (lv.r.phase === "install") return "Installing " + c + "  (" + lv.r.pkgIndex + " of " + lv.r.pkgTotal + ")";
                            if (lv.r.phase === "download") return "Downloading " + c;
                            if (lv.r.phase === "hooks") return c;
                            if (lv.r.phase === "flatpak") return "Updating flatpak apps";
                            return c || "Preparing…";
                        }
                        elide: Text.ElideRight
                        color: root.theme.text
                        font.family: root.theme.family; font.pixelSize: root.theme.fsNormal
                    }

                    Term {
                        lines: lv.r.logTail || []
                        live: lv.q ? lv.q.raw : ""
                        maxLines: lv.q ? 4 : 13
                    }
                }
            }
            Item {
                id: liveFoot
                anchors.bottom: parent.bottom
                width: parent.width
                height: 40
                Rectangle { width: parent.width; height: 1; color: root.theme.divider }
                Files {
                    anchors.bottom: parent.bottom
                    runId: lv.r.id || ""
                    path: root._home(lv.r.dir) + "/pacman.log"
                    Btn {
                        visible: !!lv.r.canStop && !lv.q
                        label: "Stop"
                        onClicked: root.upd.stop()
                    }
                }
            }
        }
    }

    // ============================ past run ============================
    Component {
        id: cRun
        Item {
            id: past
            readonly property var e: root.sel || ({})
            readonly property bool mine: !!root.upd.pendingRestart && root.upd.pendingRestart.run === e.id
            function headline() {
                if (e.status === "done") {
                    var s = root._acc(root._plural(e.updated, "package", "packages")) + " updated in " + root.upd.fmtDuration(e.seconds) + ".";
                    if (past.mine) s += " " + root.upd.restartPhrase(root.upd.restartLevel) + " to finish.";
                    return s;
                }
                if (e.status === "stopped") return "Stopped by you. Nothing was changed.";
                return e.pkgIndex > 0 ? ("Stopped at " + root._acc(e.pkgIndex + " of " + e.pkgTotal) + ".")
                                      : "The update did not install anything.";
            }
            function remedy() {
                var k = e.errorKind;
                if (k === "lock") return "Another package manager is holding the database lock. Close it and try again. If nothing else is running, the lock is stale: remove /var/lib/pacman/db.lck from a terminal.";
                if (k === "conflict") return "Nothing was installed. A file pacman wants to write already exists and belongs to no package (or another one). Check who owns it before overwriting; the pill never forces this.";
                if (k === "mirror") return "A mirror was out of date or unreachable. Check again to refresh the package lists, then retry.";
                if (k === "disk") return "Not enough free disk space. Cleaning the package cache (paccache -r, or pacman -Sc) usually frees several GB.";
                return "pacman stopped with an error. The full output is in the log.";
            }

            Flickable {
                anchors.top: parent.top
                anchors.bottom: pastFoot.top
                anchors.bottomMargin: 10
                width: parent.width
                contentHeight: pastCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: pastCol
                    width: parent.width
                    spacing: 12

                    Text {
                        width: parent.width
                        text: past.headline()
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        color: root.theme.text
                        font.family: root.theme.serif
                        font.pixelSize: root.theme.fsLarge + 8
                    }
                    Rail { visible: (past.e.phases || []).length > 0; phases: past.e.phases || [] }

                    Banner {
                        visible: past.e.status === "failed"
                        tone: "a"; icon: "error"
                        title: past.remedy()
                        body: past.e.error || ""
                        Btn { visible: past.e.errorKind === "mirror"; label: "Check again"; onClicked: root.upd.checkNow() }
                        Btn { label: "Try again"; on: !root.upd.active; onClicked: root.upd.start() }
                        Btn { label: "Terminal"; icon: "terminal"; onClicked: root.upd.terminal("repo") }
                    }
                    Banner {
                        visible: past.mine
                        tone: "m"; icon: "restart_alt"
                        title: root.upd.restartLevel === "reboot" ? "Reboot to finish."
                             : root.upd.restartLevel === "relogin" ? "Log out and back in to finish." : "The pill needs a restart."
                        body: {
                            var rs = past.e.restartReasons || [], n = [];
                            for (var i = 0; i < rs.length && i < 6; i++) n.push(rs[i].name);
                            return n.length ? "Because of: " + n.join(", ") : "";
                        }
                        Btn {
                            visible: root.upd.restartLevel !== "pill"
                            kind: "primary"; icon: "restart_alt"
                            label: root.upd.restartLevel === "reboot" ? "Reboot" : "Log out"
                            onClicked: root.restartRequested(root.upd.restartLevel)
                        }
                        Btn { label: "Later"; onClicked: root.closeRequested() }
                    }

                    Column {
                        width: parent.width
                        visible: (past.e.pacnew || []).length > 0
                        spacing: 4
                        Lbl { text: "Config files to merge · the pill never merges for you" }
                        Repeater {
                            model: past.e.pacnew || []
                            delegate: Item {
                                id: pnrow
                                required property var modelData
                                width: parent.width
                                height: 30
                                Text {
                                    anchors.left: parent.left
                                    anchors.right: pnBtn.left; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pnrow.modelData.new
                                    elide: Text.ElideMiddle
                                    color: root.theme.money
                                    font.family: root.theme.mono; font.pixelSize: root.theme.fsSmall
                                }
                                Btn {
                                    id: pnBtn
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitHeight: 24
                                    label: "Open both"
                                    onClicked: {
                                        Qt.openUrlExternally("file://" + pnrow.modelData.file);
                                        Qt.openUrlExternally("file://" + pnrow.modelData.new);
                                    }
                                }
                            }
                        }
                    }
                    Column {
                        width: parent.width
                        visible: (past.e.warnings || []).length > 0
                        spacing: 3
                        Lbl { text: "Warnings" }
                        Repeater {
                            model: past.e.warnings || []
                            delegate: Text {
                                required property var modelData
                                width: parent.width
                                text: modelData
                                wrapMode: Text.WrapAnywhere
                                color: root.theme.textDim
                                font.family: root.theme.mono; font.pixelSize: root.theme.fsSmall
                            }
                        }
                    }
                    Lbl { text: "End of the log" }
                    Term { lines: past.e.logTail || []; maxLines: 10 }
                }
            }
            Item {
                id: pastFoot
                anchors.bottom: parent.bottom
                width: parent.width
                height: 40
                Rectangle { width: parent.width; height: 1; color: root.theme.divider }
                Files {
                    anchors.bottom: parent.bottom
                    runId: past.e.id || ""
                    path: root._home(past.e.dir) + "/pacman.log"
                }
            }
        }
    }

    // ============================ older check ============================
    Component {
        id: cCheck
        Item {
            id: chk
            readonly property var e: root.sel || ({})
            Column {
                width: parent.width
                spacing: 14
                Text {
                    width: parent.width
                    text: !chk.e.total ? "Up to date at this check."
                        : (root._acc(chk.e.total + " pending") + " at " + root._hm(chk.e.at) + ", " + root._dayLabel(chk.e.at).toLowerCase() + ".")
                    textFormat: Text.StyledText
                    wrapMode: Text.WordWrap
                    color: root.theme.text
                    font.family: root.theme.serif
                    font.pixelSize: root.theme.fsLarge + 8
                }
                Row {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: [{ l: "Required", n: chk.e.required || 0, hot: true },
                                { l: "Recommended", n: chk.e.recommended || 0, hot: false },
                                { l: "Optional", n: chk.e.optional || 0, hot: false }]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 16) / 3
                            height: 62
                            radius: root.theme.radiusSmall
                            color: root.theme.bgElevated
                            Rectangle { width: parent.width; height: 2; color: (modelData.hot && modelData.n > 0) ? root.theme.accent : root.theme.borderStrong }
                            Text {
                                x: 12; y: 9
                                text: modelData.n
                                color: root.theme.text
                                font.family: root.theme.serif; font.pixelSize: root.theme.fsLarge + 9
                            }
                            Lbl { x: 12; y: 41; text: modelData.l }
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: "This is an earlier check. Only the newest one carries the package list; select it to see what is pending now."
                    wrapMode: Text.WordWrap
                    color: root.theme.textDim
                    font.family: root.theme.family; font.pixelSize: root.theme.fsNormal - 1
                }
                Btn { label: "Show what is pending now"; onClicked: root.selId = root.latestCheckId }
            }
        }
    }
}
