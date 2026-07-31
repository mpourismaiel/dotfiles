pragma ComponentBehavior: Bound
// NotificationView.qml — one notification card. Generic notifications render two
// columns in a row:
//   left  = the notification image (200px wide, aspect kept) or, if none, the
//           app icon;
//   right = three rows — [summary | close X ringed by a circular countdown],
//           [body], [relative time | actions] — plus an inline-reply field when
//           the notification supports it (Telegram, KDE Connect).
// Voice-to-text cards (appName "Transcribe") swap all of that for a dedicated
// readout layout (see the `transcribe` block below). Used as the collapsed-pill
// morph (surface:false, transparent — the pill draws the background), as floating
// cards under an open pill, and as history rows.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Rectangle {
    id: root
    required property var theme
    required property var notifs
    required property var notification
    property bool showProgress: false      // show the countdown bar
    property bool inHistory: false          // X forgets instead of dismissing
    property bool surface: true             // draw own bg/border

    // ---- keyboard-selection state (driven by NotificationHistory) ----
    property bool selected: false           // this card is the pane's selection (highlight)
    property int focusedAction: -1          // index into `actionButtons` to ring; -1 = none
    property bool replyActive: false        // request focus for the inline-reply field
    signal replyEscaped()                   // reply field escaped (return focus to the card)
    signal cardClicked()                    // the card body was clicked (sync the selection)
    // non-default actions, in order — the buttons shown AND the Left/Right nav order
    readonly property var actionButtons: {
        const as = notification ? (notification.actions || []) : [];
        return as.filter(a => a && a.identifier !== "default");
    }
    onReplyActiveChanged: if (replyActive) reply.forceActiveFocus()

    // Resolve the image robustly: prefer an explicit file-path hint loaded as a
    // file:// URL (Flameshot & co. send the screenshot via `image-path`, which
    // Quickshell would otherwise route through its *icon* provider and drop),
    // else fall back to Quickshell's `image` (image-data provider URL / file://).
    function resolveImage(n) {
        if (!n) return "";
        const h = n.hints || {};
        const p = h["image-path"] || h["image_path"] || "";
        if (typeof p === "string" && p.length > 0) {
            if (p.indexOf("file:") === 0) return p;
            if (p.indexOf("/") === 0) return "file://" + p;   // bare absolute path
        }
        return (n.image && n.image.length > 0) ? n.image : "";
    }
    readonly property string imageSource: resolveImage(notification)
    readonly property bool hasImage: imageSource.length > 0
    readonly property bool critical: !!(notification && notification.urgency === 2)  // NotificationUrgency.Critical
    // Transcribe cards (the voice-to-text pipeline) render the dedicated readout
    // layout below instead of the generic two columns.
    readonly property bool transcribe: !!(notification && notification.appName === "Transcribe")
    // the raw transcript to copy: the bridge attaches it as the `x-transcript`
    // string hint (exact text), else fall back to un-escaping the markup body.
    readonly property string copyText: {
        const h = notification ? (notification.hints || {}) : {};
        const t = h["x-transcript"];
        if (typeof t === "string" && t.length > 0) return t;
        const b = (notification && notification.body) ? notification.body : "";
        return b.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
    }
    readonly property int imgMax: 100   // notification image fits within a 100px box

    // bodies render as StyledText (so apps' <b>/<i>/<a> markup works), but
    // StyledText is HTML — it collapses literal newlines to a space. Convert
    // them to <br/> so multi-line bodies (e.g. a polished transcript with a
    // requested line break) actually wrap. The clipboard/memo file keep the
    // real \n; this is display-only.
    function bodyMarkup(s) { return (s || "").replace(/\n/g, "<br/>"); }

    // copy the raw transcript to the clipboard, then close (dismiss a popup /
    // forget a history row). printf|wl-copy so any leading dash / newline in the
    // text is safe (no arg-as-option, no trailing newline).
    Process { id: copyProc }
    function copyAndClose() {
        if (root.copyText.length > 0) {
            copyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", root.copyText];
            copyProc.running = true;
        }
        if (root.inHistory) root.notifs.forget(root.notification);
        else root.notifs.dismiss(root.notification);
    }

    // countdown state lives in Notifications (keyed by id, so it survives the
    // deck's delegate rebuilds); the card just reads it for the bar.
    readonly property real timeoutMs: notifs ? notifs.timeoutFor(notification) : 0
    readonly property real progress: notifs ? notifs.progressFor(notification) : 0

    color: surface ? (selected ? theme.rowHi : theme.card) : "transparent"
    radius: theme.radiusCard
    border.width: surface ? 1 : 0
    // a keyboard selection rings the card in accent (no width change, so no layout jump)
    border.color: selected ? theme.accent : (critical ? theme.danger : (transcribe ? theme.accentSoft : theme.border))
    implicitWidth: 420
    implicitHeight: (root.transcribe ? tCard.height : Math.max(leftCol.height, rightCol.implicitHeight)) + theme.pad * 2

    // the "default" action fires on a body click (not shown as a button)
    readonly property var defaultAction: {
        const as = notification ? notification.actions : [];
        for (const a of as) if (a.identifier === "default") return a;
        return null;
    }
    MouseArea {
        anchors.fill: parent
        // stay hit-testable even with no default action so a click can still sync the
        // keyboard selection; only show the hand cursor when there IS a default action
        cursorShape: root.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.cardClicked();
            if (root.defaultAction) { root.defaultAction.invoke(); root.notifs.drop(root.notification); }
        }
    }

    // ---- left column: image (≤100px box, aspect kept) or app icon ----
    Item {
        id: leftCol
        visible: !root.transcribe
        x: root.theme.pad; y: root.theme.pad
        width: root.hasImage ? img.width : 48
        height: root.hasImage ? img.height : 48
        Image {
            id: img
            visible: root.hasImage
            source: root.imageSource
            asynchronous: false            // Quickshell's image-data provider serves
                                           // nothing on the async path (cf. Ricelin); a
                                           // partial sourceSize can also blank it, so omit it
            cache: true
            fillMode: Image.PreserveAspectFit
            // fit within a 100px box (keep aspect, never upscale a smaller image) —
            // stops an app's square avatar (e.g. an email sender) ballooning to 200px
            width: Math.min(root.imgMax, implicitWidth > 0 ? implicitWidth : root.imgMax)
            height: (implicitWidth > 0 && implicitHeight > 0)
                    ? Math.min(root.imgMax, width * implicitHeight / implicitWidth) : width
        }
        IconImage {
            visible: !root.hasImage
            anchors.top: parent.top
            implicitSize: 48
            // an absolute-path appIcon (notify-send -i /path/to.svg — the
            // Transcribe cards do this) loads directly as a file:// URL; icon
            // *names* keep going through the theme lookup.
            source: {
                const ic = root.notification ? (root.notification.appIcon || "") : "";
                if (ic.indexOf("file:") === 0) return ic;
                if (ic.indexOf("/") === 0) return "file://" + ic;
                return Quickshell.iconPath(ic, "dialog-information");
            }
        }
    }

    // ---- right column: three rows + optional reply ----
    Column {
        id: rightCol
        visible: !root.transcribe
        x: leftCol.x + leftCol.width + root.theme.gap
        y: root.theme.pad
        width: root.width - leftCol.width - root.theme.gap - root.theme.pad * 2
        spacing: 6

        // row 1: summary (left) + close X & countdown (right)
        Item {
            width: parent.width
            height: 26
            Text {
                anchors.left: parent.left
                anchors.right: closeBox.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: (root.notification && root.notification.summary && root.notification.summary.length > 0)
                      ? root.notification.summary
                      : (root.notification ? root.notification.appName : "")
                elide: Text.ElideRight
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
                font.bold: true
            }
            // close / dismiss button — a 26px circle holding the ✕; for live popups
            // the circle doubles as the countdown ring (a brighter arc, depleting
            // clockwise from the top as the timeout elapses).
            Item {
                id: closeBox
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26

                Rectangle {                          // hover fill
                    anchors.fill: parent
                    radius: width / 2
                    color: closeMa.containsMouse ? root.theme.bgHover : "transparent"
                    Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                }

                Shape {                              // circular countdown (popups only)
                    anchors.fill: parent
                    visible: root.showProgress && root.timeoutMs > 0
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {                      // dim full track
                        strokeColor: root.theme.bgHover
                        strokeWidth: 2
                        fillColor: "transparent"
                        PathAngleArc {
                            centerX: 13; centerY: 13; radiusX: 11; radiusY: 11
                            startAngle: 0; sweepAngle: 360
                        }
                    }
                    ShapePath {                      // remaining-time arc, shrinks to 0
                        strokeColor: root.critical ? root.theme.danger : root.theme.accent
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 13; centerY: 13; radiusX: 11; radiusY: 11
                            startAngle: -90; sweepAngle: 360 * root.progress
                        }
                    }
                }

                MSym {
                    anchors.centerIn: parent
                    icon: "close"
                    size: 17
                    color: closeMa.containsMouse ? root.theme.text : root.theme.faint
                }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.inHistory ? root.notifs.forget(root.notification)
                                              : root.notifs.dismiss(root.notification)
                }
            }
        }

        // row 2: body (6-line clamp for generic cards)
        Text {
            width: parent.width
            visible: text.length > 0
            text: root.bodyMarkup(root.notification ? root.notification.body : "")
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
            color: root.theme.textDim
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
            onLinkActivated: link => Qt.openUrlExternally(link)
        }

        // row 3: relative time (left) + actions (right)
        Item {
            width: parent.width
            height: Math.max(actionRow.height, 18)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.notification ? root.notifs.relTime(root.notification.id) : ""
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }
            Row {
                id: actionRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7
                Repeater {
                    model: root.actionButtons
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        // first action reads as the primary (accent) button
                        readonly property bool primary: index === 0
                        // keyboard-focused action: an accent ring (Left/Right nav)
                        readonly property bool focused: root.focusedAction === index
                        width: actLabel.implicitWidth + 24
                        height: 26; radius: root.theme.radiusBtn
                        color: primary ? (actMa.containsMouse ? root.theme.danger : root.theme.accent)
                                       : (actMa.containsMouse ? root.theme.rowHi : root.theme.row)
                        border.color: focused ? root.theme.accent : root.theme.border
                        border.width: focused ? 2 : (primary ? 0 : 1)
                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: modelData.text
                            color: parent.primary ? "#ffffff" : root.theme.text
                            font.family: root.theme.mono
                            font.pixelSize: root.theme.fsSmall
                            font.letterSpacing: root.theme.labelSpacing
                            font.capitalization: Font.AllUppercase
                        }
                        MouseArea {
                            id: actMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { modelData.invoke(); root.notifs.drop(root.notification); }
                        }
                    }
                }
            }
        }

        // inline reply (Telegram / KDE Connect) — Enter sends, then dismisses
        Rectangle {
            width: parent.width
            visible: !!(root.notification && root.notification.hasInlineReply)
            height: visible ? 32 : 0
            radius: root.theme.radiusRow
            color: root.theme.row
            border.width: 1
            border.color: reply.activeFocus ? root.theme.accent : root.theme.border
            TextInput {
                id: reply
                objectName: "pillKbInput"
                anchors.fill: parent
                anchors.leftMargin: 10; anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
                clip: true
                // Escape hands focus back to the card (the pane refocuses its key
                // sink); it does NOT close the pane while the field is focused.
                Keys.onEscapePressed: root.replyEscaped()
                onAccepted: {
                    if (text.length > 0) {
                        root.notification.sendInlineReply(text);
                        text = "";
                        root.notifs.drop(root.notification);
                    }
                }
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: reply.text.length === 0
                    text: (root.notification && root.notification.inlineReplyPlaceholder
                           && root.notification.inlineReplyPlaceholder.length > 0)
                          ? root.notification.inlineReplyPlaceholder : "Reply…"
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ================= voice-to-text readout (Transcribe cards) =================
    // A dedicated layout, distinct from every other notification: an equalizer
    // motif + mono status label header, the transcript in an inset "screen"
    // panel, and copy / close buttons. Replaces the two-column card above when
    // appName === "Transcribe".
    Column {
        id: tCard
        visible: root.transcribe
        x: root.theme.pad
        y: root.theme.pad
        width: root.width - root.theme.pad * 2
        spacing: 10

        // ---- header: equalizer + status label (left) | copy + close (right) ----
        Item {
            width: parent.width
            height: 24

            Row {
                id: eqRow                               // little equalizer signature
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: [0.45, 0.9, 0.6, 1.0, 0.5, 0.8, 0.35]
                    delegate: Rectangle {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: Math.round(16 * modelData)
                        radius: 1
                        color: root.critical ? root.theme.danger : root.theme.accent
                    }
                }
            }
            Text {                                      // status label — elided so a long
                anchors.left: eqRow.right               // failure summary can't run under
                anchors.leftMargin: 9                   // the buttons
                anchors.right: tBtns.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: (root.notification && root.notification.summary && root.notification.summary.length > 0)
                      ? root.notification.summary : "Transcribe"
                color: root.critical ? root.theme.danger : root.theme.text
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }

            Row {
                id: tBtns
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // copy the transcript + close (only when there is text to copy)
                Item {
                    visible: root.copyText.length > 0
                    width: 26; height: 26
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: copyMa.containsMouse ? root.theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                    MSym {
                        anchors.centerIn: parent
                        icon: "content_copy"
                        size: 16
                        color: copyMa.containsMouse ? root.theme.text : root.theme.faint
                    }
                    MouseArea {
                        id: copyMa
                        anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.copyAndClose()
                    }
                }

                // close — same 26px circle + countdown ring as the generic card
                Item {
                    width: 26; height: 26
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: tCloseMa.containsMouse ? root.theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: root.theme.animFast } }
                    }
                    Shape {
                        anchors.fill: parent
                        visible: root.showProgress && root.timeoutMs > 0
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: root.theme.bgHover
                            strokeWidth: 2
                            fillColor: "transparent"
                            PathAngleArc { centerX: 13; centerY: 13; radiusX: 11; radiusY: 11; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeColor: root.critical ? root.theme.danger : root.theme.accent
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 13; centerY: 13; radiusX: 11; radiusY: 11; startAngle: -90; sweepAngle: 360 * root.progress }
                        }
                    }
                    MSym {
                        anchors.centerIn: parent
                        icon: "close"
                        size: 17
                        color: tCloseMa.containsMouse ? root.theme.text : root.theme.faint
                    }
                    MouseArea {
                        id: tCloseMa
                        anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.inHistory ? root.notifs.forget(root.notification)
                                                  : root.notifs.dismiss(root.notification)
                    }
                }
            }
        }

        // ---- the transcript itself, in an inset screen-like panel ----
        Rectangle {
            width: parent.width
            height: tBody.implicitHeight + 22
            radius: root.theme.radiusRow
            color: root.theme.desk                 // deepest wash — reads like a readout
            border.width: 1
            border.color: root.theme.border
            Text {
                id: tBody
                x: 12; y: 11
                width: parent.width - 24
                text: root.bodyMarkup(root.notification ? root.notification.body : "")
                textFormat: Text.StyledText
                wrapMode: Text.Wrap                // FULL transcript, never truncated
                color: root.critical ? root.theme.textDim : root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }

        // ---- footer: relative time (left) + a copy hint (right) ----
        Item {
            width: parent.width
            height: 12
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.notification ? root.notifs.relTime(root.notification.id) : ""
                color: root.theme.faint
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.copyText.length > 0
                text: "on clipboard"
                color: root.theme.faint
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }
        }
    }
}
