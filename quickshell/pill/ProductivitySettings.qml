pragma ComponentBehavior: Bound
// ProductivitySettings.qml — the Settings › Productivity page. Configures the
// "Done" work-history page: which project directories are scanned for git
// activity, and which commit-author emails count as yours. Both are multi-item
// lists (see ListEditor); writes reassign the JsonAdapter arrays so they flush.
import QtQuick

Item {
    id: root
    required property var theme
    property var settings: null
    property var picker: null              // root.pickFolder(cb) — native folder picker

    Flickable {
        anchors.fill: parent
        contentHeight: col.height
        clip: true
        Column {
            id: col
            width: parent.width
            spacing: 14

            Text {
                text: "Productivity"
                color: root.theme.text
                font.family: root.theme.serif
                font.pixelSize: root.theme.fsLarge + 4
            }
            Text {
                width: col.width
                wrapMode: Text.WordWrap
                text: "The Done page summarizes what you finished — commits across your "
                    + "projects, tasks closed and meetings attended. Point it at your "
                    + "project folders and tell it which emails are yours."
                color: root.theme.textDim
                font.family: root.theme.family
                font.pixelSize: root.theme.fsSmall
            }

            Rectangle { width: col.width; height: 1; color: root.theme.divider }

            ListEditor {
                width: col.width
                theme: root.theme
                label: "Project directories"
                blurb: "Each entry is a git repository, or a folder whose immediate "
                     + "subfolders are repositories. ~ expands to your home directory."
                mode: "folder"
                addLabel: "Add folder…"
                picker: root.picker
                items: root.settings ? root.settings.productivityDirs : []
                onChanged: (list) => { if (root.settings) root.settings.productivityDirs = list; }
            }

            Rectangle { width: col.width; height: 1; color: root.theme.divider }

            ListEditor {
                width: col.width
                theme: root.theme
                label: "Commit author emails"
                blurb: "Only commits authored by these emails are counted. If the "
                     + "list is empty, the code section shows an empty state."
                mode: "text"
                placeholder: "you@example.com"
                items: root.settings ? root.settings.productivityEmails : []
                onChanged: (list) => { if (root.settings) root.settings.productivityEmails = list; }
            }
        }
    }
}
