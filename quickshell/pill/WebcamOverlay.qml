pragma ComponentBehavior: Bound
// WebcamOverlay.qml — a live webcam rendered onto the record overlay, so it is
// captured into the recording (gpsr records the whole composited output; it does
// NOT composite the camera itself). Draggable to reposition (config only), rounded
// + shadowed + adjustable opacity via MultiEffect. QtMultimedia ships with
// Quickshell 0.3.0 (libquickmultimediaplugin). `preview` gates the real device so
// the headless harness can render a placeholder without opening /dev/video*.
import QtQuick
import QtQuick.Effects
import QtMultimedia

Item {
    id: web
    required property var theme
    required property var rc
    property bool preview: true       // false in the harness -> placeholder only
    property bool draggable: true
    // gate for actually OPENING /dev/video*: the owner sets this false when the
    // capture isn't live (config/recording), so the camera is released the moment
    // the record controls close — otherwise the device stays powered while idle.
    property bool live: true

    x: rc.webcamX; y: rc.webcamY
    width: rc.webcamW; height: rc.webcamH
    visible: rc.webcamOn

    MediaDevices { id: media }
    readonly property var device: {
        const vs = media.videoInputs;
        if (!vs || !vs.length) return null;
        if (rc.webcamDev)
            for (let i = 0; i < vs.length; i++) if (vs[i].id === rc.webcamDev) return vs[i];
        return vs[0];
    }
    readonly property bool cameraLive: web.preview && web.live && web.rc.webcamOn && web.device !== null

    // visual source (rendered offscreen, shown through the MultiEffect)
    Item {
        id: src
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        visible: false
        Rectangle { anchors.fill: parent; color: web.theme.bg }
        Loader {
            anchors.fill: parent
            active: web.cameraLive
            sourceComponent: Component {
                Item {
                    CaptureSession {
                        camera: Camera { cameraDevice: web.device; active: true }
                        videoOutput: vo
                    }
                    VideoOutput { id: vo; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                }
            }
        }
        Column {
            anchors.centerIn: parent
            visible: !web.cameraLive
            spacing: 6
            MSym { anchors.horizontalCenter: parent.horizontalCenter
                   icon: "videocam"; size: 34; color: web.theme.textDim }
            Text { anchors.horizontalCenter: parent.horizontalCenter
                   text: web.device ? "webcam" : "no camera"
                   color: web.theme.faint; font.family: web.theme.family; font.pixelSize: web.theme.fsSmall }
        }
    }

    // rounded-corner mask
    Item {
        id: maskSrc
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: web.rc.webcamRoundEff; color: "black" }
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        maskEnabled: true
        maskSource: maskSrc
        shadowEnabled: web.rc.webcamShadow
        shadowColor: Qt.rgba(0, 0, 0, 0.6)
        shadowBlur: 0.8
        shadowVerticalOffset: 4
        opacity: web.rc.webcamOpacity
    }

    // hairline border (follows the rounding)
    Rectangle {
        anchors.fill: parent
        radius: web.rc.webcamRoundEff
        color: "transparent"
        border.color: web.theme.border
        border.width: 1
        opacity: web.rc.webcamOpacity
    }

    // drag to reposition (config only) — updates rc, so `x: rc.webcamX` follows and
    // the binding is never broken (unlike drag.target on a bound x).
    property real _dx: 0
    property real _dy: 0
    MouseArea {
        anchors.fill: parent
        enabled: web.draggable
        cursorShape: Qt.OpenHandCursor
        onPressed: (e) => { web._dx = e.x; web._dy = e.y; }
        onPositionChanged: (e) => {
            if (!(e.buttons & Qt.LeftButton)) return;
            const p = mapToItem(web.parent, e.x, e.y);
            web.rc.webcamX = p.x - web._dx;
            web.rc.webcamY = p.y - web._dy;
        }
    }
}
