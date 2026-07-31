pragma ComponentBehavior: Bound
// VoiceRecorderPill.qml — the iPhone-voice-memo face the resting pill morphs into
// while a voice note is recording (pulsing dot + m:ss timer + rolling-bar waveform
// fed by the live mic peak), and the busy face while the take transcribes. Hover
// fades the face and reveals a stop glyph; a click stops the take (raw route).
import QtQuick

Item {
    id: root
    required property var theme
    property string mode: "recording"   // "recording" | "transcribing"
    property real level: 0              // live mic peak, 0..1 (PwNodePeakMonitor)
    property int seconds: 0             // elapsed recording time (root-owned)
    signal stopRequested()

    readonly property bool recording: mode === "recording"
    readonly property string clockText: Math.floor(seconds / 60) + ":" + ("" + (seconds % 60)).padStart(2, "0")
    // the pill is a stadium (fully rounded ends, corner radius = height/2); keep
    // full-height content inside the straight middle section so nothing pokes past
    // the rounded ends and the busy stripe fills edge-to-edge cleanly.
    readonly property int endPad: Math.round(height / 2)

    // rolling peak history — one bar per 50ms sample, newest last / rightmost;
    // sized to however many 3px slots (2px bar + 1px gap) fit the canvas.
    property var peaks: []
    Timer {
        interval: 50; repeat: true
        running: root.recording && root.visible
        onTriggered: {
            const a = root.peaks;
            a.push(Math.min(1, root.level * 1.6));
            const cap = Math.max(8, Math.floor(cv.width / 3));
            while (a.length > cap) a.shift();
            root.peaks = a;
            cv.requestPaint();
        }
    }
    onModeChanged: if (!recording) { peaks = []; cv.requestPaint(); }

    // all faces live inside the straight middle section (inset by the corner
    // radius) so full-height content — the waveform, the busy stripe — fills the
    // pill edge-to-edge without poking past the rounded ends.
    Item {
        id: content
        anchors.fill: parent
        anchors.leftMargin: root.endPad
        anchors.rightMargin: root.endPad

        // ---- recording face: dot + timer + waveform (recedes under the stop glyph) ----
        Item {
            anchors.fill: parent
            visible: root.recording
            opacity: ma.containsMouse ? 0.25 : 1
            Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }

            // pulsing record dot — breathes while the take runs
            Rectangle {
                id: recDot
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: root.theme.danger
                SequentialAnimation on opacity {
                    running: root.recording
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            Text {
                id: clockTxt
                anchors.verticalCenter: parent.verticalCenter
                x: recDot.width + 8
                text: root.clockText
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsNormal
            }

            // the rolling waveform fills whatever is left of the row
            Canvas {
                id: cv
                x: clockTxt.x + clockTxt.width + 10
                width: Math.max(0, parent.width - x)
                height: parent.height
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const h = height, mid = h / 2, maxH = Math.max(2, h - 10);
                    ctx.fillStyle = Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.75);
                    const list = root.peaks;
                    for (let i = 0; i < list.length; i++) {
                        const bx = width - (list.length - i) * 3;
                        if (bx < 0) continue;
                        const bh = Math.max(2, list[i] * maxH);
                        ctx.fillRect(bx, mid - bh / 2, 2, bh);
                    }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
        }

        // ---- stop affordance: fades in over the receded face on hover ----
        MSym {
            anchors.centerIn: parent
            icon: "stop"
            fill: 1
            size: 20
            color: root.theme.text
            opacity: root.recording && ma.containsMouse ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }
        }

    }

    // ---- transcribing face: a barber-pole that fills the WHOLE pill, rounded
    // ends included. Drawn inline (not BusyStripe) so it can clip to the stadium
    // shape and set its own opacity — a BusyStripe filling the pill would leave
    // the two rounded end-caps bare. ----
    property real stripePhase: 0
    NumberAnimation on stripePhase {
        running: root.mode === "transcribing"
        from: 0; to: 22; duration: 640; loops: Animation.Infinite
    }
    onStripePhaseChanged: busyCv.requestPaint()
    Canvas {
        id: busyCv
        anchors.fill: parent
        visible: root.mode === "transcribing"
        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            if (w <= 0 || h <= 0) return;
            const r = Math.min(w, h) / 2;
            // clip to the stadium so the stripes reach into the rounded ends
            ctx.beginPath();
            ctx.moveTo(r, 0);
            ctx.lineTo(w - r, 0);
            ctx.arc(w - r, r, r, -Math.PI / 2, Math.PI / 2);
            ctx.lineTo(r, h);
            ctx.arc(r, r, r, Math.PI / 2, -Math.PI / 2);
            ctx.closePath();
            ctx.clip();
            // slanted bars, offset by the looping phase for continuous motion
            const gap = 22, barW = 11, slant = h * 1.6;
            ctx.fillStyle = Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.28);
            for (let x = -slant - gap; x < w + gap; x += gap) {
                const xx = x + root.stripePhase;
                ctx.beginPath();
                ctx.moveTo(xx, h);
                ctx.lineTo(xx + barW, h);
                ctx.lineTo(xx + barW + slant, 0);
                ctx.lineTo(xx + slant, 0);
                ctx.closePath();
                ctx.fill();
            }
        }
    }
    Text {
        anchors.centerIn: parent
        visible: root.mode === "transcribing"
        text: "Transcribing…"
        color: root.theme.text
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.letterSpacing: root.theme.labelSpacing
        font.capitalization: Font.AllUppercase
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.recording
        cursorShape: Qt.PointingHandCursor
        onClicked: root.stopRequested()
    }
}
