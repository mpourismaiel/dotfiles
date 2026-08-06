pragma ComponentBehavior: Bound
// LauncherSearch.qml — the KRunner (org.kde.milou) search-results list for the
// launcher, deliberately split out into its own file.
//
// WHY A SEPARATE FILE: `import org.kde.milou` / `import org.kde.kirigami` only
// resolve on a system that has KDE's KRunner/Kirigami QML modules installed. A
// failed QML import doesn't fail softly — it makes the *whole* component that
// contains it fail to compile. If these imports lived in Launcher.qml (a hard
// child of the pill's PanelWindow), a machine without KDE would take the entire
// pill down at load time. By isolating them here and loading this file through a
// `Loader` (see Launcher.qml `searchLoader`), a missing module fails just this
// Loader: `searchLoader.item` stays null and the launcher falls back to plain
// local app-name filtering. The pill stays fully usable.
//
// The parent (Launcher.qml root) stays the single source of navigation truth: it
// reads `count`, drives `query`, and calls `positionAt`/`runIndex`. Everything
// else (currentIndex, favourites, the app context menu) is reached back through
// the `launcher` back-reference.
import QtQuick
import org.kde.milou as Milou
import org.kde.kirigami as Kirigami

Item {
    id: search

    // Set at creation by Launcher.qml via Loader.setSource({...}); see the note above.
    required property var theme
    required property var launcher   // the Launcher root (currentIndex, isFav, entryForResult, signals)
    property string query: ""

    // Parent-facing API (keeps Launcher.qml the owner of keyboard navigation).
    readonly property alias count: resultsList.count
    function positionAt(i) { resultsList.positionViewAtIndex(i, ListView.Contain); }
    function runIndex(i) { return krunner.run(krunner.index(i, 0)); }

    // The exact backend Plasma's launcher / KRunner / Overview use: every enabled
    // search plugin (Applications, System Settings, Power, Locations, web
    // shortcuts, calculator, …), grouped and ranked. Running a row calls back into
    // KRunner so each match launches exactly as it would there.
    Milou.ResultsModel {
        id: krunner
        queryString: search.query
    }

    // A flat, category-grouped list bound straight to the Milou model; the section
    // header is the KRunner category. Each row shows the match's own icon (themed
    // name or QIcon, both via Kirigami.Icon), title and subtext.
    ListView {
        id: resultsList

        anchors.fill: parent
        model: krunner
        clip: true
        spacing: 2
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds
        section.property: "category"
        section.criteria: ViewSection.FullString

        section.delegate: Item {
            id: secHeader

            required property string section

            width: resultsList.width
            height: 30

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: secHeader.section
                color: search.theme.faint
                font.family: search.theme.mono
                font.pixelSize: search.theme.fsSmall
                font.letterSpacing: search.theme.labelSpacing
                font.capitalization: Font.AllUppercase
            }

        }

        delegate: Rectangle {
            id: resRow

            required property var model
            required property int index

            width: resultsList.width
            height: search.theme.rowHeight
            radius: search.theme.radiusRow
            color: resRow.index === search.launcher.currentIndex ? search.theme.accentDim : resMa.containsMouse ? search.theme.rowHi : "transparent"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 24
                    implicitHeight: 24
                    source: resRow.model.decoration
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 10
                    spacing: 1

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: resRow.model.display
                        color: search.theme.text
                        font.family: search.theme.family
                        font.pixelSize: search.theme.fsNormal
                    }

                    Text {
                        width: parent.width
                        visible: text.length > 0
                        height: visible ? implicitHeight : 0
                        elide: Text.ElideRight
                        text: resRow.model.subtext || ""
                        color: search.theme.textDim
                        font.family: search.theme.family
                        font.pixelSize: search.theme.fsSmall
                    }

                }

            }

            MouseArea {
                id: resMa

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        // only app results resolve to a DesktopEntry; others get no menu
                        const e = search.launcher.entryForResult(resRow.model);
                        if (e) {
                            const p = mapToItem(search.launcher, mouse.x, mouse.y);
                            search.launcher.appMenuRequested(e, search.launcher.isFav(e), search.launcher.isPinned(e), p.x, p.y);
                        }
                        return ;
                    }
                    if (krunner.run(krunner.index(resRow.index, 0)))
                        search.launcher.launched();

                }
            }

        }

    }

}
