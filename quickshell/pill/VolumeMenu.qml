pragma ComponentBehavior: Bound
// VolumeMenu.qml — Devices tab (speakers = Audio/Sink, mics = Audio/Source) with
// per-device volume/mute/set-default, and Applications tab (Stream/Output/Audio)
// with per-stream volume/mute. Uses Quickshell.Services.Pipewire. Node audio is
// kept live by the PwObjectTracker over every node.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: root
    required property var theme
    // the shared launcher-settings JsonAdapter (init.qml) — the Transcribe tab
    // reads/writes the voice-pipeline keys on it; mutations auto-persist.
    property var settings: null
    // in-pill setup state (VoiceSetup: cloud keys + local-model download)
    property var setup: null
    signal closeRequested()
    property int tab: 0               // 0 = Devices, 1 = Applications, 2 = Transcribe

    // refresh key/model availability whenever the Transcribe tab is shown
    onTabChanged: if (tab === 2 && root.setup) root.setup.refresh()

    // open KDE's audio settings. KDE ships two: "Audio" (kcm_pulseaudio, the
    // volume/devices module) and "Multimedia" (kcm_phonon, backend/device order).
    // Try Plasma 6's kcmshell6, then systemsettings, then the Plasma 5 variants.
    Process { id: settingsProc }
    function openAudioSettings(kcm) {
        settingsProc.command = ["sh", "-c",
            "kcmshell6 " + kcm + " || systemsettings " + kcm + " || kcmshell5 " + kcm];
        settingsProc.startDetached();
        root.closeRequested();
    }

    PwObjectTracker { objects: Pipewire.nodes ? Pipewire.nodes.values : [] }

    function cls(n) { return (n && n.properties) ? (n.properties["media.class"] || "") : ""; }
    readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sinks:    allNodes.filter(n => root.cls(n) === "Audio/Sink")
    readonly property var sources:  allNodes.filter(n => root.cls(n) === "Audio/Source")
    readonly property var streams:  allNodes.filter(n => root.cls(n) === "Stream/Output/Audio")

    // the display name a row shows — the same string the search matches against
    function nodeLabel(n, isStream) {
        if (isStream)
            return (n.properties && (n.properties["application.name"] || n.properties["media.name"])) || n.name;
        return n.description || n.nickname || n.name;
    }

    // ---- search: one query filters every section (speakers / microphones on the
    // Devices tab, the Applications tab); a section's label survives only while
    // it still has matches. The Transcribe tab is settings, not a list — the
    // search row hides there ----
    function matches(s) { return search.text === "" || (s || "").toLowerCase().includes(search.text.toLowerCase()); }
    readonly property var fSinks:   sinks.filter(n => root.matches(root.nodeLabel(n, false)))
    readonly property var fSources: sources.filter(n => root.matches(root.nodeLabel(n, false)))
    readonly property var fStreams: streams.filter(n => root.matches(root.nodeLabel(n, true)))

    // one device/stream row: name + (default marker) + mute over a volume slider,
    // reused by the Speakers / Microphones / Applications sections.
    component NodeRow: Column {
        required property var node
        property bool showDefault: false
        property bool isStream: false
        width: parent ? parent.width : 0
        spacing: 4
        Row {
            width: parent.width
            spacing: 6
            Text {
                width: parent.width - 46
                elide: Text.ElideRight
                text: root.nodeLabel(node, isStream)
                color: root.theme.text
                font.family: root.theme.family
                font.pixelSize: root.theme.fsNormal
            }
            MSym {                       // default-device marker (devices only)
                anchors.verticalCenter: parent.verticalCenter
                visible: showDefault
                readonly property bool isDefault: node === Pipewire.defaultAudioSink
                       || node === Pipewire.defaultAudioSource
                readonly property bool kbFocusable: true
                property bool kbFocused: false
                function keyClick() {
                    if (root.cls(node) === "Audio/Sink")
                        Pipewire.preferredDefaultAudioSink = node;
                    else
                        Pipewire.preferredDefaultAudioSource = node;
                }
                icon: isDefault ? "radio_button_checked" : "radio_button_unchecked"
                size: 16
                color: isDefault ? root.theme.accent : kbFocused ? root.theme.text : root.theme.faint
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: parent.keyClick() }
            }
            MSym {                       // mute toggle
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool muted: node.audio && node.audio.muted
                readonly property bool kbFocusable: true
                property bool kbFocused: false
                function keyClick() { if (node.audio) node.audio.muted = !node.audio.muted; }
                icon: muted ? "volume_off" : "volume_up"
                size: 17
                fill: muted ? 0 : 1
                color: kbFocused ? root.theme.text : muted ? root.theme.faint : root.theme.textDim
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: parent.keyClick() }
            }
        }
        PillSlider {
            theme: root.theme
            width: parent.width
            value: node.audio ? node.audio.volume : 0
            onMoved: v => { if (node.audio) node.audio.volume = v; }
        }
    }

    component VolLabel: Text {
        color: root.theme.faint
        font.family: root.theme.mono
        font.pixelSize: root.theme.fsSmall
        font.letterSpacing: root.theme.labelSpacing
        font.capitalization: Font.AllUppercase
    }

    // one Transcribe-tab settings row: label left, a PillToggle right.
    component ToggleRow: Item {
        id: tgl
        property string label: ""
        property bool checked: false
        signal toggled(bool value)
        width: parent ? parent.width : 0
        height: 24
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: tgl.label
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }
        PillToggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            checked: tgl.checked
            onToggled: v => tgl.toggled(v)
        }
    }

    // one Transcribe-tab settings row: label left, a click-to-cycle chip right
    // (steps through `options` on click — the menu's no-text-entry idiom, so the
    // pill never needs a keyboard grab for these).
    component CycleRow: Item {
        id: cyc
        property string label: ""
        property var options: []
        property string value: ""
        signal picked(string v)
        width: parent ? parent.width : 0
        height: 26
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: cyc.label
            color: root.theme.text
            font.family: root.theme.family
            font.pixelSize: root.theme.fsNormal
        }
        Rectangle {
            readonly property bool kbFocusable: true
            property bool kbFocused: false
            function keyClick() {
                const i = cyc.options.indexOf(cyc.value);
                cyc.picked(cyc.options[(i + 1) % cyc.options.length]);
            }
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: cycTxt.implicitWidth + 20
            height: 22
            radius: root.theme.radiusBtn
            color: (cycMa.containsMouse || kbFocused) ? root.theme.rowHi : root.theme.row
            border.width: 1
            border.color: root.theme.border
            Text {
                id: cycTxt
                anchors.centerIn: parent
                text: cyc.value
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsSmall
                font.letterSpacing: root.theme.labelSpacing
            }
            MouseArea {
                id: cycMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.keyClick()
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: root.theme.gap

        MenuHeader {                            // back chevron + title + settings shortcuts
            theme: root.theme
            title: "Volume"
            onBack: root.closeRequested()
            // "Audio" (kcm_pulseaudio) and "Multimedia" (kcm_phonon) — KDE's two
            // audio settings panes.
            Repeater {
                model: [
                    { label: "Audio",      kcm: "kcm_pulseaudio" },
                    { label: "Multimedia", kcm: "kcm_phonon" }
                ]
                delegate: Text {
                    required property var modelData
                    readonly property bool kbFocusable: true
                    property bool kbFocused: false
                    function keyClick() { root.openAudioSettings(modelData.kcm); }
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: (setMa.containsMouse || kbFocused) ? root.theme.text : root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                    MouseArea {
                        id: setMa
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.openAudioSettings(modelData.kcm)
                    }
                }
            }
        }

        Row {                                   // tabs
            spacing: 18
            Repeater {
                model: ["Devices", "Applications", "Transcribe"]
                delegate: Text {
                    required property int index
                    required property string modelData
                    // keyboard nav: the tab bar is a left/right strip; Enter picks.
                    // Focus brightens the label (the floating square would sit
                    // behind the faint caps and wash them out).
                    readonly property bool kbFocusable: true
                    property bool kbFocused: false
                    function keyClick() { root.tab = index; }
                    text: modelData
                    color: root.tab === index ? root.theme.accent : kbFocused ? root.theme.text : root.theme.faint
                    font.family: root.theme.mono
                    font.pixelSize: root.theme.fsSmall
                    font.letterSpacing: root.theme.labelSpacing
                    font.capitalization: Font.AllUppercase
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.tab = index }
                }
            }
        }

        SearchField {
            id: search
            visible: root.tab !== 2
            width: parent.width
            theme: root.theme
            placeholder: root.tab === 1 ? "Search apps" : "Search devices"
        }

        Flickable {
            width: parent.width
            height: parent.height - 34 - 26 - root.theme.gap - (root.tab === 2 ? 0 : 34 + root.theme.gap)
            contentHeight: col.height
            clip: true
            Column {
                id: col
                width: parent.width
                spacing: 12

                // ---- Devices tab: Speakers (sinks) then Microphones (sources),
                //      kept in separate labelled sections ----
                VolLabel { text: "Speakers"; visible: root.tab === 0 && root.fSinks.length > 0 }
                Repeater {
                    model: root.tab === 0 ? root.fSinks : []
                    delegate: NodeRow { required property var modelData; width: col.width; node: modelData; showDefault: true }
                }
                VolLabel { text: "Microphones"; visible: root.tab === 0 && root.fSources.length > 0 }
                Repeater {
                    model: root.tab === 0 ? root.fSources : []
                    delegate: NodeRow { required property var modelData; width: col.width; node: modelData; showDefault: true }
                }

                // ---- Applications tab ----
                Repeater {
                    model: root.tab === 1 ? root.fStreams : []
                    delegate: NodeRow { required property var modelData; width: col.width; node: modelData; isStream: true }
                }

                // ---- Transcribe tab: voice-to-text pipeline knobs (persisted
                //      through the shared settings adapter; read by the voice
                //      state machine in init.qml and by voicebridge.py) ----
                VolLabel { text: "Input Gain"; visible: root.tab === 2 && !!Pipewire.defaultAudioSource }
                Repeater {
                    // reuse NodeRow for the default mic: name + mute + gain slider
                    model: (root.tab === 2 && Pipewire.defaultAudioSource) ? [Pipewire.defaultAudioSource] : []
                    delegate: NodeRow { required property var modelData; width: col.width; node: modelData }
                }
                VolLabel { text: "Noise"; visible: root.tab === 2 }
                ToggleRow {
                    visible: root.tab === 2
                    label: "Noise suppression (RNNoise)"
                    checked: root.settings ? root.settings.voiceNoiseSuppress : false
                    onToggled: v => { if (root.settings) root.settings.voiceNoiseSuppress = v; }
                }
                ToggleRow {
                    visible: root.tab === 2
                    label: "Voice-activity filter (VAD)"
                    checked: root.settings ? root.settings.voiceVad : true
                    onToggled: v => { if (root.settings) root.settings.voiceVad = v; }
                }
                VolLabel { text: "Whisper"; visible: root.tab === 2 }
                CycleRow {
                    visible: root.tab === 2
                    label: "Model"
                    options: ["tiny", "base", "small", "medium", "large-v3-turbo"]
                    value: root.settings ? root.settings.whisperModel : "small"
                    onPicked: v => { if (root.settings) root.settings.whisperModel = v; }
                }
                CycleRow {
                    visible: root.tab === 2
                    label: "Language"
                    options: ["auto", "en", "fa"]
                    value: root.settings ? root.settings.whisperLanguage : "auto"
                    onPicked: v => { if (root.settings) root.settings.whisperLanguage = v; }
                }
                CycleRow {
                    visible: root.tab === 2
                    label: "Device"
                    options: ["auto", "cuda", "cpu"]
                    value: root.settings ? root.settings.whisperDevice : "auto"
                    onPicked: v => { if (root.settings) root.settings.whisperDevice = v; }
                }
                VolLabel { text: "Polish"; visible: root.tab === 2 }
                // shared polish-backend picker (model + cloud key / local download)
                PolishConfig {
                    visible: root.tab === 2
                    width: parent.width
                    theme: root.theme
                    settings: root.settings
                    setup: root.setup
                }

                // where the editable prompt files live (voicebridge writes sane
                // defaults on first run; re-tangling never touches them)
                Text {
                    visible: root.tab === 2
                    width: col.width
                    wrapMode: Text.Wrap
                    text: "Prompts (editable): ~/.config/quickshell/transcribe/ — whisper-prompt.md · polish-prompt.md · org-prompt.md (defaults written on first run)."
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsSmall
                }

                Text {
                    visible: root.tab !== 2 && (root.tab === 0 ? (root.fSinks.length + root.fSources.length) : root.fStreams.length) === 0
                    text: search.text !== "" ? "No matches"
                        : root.tab === 0 ? "No audio devices" : "No apps playing audio"
                    color: root.theme.textDim
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                }
            }
        }
    }
}
