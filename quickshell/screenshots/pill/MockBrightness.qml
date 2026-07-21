pragma ComponentBehavior: Bound
// MockBrightness.qml — stand-in for Brightness.qml (screenshot harness). Displays
// are stable QtObjects (BatteryMenu mutates .value in place during a drag).
import QtQuick

Item {
    id: root
    property var displays: []
    readonly property bool available: displays.length > 0
    function refresh() {}
    function setRatio(disp, ratio) { if (disp) disp.value = Math.max(0, Math.min(1, ratio)); }

    component Display: QtObject {
        property bool internal: false
        property string label: ""
        property real value: 0          // 0..1
        property string path: ""
        property int max: 100
        property int raw: 0
    }
    Component { id: dc; Display {} }
    Component.onCompleted: {
        root.displays = [
            dc.createObject(root, { internal: true,  label: "Built-in Display",  value: 0.78 }),
            dc.createObject(root, { internal: false, label: "Samsung Odyssey",   value: 0.55 })
        ];
    }
}
