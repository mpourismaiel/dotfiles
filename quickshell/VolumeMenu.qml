pragma ComponentBehavior: Bound
// VolumeMenu.qml — Devices tab (speakers = Audio/Sink, mics = Audio/Source) with
// per-device volume/mute/set-default, and Applications tab (Stream/Output/Audio)
// with per-stream volume/mute. Uses Quickshell.Services.Pipewire. Node audio is
// kept live by the PwObjectTracker over every node.
import QtQuick
import Quickshell.Services.Pipewire

Item {
    id: root
    required property var theme
    property int tab: 0               // 0 = Devices, 1 = Applications

    PwObjectTracker { objects: Pipewire.nodes ? Pipewire.nodes.values : [] }

    function cls(n) { return (n && n.properties) ? (n.properties["media.class"] || "") : ""; }
    readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sinks:    allNodes.filter(n => root.cls(n) === "Audio/Sink")
    readonly property var sources:  allNodes.filter(n => root.cls(n) === "Audio/Source")
    readonly property var streams:  allNodes.filter(n => root.cls(n) === "Stream/Output/Audio")

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        Row {                                   // tabs
            spacing: 16
            Repeater {
                model: ["Devices", "Applications"]
                delegate: Text {
                    required property int index
                    required property string modelData
                    text: modelData
                    color: root.tab === index ? root.theme.accent : root.theme.textDim
                    font.pixelSize: root.theme.fsNormal
                    font.bold: root.tab === index
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.tab = index }
                }
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - 34
            contentHeight: col.height
            clip: true
            Column {
                id: col
                width: parent.width
                spacing: 12

                Repeater {
                    model: root.tab === 0 ? root.sinks.concat(root.sources) : root.streams
                    delegate: Column {
                        id: devCol
                        required property var modelData
                        width: col.width
                        spacing: 4

                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                width: parent.width - 46
                                elide: Text.ElideRight
                                text: {
                                    const n = devCol.modelData;
                                    if (root.tab === 1)
                                        return (n.properties && (n.properties["application.name"] || n.properties["media.name"])) || n.name;
                                    return n.description || n.nickname || n.name;
                                }
                                color: root.theme.text
                                font.pixelSize: root.theme.fsNormal
                            }
                            Text {                       // default device marker (devices tab)
                                visible: root.tab === 0
                                text: (devCol.modelData === Pipewire.defaultAudioSink
                                       || devCol.modelData === Pipewire.defaultAudioSource) ? "●" : "○"
                                color: root.theme.accent
                                font.pixelSize: root.theme.fsSmall
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.cls(devCol.modelData) === "Audio/Sink")
                                            Pipewire.preferredDefaultAudioSink = devCol.modelData;
                                        else
                                            Pipewire.preferredDefaultAudioSource = devCol.modelData;
                                    } }
                            }
                            Text {                       // mute toggle
                                text: (devCol.modelData.audio && devCol.modelData.audio.muted) ? "🔇" : "🔊"
                                font.pixelSize: root.theme.fsSmall
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (devCol.modelData.audio) devCol.modelData.audio.muted = !devCol.modelData.audio.muted }
                            }
                        }
                        PillSlider {
                            theme: root.theme
                            width: parent.width
                            value: devCol.modelData.audio ? devCol.modelData.audio.volume : 0
                            onMoved: v => { if (devCol.modelData.audio) devCol.modelData.audio.volume = v; }
                        }
                    }
                }
                Text {
                    visible: (root.tab === 0 ? (root.sinks.length + root.sources.length) : root.streams.length) === 0
                    text: root.tab === 0 ? "No audio devices" : "No apps playing audio"
                    color: root.theme.textDim
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }
    }
}
