pragma ComponentBehavior: Bound
// HabitMenu.qml — the habit tracker (menu 19): habiq's journal rendered as a
// growing jungle. Opened from the calendar menu (plant button next to the
// wallet), the finance menu (plant button next to the calendar button) and the
// `h` keyboard jump. Layout: week legend | scrolling per-week jungle
// (JungleView) | per-habit cards for today. Header: Add Habit / Freeze /
// Unfreeze (both freeze buttons open the freeze dialog) / Today. Hovering a
// tree shows that habit-week as a tooltip (dot matrix included); clicking a
// tree or a card opens the habit dialog (log with any date, edit/delete
// history). All scores/streaks/seeds come from habiq via HabitState — this
// file only renders and posts commands.
import QtQuick
import "treegen.js" as Tg

Item {
    id: root
    required property var theme
    property var habits: null              // HabitState
    signal closeRequested()

    readonly property var rep: habits && habits.report ? habits.report : null
    readonly property var rows: rep && rep.rows ? rep.rows : []

    // breeze clock: drives tree sway + vegetation shiver everywhere
    property real windT: 0
    Timer {
        interval: 50
        running: root.visible
        repeat: true
        onTriggered: root.windT += 0.05
    }

    Component.onCompleted: if (habits) habits.reload()

    // ---- weekly jungle dataset: newest week first, one cell per habit ----
    readonly property var weeksList: {
        if (!rep) return [];
        var list = [], byKey = {};
        var totals = rep.weekTotals || [];
        for (var i = 0; i < totals.length; i++) {
            var t = totals[i];
            var e = {
                key: t.week, label: "W" + t.week.split("-W")[1], start: t.start,
                season: t.season, vegetation: t.vegetation, net: t.net, max: t.max,
                cells: []
            };
            byKey[t.week] = e;
            list.push(e);
        }
        for (var r = 0; r < rows.length; r++) {
            var row = rows[r];
            for (var w = 0; w < (row.weeks || []).length; w++) {
                var wk = row.weeks[w];
                if (byKey[wk.week])
                    byKey[wk.week].cells.push({ rowId: row.id, name: row.name, row: row, week: wk });
            }
        }
        list.reverse();
        return list;
    }

    function weekOf(row, key) {
        for (var i = 0; i < (row.weeks || []).length; i++)
            if (row.weeks[i].week === key) return row.weeks[i];
        return null;
    }
    readonly property real weekTotalNet: {
        var s = 0;
        for (var i = 0; i < rows.length; i++) {
            var wk = weekOf(rows[i], rep ? rep.week : "");
            if (wk) s += wk.net;
        }
        return s;
    }
    readonly property int growingCount: rows.length

    function niceDate(iso) {
        if (!iso) return "";
        var d = new Date(iso + "T12:00:00");
        var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        var months = ["January", "February", "March", "April", "May", "June", "July",
                      "August", "September", "October", "November", "December"];
        var n = d.getDate();
        var suf = (n % 10 === 1 && n !== 11) ? "st" : (n % 10 === 2 && n !== 12) ? "nd"
                : (n % 10 === 3 && n !== 13) ? "rd" : "th";
        return days[d.getDay()] + ", " + months[d.getMonth()] + " " + n + suf;
    }
    readonly property int dayOfWeek: rep ? ((new Date(rep.today + "T12:00:00").getDay() + 6) % 7) + 1 : 1

    // ---- dialog + tooltip state ----
    property var dialogRow: null           // habit dialog target (a report row)
    property bool freezeOpen: false
    property bool addOpen: false
    property string editHabitId: ""        // definition editor target ("" = closed)
    readonly property bool dialogUp: dialogRow !== null || freezeOpen || addOpen || editHabitId !== ""

    // an active freeze covering today flips the header button to Unfreeze
    readonly property bool frozenNow: {
        if (!habits || !habits.freezes || !rep) return false;
        for (var i = 0; i < habits.freezes.length; i++) {
            var f = habits.freezes[i];
            if (rep.today >= f.start && rep.today <= f.end) return true;
        }
        return false;
    }
    property var tipCell: null
    property real tipX: 0
    property real tipY: 0

    MenuHeader {
        id: header
        theme: root.theme
        title: "Habit Tracker"
        onBack: root.closeRequested()

        Rectangle {                        // + Add Habit
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.addOpen = true; }
            width: addRow.implicitWidth + 20
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (addMa.containsMouse || kbFocused) ? root.theme.rowHi : root.theme.row
            Row {
                id: addRow
                anchors.centerIn: parent
                spacing: 5
                MSym {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "add"
                    size: 13
                    color: root.theme.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add habit"
                    color: root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
            }
            MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addOpen = true }
        }
        Rectangle {                        // Freeze ⇄ Unfreeze — one button, label
                                           // tracks whether a freeze covers today;
                                           // either way it opens the freeze dialog
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.freezeOpen = true; }
            width: frRow.implicitWidth + 20
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (frMa.containsMouse || kbFocused) ? root.theme.rowHi : root.theme.row
            Row {
                id: frRow
                anchors.centerIn: parent
                spacing: 5
                MSym {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "ac_unit"
                    size: 13
                    color: root.frozenNow ? "#dfe6ec" : root.theme.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.frozenNow ? "Unfreeze" : "Freeze"
                    color: root.frozenNow ? "#dfe6ec" : root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
            }
            MouseArea { id: frMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.freezeOpen = true }
        }
        Rectangle {                        // Today — scroll the jungle to now
            id: todayBtn
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { jungle.scrollToWeek(0); }
            width: todayTxt.implicitWidth + 20
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (todayMa.containsMouse || todayBtn.kbFocused) ? root.theme.accent : root.theme.accentSoft
            Text {
                id: todayTxt
                anchors.centerIn: parent
                text: "Today"
                color: (todayMa.containsMouse || todayBtn.kbFocused) ? "#ffffff" : root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            MouseArea { id: todayMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: jungle.scrollToWeek(0) }
        }
    }

    // ---- empty / error state (no journal yet) ----
    Column {
        visible: root.rep === null || (root.rows.length === 0)
        anchors.centerIn: parent
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.habits && root.habits.error ? "habiq: " + root.habits.error : "No habits yet"
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
            width: 420
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: initTxt.implicitWidth + 24
            height: 28
            radius: root.theme.radiusBtn
            color: initMa.containsMouse ? root.theme.accent : root.theme.accentSoft
            Text {
                id: initTxt
                anchors.centerIn: parent
                text: "Create starter journal"
                color: initMa.containsMouse ? "#ffffff" : root.theme.accent
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.capitalization: Font.AllUppercase
                font.letterSpacing: root.theme.labelSpacing
            }
            MouseArea { id: initMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.habits.initJournal() }
        }
    }

    // ---- body: legend | jungle | habit cards ----
    Item {
        anchors.top: header.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.rows.length > 0

        // week legend — click to scroll; the in-view week grows + brightens
        ListView {
            id: legend
            width: 56
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            clip: true
            model: root.weeksList
            currentIndex: Math.max(0, jungle.focusWeek)
            highlightFollowsCurrentItem: true
            delegate: Item {
                id: legRow
                required property var modelData
                required property int index
                readonly property bool active: index === Math.max(0, jungle.focusWeek)
                width: legend.width
                height: 26
                Rectangle {
                    id: legBar
                    width: 3
                    height: legRow.active ? 16 : 10
                    radius: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: legRow.active ? root.theme.accent : root.theme.track
                    Behavior on height { NumberAnimation { duration: root.theme.animFast } }
                }
                Text {
                    anchors.left: legBar.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: legRow.modelData.label
                    color: legRow.active ? root.theme.text : root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: legRow.active ? root.theme.fsNormal : root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: jungle.scrollToWeek(legRow.index)
                }
            }
        }

        // the jungle itself
        JungleView {
            id: jungle
            theme: root.theme
            anchors.left: legend.right
            anchors.leftMargin: 4
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width - legend.width - cards.width - 24
            weeksList: root.weeksList
            windT: root.windT
            onCellHovered: (wi, cell, sx, sy) => {
                root.tipCell = cell;
                var p = jungle.mapToItem(root, sx, sy);
                root.tipX = p.x;
                root.tipY = p.y;
            }
            onHoverEnded: root.tipCell = null
            onCellClicked: (cell) => { root.openHabit(cell.row); }
        }
        // lower fade — focus stays on the current week up top
        Rectangle {
            anchors.left: jungle.left
            anchors.right: jungle.right
            anchors.bottom: jungle.bottom
            height: 110
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: root.theme.bg }
            }
        }

        // ---- right: per-habit cards for the current week ----
        Column {
            id: cards
            width: 336
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: 8

            Text {
                text: root.niceDate(root.rep ? root.rep.today : "")
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: 21
            }
            Text {
                text: (root.rep ? root.rep.week : "") + " · day " + root.dayOfWeek + " of 7 · "
                      + root.growingCount + " habits growing"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
            }
            Item {
                width: parent.width
                height: 18
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "growing now"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: root.theme.labelSpacing
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.weekTotalNet >= 0 ? "+" : "") + Math.round(root.weekTotalNet) + " this week"
                    color: root.theme.good
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                }
            }

            ListView {
                id: cardList
                width: parent.width
                height: cards.height - y
                clip: true
                spacing: 8
                model: root.rows
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property var wk: root.weekOf(modelData, root.rep ? root.rep.week : "")
                    readonly property var today: {
                        if (!wk) return null;
                        for (var i = 0; i < wk.days.length; i++)
                            if (wk.days[i].date === root.rep.today) return wk.days[i];
                        return null;
                    }
                    width: cardList.width
                    height: 74
                    radius: root.theme.radiusCard
                    color: cardMa.containsMouse ? root.theme.rowHi : root.theme.row
                    border.width: 1
                    border.color: root.theme.border

                    // mini current-week tree
                    Canvas {
                        id: mini
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 60
                        renderStrategy: Canvas.Cooperative
                        property real wt: root.windT
                        onWtChanged: requestPaint()
                        // same per-week species draft the jungle runs, so the
                        // card mini is the same tree; geometry cached outside
                        // the paint loop (breeze repaints shouldn't regrow it)
                        readonly property var treeGeo: {
                            if (!card.wk) return null;
                            var seeds = [], idx = -1;
                            for (var r = 0; r < root.rows.length; r++) {
                                var wkr = root.weekOf(root.rows[r], root.rep ? root.rep.week : "");
                                if (!wkr) continue;
                                seeds.push(wkr.seed);
                                if (root.rows[r].id === card.modelData.id) idx = seeds.length - 1;
                            }
                            var sp = idx >= 0 ? Tg.assignSpecies(seeds)[idx] : undefined;
                            return Tg.build(card.wk.seed, card.wk.stage, sp);
                        }
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.reset();
                            if (!card.wk || !mini.treeGeo) return;
                            var geo = mini.treeGeo;
                            var targetH = 14 + (card.wk.stage - 1) * 12 + card.wk.sizeRatio * 8;
                            Tg.render(ctx, geo, {
                                x: width / 2, y: height - 6,
                                scale: targetH / geo.h, targetH: targetH,
                                windT: wt, phase: (card.wk.seed % 628) / 100,
                                leaf: Tg.leafBase(card.wk.band, card.wk.season),
                                dead: card.wk.band === "dead",
                                snowFrac: card.wk.band === "frozen" ? 1
                                        : Math.min(1, (card.wk.frozenDays || 0) / 7)
                            });
                        }
                    }

                    Column {
                        anchors.left: mini.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Item {
                            width: parent.width
                            height: 20
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.name
                                color: root.theme.text
                                font.family: root.theme.serif
                                font.pixelSize: root.theme.fsLarge
                                elide: Text.ElideRight
                                width: parent.width - streakTxt.width - 8
                            }
                            Text {
                                id: streakTxt
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.noStreak ? "no streak" : card.modelData.streak + "d"
                                color: card.modelData.noStreak ? root.theme.faint : root.theme.money
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                            }
                        }
                        Item {
                            width: parent.width
                            height: 14
                            HabitDots {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                theme: root.theme
                                days: card.wk ? card.wk.days : []
                                season: card.wk ? card.wk.season : "summer"
                                cell: 11
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.today && card.today.value ? card.today.value
                                    : card.today ? card.today.state : ""
                                color: card.today && card.today.state === "done" ? root.theme.text : root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                        }
                        Item {
                            width: parent.width
                            height: 12
                            Rectangle {                     // growth bar (tree size)
                                id: bar
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - grownTxt.width - 10
                                height: 3
                                radius: 1.5
                                color: root.theme.track
                                Rectangle {
                                    width: parent.width * (card.wk ? card.wk.sizeRatio : 0)
                                    height: parent.height
                                    radius: parent.radius
                                    color: card.wk && (card.wk.season === "fall" || card.wk.season === "winter")
                                           ? "#d78f3c" : "#74b06a"
                                }
                            }
                            Text {
                                id: grownTxt
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: (card.wk ? Math.round(card.wk.sizeRatio * 100) : 0) + "% · "
                                      + (card.wk ? (card.wk.net >= 0 ? "+" : "") + (Math.round(card.wk.net * 10) / 10) : "0")
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                        }
                    }
                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openHabit(card.modelData)
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }
    }

    function openHabit(row) {
        root.dialogRow = row;
        if (root.habits && row && row.members && row.members.length > 0)
            root.habits.loadHistory(row.members[0]);
    }
    function scrollToWeek(i) {              // legend/Today/harness entry point
        jungle.scrollToWeek(i);
    }

    // ---- tree tooltip: the hovered habit-week as a card ----
    Rectangle {
        visible: root.tipCell !== null && !root.dialogUp
        x: Math.min(root.tipX + 14, root.width - width - 8)
        y: Math.max(4, Math.min(root.tipY - height - 10, root.height - height - 8))
        width: tipCol.implicitWidth + 24
        height: tipCol.implicitHeight + 18
        radius: root.theme.radiusCard
        color: root.theme.bgElevated
        border.width: 1
        border.color: root.theme.borderStrong
        Column {
            id: tipCol
            x: 12
            y: 9
            spacing: 4
            Text {
                text: root.tipCell ? root.tipCell.name : ""
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: root.theme.fsLarge
            }
            Text {
                text: root.tipCell ? root.tipCell.week.week + " · " + root.tipCell.week.season
                      + (root.tipCell.week.frozenDays > 0 ? " · " + root.tipCell.week.frozenDays + " frozen" : "") : ""
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
            }
            HabitDots {
                theme: root.theme
                days: root.tipCell ? root.tipCell.week.days : []
                season: root.tipCell ? root.tipCell.week.season : "summer"
            }
            Text {
                text: root.tipCell ? Math.round(root.tipCell.week.sizeRatio * 100) + "% grown · "
                      + (root.tipCell.week.net >= 0 ? "+" : "") + (Math.round(root.tipCell.week.net * 10) / 10)
                      + " of " + Math.round(root.tipCell.week.maxFull) + " · " + root.tipCell.week.band : ""
                color: root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
            }
        }
    }

    // ---- dialogs (in-pill overlays) ----
    Loader {
        anchors.fill: parent
        active: root.dialogRow !== null
        sourceComponent: HabitDialog {
            theme: root.theme
            habits: root.habits
            row: root.dialogRow
            today: root.rep ? root.rep.today : ""
            onDismissed: root.dialogRow = null
            onEditHabitRequested: (id) => {
                root.dialogRow = null;
                root.editHabitId = id;
            }
        }
    }
    Loader {
        anchors.fill: parent
        active: root.freezeOpen
        sourceComponent: FreezeDialog {
            theme: root.theme
            habits: root.habits
            today: root.rep ? root.rep.today : ""
            onDismissed: root.freezeOpen = false
        }
    }
    Loader {
        anchors.fill: parent
        active: root.addOpen || root.editHabitId !== ""
        sourceComponent: AddHabitDialog {
            theme: root.theme
            habits: root.habits
            editId: root.editHabitId
            onDismissed: {
                root.addOpen = false;
                root.editHabitId = "";
            }
        }
    }
}
