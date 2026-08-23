pragma ComponentBehavior: Bound
// DoneMenu.qml — the "Done" work-history page (menu 15). Two stacked chapters,
// never joined or summed: CODE (git activity, accent) then AGENDA (org closures
// + attended meetings, muted). Each chapter is a headline sentence, a row of
// additive state chips, and a ranked highlight list. Header carries the period
// selector (week … all-time). Nothing here represents absence: zero-count chips
// are omitted, deletions are shown as craft (never red), figures never animate.
// Data comes from DoneState; this file is a pure view over it.
import QtQuick

Item {
    id: root
    required property var theme
    required property var done               // DoneState
    signal closeRequested()

    // the pane sizes to its content (init clamps + animates the pill height off
    // this), so switching timeframe visibly resizes the panel.
    readonly property real contentHeight: header.height + 14 + body.implicitHeight + 6

    // ---- formatting helpers -------------------------------------------------
    // Qt rich text needs #RRGGBB — a QML colour stringifies to #AARRGGBB, which its
    // CSS parser rejects (the span then falls back to the default ink).
    function _hex(c) {
        function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s; }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }
    function _acc(s) {   // accent span (highlights a "<n> <unit>" phrase)
        // StyledText only honours <font color>, not <span style> / CSS.
        return '<font color="' + root._hex(root.theme.accent) + '">' + s + '</font>';
    }
    function _plural(n, one, many) { return n === 1 ? one : many; }
    function _fig(n, one, many) { return root._acc(n + " " + root._plural(n, one, many)); }
    function _fmtInt(n) { return Number(n || 0).toLocaleString(Qt.locale("en_US"), "f", 0); }
    function _fmtHours(h) {
        if (h <= 0) return "0h";
        if (h < 1) return Math.round(h * 60) + "m";
        return (h < 10 ? h.toFixed(1) : "" + Math.round(h)) + "h";
    }
    // one net figure per code row: +additions (green) or −deletions (muted, never red)
    function _net(add, del) {
        var n = (add || 0) - (del || 0);
        return (n >= 0 ? "+" : "−") + root._fmtInt(Math.abs(n));
    }

    // ---- headline sentences (templated, past tense, numbers lead) -----------
    // Every figure — commits, repos, branches / tasks, meetings — is accented.
    function codeHeadline() {
        var c = root.done.code;
        return root._fig(c.commits, "commit", "commits")
            + " across " + root._fig(c.projects, "repo", "repos")
            + ", " + root._fig(c.branches, "branch", "branches")
            + " " + root.done.periodPhrase + ".";
    }
    function agendaHeadline() {
        var a = root.done.agenda;
        return root._fig(a.done, "task", "tasks")
            + " reached an end state and " + root._fig(a.meetings, "meeting", "meetings")
            + " got your attention.";
    }

    function codeChips() {
        var c = root.done.code;
        return [ { label: "COMMITS", n: c.commits }, { label: "BRANCHES", n: c.branches },
                 { label: "PROJECTS", n: c.projects }, { label: "MERGES", n: c.merges },
                 { label: "PRS", n: c.prs } ].filter(function (x) { return x.n > 0; });
    }
    function agendaChips() {
        var a = root.done.agenda;
        return [ { label: "DONE", n: a.done }, { label: "MEETINGS", n: a.meetings },
                 { label: "CANCELLED", n: a.cancelled } ].filter(function (x) { return x.n > 0; });
    }

    // ---- header: back + title + period selector -----------------------------
    MenuHeader {
        id: header
        theme: root.theme
        title: "Done"
        onBack: root.closeRequested()

        Row {
            spacing: 6
            Repeater {
                model: root.done.periods
                delegate: Rectangle {
                    id: pchip
                    required property var modelData
                    readonly property bool active: root.done.period === modelData.key
                    height: 24
                    width: plabel.implicitWidth + 20
                    radius: root.theme.radiusSmall
                    color: active ? root.theme.accent
                                  : (pma.containsMouse ? root.theme.accentSoft : "transparent")
                    border.width: active ? 0 : 1
                    border.color: root.theme.border
                    Text {
                        id: plabel
                        anchors.centerIn: parent
                        text: pchip.modelData.label
                        color: pchip.active ? root.theme.bg
                             : (pma.containsMouse ? root.theme.text : root.theme.textDim)
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall - 1
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: pma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.done.setPeriod(pchip.modelData.key)
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }
    }

    // switching timeframe slides + fades the fresh figures in, in the direction of
    // travel (later period → in from the right, earlier → from the left); the chip
    // numbers count to their new value (see CountText). The pane resize is animated
    // by init (Behavior on the pill height, scoped to this pane).
    readonly property var _pkeys: root.done.periods.map(function (p) { return p.key; })
    property int _lastIdx: 0
    function _idx(k) { return root._pkeys.indexOf(k); }
    Component.onCompleted: root._lastIdx = Math.max(0, root._idx(root.done.period))
    Connections {
        target: root.done
        function onPeriodChanged() {
            var ni = Math.max(0, root._idx(root.done.period));
            slideIn.from = (ni >= root._lastIdx ? 1 : -1) * 46;
            root._lastIdx = ni;
            switchAnim.restart();
        }
    }
    ParallelAnimation {
        id: switchAnim
        NumberAnimation {
            id: slideIn
            target: body; property: "x"; from: 46; to: 0
            duration: root.theme.anim; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: body; property: "opacity"; from: 0.08; to: 1.0
            duration: root.theme.anim; easing.type: Easing.OutCubic
        }
    }

    // ---- a figure that counts to its target (chip numbers) ------------------
    component CountText: Text {
        property real target: 0
        property real _v: 0
        text: root._fmtInt(_v)
        onTargetChanged: _v = target
        Behavior on _v {
            NumberAnimation { duration: Math.round(root.theme.anim * 1.6); easing.type: Easing.OutCubic }
        }
    }

    // in-flight refresh (uncached / stale period): a barber-pole under the header
    BusyStripe {
        id: loadStripe
        anchors.top: header.bottom
        anchors.topMargin: 7
        anchors.left: parent.left
        anchors.right: parent.right
        height: 3
        theme: root.theme
        active: !!root.done.refreshing
    }

    // ---- body: stacked chapters --------------------------------------------
    Flickable {
        anchors.top: header.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: body.height
        clip: true
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: body
            width: parent.width
            spacing: 26

            ChapterView {
                width: body.width
                theme: root.theme
                accentColor: root.theme.accent
                label: "CODE"
                ready: root.done.code.ready
                configured: root.done.code.configured
                empty: root.done.code.empty
                unconfiguredText: "No project directories configured — add them in Settings › Productivity."
                emptyText: "No commits in this window."
                headlineHtml: root.codeHeadline()
                chips: root.codeChips()
                rows: root.done.code.biggest
                rowMode: "code"
            }

            ChapterView {
                width: body.width
                theme: root.theme
                accentColor: root.theme.textDim
                label: "AGENDA"
                ready: root.done.agenda.ready
                configured: root.done.agenda.configured
                empty: root.done.agenda.empty
                unconfiguredText: "No agenda source — enable Org Agenda or add a calendar account in Settings."
                emptyText: "Nothing closed or attended in this window."
                headlineHtml: root.agendaHeadline()
                chips: root.agendaChips()
                rows: root.done.agenda.items
                rowMode: "agenda"
            }
        }
    }

    // ---- one chapter: rule · headline · chips · highlight list --------------
    component ChapterView: Column {
        id: chap
        property var theme
        property color accentColor: "#ffffff"
        property string label: ""
        property bool ready: false
        property bool configured: false
        property bool empty: true
        property string unconfiguredText: ""
        property string emptyText: ""
        property string headlineHtml: ""
        property var chips: []
        property var rows: []
        property string rowMode: "code"
        readonly property bool accented: chap.rowMode === "code"
        spacing: 12

        // chapter rule: label + hairline running to the panel edge
        Item {
            width: parent.width
            height: 12
            Text {
                id: ruleLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: chap.label
                color: chap.accented ? chap.accentColor : chap.theme.textDim
                font.family: chap.theme.mono
                font.pixelSize: 10
                font.letterSpacing: 2.0
                font.capitalization: Font.AllUppercase
            }
            Rectangle {
                anchors.left: ruleLabel.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: chap.theme.divider
            }
        }

        // unconfigured / loading / empty states (never a zero)
        Text {
            visible: !chap.configured
            width: parent.width
            wrapMode: Text.WordWrap
            text: chap.unconfiguredText
            color: chap.theme.faint
            font.family: chap.theme.family
            font.italic: true
            font.pixelSize: chap.theme.fsSmall
        }
        // loading skeleton — a pulsing headline bar + placeholder cards
        Column {
            id: skel
            visible: chap.configured && !chap.ready
            width: parent.width
            spacing: 12
            property real pulse: 0.5
            SequentialAnimation on pulse {
                running: skel.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.4; to: 0.85; duration: 720; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.85; to: 0.4; duration: 720; easing.type: Easing.InOutSine }
            }
            Rectangle {
                width: parent.width * 0.66; height: 26; radius: 6
                color: chap.theme.bgElevated; opacity: skel.pulse
            }
            Row {
                width: parent.width
                spacing: 8
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        width: (skel.width - 24) / 4; height: 62; radius: 10
                        color: chap.theme.bgElevated; opacity: skel.pulse
                    }
                }
            }
        }
        Text {
            visible: chap.configured && chap.ready && chap.empty
            width: parent.width
            wrapMode: Text.WordWrap
            text: chap.emptyText
            color: chap.theme.faint
            font.family: chap.theme.family
            font.italic: true
            font.pixelSize: chap.theme.fsSmall
        }

        // headline sentence — sized to sit on a single line
        Text {
            visible: chap.configured && chap.ready && !chap.empty
            width: parent.width
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: chap.headlineHtml
            color: chap.theme.text
            font.family: chap.theme.serif
            font.pixelSize: 21
        }

        // state chips — equal-width cards filling the row, left-aligned number +
        // label, with a 2px top border (accent for CODE, neutral for AGENDA)
        Row {
            id: chipRow
            visible: chap.configured && chap.ready && !chap.empty
            width: parent.width
            spacing: 8
            property int n: Math.max(1, chap.chips.length)
            Repeater {
                model: chap.chips
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    width: (chipRow.width - (chipRow.n - 1) * 8) / chipRow.n
                    height: 62
                    // square top (the 2px border is the card colour showing above the
                    // fill), rounded bottom — a flush top edge with no corner radius
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: 10
                    bottomRightRadius: 10
                    color: chap.accented ? chap.accentColor : chap.theme.borderStrong
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 2
                        topLeftRadius: 0
                        topRightRadius: 0
                        bottomLeftRadius: 10
                        bottomRightRadius: 10
                        color: chap.theme.bgElevated
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 4
                        CountText {
                            target: chip.modelData.n
                            color: chap.theme.text
                            font.family: chap.theme.serif
                            font.pixelSize: 23
                        }
                        Text {
                            width: parent.width
                            text: chip.modelData.label
                            color: chap.theme.faint
                            font.family: chap.theme.mono
                            font.pixelSize: 10
                            font.letterSpacing: 1.3
                            font.capitalization: Font.AllUppercase
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // highlight list — biggest commits (CODE) / most-clocked (AGENDA), as a
        // two-column grid: fixed verb column, description, leader rule, then the
        // figure (net lines for CODE, clocked hours for AGENDA)
        Grid {
            id: listGrid
            visible: chap.configured && chap.ready && !chap.empty && chap.rows.length > 0
            width: parent.width
            columns: 2
            rowSpacing: 9
            columnSpacing: 34
            readonly property real cellW: (width - columnSpacing) / 2
            Repeater {
                model: chap.rows
                delegate: Item {
                    id: rowd
                    required property var modelData
                    readonly property bool isCode: chap.rowMode === "code"
                    readonly property int _net: (modelData.add || 0) - (modelData.del || 0)
                    width: listGrid.cellW
                    height: 18

                    Text {
                        id: desc
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - figure.width - 20)
                        text: rowd.isCode ? rowd.modelData.subject : rowd.modelData.text
                        color: chap.theme.text
                        font.family: chap.theme.mono
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Rectangle {                             // leader rule to the figure
                        anchors.left: desc.right
                        anchors.leftMargin: 10
                        anchors.right: figure.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: chap.theme.divider
                    }
                    Text {                                  // figure (right-aligned)
                        id: figure
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowd.isCode ? root._net(rowd.modelData.add, rowd.modelData.del)
                                          : root._fmtHours(rowd.modelData.hours || 0)
                        color: rowd.isCode ? (rowd._net >= 0 ? chap.theme.success : chap.theme.faint)
                                           : chap.theme.faint
                        font.family: chap.theme.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
