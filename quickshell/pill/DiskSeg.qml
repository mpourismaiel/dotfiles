pragma ComponentBehavior: Bound
// DiskSeg.qml — a stacked proportion bar for the Disk window. `parts` is
// [{color, value}]; widths are value/total (total defaults to the sum, so pass
// the disk size to leave the free part empty).
import QtQuick

Rectangle {
    id: root
    required property var theme
    property var parts: []
    property real total: 0
    readonly property real _total: {
        if (total > 0) return total;
        var s = 0;
        for (var i = 0; i < parts.length; i++) s += parts[i].value || 0;
        return s;
    }
    implicitHeight: 10
    radius: height / 2
    color: theme.track
    clip: true

    Row {
        anchors.fill: parent
        Repeater {
            model: root.parts
            Rectangle {
                required property var modelData
                height: root.height
                width: root._total > 0 ? Math.max(0, root.width * (modelData.value || 0) / root._total) : 0
                color: modelData.color
            }
        }
    }
}
