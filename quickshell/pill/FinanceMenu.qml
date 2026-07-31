pragma ComponentBehavior: Bound
// FinanceMenu.qml — finance pane (win.menu === 8): the calendar's month grid
// re-purposed for hledger. Gold dots mark days with entries (filled = real,
// hollow = forecast); a header chip cycles the display currency; the right
// panel lists the day's transactions and hosts the quick-add form; bottom tiles
// open the forecast/register/balances/wishlist views. See FinanceState for the
// data + privacy/nag machines, hledgerbridge.py for the hledger plumbing.
import QtQuick

Item {
    id: root
    required property var theme
    property var fin                          // FinanceState (may be null)
    signal closeRequested()
    signal calendarRequested()

    // ---- mode machine ----
    property string mode: "cal"               // cal | add | forecast | register | balances | wishlist | plan
    readonly property bool calLike: root.mode === "cal" || root.mode === "add"
    readonly property var reportTitles: ({ forecast: "Forecast", register: "Register",
                                           balances: "Balances", wishlist: "Wishlist",
                                           plan: "Plan" })
    function openMode(m) {
        root.mode = m;
        root.addError = "";
        if (m === "forecast") root.forecastHorizon = 12;   // reset the lazy horizon
        loadModeData(m);
    }
    function loadModeData(m) {
        if (!root.fin) return;
        if (m === "add")      { root.fin.loadAccounts(); }
        if (m === "forecast") { root.fin.loadTimeline(root.forecastHorizon); }
        if (m === "register") { root.fin.loadRegister(root.registerFilter, 50); }
        if (m === "balances") { root.fin.loadBalances(); }
        if (m === "wishlist") { root.fin.loadWishlist(); }
        if (m === "plan")     { root.fin.loadPlan(); }
    }

    // ---- view state (mirrors CalendarMenu) ----
    property string primary: "greg"           // "greg" | "shamsi" — which calendar drives the grid
    property int gY: 2026
    property int gM: 1
    property int jY: 1405
    property int jM: 1
    property string selKey: ""                // selected day, "YYYY-MM-DD" (Gregorian)
    property string todayKey: ""
    property int hoverIdx: -1

    // ---- report state ----
    property int forecastHorizon: 12          // timeline months ahead; grows on scroll
    property string registerFilter: ""        // "" | expenses | income | assets
    readonly property var planMonths: (root.fin && root.fin.planData && root.fin.planData.months)
        ? root.fin.planData.months : []
    readonly property var planUnbuyable: {    // wishlist items that never fit the horizon
        var items = (root.fin && root.fin.planData && root.fin.planData.items)
            ? root.fin.planData.items : [];
        var out = [];
        for (var i = 0; i < items.length; i++) if (!items[i].month) out.push(items[i]);
        return out;
    }

    // ---- add-form state ----
    property string addKind: "expense"        // expense | income
    property string addCurrency: "EUR"        // EUR | IRT
    property string addAccount: ""            // picked category (expenses:… / income:…)
    property int addAssetIdx: 0               // index into fin.accounts.assets
    property string addError: ""
    function parsedAmount() {
        var v = parseFloat(amountInput.text.replace(/,/g, "").trim());
        return (isFinite(v) && v > 0) ? v : NaN;
    }
    function submitAdd() {
        if (!root.fin || root.fin.adding) return;
        var assets = root.fin.accounts.assets || [];
        root.addError = "";
        root.fin.addEntry({
            date: root.selKey,
            description: descInput.text.trim(),
            amount: root.parsedAmount(),
            currency: root.addCurrency,
            kind: root.addKind,
            account: root.addAccount,
            asset: assets.length ? assets[root.addAssetIdx % assets.length] : "assets:cash"
        });
    }

    // ---- geometry ----
    readonly property int detailW: 280
    readonly property int headerH: 26
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
        var day = (t.getUTCDay() + 6) % 7;
        t.setUTCDate(t.getUTCDate() - day + 3);
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
    // signed, formatted amount for a txn row (fmtAmount masks under privacy)
    function rowAmount(it) {
        if (!root.fin) return "";
        var sign = it.kind === "expense" ? "−" : it.kind === "income" ? "+" : "";
        return sign + root.fin.fmtAmount(it.amount, it.currency);
    }
    function rowColor(kind) {
        return kind === "expense" ? root.theme.danger
             : kind === "income" ? root.theme.good
             : root.theme.textDim;
    }

    // ---- build the 42-cell grid + 6 week numbers for the current view ----
    readonly property var view: {
        var isSh = root.primary === "shamsi";
        var first;
        if (isSh) {
            var g = root.toGregorian(root.jY, root.jM, 1);
            first = new Date(g.gy, g.gm - 1, g.gd);
        } else {
            first = new Date(root.gY, root.gM - 1, 1);
        }
        var wd = first.getDay();
        var offset = isSh ? (wd + 1) % 7 : wd;
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
            var c = cells[r * 7 + 1];
            weekNos.push(isSh ? root.shamsiWeek(c.jy, c.jm, c.jd) : root.isoWeek(c.gy, c.gm, c.gd));
        }
        return { cells: cells, weekNos: weekNos };
    }

    readonly property string title: !root.calLike
        ? root.reportTitles[root.mode]
        : root.primary === "shamsi"
            ? (root.jMonths[root.jM - 1] + " " + root.jY)
            : (root.gMonths[root.gM - 1] + " " + root.gY)

    function idxOf(key) {
        var c = root.view.cells;
        for (var i = 0; i < c.length; i++) if (c[i].key === key) return i;
        return -1;
    }
    readonly property int selIdx: root.idxOf(root.selKey)
    readonly property int todayIdx: root.idxOf(root.todayKey)

    readonly property var sel: {
        var p = root.selKey.split("-");
        var y = +p[0], m = +p[1], d = +p[2];
        var dt = new Date(y, m - 1, d);
        var j = root.toJalaali(y, m, d);
        return { y: y, m: m, d: d, dow: dt.getDay(), jy: j.jy, jm: j.jm, jd: j.jd };
    }

    // forecast timeline flattened for display: a "month" marker row precedes the
    // first event of each new month, then one "event" row per upcoming txn.
    readonly property var timelineRows: {
        var items = (root.fin && root.fin.timelineItems) ? root.fin.timelineItems : [];
        var rows = [], lastYm = "";
        for (var i = 0; i < items.length; i++) {
            var ym = ("" + items[i].date).slice(0, 7);
            if (ym !== lastYm) { rows.push({ type: "month", ym: ym }); lastYm = ym; }
            rows.push({ type: "event", it: items[i] });
        }
        return rows;
    }
    readonly property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    function monthLabel(ym) {
        var p = ("" + ym).split("-");
        return root.monthNames[(+p[1] || 1) - 1] + " " + p[0];
    }
    // the running "what I'd have" balance (one or more commodities), masked
    function balanceText(bal) {
        if (!root.fin) return "";
        if (root.fin.privacy) return "•••";
        if (!bal || bal.length === 0) return "0";
        var parts = [];
        for (var i = 0; i < bal.length; i++)
            parts.push(root.fin.fmtAmount(bal[i].value, bal[i].currency));
        return parts.join(" · ");
    }

    // ================= actions =================
    function select(key) {
        root.selKey = key;
        if (root.fin) root.fin.loadDay(key);
    }
    // point the grid at a given "YYYY-MM-DD" and select it (used by the forecast
    // prefill hand-off, which may land on a month other than today's).
    function goToDate(key) {
        var p = ("" + key).split("-");
        var y = +p[0], m = +p[1], d = +p[2];
        if (!(y && m && d)) return;
        root.gY = y; root.gM = m;
        var j = root.toJalaali(y, m, d);
        root.jY = j.jy; root.jM = j.jm;
        root.select(key);
        root.loadRange();
    }
    // prefill + open the add form from a calendar forecast row (FinanceState's
    // pendingPrefill). The category highlights by name; the money account is
    // matched to an index once `accounts` loads (resolvePendingAsset).
    property string pendingAsset: ""
    function applyPrefill(p) {
        if (!p) return;
        root.goToDate(p.date);
        root.addKind = (p.kind === "income") ? "income" : "expense";
        root.addCurrency = (p.currency === "IRT") ? "IRT" : "EUR";
        root.addAccount = p.account || "";
        root.pendingAsset = p.asset || "";
        descInput.text = p.description || "";
        amountInput.text = isFinite(p.amount) ? ("" + p.amount) : "";
        root.openMode("add");            // loads accounts → resolvePendingAsset
        root.resolvePendingAsset();
    }
    function resolvePendingAsset() {
        if (!root.pendingAsset || !root.fin) return;
        var a = root.fin.accounts.assets || [];
        var i = a.indexOf(root.pendingAsset);
        if (i >= 0) { root.addAssetIdx = i; root.pendingAsset = ""; }
    }
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
        if (root.primary === "greg") {
            root.jY = root.sel.jy; root.jM = root.sel.jm;
            root.primary = "shamsi";
        } else {
            root.gY = root.sel.y; root.gM = root.sel.m;
            root.primary = "greg";
        }
    }
    function loadRange() {
        if (!root.fin) return;
        var c = root.view.cells;
        root.fin.loadRange(c[0].key, c[41].key);
        root.fin.loadForecastRange(c[0].key, c[41].key);
    }

    Component.onCompleted: {
        var t = new Date();
        root.todayKey = root.dateKey(t.getFullYear(), t.getMonth() + 1, t.getDate());
        root.gY = t.getFullYear(); root.gM = t.getMonth() + 1;
        var j = root.toJalaali(root.gY, root.gM, t.getDate());
        root.jY = j.jy; root.jM = j.jm;
        root.select(root.todayKey);
        root.loadRange();
        // arriving from the calendar's forecast section with a row to confirm
        if (root.fin && root.fin.pendingPrefill) {
            var p = root.fin.pendingPrefill;
            root.fin.pendingPrefill = null;
            root.applyPrefill(p);
        }
    }

    // refresh the dots after a successful quick-add
    Connections {
        target: root.fin
        ignoreUnknownSignals: true
        function onEntryAdded() { root.loadRange(); }
        // a forecast row picked while the finance menu is already open
        function onPendingPrefillChanged() {
            if (root.fin && root.fin.pendingPrefill) {
                var p = root.fin.pendingPrefill;
                root.fin.pendingPrefill = null;
                root.applyPrefill(p);
            }
        }
        // accounts finished loading: resolve the prefilled money account to its index
        function onAccountsChanged() { root.resolvePendingAsset(); }
        // currency changed: the day list reloads itself in FinanceState; here we
        // re-run whichever report is open so its amounts re-value too.
        function onDisplayCurrencyChanged() {
            if (!root.calLike) root.loadModeData(root.mode);
        }
        // book switched: FinanceState re-fires the calendar loads; here we
        // re-open whichever report is showing so it reflects the new book.
        function onEntityChanged() {
            if (!root.calLike) root.loadModeData(root.mode);
        }
        function onAddFinished(ok, error) {
            if (!ok) { root.addError = error || "add failed"; return; }
            descInput.text = "";
            amountInput.text = "";
            root.addError = "";
            root.mode = "cal";
        }
    }

    // ================= header =================
    MenuHeader {
        id: header
        theme: root.theme
        title: root.title
        navArrows: root.calLike
        onBack: root.mode === "cal" ? root.closeRequested() : (root.mode = "cal")
        onPrev: root.shiftMonth(-1)
        onNext: root.shiftMonth(1)

        // Gregorian ⇄ Shamsi toggle (grid modes only)
        Rectangle {
            visible: root.calLike
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

        // book chip — cycles through the finance books (personal / company / …);
        // hidden when there is only one book. A non-personal book is gold-badged.
        Rectangle {
            visible: root.fin && root.fin.entities && root.fin.entities.length > 1
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { if (root.fin) root.fin.cycleEntity(); }
            width: hdrBookRow.implicitWidth + 18
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (hdrBookMa.containsMouse || kbFocused) ? root.theme.rowHi : root.theme.row
            border.width: 1
            border.color: root.fin && root.fin.entity !== "personal"
                        ? root.theme.money : "transparent"
            Row {
                id: hdrBookRow
                anchors.centerIn: parent
                spacing: 5
                MSym {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "menu_book"
                    size: 14
                    color: root.fin && root.fin.entity !== "personal"
                         ? root.theme.money : root.theme.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fin ? root.fin.entity : "personal"
                    color: root.fin && root.fin.entity !== "personal"
                         ? root.theme.money : root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
            }
            MouseArea {
                id: hdrBookMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.fin) root.fin.cycleEntity()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }

        // currency chip — cycles As-is → EUR → IRT (values every amount shown)
        Rectangle {
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { if (root.fin) root.fin.cycleCurrency(); }
            width: hdrCurTxt.implicitWidth + 20
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (hdrCurMa.containsMouse || kbFocused) ? root.theme.rowHi : root.theme.row
            border.width: 1
            border.color: root.fin && root.fin.displayCurrency !== "native"
                        ? root.theme.money : "transparent"
            Text {
                id: hdrCurTxt
                anchors.centerIn: parent
                text: root.fin ? root.fin.currencyLabel : "As-is"
                color: root.fin && root.fin.displayCurrency !== "native"
                     ? root.theme.money : root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            MouseArea {
                id: hdrCurMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.fin) root.fin.cycleCurrency()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }

        // privacy eye — same effective state the launcher toggle shows
        Rectangle {
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { if (root.fin) root.fin.togglePrivacy(); }
            width: 24
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (eyeMa.containsMouse || kbFocused) ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: root.fin && root.fin.privacy ? "visibility_off" : "visibility"
                fill: root.fin && root.fin.privacy ? 1 : 0
                size: 16
                color: root.fin && root.fin.privacy ? root.theme.accent
                     : (eyeMa.containsMouse ? root.theme.text : root.theme.textDim)
            }
            MouseArea {
                id: eyeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.fin) root.fin.togglePrivacy()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }

        // back to the calendar menu
        Rectangle {
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() { root.calendarRequested(); }
            width: 24
            height: 24
            radius: root.theme.radiusBtn
            anchors.verticalCenter: parent.verticalCenter
            color: (calBtnMa.containsMouse || kbFocused) ? root.theme.rowHi : "transparent"
            MSym {
                anchors.centerIn: parent
                icon: "calendar_month"
                size: 16
                color: calBtnMa.containsMouse ? root.theme.text : root.theme.textDim
            }
            MouseArea {
                id: calBtnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.calendarRequested()
            }
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
        }

        // Today (grid modes only)
        Rectangle {
            id: todayBtn
            visible: root.calLike
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

    // ================= left: the month grid (cal/add modes) =================
    Item {
        id: grid
        visible: root.calLike
        x: 0
        y: root.gridTop
        width: root.leftW
        height: root.gridH

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

                    // finance dots — filled gold: real entries; hollow gold:
                    // a forecast (expected) payment/income. Stay visible under
                    // privacy (only amounts are masked in here).
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        spacing: 3
                        Rectangle {
                            visible: root.fin && root.fin.hasItems(cell.modelData.key)
                            width: 4
                            height: 4
                            radius: 2
                            color: !cell.modelData.inMonth ? root.theme.faint : root.theme.money
                        }
                        Rectangle {
                            visible: root.fin && root.fin.hasForecast(cell.modelData.key)
                            width: 4
                            height: 4
                            radius: 2
                            color: "transparent"
                            border.width: 1
                            border.color: !cell.modelData.inMonth ? root.theme.faint : root.theme.money
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

    // ================= right panel (cal mode) =================
    Item {
        id: detail
        visible: root.mode === "cal"
        x: root.leftW + root.gap
        y: root.gridTop
        width: root.detailW
        height: root.gridH

        Column {
            id: topCol
            width: parent.width
            spacing: root.theme.gap

            // nag dismiss card — only while the evening nag is live
            Rectangle {
                visible: root.fin && root.fin.nag
                width: parent.width
                height: nagCol.height + 20
                radius: root.theme.radiusCard
                color: root.theme.row
                border.color: root.theme.border
                border.width: 1
                Column {
                    id: nagCol
                    x: 10
                    y: 10
                    width: parent.width - 20
                    spacing: 8
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "No entries today yet."
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                    Row {
                        spacing: 6
                        Rectangle {
                            width: nag1Txt.implicitWidth + 16
                            height: 22
                            radius: root.theme.radiusBtn
                            color: nag1Ma.containsMouse ? root.theme.rowHi : root.theme.bgElevated
                            Text {
                                id: nag1Txt
                                anchors.centerIn: parent
                                text: "1 hour"
                                color: root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                            MouseArea {
                                id: nag1Ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.fin) root.fin.dismissNag(60)
                            }
                        }
                        Rectangle {
                            width: nag2Txt.implicitWidth + 16
                            height: 22
                            radius: root.theme.radiusBtn
                            color: nag2Ma.containsMouse ? root.theme.rowHi : root.theme.bgElevated
                            Text {
                                id: nag2Txt
                                anchors.centerIn: parent
                                text: "2 hours"
                                color: root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                            MouseArea {
                                id: nag2Ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.fin) root.fin.dismissNag(120)
                            }
                        }
                        // "until tomorrow" silences the whole evening → two-step
                        Rectangle {
                            width: nag3Txt.implicitWidth + 16
                            height: 22
                            radius: root.theme.radiusBtn
                            color: root.confirmTomorrow ? root.theme.danger
                                 : nag3Ma.containsMouse ? root.theme.rowHi : root.theme.bgElevated
                            Text {
                                id: nag3Txt
                                anchors.centerIn: parent
                                text: root.confirmTomorrow ? "Sure?" : "Until tomorrow"
                                color: root.confirmTomorrow ? "#ffffff" : root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                            MouseArea {
                                id: nag3Ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!root.confirmTomorrow) {
                                        root.confirmTomorrow = true;
                                        confirmRevert.restart();
                                    } else if (root.fin) {
                                        root.fin.dismissNagUntilTomorrow();
                                        root.confirmTomorrow = false;
                                    }
                                }
                            }
                            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                        }
                    }
                }
            }

            // selected day in both calendars
            Text {
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
            Text {
                text: root.primary === "shamsi"
                    ? (root.gWeekdays[root.sel.dow] + ", " + root.gMonths[root.sel.m - 1] + " " + root.sel.d + ", " + root.sel.y)
                    : (root.sel.jd + " " + root.jMonths[root.sel.jm - 1] + " " + root.sel.jy)
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }

            Rectangle {
                width: parent.width
                height: 1
                color: root.theme.divider
            }

            // "Finance" title + add button
            Item {
                width: parent.width
                height: 24
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
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: root.theme.radiusBtn
                    color: addMa.containsMouse ? root.theme.rowHi : "transparent"
                    MSym {
                        anchors.centerIn: parent
                        icon: "add"
                        size: 16
                        color: addMa.containsMouse ? root.theme.text : root.theme.textDim
                    }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openMode("add")
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }

        // the selected day's transactions
        Flickable {
            anchors.top: topCol.bottom
            anchors.topMargin: 6
            anchors.bottom: gitRow.top
            anchors.bottomMargin: root.theme.gap
            width: parent.width
            contentHeight: dayCol.height
            clip: true
            Column {
                id: dayCol
                width: parent.width
                spacing: 8

                Repeater {
                    model: (root.fin && root.fin.dayItems) ? root.fin.dayItems : []
                    delegate: Item {
                        id: dayRow
                        required property var modelData
                        width: dayCol.width
                        height: Math.max(descTxt.height, amtTxt.height)
                        Text {
                            id: descTxt
                            anchors.left: parent.left
                            width: parent.width - 116
                            wrapMode: Text.WordWrap
                            text: dayRow.modelData.description
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            id: amtTxt
                            anchors.right: parent.right
                            width: 110
                            horizontalAlignment: Text.AlignRight
                            text: root.rowAmount(dayRow.modelData)
                            color: root.rowColor(dayRow.modelData.kind)
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }

                Text {
                    visible: !root.fin || !root.fin.dayItems || root.fin.dayItems.length === 0
                    text: "No entries."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }

        // git strip: branch + local/remote counts, ff-pull + commit&push.
        // Conflicts stay a terminal job — the strip only reports them.
        Item {
            id: gitRow
            visible: !!(root.fin && root.fin.gitInfo && root.fin.gitInfo.repo)
            anchors.bottom: switcher.top
            anchors.bottomMargin: 6
            width: parent.width
            height: visible ? 22 : 0
            Text {
                anchors.left: parent.left
                anchors.right: gitButtons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: {
                    if (!root.fin || !root.fin.gitInfo || !root.fin.gitInfo.repo) return "";
                    if (root.fin.gitError) return root.fin.gitError;
                    var g = root.fin.gitInfo;
                    var bits = [g.branch || "?"];
                    if (g.dirty) bits.push(g.dirty + " unsaved");
                    if (g.ahead) bits.push(g.ahead + "↑");
                    if (g.behind) bits.push(g.behind + "↓");
                    return bits.join(" · ");
                }
                color: (root.fin && root.fin.gitError) ? root.theme.danger : root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall - 1
            }
            Row {
                id: gitButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle {
                    width: 22
                    height: 22
                    radius: root.theme.radiusBtn
                    color: gitSyncMa.containsMouse ? root.theme.rowHi : "transparent"
                    opacity: (root.fin && root.fin.gitBusy) ? 0.4 : 1
                    MSym {
                        anchors.centerIn: parent
                        icon: "sync"
                        size: 14
                        color: gitSyncMa.containsMouse ? root.theme.text : root.theme.textDim
                    }
                    MouseArea {
                        id: gitSyncMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.fin && !root.fin.gitBusy) root.fin.gitSync()
                    }
                }
                Rectangle {
                    width: 22
                    height: 22
                    radius: root.theme.radiusBtn
                    color: gitPushMa.containsMouse ? root.theme.rowHi : "transparent"
                    opacity: (root.fin && root.fin.gitBusy) ? 0.4 : 1
                    MSym {
                        anchors.centerIn: parent
                        icon: "cloud_upload"
                        size: 14
                        color: {
                            if (!root.fin) return root.theme.textDim;
                            var g = root.fin.gitInfo || {};
                            return (g.dirty || g.ahead)
                                ? root.theme.money
                                : (gitPushMa.containsMouse ? root.theme.text : root.theme.textDim);
                        }
                    }
                    MouseArea {
                        id: gitPushMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.fin && !root.fin.gitBusy) root.fin.gitPush()
                    }
                }
            }
        }

        // report tiles
        Row {
            id: switcher
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 6
            Repeater {
                model: [
                    { key: "forecast", ic: "query_stats",     label: "Forecast" },
                    { key: "plan",     ic: "savings",         label: "Plan" },
                    { key: "register", ic: "receipt_long",    label: "Register" },
                    { key: "balances", ic: "account_balance", label: "Balances" },
                    { key: "wishlist", ic: "favorite",        label: "Wishlist" }
                ]
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    width: (switcher.width - 24) / 5
                    height: 46
                    radius: root.theme.radiusBtn
                    color: tileMa.containsMouse ? root.theme.rowHi : root.theme.row
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        MSym {
                            anchors.horizontalCenter: parent.horizontalCenter
                            icon: tile.modelData.ic
                            size: 16
                            color: tileMa.containsMouse ? root.theme.text : root.theme.textDim
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.label
                            color: tileMa.containsMouse ? root.theme.text : root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall - 2
                            font.letterSpacing: 0.6
                            font.capitalization: Font.AllUppercase
                        }
                    }
                    MouseArea {
                        id: tileMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openMode(tile.modelData.key)
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }
    }

    property bool confirmTomorrow: false
    Timer {
        id: confirmRevert
        interval: 3000
        onTriggered: root.confirmTomorrow = false
    }

    // ================= right panel (add mode): the quick-add form =================
    Flickable {
        visible: root.mode === "add"
        x: root.leftW + root.gap
        y: root.gridTop
        width: root.detailW
        height: root.gridH
        contentHeight: formCol.height
        clip: true

        Column {
            id: formCol
            width: parent.width
            spacing: 10

            Text {
                text: "Add entry — " + root.selKey
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }

            // Expense / Income segment
            Row {
                spacing: 0
                Rectangle {
                    width: 90
                    height: 24
                    radius: root.theme.radiusBtn
                    color: root.addKind === "expense" ? root.theme.accentSoft : (kExpMa.containsMouse ? root.theme.rowHi : root.theme.row)
                    border.color: root.addKind === "expense" ? root.theme.accent : "transparent"
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "Expense"
                        color: root.addKind === "expense" ? root.theme.accent : root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: kExpMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addKind = "expense"; root.addAccount = ""; }
                    }
                }
                Item { width: 6; height: 1 }
                Rectangle {
                    width: 90
                    height: 24
                    radius: root.theme.radiusBtn
                    color: root.addKind === "income" ? root.theme.accentSoft : (kIncMa.containsMouse ? root.theme.rowHi : root.theme.row)
                    border.color: root.addKind === "income" ? root.theme.accent : "transparent"
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "Income"
                        color: root.addKind === "income" ? root.theme.accent : root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: kIncMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addKind = "income"; root.addAccount = ""; }
                    }
                }
            }

            // description
            Rectangle {
                width: parent.width
                height: 32
                radius: root.theme.radiusRow
                color: root.theme.row
                border.color: descInput.activeFocus ? root.theme.accent : root.theme.border
                border.width: 1
                TextInput {
                    id: descInput
                    objectName: "pillKbInput"
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                    clip: true
                    selectByMouse: true
                    selectionColor: root.theme.accentDim
                    Text {
                        visible: descInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Description"
                        color: root.theme.faint
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                }
            }

            // amount + currency toggle
            Row {
                width: parent.width
                spacing: 6
                Rectangle {
                    width: parent.width - 66
                    height: 32
                    radius: root.theme.radiusRow
                    color: root.theme.row
                    border.color: amountInput.activeFocus ? root.theme.accent : root.theme.border
                    border.width: 1
                    TextInput {
                        id: amountInput
                        objectName: "pillKbInput"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsNormal
                        clip: true
                        selectByMouse: true
                        selectionColor: root.theme.accentDim
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        Text {
                            visible: amountInput.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Amount"
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsNormal
                        }
                    }
                }
                Rectangle {
                    width: 60
                    height: 32
                    radius: root.theme.radiusRow
                    color: curMa.containsMouse ? root.theme.rowHi : root.theme.row
                    border.color: root.theme.border
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: root.addCurrency
                        color: root.theme.text
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                    }
                    MouseArea {
                        id: curMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.addCurrency = root.addCurrency === "EUR" ? "IRT" : "EUR"
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }

            // category picker (expenses:… or income:… by kind)
            Text {
                text: "Category"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Flickable {
                width: parent.width
                height: 110
                contentHeight: catCol.height
                clip: true
                Column {
                    id: catCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: root.fin
                            ? (root.addKind === "expense" ? root.fin.accounts.expenses : root.fin.accounts.income)
                            : []
                        delegate: Rectangle {
                            id: catRow
                            required property var modelData
                            width: catCol.width
                            height: 24
                            radius: root.theme.radiusBtn
                            color: root.addAccount === catRow.modelData ? root.theme.accentSoft
                                 : (catMa.containsMouse ? root.theme.rowHi : "transparent")
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16
                                elide: Text.ElideLeft
                                text: catRow.modelData
                                color: root.addAccount === catRow.modelData ? root.theme.accent : root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                            MouseArea {
                                id: catMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addAccount = catRow.modelData
                            }
                        }
                    }
                    Text {
                        visible: !root.fin
                            || (root.addKind === "expense" ? root.fin.accounts.expenses : root.fin.accounts.income).length === 0
                        text: "No accounts found."
                        color: root.theme.faint
                        font.family: root.theme.family
                        font.italic: true
                        font.pixelSize: root.theme.fsSmall
                    }
                }
            }

            // asset account (click to cycle)
            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.addKind === "expense" ? "From" : "To"
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: assetTxt.implicitWidth + 16
                    height: 24
                    radius: root.theme.radiusBtn
                    color: assetMa.containsMouse ? root.theme.rowHi : root.theme.row
                    Text {
                        id: assetTxt
                        anchors.centerIn: parent
                        text: {
                            var a = root.fin ? (root.fin.accounts.assets || []) : [];
                            return a.length ? a[root.addAssetIdx % a.length] : "assets:cash";
                        }
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                    }
                    MouseArea {
                        id: assetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.addAssetIdx += 1
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }

            // hledger check error, verbatim
            Text {
                visible: root.addError.length > 0
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: root.addError
                color: root.theme.danger
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall - 1
            }

            // Save / Cancel
            Row {
                spacing: 6
                Rectangle {
                    readonly property bool valid: root.fin && !root.fin.adding
                        && descInput.text.trim().length > 0
                        && isFinite(root.parsedAmount())
                        && root.addAccount.length > 0
                    width: saveTxt.implicitWidth + 24
                    height: 26
                    radius: root.theme.radiusBtn
                    color: !valid ? root.theme.row
                         : saveMa.containsMouse ? root.theme.accent : root.theme.accentSoft
                    Text {
                        id: saveTxt
                        anchors.centerIn: parent
                        text: root.fin && root.fin.adding ? "Saving…" : "Save"
                        color: !parent.valid ? root.theme.faint
                             : saveMa.containsMouse ? "#ffffff" : root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: saveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.valid ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: parent.valid
                        onClicked: root.submitAdd()
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
                Rectangle {
                    width: cancelTxt.implicitWidth + 24
                    height: 26
                    radius: root.theme.radiusBtn
                    color: cancelMa.containsMouse ? root.theme.rowHi : root.theme.row
                    Text {
                        id: cancelTxt
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.addError = ""; root.mode = "cal"; }
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }
    }

    // ================= report modes (full width below the header) =================

    // ---- forecast timeline ----
    Item {
        visible: root.mode === "forecast"
        x: 0
        y: root.gridTop
        width: root.width
        height: root.gridH

        // column header: what each field means
        Item {
            id: tlHead
            width: parent.width
            height: 18
            Text {
                anchors.left: parent.left
                text: "Upcoming — projected balance"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
            Text {
                anchors.right: parent.right
                text: "Amount → would have"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
        }

        Flickable {
            id: tlFlick
            anchors.top: tlHead.bottom
            anchors.topMargin: 6
            anchors.bottom: parent.bottom
            width: parent.width
            contentHeight: tlCol.height
            clip: true
            // grow the horizon (lazily) as the user nears the bottom → "infinite"
            onContentYChanged: {
                if (contentHeight > height
                    && contentY >= contentHeight - height - 80
                    && root.forecastHorizon < 120) {
                    root.forecastHorizon += 12;
                    if (root.fin) root.fin.loadTimeline(root.forecastHorizon);
                }
            }
            Column {
                id: tlCol
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.timelineRows
                    delegate: Loader {
                        required property var modelData
                        width: tlCol.width
                        sourceComponent: modelData.type === "month" ? monthMarker : eventRow
                        onLoaded: item.rowData = modelData
                    }
                }
                Text {
                    visible: root.timelineRows.length === 0
                    text: "Nothing upcoming — add rules to forecast.journal."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }

        // month separator
        Component {
            id: monthMarker
            Item {
                property var rowData
                width: tlCol.width
                height: 26
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.left: mLabel.right
                    anchors.leftMargin: 8
                    height: 1
                    color: root.theme.divider
                }
                Text {
                    id: mLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.monthLabel(parent.rowData ? parent.rowData.ym : "")
                    color: root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
            }
        }

        // one upcoming event: date · description on the left; the ±amount and
        // the running "would have" balance stacked on the right (stacking keeps
        // big IRT figures and native two-currency balances from colliding).
        Component {
            id: eventRow
            Item {
                property var rowData
                readonly property var it: rowData ? rowData.it : ({})
                width: tlCol.width
                height: 40
                Text {
                    id: evDate
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 74
                    text: parent.it.date || ""
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                }
                Text {
                    id: evDesc
                    anchors.left: evDate.right
                    anchors.right: evRight.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: parent.it.description || ""
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                }
                Column {
                    id: evRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 300
                    spacing: 1
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: root.rowAmount(evRight.parent.it)
                        color: root.rowColor(evRight.parent.it.kind)
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: "→ " + root.balanceText(evRight.parent.it.balance)
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall - 1
                    }
                }
            }
        }
    }

    // ---- register ----
    Item {
        visible: root.mode === "register"
        x: 0
        y: root.gridTop
        width: root.width
        height: root.gridH

        Row {
            id: regChips
            spacing: 6
            Repeater {
                model: [
                    { label: "All", q: "" },
                    { label: "Expenses", q: "expenses" },
                    { label: "Income", q: "income" },
                    { label: "Assets", q: "assets" }
                ]
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    width: chipTxt.implicitWidth + 16
                    height: 22
                    radius: root.theme.radiusBtn
                    color: root.registerFilter === chip.modelData.q ? root.theme.accentSoft
                         : (chipMa.containsMouse ? root.theme.rowHi : root.theme.row)
                    border.color: root.registerFilter === chip.modelData.q ? root.theme.accent : "transparent"
                    border.width: 1
                    Text {
                        id: chipTxt
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: root.registerFilter === chip.modelData.q ? root.theme.accent : root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                    }
                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.registerFilter = chip.modelData.q;
                            if (root.fin) root.fin.loadRegister(chip.modelData.q, 50);
                        }
                    }
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }
            }
        }

        Flickable {
            anchors.top: regChips.bottom
            anchors.topMargin: root.theme.gap
            anchors.bottom: parent.bottom
            width: parent.width
            contentHeight: regCol.height
            clip: true
            Column {
                id: regCol
                width: parent.width
                spacing: 6
                Repeater {
                    model: (root.fin && root.fin.registerItems) ? root.fin.registerItems : []
                    delegate: Item {
                        id: regRow
                        required property var modelData
                        width: regCol.width
                        height: Math.max(regDesc.height, 18)
                        Text {
                            id: regDate
                            anchors.left: parent.left
                            width: 84
                            text: regRow.modelData.date
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                        Text {
                            id: regDesc
                            anchors.left: regDate.right
                            anchors.right: regAmt.left
                            anchors.rightMargin: 8
                            wrapMode: Text.WordWrap
                            text: regRow.modelData.description
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            id: regAmt
                            anchors.right: parent.right
                            width: 120
                            horizontalAlignment: Text.AlignRight
                            text: root.rowAmount(regRow.modelData)
                            color: root.rowColor(regRow.modelData.kind)
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }
                Text {
                    visible: !root.fin || !root.fin.registerItems || root.fin.registerItems.length === 0
                    text: "No transactions."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }
    }

    // ---- balances ----
    Flickable {
        visible: root.mode === "balances"
        x: 0
        y: root.gridTop
        width: root.width
        height: root.gridH
        contentHeight: balCol.height
        clip: true
        Column {
            id: balCol
            width: parent.width
            spacing: 4
            Repeater {
                model: (root.fin && root.fin.balances.rows) ? root.fin.balances.rows : []
                delegate: Item {
                    id: balRow
                    required property var modelData
                    width: balCol.width
                    height: Math.max(balAmts.height, 18)
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: balRow.modelData.indent * 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            var parts = ("" + balRow.modelData.account).split(":");
                            return parts[parts.length - 1];
                        }
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                    }
                    Column {
                        id: balAmts
                        anchors.right: parent.right
                        spacing: 1
                        Repeater {
                            model: balRow.modelData.amounts
                            delegate: Text {
                                id: balAmt
                                required property var modelData
                                anchors.right: parent.right
                                text: root.fin ? root.fin.fmtAmount(balAmt.modelData.value, balAmt.modelData.currency) : ""
                                color: balAmt.modelData.value < 0 ? root.theme.danger : root.theme.textDim
                                font.family: root.theme.mono
                                font.pixelSize: root.theme.fsSmall
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 1
                color: root.theme.divider
            }
            Item {
                width: balCol.width
                height: Math.max(totAmts.height, 18)
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Total"
                    color: root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                }
                Column {
                    id: totAmts
                    anchors.right: parent.right
                    spacing: 1
                    Repeater {
                        model: (root.fin && root.fin.balances.totals) ? root.fin.balances.totals : []
                        delegate: Text {
                            id: totAmt
                            required property var modelData
                            anchors.right: parent.right
                            text: root.fin ? root.fin.fmtAmount(totAmt.modelData.value, totAmt.modelData.currency) : ""
                            color: totAmt.modelData.value < 0 ? root.theme.danger : root.theme.text
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }
            }
            Text {
                visible: !root.fin || !root.fin.balances.rows || root.fin.balances.rows.length === 0
                text: "No balances."
                color: root.theme.faint
                font.family: root.theme.family
                font.italic: true
                font.pixelSize: root.theme.fsNormal
            }
        }
    }

    // ---- wishlist ----
    Item {
        visible: root.mode === "wishlist"
        x: 0
        y: root.gridTop
        width: root.width
        height: root.gridH

        // liquid − buffer = spendable strip (affordability subtracts the buffer)
        Text {
            id: liquidHead
            text: {
                if (!root.fin) return "Liquid: —";
                var w = root.fin.wishlist, cur = w.currency || "EUR";
                return "Spendable " + root.fin.fmtAmount(w.spendable || 0, cur)
                     + "   =  liquid " + root.fin.fmtAmount(w.liquid || 0, cur)
                     + " − buffer " + root.fin.fmtAmount(w.buffer || 0, cur);
            }
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
            font.letterSpacing: root.theme.labelSpacing
            font.capitalization: Font.AllUppercase
        }

        Flickable {
            anchors.top: liquidHead.bottom
            anchors.topMargin: root.theme.gap
            anchors.bottom: parent.bottom
            width: parent.width
            contentHeight: wishCol.height
            clip: true
            Column {
                id: wishCol
                width: parent.width
                spacing: 8
                Repeater {
                    model: (root.fin && root.fin.wishlist.items) ? root.fin.wishlist.items : []
                    delegate: Item {
                        id: wishRow
                        required property var modelData
                        width: wishCol.width
                        height: 22
                        // affordable ✓ · not yet ⏳ · null = no same-commodity assets
                        MSym {
                            id: wishBadge
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            icon: wishRow.modelData.affordable === true ? "check_circle"
                                : wishRow.modelData.affordable === false ? "hourglass_empty"
                                : "help"
                            fill: wishRow.modelData.affordable === true ? 1 : 0
                            size: 16
                            color: wishRow.modelData.affordable === true ? root.theme.good
                                 : wishRow.modelData.affordable === false ? root.theme.faint
                                 : root.theme.textDim
                        }
                        Text {
                            anchors.left: wishBadge.right
                            anchors.leftMargin: 8
                            anchors.right: wishAmt.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: wishRow.modelData.description
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            id: wishAmt
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fin ? root.fin.fmtAmount(wishRow.modelData.amount, wishRow.modelData.currency) : ""
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }
                Text {
                    visible: !root.fin || !root.fin.wishlist.items || root.fin.wishlist.items.length === 0
                    text: "Wishlist is empty — add items to wishlist.journal."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }
    }

    // ---- plan: month-by-month savings + wishlist-purchase schedule ----
    Item {
        visible: root.mode === "plan"
        x: 0
        y: root.gridTop
        width: root.width
        height: root.gridH

        // targets strip (buffer + goal from plan.conf)
        Text {
            id: planHead
            readonly property var pd: root.fin ? root.fin.planData : ({})
            text: {
                if (!root.fin) return "—";
                var cur = planHead.pd.currency || "EUR";
                var s = "Keep ≥ " + root.fin.fmtAmount(planHead.pd.buffer || 0, cur) + " buffer";
                if (planHead.pd.goal)
                    s += "   ·   reach " + root.fin.fmtAmount(planHead.pd.goal, cur)
                       + " by " + planHead.pd.goal_date;
                return s;
            }
            color: root.theme.textDim
            font.family: root.theme.mono
            font.pixelSize: root.theme.fsSmall
            font.letterSpacing: root.theme.labelSpacing
            font.capitalization: Font.AllUppercase
        }

        Flickable {
            anchors.top: planHead.bottom
            anchors.topMargin: root.theme.gap
            anchors.bottom: parent.bottom
            width: parent.width
            contentHeight: planCol.height
            clip: true
            Column {
                id: planCol
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.planMonths
                    delegate: Item {
                        id: pRow
                        required property var modelData
                        readonly property var buys: pRow.modelData.purchases || []
                        readonly property string cur: (root.fin && root.fin.planData.currency)
                            ? root.fin.planData.currency : "EUR"
                        width: planCol.width
                        height: pRow.buys.length ? 40 : 22

                        Text {                       // month label
                            id: pMonth
                            anchors.left: parent.left
                            y: 0
                            text: root.monthLabel(pRow.modelData.month)
                            color: root.theme.text
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: root.theme.labelSpacing
                        }
                        Text {                       // save Δ → projected balance
                            anchors.right: parent.right
                            y: 0
                            text: (root.fin ? (((pRow.modelData.net || 0) >= 0 ? "+" : "−")
                                    + root.fin.fmtAmount(Math.abs(pRow.modelData.net || 0), pRow.cur))
                                    : "")
                                  + "  →  " + (root.fin
                                    ? root.fin.fmtAmount(pRow.modelData.projected || 0, pRow.cur) : "")
                            color: root.theme.textDim
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                        Text {                       // cushion above the floor
                            anchors.left: pMonth.right
                            anchors.leftMargin: 10
                            y: 0
                            text: root.fin ? ("cushion " + root.fin.fmtAmount(
                                    pRow.modelData.cushion || 0, pRow.cur)) : ""
                            color: (pRow.modelData.cushion || 0) < 0 ? root.theme.danger
                                 : root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall - 2
                        }
                        Row {                        // buy: … (gold, only when purchases)
                            visible: pRow.buys.length > 0
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            spacing: 5
                            MSym {
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "shopping_bag"
                                size: 13
                                color: root.theme.money
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "buy: " + pRow.buys.join(", ")
                                color: root.theme.money
                                font.family: root.theme.family
                                font.pixelSize: root.theme.fsNormal
                            }
                        }
                    }
                }

                // items that never fit within the plan horizon
                Text {
                    visible: root.planUnbuyable.length > 0
                    text: "Not yet within reach:"
                    color: root.theme.textDim
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                    topPadding: 6
                }
                Repeater {
                    model: root.planUnbuyable
                    delegate: Item {
                        id: uRow
                        required property var modelData
                        width: planCol.width
                        height: 20
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: uRow.modelData.description
                            color: root.theme.text
                            font.family: root.theme.family
                            font.pixelSize: root.theme.fsNormal
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.fin && uRow.modelData.shortfall != null)
                                ? ("need " + root.fin.fmtAmount(uRow.modelData.shortfall,
                                    root.fin.planData.currency || "EUR") + " more")
                                : "no rate"
                            color: root.theme.faint
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                        }
                    }
                }

                Text {
                    visible: root.planMonths.length === 0
                    text: "No plan yet — set a buffer/goal in plan.conf and add a forecast."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.italic: true
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }
    }
}
