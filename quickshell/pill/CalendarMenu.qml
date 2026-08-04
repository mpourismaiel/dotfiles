pragma ComponentBehavior: Bound
// CalendarMenu.qml — month calendar pane (win.menu === 6), opened from the
// dashboard date/time. 7 rows (weekday headers + 6 weeks) with ISO week numbers
// and adjacent-month fill days; Gregorian primary + Shamsi (Jalaali) subtext, a
// header toggle swaps which drives the grid. Today selected on open. Two detached
// roving squares (faded-gray hover + accent-soft selection) slide between cells.
// Right panel: the selected day in both calendars + its Org agenda (from the Emacs
// daemon via OrgAgenda), with agenda dots on days and a + button to open the agenda.
import QtQuick

Item {
    id: root
    required property var theme
    property var org                          // OrgAgenda state (may be null)
    property var fin                          // FinanceState (may be null)
    property var cal                          // CalendarEvents state (may be null)
    signal closeRequested()
    signal financeRequested()                 // header wallet button → finance menu

    // ---- view state ----
    property string primary: "greg"           // "greg" | "shamsi" — which calendar drives the grid
    property int gY: 2026                      // Gregorian view year / month (1-12)
    property int gM: 1
    property int jY: 1405                      // Jalaali view year / month (1-12)
    property int jM: 1
    property string selKey: ""                 // selected day, "YYYY-MM-DD" (Gregorian)
    property string todayKey: ""
    property int hoverIdx: -1                   // hovered cell (0..41) or -1
    property double nowMs: Date.now()           // wall-clock for the imminent-event banner (ticked below)

    // ---- geometry ----
    readonly property int detailW: 280
    readonly property int headerH: 26          // menu header row
    readonly property int gap: root.theme.gap
    readonly property int leftW: root.width - detailW - gap
    readonly property int gridTop: headerH + gap
    readonly property int gridH: root.height - gridTop
    readonly property int weekNumW: 30
    readonly property int wdHeadH: 24
    readonly property real cellW: (leftW - weekNumW) / 7
    readonly property real cellH: (gridH - wdHeadH) / 6
    readonly property int cellInset: 4

    // ---- calendar labels ----
    readonly property var gMonths: ["January","February","March","April","May","June","July","August","September","October","November","December"]
    readonly property var gWeekdays: ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    readonly property var jMonths: ["Farvardin","Ordibehesht","Khordad","Tir","Mordad","Shahrivar","Mehr","Aban","Azar","Dey","Bahman","Esfand"]
    readonly property var jWeekdays: ["Yekshanbeh","Doshanbeh","Seshanbeh","Chaharshanbeh","Panjshanbeh","Jomeh","Shanbeh"]
    // weekday column headers, ordered per the primary calendar's week start
    readonly property var weekLabels: root.primary === "shamsi"
        ? ["Sat","Sun","Mon","Tue","Wed","Thu","Fri"]
        : ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    // ================= Jalaali conversion (compact jalaali-js) =================
    function _div(a, b) { return ~~(a / b); }
    function _mod(a, b) { return a - ~~(a / b) * b; }
    function g2d(gy, gm, gd) {
        var d = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4)
              + _div(153 * _mod(gm + 9, 12) + 2, 5) + gd - 34840408;
        d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
        return d;
    }
    function d2g(jdn) {
        var j = 4 * jdn + 139361631;
        j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908;
        var i = _div(_mod(j, 1461), 4) * 5 + 308;
        var gd = _div(_mod(i, 153), 5) + 1;
        var gm = _mod(_div(i, 153), 12) + 1;
        var gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
        return { gy: gy, gm: gm, gd: gd };
    }
    function jalCal(jy) {
        var breaks = [-61,9,38,199,426,686,756,818,1111,1181,1210,1635,2060,2097,2192,2262,2324,2394,2456,3178];
        var bl = breaks.length, gy = jy + 621, leapJ = -14, jp = breaks[0];
        var jm = 0, jump = 0, leap, leapG, march, n, i;
        for (i = 1; i < bl; i += 1) {
            jm = breaks[i];
            jump = jm - jp;
            if (jy < jm) break;
            leapJ = leapJ + _div(jump, 33) * 8 + _div(_mod(jump, 33), 4);
            jp = jm;
        }
        n = jy - jp;
        leapJ = leapJ + _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4);
        if (_mod(jump, 33) === 4 && jump - n === 4) leapJ += 1;
        leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
        march = 20 + leapJ - leapG;
        if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
        leap = _mod(_mod(n + 1, 33) - 1, 4);
        if (leap === -1) leap = 4;
        return { leap: leap, gy: gy, march: march };
    }
    function jIsLeap(jy) { return jalCal(jy).leap === 0; }
    function jMonthLen(jy, jm) { return jm <= 6 ? 31 : (jm <= 11 ? 30 : (jIsLeap(jy) ? 30 : 29)); }
    function toJalaali(gy, gm, gd) {
        var jdn = g2d(gy, gm, gd);
        var gyy = d2g(jdn).gy, jy = gyy - 621, r = jalCal(jy);
        var jdn1f = g2d(gyy, 3, r.march), jd, jm, k = jdn - jdn1f;
        if (k >= 0) {
            if (k <= 185) return { jy: jy, jm: 1 + _div(k, 31), jd: _mod(k, 31) + 1 };
            k -= 186;
        } else {
            jy -= 1; k += 179;
            if (r.leap === 1) k += 1;
        }
        jm = 7 + _div(k, 30);
        jd = _mod(k, 30) + 1;
        return { jy: jy, jm: jm, jd: jd };
    }
    function toGregorian(jy, jm, jd) {
        var r = jalCal(jy);
        var jdn = g2d(r.gy, 3, r.march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1;
        return d2g(jdn);
    }

    // ================= helpers =================
    function pad2(n) { return n < 10 ? "0" + n : "" + n; }
    function dateKey(y, m, d) { return y + "-" + pad2(m) + "-" + pad2(d); }
    function ordinal(n) {
        var s = ["th","st","nd","rd"], v = n % 100;
        return n + (s[(v - 20) % 10] || s[v] || s[0]);
    }
    function isoWeek(y, m, d) {
        var t = new Date(Date.UTC(y, m - 1, d));
        var day = (t.getUTCDay() + 6) % 7;             // Mon=0
        t.setUTCDate(t.getUTCDate() - day + 3);        // to this week's Thursday
        var firstThu = new Date(Date.UTC(t.getUTCFullYear(), 0, 4));
        var fday = (firstThu.getUTCDay() + 6) % 7;
        firstThu.setUTCDate(firstThu.getUTCDate() - fday + 3);
        return 1 + Math.round((t - firstThu) / (7 * 86400000));
    }
    function shamsiWeek(jy, jm, jd) {
        var doy = jd;
        for (var m = 1; m < jm; m++) doy += jMonthLen(jy, m);
        return Math.floor((doy - 1) / 7) + 1;
    }

    // ---- build the 42-cell grid + 6 week numbers for the current view ----
    readonly property var view: {
        var isSh = root.primary === "shamsi";
        var first;                                     // first day of the shown month, as a JS Date
        if (isSh) {
            var g = root.toGregorian(root.jY, root.jM, 1);
            first = new Date(g.gy, g.gm - 1, g.gd);
        } else {
            first = new Date(root.gY, root.gM - 1, 1);
        }
        var wd = first.getDay();                       // 0 Sun .. 6 Sat
        var offset = isSh ? (wd + 1) % 7 : wd;         // Shamsi weeks start Saturday
        var start = new Date(first);
        start.setDate(start.getDate() - offset);
        var cells = [];
        for (var i = 0; i < 42; i++) {
            var dt = new Date(start);
            dt.setDate(dt.getDate() + i);
            var gy = dt.getFullYear(), gm = dt.getMonth() + 1, gd = dt.getDate();
            var j = root.toJalaali(gy, gm, gd);
            var inMonth = isSh ? (j.jm === root.jM && j.jy === root.jY) : (gm === root.gM && gy === root.gY);
            cells.push({
                gy: gy, gm: gm, gd: gd, jy: j.jy, jm: j.jm, jd: j.jd,
                key: root.dateKey(gy, gm, gd), inMonth: inMonth,
                primaryDay: isSh ? j.jd : gd, subDay: isSh ? gd : j.jd
            });
        }
        var weekNos = [];
        for (var r = 0; r < 6; r++) {
            var c = cells[r * 7 + 1];                  // the row's Monday / second cell
            weekNos.push(isSh ? root.shamsiWeek(c.jy, c.jm, c.jd) : root.isoWeek(c.gy, c.gm, c.gd));
        }
        return { cells: cells, weekNos: weekNos };
    }

    readonly property string title: root.primary === "shamsi"
        ? (root.jMonths[root.jM - 1] + " " + root.jY)
        : (root.gMonths[root.gM - 1] + " " + root.gY)

    // index of a "YYYY-MM-DD" key within the current 42 cells, or -1
    function idxOf(key) {
        var c = root.view.cells;
        for (var i = 0; i < c.length; i++) if (c[i].key === key) return i;
        return -1;
    }
    readonly property int selIdx: root.idxOf(root.selKey)
    readonly property int todayIdx: root.idxOf(root.todayKey)

    // selected day, broken out for the detail panel
    readonly property var sel: {
        var p = root.selKey.split("-");
        var y = +p[0], m = +p[1], d = +p[2];
        var dt = new Date(y, m - 1, d);
        var j = root.toJalaali(y, m, d);
        return { y: y, m: m, d: d, dow: dt.getDay(), jy: j.jy, jm: j.jm, jd: j.jd };
    }

    // ================= actions =================
    function select(key) {
        root.selKey = key;
        if (root.org) root.org.loadDay(key);
        if (root.fin) root.fin.loadDay(key);
    }
    // the selected day's forecast occurrences (from the range already loaded for
    // the dots, so the list always matches them). Empty under privacy.
    readonly property var selForecast: (root.showFin && root.selKey)
        ? root.fin.forecastForDay(root.selKey) : []
    // hand a forecast occurrence to the finance menu's add form, prefilled, so
    // the user can confirm/adjust it into a real transaction.
    function confirmForecast(item) {
        if (!root.fin) return;
        root.fin.pendingPrefill = {
            date: root.selKey,
            description: item.description,
            amount: item.amount,
            currency: item.currency,
            kind: item.kind === "income" ? "income" : "expense",
            account: item.account || "",
            asset: item.asset || "assets:cash"
        };
        root.financeRequested();
    }
    // select a grid cell; if it's a leading/trailing day of an adjacent month,
    // page to that month (with the slide animation) so the selection stays framed
    function pickCell(c) {
        root.select(c.key);
        if (c.inMonth) return;
        var delta = root.primary === "shamsi"
            ? ((c.jy * 12 + c.jm) < (root.jY * 12 + root.jM) ? -1 : 1)
            : ((c.gy * 12 + c.gm) < (root.gY * 12 + root.gM) ? -1 : 1);
        root.shiftMonth(delta);
    }
    function shiftMonth(delta) {
        if (root.primary === "shamsi") {
            var m = root.jM + delta, y = root.jY;
            if (m > 12) { m = 1; y += 1; } else if (m < 1) { m = 12; y -= 1; }
            root.jM = m; root.jY = y;
        } else {
            var gm = root.gM + delta, gy = root.gY;
            if (gm > 12) { gm = 1; gy += 1; } else if (gm < 1) { gm = 12; gy -= 1; }
            root.gM = gm; root.gY = gy;
        }
        slideT.x = delta > 0 ? 34 : -34;
        gridWrap.opacity = 0;
        slideAnim.restart();
        root.loadRange();
    }
    function goToday() {
        var t = new Date();
        root.gY = t.getFullYear(); root.gM = t.getMonth() + 1;
        var j = root.toJalaali(root.gY, root.gM, t.getDate());
        root.jY = j.jy; root.jM = j.jm;
        root.select(root.dateKey(root.gY, root.gM, t.getDate()));
        root.loadRange();
    }
    function toggleCalendar() {
        // keep the currently-selected day framed after the swap
        if (root.primary === "greg") {
            root.jY = root.sel.jy; root.jM = root.sel.jm;
            root.primary = "shamsi";
        } else {
            root.gY = root.sel.y; root.gM = root.sel.m;
            root.primary = "greg";
        }
    }
    // ask Org (and finance) for the set of days-with-entries across the grid
    function loadRange() {
        var c = root.view.cells;
        if (root.org) root.org.loadRange(c[0].key, c[41].key);
        if (root.fin) {
            root.fin.loadRange(c[0].key, c[41].key);
            root.fin.loadForecastRange(c[0].key, c[41].key);
        }
        // Google Calendar events are cached in a window; only refetch when the
        // shown grid falls outside it (the hourly Timer keeps it fresh otherwise).
        if (root.cal) root.cal.ensureCovers(c[0].key, c[41].key);
    }
    // the selected day's Google Calendar events (client-side filter of the cache)
    readonly property var calEvents: (root.cal && root.selKey)
        ? root.cal.dayEvents(root.selKey) : []
    // hide every calendar signal (events + grid dots) while finance privacy / DND is
    // on — reusing the same effective privacy state the finance section respects.
    readonly property bool showCal: !!root.cal && !(root.fin && root.fin.privacy)
    // the org agenda hides under the same finance privacy / DND toggle (the eye),
    // so nothing personal shows while it's on — matching the finance + Google sections.
    // Also gated by the Org Agenda feature toggle (Settings): off → no org section.
    readonly property bool showOrg: !!root.org && root.org.enabled && !(root.fin && root.fin.privacy)
    // the finance section/dots need the Finance feature enabled (Settings) and
    // privacy off — the wallet header button and every finance signal key off this.
    readonly property bool showFin: !!root.fin && root.fin.enabled && !root.fin.privacy

    Component.onCompleted: {
        var t = new Date();
        root.todayKey = root.dateKey(t.getFullYear(), t.getMonth() + 1, t.getDate());
        root.gY = t.getFullYear(); root.gM = t.getMonth() + 1;
        var j = root.toJalaali(root.gY, root.gM, t.getDate());
        root.jY = j.jy; root.jM = j.jm;
        root.select(root.todayKey);
        root.loadRange();
    }

    // tick the wall-clock ~3×/min so an event's "imminent" banner appears and
    // clears on time, without a heavy per-second tick.
    Timer {
        interval: 20000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // ================= header =================
    MenuHeader {
        id: header
        theme: root.theme
        title: root.title
        navArrows: true
        onBack: root.closeRequested()
        onPrev: root.shiftMonth(-1)
        onNext: root.shiftMonth(1)

        // Gregorian ⇄ Shamsi toggle
        Rectangle {
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.toggleCalendar(); }
            width: calToggleTxt.implicitWidth + 20
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (calToggleMa.containsMouse || kbFocused) ? root.theme.rowHi : root.theme.row
            Text {
                id: calToggleTxt
                anchors.centerIn: parent
                text: root.primary === "shamsi" ? "Shamsi" : "Gregorian"
                color: root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            MouseArea {
                id: calToggleMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleCalendar()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }

        // wallet — switch to the finance menu (win.menu 8); sits immediately left
        // of Today. Only present when the Finance feature is enabled (Settings).
        Rectangle {
            visible: root.fin && root.fin.enabled
            readonly property bool kbFocusable: root.fin && root.fin.enabled
            property bool kbFocused: false
            function keyClick() { root.financeRequested(); }
            width: 24
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (finBtnMa.containsMouse || kbFocused) ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "account_balance_wallet"
                size: 16
                color: finBtnMa.containsMouse ? root.theme.text : root.theme.textDim
            }
            MouseArea {
                id: finBtnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.financeRequested()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }

        // Today
        Rectangle {
            id: todayBtn
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.goToday(); }
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
            MouseArea {
                id: todayMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToday()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }
    }

    // ================= left: the month grid =================
    Item {
        id: grid
        x: 0
        y: root.gridTop
        width: root.leftW
        height: root.gridH

        // weekday column headers
        Row {
            x: root.weekNumW
            width: root.leftW - root.weekNumW
            height: root.wdHeadH
            Repeater {
                model: root.weekLabels
                delegate: Item {
                    id: wdCell
                    required property var modelData
                    width: root.cellW
                    height: root.wdHeadH
                    Text {
                        anchors.centerIn: parent
                        text: wdCell.modelData
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                }
            }
        }

        // wrapper for the week-numbers + day cells, slid/faded on month change
        Item {
            id: gridWrap
            x: 0
            y: root.wdHeadH
            width: root.leftW
            height: root.gridH - root.wdHeadH
            transform: Translate { id: slideT }

            ParallelAnimation {
                id: slideAnim
                NumberAnimation { target: slideT; property: "x"; to: 0; duration: root.theme.anim; easing.type: Easing.OutCubic }
                NumberAnimation { target: gridWrap; property: "opacity"; to: 1; duration: root.theme.anim }
            }

            // week numbers (italic serif rail, like the reference)
            Repeater {
                model: root.view.weekNos
                delegate: Text {
                    id: wkNo
                    required property int index
                    required property var modelData
                    x: 0
                    y: wkNo.index * root.cellH
                    width: root.weekNumW
                    height: root.cellH
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: wkNo.modelData
                    color: root.theme.faint
                    font.family: root.theme.serif
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
            }

            // detached hover square (faded gray) — mirrors the dashboard indicator
            Rectangle {
                id: hoverSq
                readonly property int col: root.hoverIdx >= 0 ? root.hoverIdx % 7 : 0
                readonly property int rw: root.hoverIdx >= 0 ? Math.floor(root.hoverIdx / 7) : 0
                x: root.weekNumW + col * root.cellW + root.cellInset
                y: rw * root.cellH + root.cellInset
                width: root.cellW - root.cellInset * 2
                height: root.cellH - root.cellInset * 2
                radius: root.theme.radiusSmall
                color: root.theme.bgHover
                opacity: root.hoverIdx >= 0 ? 1 : 0
                visible: opacity > 0
                Behavior on x { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
            }

            // detached selection square (launcher-hover accent-soft)
            Rectangle {
                id: selSq
                readonly property int col: root.selIdx >= 0 ? root.selIdx % 7 : 0
                readonly property int rw: root.selIdx >= 0 ? Math.floor(root.selIdx / 7) : 0
                x: root.weekNumW + col * root.cellW + root.cellInset
                y: rw * root.cellH + root.cellInset
                width: root.cellW - root.cellInset * 2
                height: root.cellH - root.cellInset * 2
                radius: root.theme.radiusSmall
                color: root.theme.accentSoft
                border.color: root.theme.accent
                border.width: 1
                opacity: root.selIdx >= 0 ? 1 : 0
                visible: opacity > 0
                Behavior on x { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
            }

            // today ring (only when today isn't the selected cell)
            Rectangle {
                visible: root.todayIdx >= 0 && root.todayIdx !== root.selIdx
                x: root.weekNumW + (root.todayIdx >= 0 ? root.todayIdx % 7 : 0) * root.cellW + root.cellInset
                y: (root.todayIdx >= 0 ? Math.floor(root.todayIdx / 7) : 0) * root.cellH + root.cellInset
                width: root.cellW - root.cellInset * 2
                height: root.cellH - root.cellInset * 2
                radius: root.theme.radiusSmall
                color: "transparent"
                border.color: root.theme.borderStrong
                border.width: 1
            }

            // day cells
            Repeater {
                model: root.view.cells
                delegate: Item {
                    id: cell
                    required property int index
                    required property var modelData
                    x: root.weekNumW + (index % 7) * root.cellW
                    y: Math.floor(index / 7) * root.cellH
                    width: root.cellW
                    height: root.cellH

                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.modelData.primaryDay
                            color: cell.modelData.inMonth ? root.theme.text : root.theme.faint
                            font.family: root.theme.serif
                            font.pixelSize: root.theme.fsLarge + 5
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.modelData.subDay
                            color: cell.modelData.inMonth ? root.theme.textDim : root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall - 1
                        }
                    }

                    // dots, centered as a row: vermillion/green = agenda,
                    // filled gold = a real finance entry, hollow gold = a
                    // forecast (expected) payment or income on that day.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        spacing: 3
                        Rectangle {
                            visible: root.showOrg && root.org.hasItems(cell.modelData.key)
                            width: 4
                            height: 4
                            radius: 2
                            // pastel-green when every dated todo that day is done,
                            // else the accent dot; adjacent-month days stay faint.
                            color: !cell.modelData.inMonth ? root.theme.faint
                                 : (root.org && root.org.allDone(cell.modelData.key)) ? root.theme.success
                                 : root.theme.accent
                        }
                        // filled gold: the day has real finance entries
                        Rectangle {
                            visible: root.showFin && root.fin.hasItems(cell.modelData.key)
                            width: 4
                            height: 4
                            radius: 2
                            color: !cell.modelData.inMonth ? root.theme.faint : root.theme.money
                        }
                        // hollow gold ring: a forecast entry falls on this day
                        Rectangle {
                            visible: root.showFin && root.fin.hasForecast(cell.modelData.key)
                            width: 4
                            height: 4
                            radius: 2
                            color: "transparent"
                            border.width: 1
                            border.color: !cell.modelData.inMonth ? root.theme.faint : root.theme.money
                        }
                        // soft-blue: the day has Google Calendar events (hidden under
                        // finance privacy / DND, like the finance dots)
                        Rectangle {
                            visible: root.showCal && root.cal.hasEvents(cell.modelData.key)
                            width: 4
                            height: 4
                            radius: 2
                            color: !cell.modelData.inMonth ? root.theme.faint : root.theme.event
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hoverIdx = cell.index
                        onExited: if (root.hoverIdx === cell.index) root.hoverIdx = -1
                        onClicked: root.pickCell(cell.modelData)
                    }
                }
            }
        }
    }

    // ================= right: selected-day detail + agenda =================
    Item {
        id: detail
        x: root.leftW + root.gap
        y: root.gridTop
        width: root.detailW
        height: root.gridH

        // primary-calendar line (weekday, month day-ordinal, year)
        Text {
            id: dLine1
            anchors.top: parent.top
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.primary === "shamsi"
                ? (root.jWeekdays[root.sel.dow] + "، " + root.sel.jd + " " + root.jMonths[root.sel.jm - 1] + " " + root.sel.jy)
                : (root.gWeekdays[root.sel.dow] + ", " + root.gMonths[root.sel.m - 1] + " " + root.ordinal(root.sel.d) + ", " + root.sel.y)
            color: root.theme.text
            font.family: root.theme.serif
            font.pixelSize: root.theme.fsLarge + 5
            lineHeight: 0.95
        }
        // secondary-calendar line
        Text {
            id: dLine2
            anchors.top: dLine1.bottom
            anchors.topMargin: 4
            text: root.primary === "shamsi"
                ? (root.gWeekdays[root.sel.dow] + ", " + root.gMonths[root.sel.m - 1] + " " + root.sel.d + ", " + root.sel.y)
                : (root.sel.jd + " " + root.jMonths[root.sel.jm - 1] + " " + root.sel.jy)
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }

        Rectangle {
            id: dRule
            anchors.top: dLine2.bottom
            anchors.topMargin: root.theme.gap
            width: parent.width
            height: 1
            color: root.theme.divider
        }

        // Org agenda title + open-in-Emacs button
        Item {
            id: agendaHead
            anchors.top: dRule.bottom
            anchors.topMargin: root.showOrg ? root.theme.gap : 0
            width: parent.width
            visible: root.showOrg
            height: root.showOrg ? 24 : 0
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Org agenda"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                radius: root.theme.radiusBtn
                color: openMa.containsMouse ? root.theme.rowHi : "transparent"
                MSym {
                    anchors.centerIn: parent
                    icon: "open_in_new"
                    size: 16
                    color: openMa.containsMouse ? root.theme.text : root.theme.textDim
                }
                MouseArea {
                    id: openMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.org) root.org.openAgenda(root.selKey)
                }
                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            }
        }

        // agenda entries — TODOs first, then everything else
        Flickable {
            anchors.top: agendaHead.bottom
            anchors.topMargin: 6
            anchors.bottom: parent.bottom
            width: parent.width
            contentHeight: agendaCol.height
            clip: true
            Column {
                id: agendaCol
                width: parent.width
                spacing: 8

                Repeater {
                    model: {
                        var items = (root.showOrg && root.org.dayItems) ? root.org.dayItems.slice() : [];
                        // group order: dated (scheduled/deadline) first, then the
                        // active undated todos, then done undated todos last — a
                        // done dated item still sorts above the undated todos.
                        function grp(it) {
                            if (it.dated)
                                return 0;
                            return it.done ? 2 : 1;
                        }
                        // within a group, higher priority (A > B > C > none) first
                        function pri(p) {
                            return p === "A" ? 3 : p === "B" ? 2 : p === "C" ? 1 : 0;
                        }
                        items.sort(function (a, b) {
                            var g = grp(a) - grp(b);
                            if (g !== 0)
                                return g;
                            // active before done within a group (a done dated
                            // item sinks below its still-open siblings)
                            var d = (a.done ? 1 : 0) - (b.done ? 1 : 0);
                            if (d !== 0)
                                return d;
                            return pri(b.priority) - pri(a.priority);
                        });
                        return items;
                    }
                    delegate: Row {
                        id: agendaRow
                        required property var modelData
                        width: agendaCol.width
                        spacing: 8

                        readonly property bool isTodo: !!(modelData.todo && modelData.todo.length)
                        // optimistic tick state: clicking sets `doneOverride` so
                        // the row animates at once, before the Emacs round-trip
                        // and reload land (-1 follow model, 0 active, 1 done).
                        property int doneOverride: -1
                        readonly property bool isDone: agendaRow.doneOverride === -1 ? !!modelData.done : (agendaRow.doneOverride === 1)
                        // heading text is already clean from orgbridge; just
                        // collapse any stray double spaces.
                        readonly property string heading: ("" + (modelData.text || "")).replace(/\s{2,}/g, " ").trim()
                        // Deadline / scheduled kind, shown as the pill's own dim
                        // label instead of Emacs's inline "Deadline:" text.
                        readonly property string kind: {
                            var ty = ("" + (modelData.type || "")).toLowerCase();
                            if (ty.indexOf("deadline") !== -1)
                                return "Deadline";
                            if (ty.indexOf("scheduled") !== -1)
                                return "Scheduled";
                            return "";
                        }
                        // #A → 3 bars, #B → 2, #C → 1, colour-coded by urgency
                        readonly property int priCount: modelData.priority === "A" ? 3 : modelData.priority === "B" ? 2 : modelData.priority === "C" ? 1 : 0
                        readonly property color priColor: modelData.priority === "A" ? root.theme.accent : modelData.priority === "B" ? "#d9a441" : root.theme.textDim

                        // todos get a tickable checkbox; plain timestamp entries
                        // keep the small dot. Clicking a checkbox flips done state.
                        Item {
                            width: 16
                            height: 16
                            anchors.top: parent.top
                            anchors.topMargin: 3
                            Rectangle {
                                visible: agendaRow.isTodo
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                radius: 4
                                color: agendaRow.isDone ? root.theme.accent : "transparent"
                                border.width: 1
                                border.color: agendaRow.isDone ? root.theme.accent : root.theme.faint
                                Behavior on color { ColorAnimation { duration: root.theme.anim } }
                                Behavior on border.color { ColorAnimation { duration: root.theme.anim } }
                                MSym {
                                    anchors.centerIn: parent
                                    icon: "check"
                                    fill: 1
                                    size: 11
                                    color: root.theme.bg
                                    // pops in when ticked, shrinks away when un-ticked
                                    opacity: agendaRow.isDone ? 1 : 0
                                    scale: agendaRow.isDone ? 1 : 0.4
                                    Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
                                    Behavior on scale { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
                                }
                            }
                            Rectangle {
                                visible: !agendaRow.isTodo
                                anchors.centerIn: parent
                                width: 5
                                height: 5
                                radius: 2.5
                                color: root.theme.faint
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: agendaRow.isTodo && !!agendaRow.modelData.file
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.org)
                                        return;
                                    agendaRow.doneOverride = agendaRow.isDone ? 0 : 1;
                                    root.org.toggleDone(agendaRow.modelData.file, agendaRow.modelData.pos);
                                }
                            }
                        }

                        Column {
                            width: agendaCol.width - 52
                            spacing: 2
                            Text {
                                visible: agendaRow.kind.length > 0
                                text: agendaRow.kind
                                color: root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                                font.letterSpacing: root.theme.labelSpacing
                                font.capitalization: Font.AllUppercase
                            }
                            Text {
                                id: hd
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: agendaRow.heading
                                color: agendaRow.isDone ? root.theme.faint : root.theme.text
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsNormal
                                Behavior on color { ColorAnimation { duration: root.theme.anim } }

                                // strikethrough that sweeps across as it's ticked
                                // (animated width beats the instant font.strikeout).
                                Rectangle {
                                    anchors.left: parent.left
                                    y: hd.font.pixelSize * 0.62
                                    height: 1
                                    radius: 0.5
                                    color: root.theme.faint
                                    width: agendaRow.isDone ? Math.min(hd.contentWidth, hd.width) : 0
                                    opacity: agendaRow.isDone ? 1 : 0
                                    Behavior on width { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
                                }
                            }
                        }

                        // priority marks — 1–3 stacked 4px lines (reserve the
                        // slot even when empty so headings stay aligned).
                        Column {
                            width: 20
                            spacing: 2
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            Repeater {
                                model: agendaRow.priCount
                                delegate: Rectangle {
                                    anchors.right: parent.right
                                    width: 14
                                    height: 4
                                    radius: 1
                                    color: agendaRow.priColor
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: root.showOrg && (!root.org.dayItems || root.org.dayItems.length === 0)
                    text: "Nothing scheduled."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }

                // ---- the day's Google Calendar events (from CalendarEvents; each
                //      row is collapsed by default and expands to its location,
                //      description, guests and a Join button). The whole section
                //      hides under finance privacy / DND (root.showCal). ----
                Rectangle {
                    visible: root.showCal
                    width: agendaCol.width
                    height: 1
                    color: root.theme.divider
                }
                Item {
                    visible: root.showCal
                    width: agendaCol.width
                    height: 20
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Calendar"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                    // refetch — refreshes the shown month's window from Google;
                    // the icon spins while a fetch is in flight.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        radius: root.theme.radiusBtn
                        color: refetchMa.containsMouse ? root.theme.rowHi : "transparent"
                        MSym {
                            anchors.centerIn: parent
                            icon: "refresh"
                            size: 16
                            color: refetchMa.containsMouse ? root.theme.text : root.theme.textDim
                            RotationAnimation on rotation {
                                running: !!(root.cal && root.cal.loading)
                                loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 900
                            }
                        }
                        MouseArea {
                            id: refetchMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.cal) root.cal.fetch(root.view.cells[0].key,
                                                                    root.view.cells[41].key)
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                }
                // sign-in / fetch error, if any (helps spot a re-consent need)
                Text {
                    visible: root.showCal && !!(root.cal && root.cal.lastError)
                          && root.calEvents.length === 0
                    width: agendaCol.width
                    wrapMode: Text.WordWrap
                    text: root.cal ? root.cal.lastError : ""
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall - 1
                }
                Text {
                    visible: root.showCal && root.calEvents.length === 0
                          && !(root.cal && root.cal.lastError)
                    text: "No events."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
                Repeater {
                    model: root.showCal ? root.calEvents : []
                    delegate: EventCard {
                        // the Repeater injects modelData into EventCard's required
                        // property; the rest of the card's state comes from here.
                        theme: root.theme
                        width: agendaCol.width
                        nowMs: root.nowMs
                        showAccount: !!(root.cal && root.cal.accounts.length > 1)
                    }
                }

                // ---- the day's finance entries (from FinanceState; whole
                //      section hides under privacy) ----
                Rectangle {
                    visible: root.showFin && root.fin.dayItems.length > 0
                    width: agendaCol.width
                    height: 1
                    color: root.theme.divider
                }
                Item {
                    visible: root.showFin && root.fin.dayItems.length > 0
                    width: agendaCol.width
                    height: 20
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Finance"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                    // currency chip — same shared displayCurrency the finance menu cycles
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: calCurTxt.implicitWidth + 14
                        height: 18
                        radius: root.theme.radiusBtn
                        color: calCurMa.containsMouse ? root.theme.rowHi : root.theme.row
                        border.width: 1
                        border.color: root.fin && root.fin.displayCurrency !== "native"
                                    ? root.theme.money : "transparent"
                        Text {
                            id: calCurTxt
                            anchors.centerIn: parent
                            text: root.fin ? root.fin.currencyLabel : "As-is"
                            color: root.fin && root.fin.displayCurrency !== "native"
                                 ? root.theme.money : root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall - 1
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        MouseArea {
                            id: calCurMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.fin) root.fin.cycleCurrency()
                        }
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                }
                Repeater {
                    model: root.showFin ? root.fin.dayItems : []
                    delegate: Item {
                        id: finRow
                        required property var modelData
                        width: agendaCol.width
                        height: Math.max(finDesc.height, finAmt.height)
                        Text {
                            id: finDesc
                            anchors.left: parent.left
                            width: parent.width - 116
                            wrapMode: Text.WordWrap
                            text: finRow.modelData.description
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            id: finAmt
                            anchors.right: parent.right
                            width: 110
                            horizontalAlignment: Text.AlignRight
                            text: (finRow.modelData.kind === "expense" ? "−"
                                 : finRow.modelData.kind === "income" ? "+" : "")
                                + (root.fin ? root.fin.fmtAmount(finRow.modelData.amount, finRow.modelData.currency) : "")
                            color: finRow.modelData.kind === "expense" ? root.theme.danger
                                 : finRow.modelData.kind === "income" ? root.theme.good
                                 : root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }

                // ---- the day's forecast (periodic) occurrences — each is a
                //      tickable row that opens the finance menu's add form
                //      prefilled, so the user can confirm/adjust it into a real
                //      transaction (hides under privacy). ----
                Rectangle {
                    visible: root.selForecast.length > 0
                    width: agendaCol.width
                    height: 1
                    color: root.theme.divider
                }
                Item {
                    visible: root.selForecast.length > 0
                    width: agendaCol.width
                    height: 20
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Upcoming"
                        color: root.theme.faint
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                }
                Repeater {
                    model: root.selForecast
                    delegate: Row {
                        id: fcRow
                        required property var modelData
                        width: agendaCol.width
                        spacing: 8

                        // gold checkbox — ticking opens the prefilled add form
                        // (its state is transient: the row navigates away on click)
                        Item {
                            width: 16
                            height: 16
                            anchors.top: parent.top
                            anchors.topMargin: 3
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                radius: 4
                                color: fcCheckMa.containsMouse ? root.theme.money : "transparent"
                                border.width: 1
                                border.color: root.theme.money
                                Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                                MSym {
                                    anchors.centerIn: parent
                                    icon: "check"
                                    fill: 1
                                    size: 11
                                    color: root.theme.bg
                                    opacity: fcCheckMa.containsMouse ? 1 : 0
                                    scale: fcCheckMa.containsMouse ? 1 : 0.4
                                    Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
                                    Behavior on scale { NumberAnimation { duration: root.theme.anim; easing.type: Easing.OutBack } }
                                }
                            }
                            MouseArea {
                                id: fcCheckMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmForecast(fcRow.modelData)
                            }
                        }

                        Column {
                            width: agendaCol.width - 24 - 110 - 16
                            spacing: 1
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: fcRow.modelData.description
                                color: root.theme.text
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsNormal
                            }
                            // the category it will post to (dim subtext)
                            Text {
                                visible: !!fcRow.modelData.account
                                width: parent.width
                                elide: Text.ElideLeft
                                text: fcRow.modelData.account
                                color: root.theme.faint
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall - 1
                            }
                        }

                        Text {
                            width: 110
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            horizontalAlignment: Text.AlignRight
                            text: (fcRow.modelData.kind === "expense" ? "−"
                                 : fcRow.modelData.kind === "income" ? "+" : "")
                                + (root.fin ? root.fin.fmtAmount(fcRow.modelData.amount, fcRow.modelData.currency) : "")
                            color: root.theme.money
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }
            }
        }
    }
}
