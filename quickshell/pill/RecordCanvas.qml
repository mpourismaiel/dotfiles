pragma ComponentBehavior: Bound
// RecordCanvas.qml — the fullscreen part of screen-record: a transparent overlay
// (the live desktop shows through) with an optional region rubber-band and the
// on-screen webcam (captured into the recording). The SETTINGS (sources, quality,
// webcam config, Record button) live in the PILL now (RecordControls), and there is
// no on-canvas REC timer — the pill's capture button stops recording. This window
// just handles what must be full-screen: region drawing + the webcam preview.
import QtQuick

Item {
    id: rec
    required property var state
    required property var theme
    required property var rc
    property bool preview: true          // false in a headless harness (placeholder webcam)

    focus: true
    Keys.onEscapePressed: if (rec.state.mode === "recConfig") rec.state.cancel()

    readonly property bool config: rec.state.mode === "recConfig"
    readonly property bool live: rec.state.mode === "recording"
    readonly property rect r: rec.state.region
    readonly property bool hasRegion: r.width > 1 && r.height > 1

    // feed screen size to the controller (for the webcam collision gate + corner snap)
    onWidthChanged: rec.rc.screenW = width
    onHeightChanged: rec.rc.screenH = height
    Component.onCompleted: { rec.rc.screenW = width; rec.rc.screenH = height; }

    // ---- region rubber-band (only when "Select area" is on) ----------------
    property real _sx: 0
    property real _sy: 0
    MouseArea {
        anchors.fill: parent
        enabled: rec.config && rec.rc.useRegion
        cursorShape: Qt.CrossCursor
        onPressed: (e) => { rec._sx = e.x; rec._sy = e.y; rec.state.region = Qt.rect(e.x, e.y, 0, 0); }
        onPositionChanged: (e) => rec.state.region = Qt.rect(
            Math.min(rec._sx, e.x), Math.min(rec._sy, e.y),
            Math.abs(e.x - rec._sx), Math.abs(e.y - rec._sy))
    }
    // region outline + dim outside
    Item {
        anchors.fill: parent
        visible: rec.config && rec.rc.useRegion && rec.hasRegion
        Rectangle { color: Qt.rgba(0,0,0,0.35); x:0; y:0; width: parent.width; height: rec.r.y }
        Rectangle { color: Qt.rgba(0,0,0,0.35); x:0; y: rec.r.y+rec.r.height; width: parent.width; height: parent.height-(rec.r.y+rec.r.height) }
        Rectangle { color: Qt.rgba(0,0,0,0.35); x:0; y: rec.r.y; width: rec.r.x; height: rec.r.height }
        Rectangle { color: Qt.rgba(0,0,0,0.35); x: rec.r.x+rec.r.width; y: rec.r.y; width: parent.width-(rec.r.x+rec.r.width); height: rec.r.height }
        Rectangle { x: rec.r.x; y: rec.r.y; width: rec.r.width; height: rec.r.height
                    color: "transparent"; border.color: rec.theme.accent; border.width: 2 }
    }

    // ---- region 8-point resize + middle-drag move (once an area exists) -----
    // Declared AFTER the full-screen rubber-band, so grabbing INSIDE the region
    // moves/resizes it while a drag OUTSIDE still draws a fresh one.
    ResizeHandles {
        theme: rec.theme
        active: rec.config && rec.rc.useRegion && rec.hasRegion
        rect_: rec.state.region
        boundW: rec.width; boundH: rec.height
        minW: 40; minH: 40
        moveEnabled: true
        onChanged: (r) => rec.state.region = r
    }

    // ---- the on-screen webcam (captured into the recording) ----------------
    WebcamOverlay {
        id: webcam
        visible: rec.rc.webcamOn && (rec.config || rec.live)
        theme: rec.theme
        rc: rec.rc
        preview: rec.preview
        // open /dev/video* ONLY while configuring or recording; released the moment
        // the record controls close (mode leaves recConfig/recording) so the camera
        // light doesn't stay on while the pill is idle.
        live: rec.config || rec.live
        draggable: rec.config          // reposition only while configuring
    }
    // webcam 8-point resize grips (the overlay owns its own middle-drag, so the
    // move area here stays off — clicks in the middle fall through to the camera).
    ResizeHandles {
        theme: rec.theme
        active: rec.config && rec.rc.webcamOn
        rect_: Qt.rect(rec.rc.webcamX, rec.rc.webcamY, rec.rc.webcamW, rec.rc.webcamH)
        boundW: rec.width; boundH: rec.height
        minW: 120; minH: 90
        moveEnabled: false
        onChanged: (r) => {
            rec.rc.webcamX = r.x; rec.rc.webcamY = r.y;
            rec.rc.webcamW = r.width; rec.rc.webcamH = r.height;
        }
    }
}
