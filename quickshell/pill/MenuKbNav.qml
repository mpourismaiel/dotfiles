pragma ComponentBehavior: Bound
// MenuKbNav.qml — generic keyboard navigation for the control-panel menus (kbNav
// mode only). Scans `target` for kbFocusable-tagged items, moves between them
// spatially with the arrows, Enter fires the focused item's keyClick(), Escape
// emits escaped() (back to the expanded dashboard) and — in the calendar menu —
// f/c/n/w/v/b emit shortcutRequested(menu). Hovering any focusable re-focuses it.
// The focused item wears an accent ring; a slow tick re-maps it so it follows
// Flickable scrolls and layout changes.
import QtQuick

Item {
    id: root
    required property var theme
    property Item target                 // the loaded menu to scan (menuLoader.item)
    property bool active: false
    property bool shortcuts: false       // letter shortcuts (calendar menu)
    signal escaped()
    signal shortcutRequested(int menu)

    property Item cur: null              // focused item (a kbFocusable tag)
    property Item kbPrev: null           // last self-styling item we lit up
    property int tick: 0                 // bumped to re-map the highlight (scroll/layout)

    // the floating highlight square renders BELOW the menu content (init sets
    // z: -1 on this overlay) — same trick as the dashboard's hover square — and
    // must never paint outside the menu area (the pill doesn't clip).
    clip: true

    focus: root.active
    onActiveChanged: {
        if (root.active)
            Qt.callLater(root.focusDefault);
        else
            root.cur = null;
    }
    // a menu switch swaps the loader item under us — refocus its back button
    onTargetChanged: if (root.active) Qt.callLater(root.focusDefault)

    // an item that declares `kbFocused` styles its own focus (clipboard-style
    // rowHi fill — opaque rows would hide the under-square); light it up / clear
    // the previous one as the focus moves. try/catch guards a row destroyed by a
    // model refresh between moves.
    onCurChanged: {
        try {
            if (root.kbPrev && root.kbPrev !== root.cur && root.kbPrev.kbFocused !== undefined)
                root.kbPrev.kbFocused = false;
        } catch (e) {}
        if (root.cur && root.cur.kbFocused !== undefined)
            root.cur.kbFocused = true;
        root.kbPrev = root.cur;
    }

    // an in-menu text field (search / wifi password) that takes focus gets the
    // keys; when it lets go (its Escape), active focus lands on some focus
    // scope (the menu Loader, the window content item) — reclaim the key
    // handling (the `focus:` binding alone doesn't re-fire, its value never
    // changed). Only a pillKbInput field may hold the keys away from us.
    readonly property Item afi: Window.activeFocusItem
    onAfiChanged: {
        if (root.active && root.afi !== root && !(root.afi && root.afi.objectName === "pillKbInput"))
            root.forceActiveFocus();

    }

    // every visible kbFocusable under `target`, in document order. Invisible
    // subtrees (hidden tabs, collapsed sections) are skipped wholesale.
    function collect() {
        const out = [];
        function walk(it) {
            if (!it)
                return ;

            for (let i = 0; i < it.children.length; i++) {
                const c = it.children[i];
                if (!c.visible)
                    continue;

                if (c.kbFocusable === true && c.width > 0 && c.height > 0)
                    out.push(c);

                walk(c);
            }
        }
        if (root.target && root.target.visible)
            walk(root.target);

        return out;
    }

    function focusDefault() {
        const items = root.collect();
        root.cur = items.find(i => i.kbDefault === true) || (items.length ? items[0] : null);
    }

    function rectOf(it) {
        const p = it.mapToItem(root, 0, 0);
        return {
            "x": p.x,
            "y": p.y,
            "w": it.width,
            "h": it.height,
            "cx": p.x + it.width / 2,
            "cy": p.y + it.height / 2
        };
    }

    // rectOf clipped by every clipping ancestor (a Flickable's viewport): a row
    // scrolled out of view has an empty visible rect. The hover hit-test uses
    // this so the pointer near the pill's edge can't focus a hidden row (the
    // arrows still reach them — they scroll into view via ensureVisible).
    function visRectOf(it) {
        let r = root.rectOf(it);
        let a = it.parent;
        while (a && a !== root.target) {
            if (a.clip) {
                const p = a.mapToItem(root, 0, 0);
                const x2 = Math.min(r.x + r.w, p.x + a.width);
                const y2 = Math.min(r.y + r.h, p.y + a.height);
                r.x = Math.max(r.x, p.x);
                r.y = Math.max(r.y, p.y);
                r.w = Math.max(0, x2 - r.x);
                r.h = Math.max(0, y2 - r.y);
            }
            a = a.parent;
        }
        return r;
    }

    // nearest focusable in the pressed direction; the orthogonal offset weighs
    // 3x so rows/columns feel "sticky" (tabs step left/right, lists step up/down)
    function move(dx, dy) {
        const items = root.collect();
        if (!items.length)
            return ;

        if (!root.cur || items.indexOf(root.cur) < 0) {
            root.cur = items.find(i => i.kbDefault === true) || items[0];
            return ;
        }
        const c = root.rectOf(root.cur);
        let best = null;
        let bestScore = 1e9;
        for (const it of items) {
            if (it === root.cur)
                continue;

            const r = root.rectOf(it);
            const fwd = dx !== 0 ? (r.cx - c.cx) * dx : (r.cy - c.cy) * dy;
            if (fwd <= 2)
                continue;

            const ortho = dx !== 0 ? Math.abs(r.cy - c.cy) : Math.abs(r.cx - c.cx);
            const score = fwd + ortho * 3;
            if (score < bestScore) {
                bestScore = score;
                best = it;
            }
        }
        if (best) {
            root.cur = best;
            root.ensureVisible(best);
            root.tick++;
        }
    }

    // scroll the focused item into view if it sits inside a Flickable
    function ensureVisible(it) {
        let f = it.parent;
        while (f && f !== root.target && f.contentY === undefined) f = f.parent;
        if (!f || f === root.target || f.contentY === undefined || f.contentHeight === undefined)
            return ;

        const p = it.mapToItem(f.contentItem, 0, 0);
        if (p.y < f.contentY)
            f.contentY = Math.max(0, p.y - 8);
        else if (p.y + it.height > f.contentY + f.height)
            f.contentY = Math.min(Math.max(0, f.contentHeight - f.height), p.y + it.height - f.height + 8);
    }

    Keys.onPressed: (event) => {
        if (!root.active)
            return ;

        if (event.key === Qt.Key_Escape) {
            root.escaped();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            root.move(-1, 0);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.move(1, 0);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.move(0, -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.move(0, 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cur && root.cur.keyClick)
                root.cur.keyClick();

            event.accepted = true;
        } else if (root.shortcuts) {
            // same first-level jumps the expanded dashboard offers
            const m = event.key === Qt.Key_F ? 8 : event.key === Qt.Key_C ? 6 : event.key === Qt.Key_N ? 4 : event.key === Qt.Key_W ? 0 : event.key === Qt.Key_V ? 1 : event.key === Qt.Key_B ? 2 : -1;
            if (m >= 0) {
                root.shortcutRequested(m);
                event.accepted = true;
            }
        }
    }

    // hover overrides focus: whatever focusable the pointer is over becomes `cur`
    // (clip-aware, so a row scrolled out of a Flickable can't catch the pointer)
    HoverHandler {
        enabled: root.active
        onPointChanged: {
            const items = root.collect();
            const px = point.position.x;
            const py = point.position.y;
            for (const it of items) {
                const r = root.visRectOf(it);
                if (r.w > 0 && r.h > 0 && px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h) {
                    if (root.cur !== it) {
                        root.cur = it;
                        root.tick++;
                    }
                    return ;
                }
            }
        }
    }

    // keep the highlight glued through Flickable scrolls / animated layouts
    Timer {
        interval: 250
        running: root.active && root.cur !== null
        repeat: true
        onTriggered: root.tick++
    }

    // the floating hover square (same look as the dashboard's roving square),
    // sliding between the unfilled focusables — back button, toggles, tabs,
    // icons. It renders under the menu content (the overlay is z: -1), so an
    // opaque row would hide it; those style themselves via `kbFocused` instead
    // and the square stays hidden.
    Rectangle {
        readonly property var r: {
            const _dep = [root.tick, root.cur, root.width, root.height];
            return (root.cur && root.cur.visible) ? root.rectOf(root.cur) : null;
        }
        readonly property bool selfStyled: root.cur !== null && root.cur.kbFocused !== undefined

        visible: root.active && r !== null && !selfStyled
        x: r ? r.x - 4 : 0
        y: r ? r.y - 4 : 0
        width: r ? r.w + 8 : 0
        height: r ? r.h + 8 : 0
        radius: root.theme.radiusSmall
        color: root.theme.bgHover

        Behavior on x {
            NumberAnimation {
                duration: root.theme.animFast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on y {
            NumberAnimation {
                duration: root.theme.animFast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on width {
            NumberAnimation {
                duration: root.theme.animFast
                easing.type: Easing.OutCubic
            }

        }

        Behavior on height {
            NumberAnimation {
                duration: root.theme.animFast
                easing.type: Easing.OutCubic
            }

        }

    }
}
