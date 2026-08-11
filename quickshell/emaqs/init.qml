pragma ComponentBehavior: Bound
// ----------------------------------------------------------------------------
// init.qml — emaqs: an Emacs-workspace pill for KDE Plasma 6 / KWin / Wayland.
//
// Stages: collapsed (up-chevron tab) -> expanded (workspace bar; click the tab to
// focus it, stays open until a click elsewhere) -> menu (right-click buffer menu).
// See qs-emaqs-docs.org for the full notes.
//
// Run with:  ./run-emaqs.sh   (or: qs -p ~/.config/quickshell/emaqs/init.qml)
// ----------------------------------------------------------------------------
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    Theme { id: theme }
    EmaqsBridge { id: emacs }
    AgentBridge { id: agent }

    // ---- screen-share detection (for the DND indicator) ----
    // emaqs mirrors the pill's DND-while-sharing: when a screencast is live it shows
    // its DND bell as "on". Detected independently of the pill (no cross-process
    // coupling) via PipeWire — a live screencast publishes a "Stream/Output/Video"
    // node (cameras are "Video/Source", consumers "Stream/Input/Video", so a video
    // *output* stream uniquely means the screen itself is being captured). Note this
    // only drives the *indicator*: agent-shell turns still surface as usual while
    // sharing (they're gated by agent.dnd alone, which this does NOT set) — a
    // permission request must never be silently swallowed mid-share.
    PwObjectTracker { objects: Pipewire.nodes ? Pipewire.nodes.values : [] }
    readonly property bool screenRecording: {
        const ns = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < ns.length; i++) {
            const p = ns[i].properties;
            if (p && p["media.class"] === "Stream/Output/Video") return true;
        }
        return false;
    }

    // is the currently-focused window fullscreen? Fed by fswatch.py (a minimal
    // KWin-script watcher, emaqs's own DBus name so it never clashes with the
    // pill's winbridge). The resting tab hides while a window is fullscreen — same
    // behaviour as the pill's fsHide.
    property bool activeFullscreen: false
    Process {
        running: true
        command: ["python", Quickshell.shellPath("fswatch.py")]
        stdout: SplitParser {
            onRead: line => {
                try { root.activeFullscreen = !!JSON.parse(line).fullscreen; }
                catch (e) {}
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData

            // ---- stage state ----
            property bool focused: false     // bar expanded & held (focus mode)
            property bool menuOpen: false
            property string menuWs: ""       // workspace the buffer menu is about
            property bool confirmClose: false
            property int hoverIdx: -1        // hovered workspace label, -1 none
            // the open model/session-mode dropdown in the permission card (an
            // AgentSelect), or null. Its list is drawn by the win-level overlay
            // below, so it can escape the card's bounds (see agentDropLayer).
            property var agentSel: null

            // "focus mode": clicking the tab expands the bar, which stays open until a
            // click elsewhere (backdrop) — or a workspace switch — moves focus away.
            // No hover: the tab never expands just by passing the pointer over it.
            readonly property bool expanded: focused || menuOpen
            readonly property bool dash: expanded   // any non-collapsed stage

            // ---- agent-shell (emaqs) surfaced state ----
            // The collapsed tab morphs to (priority): permission card > "finished"
            // line > bouncing three-dots > chevron. DND hides every agent visual.
            readonly property var permNotif: (!agent.dnd && agent.permissionNotif) ? agent.permissionNotif : null
            readonly property var finNotif: (!agent.dnd && !permNotif && agent.finishedNotif) ? agent.finishedNotif : null
            readonly property bool showPermission: permNotif !== null && !expanded
            readonly property bool showFinished: finNotif !== null && !expanded
            readonly property bool showDots: !agent.dnd && agent.workingCount > 0
                                             && permNotif === null && finNotif === null && !expanded
            readonly property bool agentCard: showPermission || showFinished  // interactive collapsed content
            readonly property int agentCount: agent.dnd ? 0 : agent.workingCount

            // hide the resting tab while a fullscreen window is focused (games,
            // video…); hovering / an open menu overrides it, like the pill — and so
            // does a permission/finished card (those need attention).
            readonly property bool fsHide: root.activeFullscreen && !dash
                                           && !showPermission && !showFinished

            // A compact icon-button model / session-mode picker. Clicking it
            // registers as `win.agentSel`, so the shared overlay (below) paints its
            // option list above everything. Used both on the permission card and
            // next to each agent-shell buffer in the workspace menu. Hidden when
            // there is nothing to offer. `currentToken` highlights the active choice
            // in the list; the icon tints accent while its list is open.
            component AgentPicker: Rectangle {
                id: pk
                property var options: []          // [{token,label}]
                property string currentToken: ""
                property string glyph: ""         // Material symbol
                property int listWidth: 190       // width of the popped list
                signal picked(string token)
                readonly property bool openList: win.agentSel === pk
                readonly property string curLabel: {
                    for (var i = 0; i < options.length; i++)
                        if (options[i].token === currentToken) return options[i].label;
                    return "";
                }
                function pick(t) { pk.picked(t); win.agentSel = null; }
                visible: options.length > 0
                implicitWidth: 26; implicitHeight: 26
                radius: theme.radiusBtn
                color: (pk.openList || pma.containsMouse) ? theme.bgHover : theme.row
                border.color: pk.openList ? theme.accent : theme.border
                border.width: 1
                MSym {
                    anchors.centerIn: parent
                    icon: pk.glyph; size: 15
                    color: pk.openList ? theme.accent : theme.textDim
                }
                MouseArea {
                    id: pma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.agentSel = (win.agentSel === pk ? null : pk)
                }
                Behavior on color { ColorAnimation { duration: theme.animFast } }
            }

            function openMenu(ws) {
                win.menuWs = ws;
                win.confirmClose = false;
                emacs.loadBuffers(ws);
                win.menuOpen = true;
            }
            function closeMenu() {          // back button: return to the bar
                win.menuOpen = false;
                win.confirmClose = false;
            }
            function collapseAll() {        // an action moved focus to Emacs: fully collapse
                win.menuOpen = false;
                win.confirmClose = false;
                win.focused = false;
            }

            // lazy load: grab the workspace list the moment the bar opens; reset
            // the hover highlight when it collapses.
            onDashChanged: {
                if (win.dash)
                    emacs.loadWorkspaces();
                else
                    win.hoverIdx = -1;
            }

            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // click-through everywhere except the tab; once expanded (bar or menu)
            // the window grabs the whole screen (backdrop) so a click elsewhere
            // collapses it; while a fullscreen window is focused the tab is hidden
            // and the whole window is click-through.
            // an open in-card dropdown grabs the whole screen too, so its list
            // (drawn outside the tab region) is clickable and a click-away closes it.
            mask: (win.expanded || win.agentSel) ? fullRegion
                                                 : (win.fsHide ? emptyRegion : tabRegion)

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Region { id: tabRegion; item: pill }
            Region { id: fullRegion; item: backdrop }
            Region { id: emptyRegion }

            // a click anywhere outside the pill collapses it (focus moved away).
            MouseArea {
                id: backdrop
                anchors.fill: parent
                enabled: win.expanded
                onClicked: { win.focused = false; win.closeMenu(); }
            }

            // ---------------------------------------------------------------
            // the morphing tab / bar / menu, bottom-anchored & horizontally centred
            // ---------------------------------------------------------------
            Item {
                id: pill

                // flush with the screen's bottom edge in every stage: the tab, the
                // bar and the menu all grow *upward* only, attached to the edge.
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 0

                readonly property int collapsedW: 44
                readonly property int collapsedH: 20
                readonly property int barH: 44
                readonly property int menuW: 520
                readonly property int menuH: 420
                readonly property int permCardW: 360

                width: win.menuOpen ? menuW
                     : win.expanded ? Math.max(120, wsRow.implicitWidth + theme.pad * 2)
                     : win.showPermission ? permCardW
                     : win.showFinished ? finRow.implicitWidth + theme.pad * 2 + 24
                     : win.showDots ? 58
                     : collapsedW
                height: win.menuOpen ? menuH
                      : win.expanded ? barH
                      : win.showPermission ? permCard.cardHeight
                      : win.showFinished ? Math.max(34, finRow.implicitHeight + 14)
                      : collapsedH
                opacity: win.fsHide ? 0 : ((win.dash || win.agentCard) ? 1 : theme.idleOpacity)

                Behavior on width  { NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: theme.animFast } }

                // ---- surface: flush bottom, convex top corners, "rounded out"
                //      (concave wing) bottom corners melting into the screen edge.
                //      Borderless in every stage (tab, bar and menu). ----
                PillSurface {
                    id: surface
                    anchors.fill: parent
                    theme: theme
                    radius: win.menuOpen ? theme.radiusPanel : (win.expanded || win.agentCard) ? 14 : 9
                    wing: win.menuOpen ? 14 : (win.expanded || win.agentCard) ? 11 : 7
                    fillColor: (win.dash || win.agentCard) ? theme.bg : theme.bgTranslucent
                    strokeColor: "transparent"
                    strokeWidth: 0
                    Behavior on fillColor { ColorAnimation { duration: theme.animFast } }
                }

                // click the collapsed tab to expand (focus mode). Disabled once
                // expanded — and while an agent card shows, since that card's own
                // buttons / body-click handle interaction instead.
                MouseArea {
                    anchors.fill: parent
                    enabled: !win.expanded && !win.agentCard
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.focused = true
                }

                // ================= COLLAPSED: up-chevron tab =================
                MSym {
                    id: chevron
                    anchors.centerIn: parent
                    visible: !win.expanded && !win.menuOpen && !win.showDots
                             && !win.showPermission && !win.showFinished && opacity > 0
                    opacity: (!win.expanded && !win.menuOpen && !win.showDots
                              && !win.showPermission && !win.showFinished) ? 1 : 0
                    icon: "expand_less"
                    size: 16
                    weight: 500
                    color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.82)
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }
                }

                // ============ COLLAPSED: three dots (an agent is working) ============
                // three dots that jump up and fall in a staggered sequence; each dot's
                // pre/post pauses sum to a constant 940ms so they stay phase-locked.
                Item {
                    id: dots
                    anchors.centerIn: parent
                    width: 22; height: 12
                    visible: win.showDots && opacity > 0
                    opacity: win.showDots ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 5; height: 5; radius: 2.5
                            x: index * 8.5
                            y: 4
                            color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.85)
                            SequentialAnimation on y {
                                running: dots.visible
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 140 }
                                NumberAnimation { from: 4; to: -1; duration: 210; easing.type: Easing.OutQuad }
                                NumberAnimation { from: -1; to: 4; duration: 210; easing.type: Easing.InQuad }
                                PauseAnimation { duration: 520 - index * 140 }
                            }
                        }
                    }
                }

                // ============ COLLAPSED: "Agent finished" line ============
                // A small flourish: a check badge that pops in, the buffer name in
                // quiet mono caps, then "Agent finished!" in the accent serif display.
                Item {
                    id: finItem
                    anchors.fill: parent
                    visible: win.showFinished && opacity > 0
                    opacity: win.showFinished ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }
                    property var n: win.finNotif

                    Row {
                        id: finRow
                        anchors.centerIn: parent
                        spacing: 9

                        // active-agent count (only when more than one is running)
                        AgentCountBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            theme: theme
                            count: win.agentCount
                        }

                        // check badge — a filled ✓ in an accent halo that pops on show
                        Rectangle {
                            id: finCheck
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: theme.accentSoft
                            MSym {
                                anchors.centerIn: parent
                                icon: "task_alt"; size: 16; fill: 1; weight: 600
                                color: theme.accent
                            }
                            SequentialAnimation on scale {
                                running: finItem.visible
                                NumberAnimation { from: 0.4; to: 1.16; duration: 200; easing.type: Easing.OutBack }
                                NumberAnimation { to: 1.0; duration: 140; easing.type: Easing.OutCubic }
                            }
                        }

                        // One typographic voice (the mono small-caps label, same as the
                        // workspace bar): buffer name (quiet) │ AGENT FINISHED (accent),
                        // split by a hairline divider so it reads as one stamped tag.
                        // Clicking the phrase switches to the shell (the default action).
                        Item {
                            id: finPhrase
                            anchors.verticalCenter: parent.verticalCenter
                            width: phraseRow.width
                            height: phraseRow.height
                            Row {
                                id: phraseRow
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: finItem.n ? finItem.n.title : ""
                                    color: theme.textDim
                                    font.family: theme.mono
                                    font.pixelSize: theme.fsSmall
                                    font.letterSpacing: theme.labelSpacing
                                    font.capitalization: Font.AllUppercase
                                    // keep a long buffer name from pushing the card off-screen:
                                    // fit content, but elide past a sane cap.
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 220)
                                }
                                Rectangle {                       // hairline divider
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 1; height: 13
                                    color: theme.divider
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Agent finished"
                                    color: theme.accent
                                    font.family: theme.mono
                                    font.pixelSize: theme.fsSmall
                                    font.letterSpacing: 2
                                    font.capitalization: Font.AllUppercase
                                    font.bold: true
                                }
                                // how long the whole prompt took (when Emacs reports it)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!text
                                    text: (finItem.n && finItem.n.meta && finItem.n.meta.elapsed)
                                          ? ("· " + finItem.n.meta.elapsed) : ""
                                    color: theme.textDim
                                    font.family: theme.mono
                                    font.pixelSize: theme.fsSmall
                                    font.letterSpacing: 1
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (finItem.n) { agent.action(finItem.n.id, "default"); agent.dismiss(finItem.n.id); }
                                }
                            }
                        }

                        // dismiss (✕)
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22; radius: 11
                            theme: theme
                            icon: "close"; iconSize: 15
                            hoverBg: theme.bgHover
                            onClicked: { if (finItem.n) agent.dismiss(finItem.n.id); }
                        }
                    }
                }

                // ============ COLLAPSED: permission-request card ============
                // Same design as the pill's notification card: [count?] buffer-name +
                // X, the description of what the agent wants, then Allow / Deny. A
                // click on the card body is the default action (switch to the shell).
                Item {
                    id: permCard
                    anchors.fill: parent
                    visible: win.showPermission && opacity > 0
                    opacity: win.showPermission ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }
                    property var n: win.permNotif
                    readonly property var meta: (n && n.meta) ? n.meta : ({})
                    // the ACP tool-call kind → a human label + icon, so the card
                    // says *what* the agent is asking to do (run a command, read/edit
                    // files, send a request…), not just "permission".
                    readonly property string opKind: meta.optype ? meta.optype : ""
                    readonly property string opLabel: {
                        switch (opKind) {
                        case "execute":     return "Run command";
                        case "read":        return "Read files";
                        case "edit":        return "Edit files";
                        case "write":       return "Write file";
                        case "delete":      return "Delete";
                        case "move":        return "Move";
                        case "search":      return "Search";
                        case "fetch":       return "Send request";
                        case "think":       return "Thinking";
                        case "switch_mode": return "Switch mode";
                        default:            return "Permission";
                        }
                    }
                    readonly property string opIcon: {
                        switch (opKind) {
                        case "execute":     return "terminal";
                        case "read":        return "description";
                        case "edit":        return "edit";
                        case "write":       return "note_add";
                        case "delete":      return "delete";
                        case "move":        return "drive_file_move";
                        case "search":      return "search";
                        case "fetch":       return "cloud";
                        case "think":       return "psychology";
                        case "switch_mode": return "tune";
                        default:            return "pan_tool";
                        }
                    }
                    readonly property int cardPad: theme.pad + 4
                    readonly property int cardHeight: permCol.implicitHeight + cardPad * 2

                    MouseArea {                                // body click = switch to shell
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (permCard.n) { agent.action(permCard.n.id, "default"); agent.dismiss(permCard.n.id); }
                        }
                    }

                    Column {
                        id: permCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: permCard.cardPad
                        anchors.rightMargin: permCard.cardPad
                        anchors.topMargin: permCard.cardPad
                        spacing: 10

                        // row 1: [badge] PERMISSION eyebrow [count?]  ....  X — the same
                        // accent-badge + mono-caps tag language as the finished line, so
                        // the two cards read as a set.
                        Item {
                            width: parent.width
                            height: 24
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9
                                Rectangle {                       // accent badge (op-type icon)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24; height: 24; radius: 12
                                    color: theme.accentSoft
                                    MSym {
                                        anchors.centerIn: parent
                                        icon: permCard.opIcon; size: 14; fill: 1; weight: 600
                                        color: theme.accent
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: permCard.opLabel
                                    color: theme.accent
                                    font.family: theme.mono
                                    font.pixelSize: theme.fsSmall
                                    font.letterSpacing: 2
                                    font.capitalization: Font.AllUppercase
                                    font.bold: true
                                }
                                AgentCountBadge {                 // active-agent count (>1)
                                    anchors.verticalCenter: parent.verticalCenter
                                    theme: theme
                                    count: win.agentCount
                                }
                            }
                            IconButton {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; height: 22; radius: 11
                                theme: theme
                                icon: "close"; iconSize: 15
                                hoverBg: theme.bgHover
                                onClicked: { if (permCard.n) agent.dismiss(permCard.n.id); }
                            }
                        }

                        // row 2: the shell buffer (the title), mono caps like the bar
                        Text {
                            width: parent.width
                            text: permCard.n ? permCard.n.title : ""
                            elide: Text.ElideRight
                            color: theme.text
                            font.family: theme.mono
                            font.pixelSize: theme.fsNormal
                            font.letterSpacing: theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }

                        // row 3: what the agent wants to do (readable sans)
                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: permCard.n ? permCard.n.body : ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            color: theme.textDim
                            font.family: theme.family
                            font.pixelSize: theme.fsNormal
                            lineHeight: 1.2
                        }

                        // row 4: model + mode icon pickers (left) │ Deny / Allow (right).
                        // The pickers only appear when the agent advertises options;
                        // changing one applies immediately and leaves the dialog up
                        // (decide model/mode *then* Allow/Deny).
                        Item {
                            width: parent.width
                            height: 30
                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                AgentPicker {
                                    glyph: "neurology"; listWidth: 200
                                    options: permCard.meta.models || []
                                    currentToken: permCard.meta.model || ""
                                    onPicked: (t) => {
                                        if (permCard.n)
                                            agent.setSession(permCard.n.id, permCard.n.buffer, "model", t);
                                    }
                                }
                                AgentPicker {
                                    glyph: "tune"; listWidth: 200
                                    options: permCard.meta.modes || []
                                    currentToken: permCard.meta.mode || ""
                                    onPicked: (t) => {
                                        if (permCard.n)
                                            agent.setSession(permCard.n.id, permCard.n.buffer, "mode", t);
                                    }
                                }
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                Repeater {
                                    model: permCard.n ? permCard.n.actions : []
                                    delegate: Rectangle {
                                        id: actBtn
                                        required property var modelData
                                        required property int index
                                        readonly property bool primary: index === 0
                                        width: actLbl.implicitWidth + 30
                                        height: 30; radius: theme.radiusBtn
                                        color: primary ? (actMa.containsMouse ? theme.danger : theme.accent)
                                                       : (actMa.containsMouse ? theme.rowHi : theme.row)
                                        border.color: theme.border
                                        border.width: primary ? 0 : 1
                                        Text {
                                            id: actLbl
                                            anchors.centerIn: parent
                                            text: actBtn.modelData[1]
                                            color: actBtn.primary ? "white" : theme.text
                                            font.family: theme.mono
                                            font.pixelSize: theme.fsSmall
                                            font.letterSpacing: 1.5
                                            font.capitalization: Font.AllUppercase
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: actMa
                                            anchors.fill: parent
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (permCard.n) { agent.action(permCard.n.id, actBtn.modelData[0]); agent.dismiss(permCard.n.id); }
                                            }
                                        }
                                        Behavior on color { ColorAnimation { duration: theme.animFast } }
                                    }
                                }
                            }
                        }
                    }
                }

                // ================= EXPANDED: workspace bar ==================
                Item {
                    id: bar
                    anchors.fill: parent
                    visible: win.expanded && !win.menuOpen && opacity > 0
                    opacity: (win.expanded && !win.menuOpen) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }

                    // focus highlight — glides to the current workspace's label.
                    // `anim` is primed one tick AFTER the highlight first appears, so
                    // it *snaps* into place on expand (no slide-in from the left) and
                    // only animates when moving between labels afterwards.
                    Rectangle {
                        id: focusHi
                        property Item t: (emacs.currentIdx >= 0 && emacs.currentIdx < wsRep.count)
                                         ? wsRep.itemAt(emacs.currentIdx) : null
                        property bool anim: false
                        visible: t !== null
                        onVisibleChanged: { if (visible) Qt.callLater(() => focusHi.anim = true); else focusHi.anim = false; }
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        x: wsRow.x + (t ? t.x : 0)
                        width: t ? t.width : 0
                        radius: theme.radiusBtn
                        color: theme.accentDim
                        Behavior on x { enabled: focusHi.anim; NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }
                        Behavior on width { enabled: focusHi.anim; NumberAnimation { duration: theme.anim; easing.type: Easing.OutCubic } }
                    }

                    // hover highlight — glides to the pointed-at label (like the pill).
                    Rectangle {
                        id: hoverHi
                        property Item t: (win.hoverIdx >= 0 && win.hoverIdx < wsRep.count)
                                         ? wsRep.itemAt(win.hoverIdx) : null
                        property bool anim: false
                        visible: t !== null
                        onVisibleChanged: { if (visible) Qt.callLater(() => hoverHi.anim = true); else hoverHi.anim = false; }
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        x: wsRow.x + (t ? t.x : 0)
                        width: t ? t.width : 0
                        radius: theme.radiusBtn
                        color: theme.bgHover
                        opacity: 0.55
                        Behavior on x { enabled: hoverHi.anim; NumberAnimation { duration: theme.animFast; easing.type: Easing.OutCubic } }
                        Behavior on width { enabled: hoverHi.anim; NumberAnimation { duration: theme.animFast; easing.type: Easing.OutCubic } }
                    }

                    // per-workspace "working" pulse — a breathing accent ring behind
                    // each label whose workspace has an agent-shell currently working.
                    Repeater {
                        model: agent.dnd ? [] : agent.workingList
                        delegate: Item {
                            id: workGlow
                            required property var modelData
                            readonly property int wsIdx: emacs.names.indexOf(modelData.workspace)
                            readonly property Item t: (wsIdx >= 0 && wsIdx < wsRep.count)
                                                      ? wsRep.itemAt(wsIdx) : null
                            visible: t !== null
                            anchors.verticalCenter: parent.verticalCenter
                            height: 30
                            x: wsRow.x + (t ? t.x : 0)
                            width: t ? t.width : 0
                            Rectangle {
                                anchors.fill: parent
                                radius: theme.radiusBtn
                                color: "transparent"
                                border.color: theme.accent
                                border.width: 1.5
                                SequentialAnimation on opacity {
                                    running: workGlow.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.25; to: 0.9; duration: 700; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.9; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }

                    Row {
                        id: wsRow
                        // left-anchored (not centred) so wsRow.x is a constant `pad`;
                        // centreIn would shift x while the bar's width animates, which
                        // dragged the highlights sideways during the expand.
                        anchors.left: parent.left
                        anchors.leftMargin: theme.pad
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // leading: how many agents are working (only when >1) — the
                        // "left of the title" count for the multiple-pulse case.
                        AgentCountBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            theme: theme
                            count: win.agentCount
                            diameter: 22
                        }

                        Repeater {
                            id: wsRep
                            model: emacs.names
                            delegate: Item {
                                id: del
                                required property int index
                                required property var modelData
                                width: lbl.implicitWidth + 22
                                height: 30

                                Text {
                                    id: lbl
                                    anchors.centerIn: parent
                                    // display the human label; switch by the raw name (del.modelData)
                                    text: emacs.labelFor(del.modelData)
                                    color: (win.hoverIdx === del.index || emacs.currentIdx === del.index)
                                           ? theme.text : theme.textDim
                                    font.family: theme.mono
                                    font.pixelSize: theme.fsNormal - 2
                                    font.letterSpacing: theme.labelSpacing
                                    font.capitalization: Font.AllUppercase
                                    Behavior on color { ColorAnimation { duration: theme.animFast } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onEntered: win.hoverIdx = del.index
                                    onExited: if (win.hoverIdx === del.index) win.hoverIdx = -1
                                    onClicked: (m) => {
                                        if (m.button === Qt.RightButton) {
                                            win.openMenu(del.modelData);
                                        } else {
                                            // switching focuses the Emacs frame — focus
                                            // moved away, so collapse emaqs.
                                            emacs.switchTo(del.modelData);
                                            win.collapseAll();
                                        }
                                    }
                                }
                            }
                        }

                        // trailing: do-not-disturb — mutes every agent-shell visual
                        // (cards, three-dots, per-workspace pulse). emaqs-local: Emacs
                        // isn't told, so the in-buffer permission dialog still works.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30; height: 30; radius: theme.radiusBtn
                            color: dndMa.containsMouse ? theme.row : "transparent"
                            // "on" when DND is toggled manually OR a screencast is
                            // live (screen-share auto-DND, indicator only — agent
                            // turns still surface). Click still toggles the manual
                            // agent.dnd; while sharing the bell reads on regardless.
                            readonly property bool dndActive: agent.dnd || root.screenRecording
                            MSym {
                                anchors.centerIn: parent
                                icon: parent.dndActive ? "notifications_off" : "notifications"
                                size: 18
                                color: parent.dndActive ? theme.accent
                                     : (dndMa.containsMouse ? theme.text : theme.faint)
                            }
                            MouseArea {
                                id: dndMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: agent.dnd = !agent.dnd
                            }
                            Behavior on color { ColorAnimation { duration: theme.animFast } }
                        }
                    }

                    // fallback hint when Emacs is unreachable / has no workspaces
                    Text {
                        anchors.centerIn: parent
                        visible: wsRep.count === 0
                        text: "emacs?"
                        color: theme.faint
                        font.family: theme.mono
                        font.pixelSize: theme.fsSmall
                        font.letterSpacing: theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                }

                // ================= MENU: buffer list ========================
                Item {
                    id: menu
                    anchors.fill: parent
                    anchors.topMargin: theme.pad
                    anchors.bottomMargin: theme.pad
                    anchors.leftMargin: theme.pad + 6
                    anchors.rightMargin: theme.pad + 6
                    visible: win.menuOpen && opacity > 0
                    opacity: win.menuOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: theme.animFast } }

                    MenuHeader {
                        id: header
                        theme: theme
                        // menuWs is the raw name (used for actions); show its label
                        title: emacs.labelFor(win.menuWs)
                        onBack: win.closeMenu()

                        // trailing: magit + close (opposite the header)
                        IconButton {
                            width: 28; height: 28
                            theme: theme
                            icon: "account_tree"; iconSize: 19
                            onClicked: { emacs.magit(win.menuWs); win.collapseAll(); }
                        }
                        IconButton {
                            width: 28; height: 28
                            theme: theme
                            icon: "close"; iconSize: 19
                            hoverBg: theme.accentSoft; hoverColor: theme.danger
                            onClicked: win.confirmClose = true
                        }
                    }

                    // scrollable grouped buffer list
                    Flickable {
                        id: flick
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: header.bottom
                        anchors.topMargin: theme.gap
                        anchors.bottom: parent.bottom
                        clip: true
                        contentWidth: width
                        contentHeight: groupsCol.height
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: groupsCol
                            width: flick.width
                            spacing: theme.gap

                            Repeater {
                                model: emacs.bufferGroups
                                delegate: Column {
                                    id: grp
                                    required property var modelData
                                    width: groupsCol.width
                                    spacing: 2

                                    readonly property string groupIcon:
                                        modelData.group === "Ghostel" ? "terminal"
                                      : modelData.group === "Agent Shell" ? "smart_toy"
                                      : "description"

                                    Text {                      // group label
                                        text: grp.modelData.group
                                        color: theme.faint
                                        font.family: theme.mono
                                        font.pixelSize: theme.fsSmall
                                        font.letterSpacing: theme.labelSpacing
                                        font.capitalization: Font.AllUppercase
                                        leftPadding: 10        // align with the buffer rows below
                                        topPadding: 4
                                        bottomPadding: 2
                                    }

                                    Repeater {
                                        model: grp.modelData.items
                                        delegate: Rectangle {
                                            id: bufRow
                                            required property var modelData
                                            width: grp.width
                                            height: theme.rowHeight
                                            radius: theme.radiusRow
                                            color: bufMa.containsMouse ? theme.row : "transparent"
                                            Behavior on color { ColorAnimation { duration: theme.animFast } }

                                            // agent-shell rows carry per-buffer model/mode
                                            // session info (keyed by buffer name); other
                                            // groups have none → no pickers.
                                            readonly property var sess:
                                                (grp.modelData.group === "Agent Shell" && grp.modelData.sessions)
                                                ? (grp.modelData.sessions[bufRow.modelData] || null) : null

                                            Row {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 10
                                                anchors.right: parent.right
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 9
                                                MSym {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    icon: grp.groupIcon
                                                    size: 16
                                                    color: bufMa.containsMouse ? theme.text : theme.faint
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: bufRow.width - 40 - (bufRow.sess ? 68 : 0)
                                                    text: bufRow.modelData
                                                    elide: Text.ElideRight
                                                    color: theme.text
                                                    font.family: theme.family
                                                    font.pixelSize: theme.fsNormal
                                                }
                                            }
                                            MouseArea {
                                                id: bufMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    emacs.openBuffer(bufRow.modelData, win.menuWs);
                                                    win.collapseAll();
                                                }
                                            }
                                            // model + mode icon pickers for this shell (on
                                            // top of bufMa so they don't open the buffer).
                                            Row {
                                                visible: bufRow.sess !== null
                                                anchors.right: parent.right
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 6
                                                AgentPicker {
                                                    glyph: "neurology"; listWidth: 200
                                                    options: bufRow.sess ? (bufRow.sess.models || []) : []
                                                    currentToken: bufRow.sess ? (bufRow.sess.model || "") : ""
                                                    onPicked: (t) => emacs.setAgentSession(bufRow.modelData, "model", t)
                                                }
                                                AgentPicker {
                                                    glyph: "tune"; listWidth: 200
                                                    options: bufRow.sess ? (bufRow.sess.modes || []) : []
                                                    currentToken: bufRow.sess ? (bufRow.sess.mode || "") : ""
                                                    onPicked: (t) => emacs.setAgentSession(bufRow.modelData, "mode", t)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {                              // empty state
                                visible: emacs.bufferGroups.length === 0
                                text: "No buffers"
                                color: theme.faint
                                font.family: theme.family
                                font.pixelSize: theme.fsNormal
                                topPadding: 6
                            }
                        }
                    }

                    // ---- close-workspace confirmation, overlaying the buffer list ----
                    Rectangle {
                        anchors.fill: parent
                        visible: win.confirmClose
                        color: theme.bg
                        radius: theme.radiusRow

                        Column {
                            anchors.centerIn: parent
                            spacing: theme.gap
                            width: parent.width - theme.pad * 2

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: "Close workspace “" + emacs.labelFor(win.menuWs) + "”?"
                                color: theme.text
                                font.family: theme.serif
                                font.pixelSize: theme.fsLarge + 2
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: theme.gap

                                Rectangle {
                                    width: 120; height: 38; radius: theme.radiusBtn
                                    color: cancelMa.containsMouse ? theme.row : "transparent"
                                    border.color: theme.border; border.width: 1
                                    Text {
                                        anchors.centerIn: parent; text: "Cancel"
                                        color: theme.text; font.family: theme.family
                                        font.pixelSize: theme.fsNormal
                                    }
                                    MouseArea {
                                        id: cancelMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.confirmClose = false
                                    }
                                    Behavior on color { ColorAnimation { duration: theme.animFast } }
                                }
                                Rectangle {
                                    width: 120; height: 38; radius: theme.radiusBtn
                                    color: closeConfMa.containsMouse ? theme.danger : theme.accentSoft
                                    Text {
                                        anchors.centerIn: parent; text: "Close"
                                        color: closeConfMa.containsMouse ? "white" : theme.danger
                                        font.family: theme.family; font.pixelSize: theme.fsNormal
                                    }
                                    MouseArea {
                                        id: closeConfMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            emacs.closeWorkspace(win.menuWs);
                                            win.closeMenu();
                                        }
                                    }
                                    Behavior on color { ColorAnimation { duration: theme.animFast } }
                                }
                            }
                        }
                    }
                }
            }

            // ---- shared dropdown overlay for the permission card's AgentSelects ----
            // A win-level sibling of the pill (painted above it) so an open list can
            // escape the small card's bounds. The card sits at the screen's bottom
            // edge, so lists open *upward*. Only interactive because `mask` widens to
            // the whole screen while a select is open (see win.mask above).
            Item {
                id: agentDropLayer
                anchors.fill: parent
                z: 2000
                visible: win.agentSel !== null
                // click-away closes the open list
                MouseArea { anchors.fill: parent; onClicked: win.agentSel = null }
                Rectangle {
                    id: agentDropBox
                    readonly property var sel: win.agentSel
                    readonly property point p: sel ? sel.mapToItem(agentDropLayer, 0, 0)
                                                   : Qt.point(0, 0)
                    readonly property real selW: sel ? sel.width : 0
                    readonly property real selH: sel ? sel.height : 0
                    readonly property real upY: p.y - height - 4
                    visible: sel !== null
                    width: sel ? (sel.listWidth ? sel.listWidth : sel.width) : 0
                    height: Math.min(agentDropCol.implicitHeight + 8, 240)
                    // right-align the list to the (usually right-hand) picker, kept
                    // fully on-screen; open upward when there's room, else downward.
                    x: Math.max(6, Math.min(p.x + selW - width, agentDropLayer.width - width - 6))
                    y: upY >= 6 ? upY : (p.y + selH + 4)
                    radius: theme.radiusBtn
                    color: theme.bgElevated
                    border.color: theme.border; border.width: 1
                    clip: true
                    Column {
                        id: agentDropCol
                        width: parent.width; y: 4
                        Repeater {
                            model: agentDropBox.sel ? agentDropBox.sel.options : []
                            Rectangle {
                                required property var modelData
                                width: parent.width; height: 28
                                readonly property bool cur: agentDropBox.sel
                                                            && agentDropBox.sel.currentToken === modelData.token
                                color: oma.containsMouse ? theme.bgHover
                                                         : (cur ? theme.accentSoft : "transparent")
                                Text {
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight; text: modelData.label
                                    color: parent.cur ? theme.accent : theme.text
                                    font.family: theme.family; font.pixelSize: theme.fsSmall
                                }
                                MouseArea {
                                    id: oma; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: agentDropBox.sel.pick(modelData.token)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
