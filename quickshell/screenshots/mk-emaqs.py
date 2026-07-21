#!/usr/bin/env python
"""Transform a tangled emaqs init.qml into an off-screen screenshot harness.

Usage: mk-emaqs.py <emaqs_build_dir> <out_dir>

Reads <emaqs_build_dir>/init.qml (a throwaway tangle — NEVER the live config), swaps
the real bridges for MockEmacs/MockAgent (copied into the build dir by shoot.sh),
replaces the layer-shell PanelWindow with a plain FloatingWindow, and appends a
grabber that steps through every UI stage saving each PNG to <out_dir>. fswatch.py is
neutered to a sleep loop so the harness can never grab the live emaqs org.kde.emaqs
DBus name.
"""
import sys, pathlib

D = pathlib.Path(sys.argv[1])
OUT = sys.argv[2]
src = (D / "init.qml").read_text()

# 1. real bridges -> mocks (structurally identical, so nothing else shifts)
src = src.replace("EmaqsBridge { id: emacs }", "MockEmacs { id: emacs }")
src = src.replace("AgentBridge { id: agent }", "MockAgent { id: agent }")

# 2. layer-shell PanelWindow (inside Variants) -> a single FloatingWindow
src = src.replace(
    "    Variants {\n"
    "        model: Quickshell.screens\n"
    "\n"
    "        PanelWindow {\n"
    "            id: win\n"
    "            required property var modelData\n",
    "    FloatingWindow {\n"
    "            id: win\n"
    "            visible: true\n"
    "            implicitWidth: 900\n"
    "            implicitHeight: 540\n"
    '            property string outDir: "' + OUT + '"\n',
)

# 3. strip the layer-shell-only window properties
for line in [
    "            screen: modelData\n",
    "            WlrLayershell.layer: WlrLayer.Overlay\n",
    "            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n",
    "            exclusionMode: ExclusionMode.Ignore\n",
    "            mask: win.expanded ? fullRegion : (win.fsHide ? emptyRegion : tabRegion)\n",
    "            Region { id: tabRegion; item: pill }\n",
    "            Region { id: fullRegion; item: backdrop }\n",
    "            Region { id: emptyRegion }\n",
]:
    assert line in src, "missing: " + line.strip()
    src = src.replace(line, "")

# transparent -> a dark desktop wash so the resting pill's translucency reads
src = src.replace('            color: "transparent"\n', '            color: "#151310"\n')

# drop the fullscreen anchors block (FloatingWindow uses its implicit size)
src = src.replace(
    "            anchors {\n"
    "                top: true\n"
    "                bottom: true\n"
    "                left: true\n"
    "                right: true\n"
    "            }\n",
    "",
)

# 4. append the grabber as a sibling of `pill`, just before the window closes.
GRAB = r'''
            // ================= screenshot grabber (harness only) =================
            property int _shot: -1
            readonly property var _states: [
                { name: "collapsed",  fn: function(){ win.focused=false; win.menuOpen=false; agent.dnd=false; agent.workingCount=0; agent.workingList=[]; agent.permissionNotif=null; agent.finishedNotif=null; } },
                { name: "working",    fn: function(){ win.focused=false; win.menuOpen=false; agent.workingCount=2; agent.workingList=[{workspace:"AWESOME"},{workspace:"DOOM"}]; agent.permissionNotif=null; agent.finishedNotif=null; } },
                { name: "finished",   fn: function(){ win.focused=false; win.menuOpen=false; agent.workingCount=1; agent.workingList=[{workspace:"DOOM"}]; agent.permissionNotif=null; agent.finishedNotif={id:"1", title:"claude: refactor pill"}; } },
                { name: "permission", fn: function(){ win.focused=false; win.menuOpen=false; agent.workingCount=1; agent.workingList=[{workspace:"DOOM"}]; agent.finishedNotif=null; agent.permissionNotif={id:"2", title:"claude: write tests", body:"Run shell command: qs -p init.qml to validate the harness output", actions:[["allow","Allow"],["deny","Deny"]]}; } },
                { name: "bar",        fn: function(){ agent.permissionNotif=null; agent.finishedNotif=null; agent.workingCount=1; agent.workingList=[{workspace:"AWESOME"}]; win.menuOpen=false; win.focused=true; } },
                { name: "menu",       fn: function(){ win.focused=true; win.menuWs="AWESOME"; win.confirmClose=false; win.menuOpen=true; } },
                { name: "confirm",    fn: function(){ win.focused=true; win.menuWs="AWESOME"; win.menuOpen=true; win.confirmClose=true; } }
            ]
            function _next() {
                win._shot++;
                if (win._shot >= win._states.length) { Qt.quit(); return; }
                win._states[win._shot].fn();
                grabTimer.restart();
            }
            Timer { id: startTimer; interval: 800; running: true; onTriggered: win._next() }
            Timer {
                id: grabTimer; interval: 600; repeat: false
                onTriggered: {
                    var s = win._states[win._shot];
                    pill.grabToImage(function(res){
                        res.saveToFile(win.outDir + "/emaqs-" + win._shot + "-" + s.name + ".png");
                        Qt.callLater(win._next);
                    }, Qt.size(Math.ceil(pill.width*2), Math.ceil(pill.height*2)));
                }
            }
'''

# insert the grabber inside the FloatingWindow, after `pill`'s close brace.
lines = src.rstrip().split("\n")
assert lines[-1] == "}", lines[-1]
assert lines[-2].strip() == "}", lines[-2]
del lines[-2]                       # remove the now-orphaned Variants close brace
assert lines[-2].strip() == "}", lines[-2]
lines.insert(-2, GRAB)
src = "\n".join(lines) + "\n"

(D / "harness.qml").write_text(src)

# 5. neuter fswatch.py so the harness never grabs the live emaqs DBus name
(D / "fswatch.py").write_text("#!/usr/bin/env python\nimport time\nwhile True: time.sleep(3600)\n")

print("wrote", D / "harness.qml", "(%d lines)" % len(lines))
