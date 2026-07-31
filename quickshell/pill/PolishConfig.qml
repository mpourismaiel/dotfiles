pragma ComponentBehavior: Bound
// PolishConfig.qml — polish model + credentials/download, shared by the
// Transcribe tab and the voice-memo menu. settings holds the model ids; setup
// (VoiceSetup) reports/stores keys and drives the local-model download.
import QtQuick

Column {
    id: root
    required property var theme
    property var settings: null
    property var setup: null
    spacing: root.theme.gap

    // which backend the selected model uses: "local" | "gemini" | "openai" | "claude"
    readonly property string provider: {
        const m = root.settings ? root.settings.claudeModel : "";
        if (m === "local") return "local";
        if (m.indexOf("gemini") === 0) return "gemini";
        if (m.indexOf("gpt") === 0) return "openai";
        return "claude";
    }
    function refresh() { if (root.setup) root.setup.refresh(); }
    Component.onCompleted: root.refresh()

    // one click-to-cycle row (label left, value chip right)
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

    CycleRow {
        label: "Model"
        // claude-* / gemini-* / gpt-* use a cloud API (key below); "local" runs
        // offline via ollama (download below). Gemini ids are free-tier flash models.
        options: ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5",
                  "gemini-3.5-flash-lite", "gemini-3.5-flash",
                  "gpt-5", "gpt-5-mini", "gpt-4o-mini", "local"]
        value: root.settings ? root.settings.claudeModel : "claude-opus-4-8"
        onPicked: v => { if (root.settings) root.settings.claudeModel = v; }
    }
    CycleRow {
        visible: root.provider === "local"
        label: "Local model"
        options: ["qwen2.5:3b", "llama3.2:3b", "gemma2:2b"]
        value: root.settings ? root.settings.localModel : "qwen2.5:3b"
        onPicked: v => { if (root.settings) root.settings.localModel = v; root.refresh(); }
    }

    // ---- cloud API key (Anthropic / Google) — masked, eye toggle ----
    Item {
        id: keyArea
        visible: root.provider !== "local"
        width: parent.width
        height: visible ? keyRow.height + keyHint.height + 6 : 0
        property bool reveal: false
        readonly property string prov: root.provider === "gemini" ? "google"
                                     : root.provider === "openai" ? "openai" : "anthropic"
        readonly property string provLabel: root.provider === "gemini" ? "Google"
                                          : root.provider === "openai" ? "OpenAI" : "Anthropic"
        readonly property bool isSet: root.setup ? root.setup.keySet(keyArea.prov) : false

        Rectangle {
            id: keyRow
            width: parent.width; height: 40
            radius: root.theme.radiusRow
            color: root.theme.row
            border.width: 1
            border.color: keyInput.activeFocus ? root.theme.accent : root.theme.border
            MSym {
                id: keyIcon
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                icon: "key"; size: 18
                color: keyInput.activeFocus ? root.theme.accent : root.theme.faint
            }
            TextInput {
                id: keyInput
                objectName: "pillKbInput"
                anchors.left: keyIcon.right; anchors.leftMargin: 8
                anchors.right: eyeBtn.left; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                echoMode: keyArea.reveal ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                color: root.theme.text
                font.family: root.theme.mono
                font.pixelSize: root.theme.fsNormal
                clip: true
                selectByMouse: true
                selectionColor: root.theme.accentDim
                onAccepted: {                       // Enter -> save to keyring, clear
                    if (root.setup && text.length > 0) {
                        root.setup.setKey(keyArea.prov, text);
                        text = "";
                    }
                }
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: keyInput.text.length === 0
                    text: keyArea.isSet ? "Key saved — type a new one to replace"
                                        : ("Paste your " + keyArea.provLabel + " API key")
                    color: root.theme.faint
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                    elide: Text.ElideRight
                }
            }
            Item {                                  // eye toggle
                id: eyeBtn
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24
                MSym {
                    anchors.centerIn: parent
                    icon: keyArea.reveal ? "visibility_off" : "visibility"
                    size: 18
                    color: eyeMa.containsMouse ? root.theme.text : root.theme.faint
                }
                MouseArea {
                    id: eyeMa
                    anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: keyArea.reveal = !keyArea.reveal
                }
            }
        }
        Text {
            id: keyHint
            anchors.top: keyRow.bottom; anchors.topMargin: 6
            anchors.left: parent.left; anchors.right: parent.right
            wrapMode: Text.Wrap
            text: keyArea.isSet
                  ? ("✓ " + keyArea.provLabel + " key saved (stored in the keyring)")
                  : (keyArea.provLabel + " API key needed for this model — press Enter to save")
            color: keyArea.isSet ? root.theme.good : root.theme.faint
            font.family: root.theme.family
            font.pixelSize: root.theme.fsSmall
        }
    }

    // ---- local model download (ollama pull) with progress ----
    Item {
        id: dlArea
        visible: root.provider === "local"
        width: parent.width
        height: visible ? 40 : 0
        readonly property string model: root.settings ? root.settings.localModel : ""
        readonly property bool present: root.setup ? root.setup.localPresent : false
        readonly property bool busy: root.setup ? root.setup.pulling : false

        Rectangle {
            id: dlBtn
            anchors.fill: parent
            radius: root.theme.radiusRow
            color: (dlMa.containsMouse && !dlArea.present && !dlArea.busy) ? root.theme.rowHi : root.theme.row
            border.width: 1
            border.color: dlArea.present ? root.theme.good : root.theme.border
            clip: true
            Behavior on color { ColorAnimation { duration: root.theme.animFast } }

            Rectangle {                             // progress fill while pulling
                visible: dlArea.busy
                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                width: parent.width * (root.setup ? root.setup.pullProgress : 0)
                color: root.theme.accentSoft
                Behavior on width { NumberAnimation { duration: root.theme.animFast } }
            }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                MSym {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: dlArea.present ? "check_circle" : (dlArea.busy ? "downloading" : "download")
                    fill: dlArea.present ? 1 : 0
                    size: 18
                    color: dlArea.present ? root.theme.good : root.theme.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dlArea.present ? ("Downloaded — " + dlArea.model)
                        : dlArea.busy ? ((root.setup ? root.setup.pullStatus : "") + " · "
                                         + Math.round((root.setup ? root.setup.pullProgress : 0) * 100) + "%")
                        : ("Download " + dlArea.model)
                    color: root.theme.text
                    font.family: root.theme.family
                    font.pixelSize: root.theme.fsNormal
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                id: dlMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: !dlArea.present && !dlArea.busy
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.setup) root.setup.pull(dlArea.model)
            }
        }
    }
}
