pragma ComponentBehavior: Bound
// ClipboardMenu.qml — clipboard history (cliphist via Clipboard/clipbridge.py).
// Fuzzy search + Clear all at the top; a scrolling list below (ten newest at rest,
// all matches while searching). Image entries preview the picture (<=300px wide,
// centered on a rounded checker box when it doesn't fill it, fit when larger); text
// entries preview the text (fading out before an always-shown Delete label) with a
// "+N images" chip for embedded data:image screenshots. Row click copies + closes;
// Delete only removes.
import QtQuick
import Quickshell.Widgets

Item {
    id: root
    required property var theme
    required property var clip
    required property var memos           // permanent voice memos (Memos.qml)
    signal closeRequested()

    property int tab: 0                    // 0 = Clipboard, 1 = Memos

    Component.onCompleted: { root.clip.refresh(); root.memos.refresh(); search.forceActiveFocus(); }

    readonly property string q: search.text.trim().toLowerCase()

    // what a row is matched against: text preview, or a synthetic image label so
    // "png"/"image"/dimensions still find screenshots.
    function label(e) {
        return e.kind === "image" ? ("image " + e.w + "x" + e.h + " png") : (e.text || "");
    }
    // subsequence fuzzy match: -1 no match, else a score (adjacency rewarded).
    function fuzzy(needle, hay) {
        hay = hay.toLowerCase();
        if (needle.length === 0) return 0;
        let hi = 0, score = 0, run = 0;
        for (let ni = 0; ni < needle.length; ni++) {
            const c = needle[ni];
            let found = -1;
            for (let k = hi; k < hay.length; k++) { if (hay[k] === c) { found = k; break; } }
            if (found < 0) return -1;
            run = (found === hi) ? run + 1 : 0;
            score += 1 + run;
            hi = found + 1;
        }
        return score;
    }
    readonly property var shownClip: {
        const all = root.clip.entries || [];
        if (root.q.length === 0) return all.slice(0, 10);
        const scored = [];
        for (const e of all) { const s = root.fuzzy(root.q, root.label(e)); if (s >= 0) scored.push({ e: e, s: s }); }
        scored.sort((a, b) => b.s - a.s);
        return scored.map(x => x.e);
    }
    // memos: the full permanent store at rest (fuzzy-filtered while searching)
    readonly property var shownMemo: {
        const all = root.memos.entries || [];
        if (root.q.length === 0) return all;
        const scored = [];
        for (const e of all) { const s = root.fuzzy(root.q, (e.text || "") + " " + (e.type || "")); if (s >= 0) scored.push({ e: e, s: s }); }
        scored.sort((a, b) => b.s - a.s);
        return scored.map(x => x.e);
    }
    // the active list (drives keyboard nav + the empty-state text)
    readonly property var shown: root.tab === 1 ? root.shownMemo : root.shownClip

    // ---- keyboard selection (arrow-key navigation) ----
    // The list is vertical, so up/down move the row highlight while left/right stay
    // with the search field's text cursor (see the field's Keys handlers). Enter
    // copies the highlighted entry; a row click still copies directly. The selection
    // resets to the top on a new query and clamps if the shown set shrinks.
    property int currentIndex: 0
    onQChanged: root.currentIndex = 0
    onShownChanged: if (root.currentIndex > root.shown.length - 1) root.currentIndex = Math.max(0, root.shown.length - 1)
    function setSel(i) {
        const n = root.shown.length;
        root.currentIndex = n === 0 ? 0 : Math.max(0, Math.min(n - 1, i));
        const lv = root.tab === 1 ? memoView : listView;
        if (n > 0) lv.positionViewAtIndex(root.currentIndex, ListView.Contain);
    }
    function activateCurrent() {
        const n = root.shown.length;
        if (n === 0) return;
        const e = root.shown[Math.max(0, Math.min(n - 1, root.currentIndex))];
        if (root.tab === 1) root.memos.copy(e.id); else root.clip.copy(e.id);
        root.closeRequested();
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {
            theme: root.theme
            title: "Clipboard"
            onBack: root.closeRequested()
            Text {                                // Clear all — clipboard tab only
                anchors.verticalCenter: parent.verticalCenter
                visible: root.tab === 0 && (root.clip.entries || []).length > 0
                text: "Clear all"
                color: clearMa.containsMouse ? root.theme.danger : root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
                MouseArea {
                    id: clearMa
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.clip.wipe()
                }
            }
        }

        Row {                                    // tabs
            id: tabRow
            spacing: 18
            Repeater {
                model: ["Clipboard", "Memos"]
                delegate: Text {
                    required property int index
                    required property string modelData
                    text: modelData
                    color: root.tab === index ? root.theme.accent : root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.tab = index; root.currentIndex = 0; }
                    }
                }
            }
        }

        Rectangle {                              // fuzzy search field
            id: searchBox
            width: parent.width
            height: 40
            radius: root.theme.radiusRow
            color: root.theme.row
            border.color: search.activeFocus ? root.theme.accent : root.theme.border
            border.width: 1
            MSym {
                id: searchIcon
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                icon: "search"; size: 18
                color: search.activeFocus ? root.theme.accent : root.theme.faint
            }
            TextInput {
                id: search
                objectName: "pillKbInput"
                anchors.left: searchIcon.right; anchors.leftMargin: 8
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
                clip: true
                selectByMouse: true
                selectionColor: root.theme.accentDim
                Keys.onEscapePressed: root.closeRequested()
                // vertical list: up/down move the row highlight; left/right fall
                // through to the text cursor. Enter copies the highlighted entry
                // (a row click still copies directly).
                Keys.onUpPressed: root.setSel(root.currentIndex - 1)
                Keys.onDownPressed: root.setSel(root.currentIndex + 1)
                Keys.onReturnPressed: root.activateCurrent()
                Keys.onEnterPressed: root.activateCurrent()
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: root.tab === 1 ? "Search memos" : "Search clipboard"
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                    elide: Text.ElideRight
                }
            }
        }

        // ---- one history row: image preview, or text preview + Delete ----
        component ClipRow: Rectangle {
            id: clipRow
            required property var entry
            property bool selected: false
            width: parent ? parent.width : 0

            readonly property bool isImg: entry.kind === "image"
            // never upscale; cap both dimensions at 300 so tall/wide shots stay sane
            readonly property real imgScale: isImg ? Math.min(1, 300 / entry.w, 300 / entry.h) : 1
            readonly property int imgW: isImg ? Math.round(entry.w * imgScale) : 0
            readonly property int imgH: isImg ? Math.round(entry.h * imgScale) : 0

            height: isImg ? (imgH + 20) : root.theme.rowHeight
            radius: root.theme.radiusRow
            color: (clipRow.selected || rowMa.containsMouse) ? root.theme.rowHi : root.theme.row
            clip: true
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }

            // click anywhere = copy + close (declared first so it sits below the
            // Delete label's own MouseArea, which then wins over its region).
            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.clip.copy(clipRow.entry.id); root.closeRequested(); }
            }

            // image preview: rounded, checker-patterned box; image centered when it
            // doesn't fill 300px, fit when larger (see imgScale).
            ClippingRectangle {
                visible: clipRow.isImg
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 300; height: clipRow.imgH
                radius: root.theme.radiusCard
                color: root.theme.desk
                Canvas {                         // checkerboard, shows around small images
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        const s = 10, a = "#242019", b = "#1b1712";
                        for (let y = 0; y < height; y += s)
                            for (let x = 0; x < width; x += s) {
                                ctx.fillStyle = ((Math.floor(x / s) + Math.floor(y / s)) % 2 === 0) ? a : b;
                                ctx.fillRect(x, y, s, s);
                            }
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }
                Image {
                    anchors.centerIn: parent
                    width: clipRow.imgW; height: clipRow.imgH
                    source: clipRow.isImg ? ("file://" + clipRow.entry.path) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    sourceSize.width: clipRow.imgW
                    sourceSize.height: clipRow.imgH
                }
            }

            // text preview: optional "+N images" chip, then the text. The content
            // is hard-clipped well before the Delete label (so overflow can't bleed
            // through it), and the gradient softens that cut into the row colour so
            // the tail fades out instead of ending in a sharp edge.
            Item {
                id: textClip
                visible: !clipRow.isImg
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.right: delText.left; anchors.rightMargin: 12
                anchors.top: parent.top; anchors.bottom: parent.bottom
                clip: true
                Row {
                    id: textRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Rectangle {
                        visible: (clipRow.entry.images || 0) > 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: 20; width: chipT.implicitWidth + 14; radius: 6
                        color: root.theme.accentSoft
                        Text {
                            id: chipT
                            anchors.centerIn: parent
                            text: "+" + clipRow.entry.images + (clipRow.entry.images === 1 ? " image" : " images")
                            color: root.theme.accent
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (clipRow.entry.text && clipRow.entry.text.length) ? clipRow.entry.text
                            : ((clipRow.entry.images || 0) > 0 ? "" : "(empty)")
                        color: root.theme.text
                        font.family: root.theme.family
                        font.pixelSize: root.theme.fsNormal
                        // no elide — overflow is clipped by textClip and the gradient
                        // below fades the tail into the row colour
                    }
                }
                // fade the tail into the row colour at the clip edge
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: 56
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(clipRow.color.r, clipRow.color.g, clipRow.color.b, 0) }
                        GradientStop { position: 1.0; color: clipRow.color }
                    }
                }
            }

            // always-visible Delete (like Connect/Disconnect); removes only.
            Text {
                id: delText
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "Delete"
                color: delMa.containsMouse ? root.theme.danger : root.theme.textDim
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
                MouseArea {
                    id: delMa
                    anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.clip.remove(clipRow.entry.id)
                }
            }
        }

        // ---- one memo row: click to expand/collapse; copy/polish/delete buttons.
        // When expanded, the full text shows; a polished memo also offers a
        // "see unpolished" toggle (and copy then copies whichever is shown). ----
        component MemoRow: Rectangle {
            id: memoRow
            required property var entry
            property bool selected: false
            property bool expanded: false
            property bool showRaw: false
            // a polished memo carries its original transcript (entry.raw)
            readonly property bool hasRaw: !!(memoRow.entry.polished && memoRow.entry.raw && memoRow.entry.raw.length > 0)
            readonly property bool showToggle: memoRow.expanded && memoRow.hasRaw
            readonly property string shownText: (memoRow.showRaw && memoRow.hasRaw)
                                                ? memoRow.entry.raw : (memoRow.entry.text || "")

            width: parent ? parent.width : 0
            height: memoRow.expanded
                    ? (bodyText.y + bodyText.implicitHeight + (memoRow.showToggle ? toggleRow.height + 8 : 0) + 12)
                    : 50
            radius: root.theme.radiusRow
            color: (memoRow.selected || mRowMa.containsMouse) ? root.theme.rowHi : root.theme.row
            clip: true
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
            Behavior on height { NumberAnimation { duration: root.theme.animFast; easing.type: Easing.OutCubic } }

            // click the row body = expand/collapse (buttons keep their own actions)
            MouseArea {
                id: mRowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: memoRow.expanded = !memoRow.expanded
            }

            // header: type chip + time (+ polished), top-left
            Row {
                id: headerRow
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.top: parent.top; anchors.topMargin: 9
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18; width: chip.implicitWidth + 14; radius: 6
                    color: root.theme.accentSoft
                    Text {
                        id: chip
                        anchors.centerIn: parent
                        text: memoRow.entry.type || "note"
                        color: root.theme.accent
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const c = memoRow.entry.created || "";
                        const t = c ? c.replace("T", " ").slice(0, 16) : "";
                        return t + (memoRow.entry.polished ? " · polished" : "");
                    }
                    color: root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                }
            }

            // copy / polish / delete — aligned with the header line, top-right
            Row {
                id: memoActions
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.top: parent.top; anchors.topMargin: 4
                spacing: 2
                Repeater {
                    model: [
                        { ic: "content_copy",  act: "copy",   danger: false },
                        { ic: "auto_fix_high", act: "polish", danger: false },
                        { ic: "delete",        act: "delete", danger: true }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: 28; height: 28
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: aMa.containsMouse ? (parent.modelData.danger ? root.theme.danger : root.theme.bgHover) : "transparent"
                            Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                        }
                        MSym {
                            anchors.centerIn: parent
                            icon: parent.modelData.ic
                            size: 16
                            color: aMa.containsMouse ? root.theme.text : root.theme.faint
                        }
                        MouseArea {
                            id: aMa
                            anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = parent.modelData.act;
                                // copy the currently-shown version (polished or unpolished)
                                if (a === "copy") { root.memos.copyText(memoRow.shownText); root.closeRequested(); }
                                else if (a === "polish") root.memos.repolish(memoRow.entry.id);
                                else root.memos.remove(memoRow.entry.id);
                            }
                        }
                    }
                }
            }

            // body: 1-line preview when collapsed, full wrapped text when expanded
            Text {
                id: bodyText
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.top: headerRow.bottom; anchors.topMargin: 3
                // PlainText (not the default AutoText, which can pick RichText and
                // eat newlines). Collapsed: flatten whitespace for a one-line
                // preview; expanded: the real multi-line text.
                textFormat: Text.PlainText
                text: memoRow.expanded ? memoRow.shownText : memoRow.shownText.replace(/\s+/g, " ").trim()
                wrapMode: Text.Wrap
                maximumLineCount: memoRow.expanded ? 100000 : 1
                elide: memoRow.expanded ? Text.ElideNone : Text.ElideRight
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }

            // "see unpolished" / "see polished" toggle (expanded polished memos only)
            Row {
                id: toggleRow
                visible: memoRow.showToggle
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.top: bodyText.bottom; anchors.topMargin: 8
                height: 22
                Rectangle {
                    width: tgTxt.implicitWidth + 20; height: 22; radius: root.theme.radiusBtn
                    color: tgMa.containsMouse ? root.theme.rowHi : root.theme.row
                    border.width: 1; border.color: root.theme.border
                    Text {
                        id: tgTxt
                        anchors.centerIn: parent
                        text: memoRow.showRaw ? "See polished" : "See unpolished"
                        color: root.theme.textDim
                        font.family: root.theme.mono
                        font.pixelSize: root.theme.fsSmall
                        font.letterSpacing: root.theme.labelSpacing
                        font.capitalization: Font.AllUppercase
                    }
                    MouseArea {
                        id: tgMa
                        anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: memoRow.showRaw = !memoRow.showRaw
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: parent.height - 26 - tabRow.height - 40 - root.theme.gap * 3
            // clipboard list
            ListView {
                id: listView
                anchors.fill: parent
                visible: root.tab === 0
                clip: true
                spacing: 8
                model: root.shownClip
                currentIndex: root.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                delegate: ClipRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    entry: modelData
                    selected: index === root.currentIndex
                }
            }
            // memos list
            ListView {
                id: memoView
                anchors.fill: parent
                visible: root.tab === 1
                clip: true
                spacing: 8
                model: root.shownMemo
                currentIndex: root.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                delegate: MemoRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    entry: modelData
                    selected: index === root.currentIndex
                }
            }
            Text {
                anchors.top: parent.top
                visible: root.shown.length === 0
                text: root.q.length > 0 ? "No matches"
                    : (root.tab === 1 ? "No memos yet" : "Clipboard is empty")
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }
        }
    }
}
