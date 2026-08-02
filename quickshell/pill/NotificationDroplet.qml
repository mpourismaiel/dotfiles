pragma ComponentBehavior: Bound
// NotificationDroplet.qml — a stylised "water droplet" that wells out of the
// resting pill's bottom lip when a notification arrives and then *expands into the
// notification card* just below it. It replaces the old pill-morph (which took the
// pill over and made the clock / dashboard inaccessible): the pill stays put and
// the notification visibly grows out of it, so nothing appears from nowhere.
//
// The drop is intentionally *short* — its top never falls more than `fallDistance`
// (a handful of px) below the pill — and its colour runs the pill's own sequence:
// it starts as the pill background, tints to the accent as it pinches off and
// falls, then settles to the card colour as it expands into the card footprint.
// The real card fades in over that expanded rect (same size/colour/position), so
// the rectangle literally *becomes* the notification. `landed()` fires the instant
// the expand begins so the caller can sync the card's fade-in to it.
//
// Geometry: the caller centres this Item horizontally on the pill and anchors its
// TOP to the pill's bottom lip; the droplet is drawn around x = width/2, y = 0.
// The final expand grows to `cardWidth`×`cardHeight` (the top card's size) with
// `cardRadius` corners, which — because both are centred on the same axis — lands
// exactly over the real card floating `fallDistance` below.
import QtQuick

Item {
    id: root
    required property var theme
    // how far the drop's TOP may fall below the pill lip before it expands into the
    // card (kept small — the card floats this far below the pill).
    property real fallDistance: 8
    // the card footprint the drop expands into (the top notification card).
    property real cardWidth: 420
    property real cardHeight: 88
    property real cardRadius: theme.radiusCard
    // colour sequence: pill background → accent (brick orange) → card colour.
    property color bgColor: theme.bg
    property color accentColor: theme.accent
    property color cardColor: theme.card
    signal landed()

    // ---- animated state (driven by `anim`) ----
    property real by: 0        // blob TOP, relative to the pill lip (y grows downward)
    property real bw: 22       // blob width
    property real bh: 4        // blob height
    property real nw: 16       // neck width (the thread still joined to the pill)
    property real dropOpacity: 0
    property color blobColor: bgColor

    function play() {
        anim.stop();
        root.by = 0; root.bw = 22; root.bh = 4; root.nw = 16;
        root.dropOpacity = 0; root.blobColor = root.bgColor;
        anim.start();
    }

    // clear the drop (call when the resting notification goes away) — the expanded
    // rect otherwise stays as an opaque card-coloured backing behind the deck.
    function reset() {
        anim.stop();
        root.dropOpacity = 0;
        root.by = 0; root.bw = 22; root.bh = 4; root.nw = 16;
    }

    // the neck: a tapering thread from the pill lip (y=0) down to the blob's top,
    // rendered under the blob; it vanishes once the drop pinches off.
    Rectangle {
        id: neck
        x: root.width / 2 - width / 2
        y: 0
        width: root.nw
        height: Math.max(0, root.by)
        radius: width / 2
        color: root.blobColor
        opacity: root.dropOpacity
        antialiasing: true
    }

    // the blob → which expands into the card rectangle. `radius: cardRadius` is
    // clamped by Qt to half the smaller side, so a small blob reads fully rounded
    // and the expanded rect gets proper card corners.
    Rectangle {
        id: blob
        x: root.width / 2 - width / 2
        y: root.by
        width: root.bw
        height: root.bh
        radius: root.cardRadius
        color: root.blobColor
        opacity: root.dropOpacity
        antialiasing: true
    }

    // swell (bg colour) → pinch off + tint to accent → short fall → expand into the
    // card (accent → card colour) while emitting landed() so the card fades in over
    // it. A final fade removes the blob once the real card (same colour) covers it.
    SequentialAnimation {
        id: anim
        PropertyAction { target: root; property: "dropOpacity"; value: 1 }
        PropertyAction { target: root; property: "blobColor"; value: root.bgColor }
        // 1: swell into a hanging teardrop, still the pill's own background colour
        ParallelAnimation {
            NumberAnimation { target: root; property: "by"; to: root.fallDistance * 0.55; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "bw"; to: 16; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "bh"; to: 16; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "nw"; to: 9;  duration: 150; easing.type: Easing.OutQuad }
        }
        // 2: pinch the neck off and tint to the accent
        ParallelAnimation {
            NumberAnimation { target: root; property: "nw"; to: 0;  duration: 95; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "bw"; to: 14; duration: 95; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "bh"; to: 17; duration: 95; easing.type: Easing.OutQuad }
            ColorAnimation  { target: root; property: "blobColor"; to: root.accentColor; duration: 130 }
        }
        // 3: a short fall to the card's top, squashing a touch on arrival
        ParallelAnimation {
            NumberAnimation { target: root; property: "by"; to: root.fallDistance; duration: 105; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "bh"; to: 14; duration: 105; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "bw"; to: 18; duration: 105; easing.type: Easing.OutQuad }
        }
        // the drop reaches the card — cue the caller. The card fades in *behind a
        // short lead delay* (see init.qml), so the accent rect grows to the full card
        // footprint FIRST, then the card content resolves over this opaque backing.
        ScriptAction { script: root.landed() }
        // 4: expand into the card footprint, tinting from accent to the card colour.
        // The blob stays opaque afterwards as the card's backing; reset() clears it.
        ParallelAnimation {
            NumberAnimation { target: root; property: "bw"; to: root.cardWidth;  duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bh"; to: root.cardHeight; duration: 220; easing.type: Easing.OutCubic }
            ColorAnimation  { target: root; property: "blobColor"; to: root.cardColor; duration: 200 }
        }
    }
}
