pragma ComponentBehavior: Bound
// OnAirWave.qml — a horizontal "on-air" waveform across the vertical middle of the
// collapsed pill while a camera / screencast is live. Mic open => a wavy equalizer
// line whose amplitude tracks live voice input (accent, translucent); mic muted =>
// a flat straight line in the clock's colour, fainter still. See qs-pill-docs.org.
import QtQuick

Item {
    id: root
    required property var theme
    property bool active: false     // a camera or screencast is live
    property bool micOn: false      // default source not muted
    property real level: 0          // live mic peak, 0..1

    visible: active
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.theme.animFast } }

    // smoothed amplitude: 0 (=> flat line) when muted, else grows with the voice
    // level with a small floor so it keeps a gentle idle ripple even in near-silence.
    property real amp: micOn ? Math.max(0.12, Math.min(1, level * 1.6)) : 0
    Behavior on amp { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    // accent while live, the clock's own colour when muted; kept only lightly
    // transparent so the thin (1px) line still reads, the muted line a touch softer.
    property color waveColor: micOn
        ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.5)
        : Qt.rgba(root.theme.text.r,   root.theme.text.g,   root.theme.text.b,   0.05)
    Behavior on waveColor { ColorAnimation { duration: root.theme.anim } }

    property real phase: 0

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height, mid = h / 2;
            const maxA = Math.max(0, mid - 3);       // stay inside the pill
            ctx.lineWidth = 1;
            ctx.lineCap = "round";
            ctx.strokeStyle = root.waveColor;
            ctx.beginPath();
            for (let x = 0; x <= w; x += 2) {
                const t = w > 0 ? x / w : 0;
                const taper = Math.sin(Math.PI * t);  // fade the wave into both ends
                const y = mid
                    + Math.sin(t * 18 + root.phase)        * 0.6 * maxA * root.amp * taper
                    + Math.sin(t *  7 - root.phase * 1.7)  * 0.4 * maxA * root.amp * taper;
                if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.stroke();
        }
    }

    // scroll the wave only while live + unmuted; a muted (flat) line is static.
    Timer {
        running: root.visible && root.micOn
        interval: 33; repeat: true
        onTriggered: { root.phase += 0.35; cv.requestPaint(); }
    }
    // repaint on any state change so the muted/idle line is always current.
    onAmpChanged:       cv.requestPaint()
    onWaveColorChanged: cv.requestPaint()
    onWidthChanged:     cv.requestPaint()
    onHeightChanged:    cv.requestPaint()
    onVisibleChanged:   cv.requestPaint()
}
