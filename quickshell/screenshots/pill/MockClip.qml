pragma ComponentBehavior: Bound
// MockClip.qml — stand-in for Clipboard.qml (screenshot harness). Mixed text/image
// history; the image entry points at a real PNG so it renders.
import QtQuick

QtObject {
    id: root
    property var entries: [
        { id: 1, kind: "text", text: "git commit -m 'add emaqs notifications'" },
        { id: 2, kind: "text", text: "https://quickshell.org/docs/types/Quickshell.Io/" },
        { id: 3, kind: "image", w: 1046, h: 820, path: "@OUT@/emaqs-5-menu.png" },
        { id: 4, kind: "text", text: "", images: 2 },
        { id: 5, kind: "text", text: "The quick brown fox jumps over the lazy dog while thirteen wizards chart the sky." },
        { id: 6, kind: "text", text: "#cf4636  /* vermillion accent */" }
    ]
    function refresh() {}
    function wipe() {}
    function copy(id) {}
    function remove(id) {}
}
