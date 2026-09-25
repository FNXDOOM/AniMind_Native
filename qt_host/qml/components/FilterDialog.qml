import QtQuick
import QtQuick.Controls
import ".."

// Filter & Sort modal. Opens over a dimmed scrim with the dialog scaling
// 0.96 -> 1, per section 24.
//
// Every group is single-select and drawn as a radio. The reference mock uses
// checkboxes for genre, but AniList's Page.media takes only a singular `genre`
// argument (there is no `genres`), so checkboxes here would promise a
// combination the query cannot perform and silently keep the last tick.
Rectangle {
    id: dlg

    property bool open: false

    property var genreOpts:  []      // [{ v, label }]
    property var statusOpts: []
    property var typeOpts:   []
    property var sortOpts:   []      // [{ v: index, label }]
    property var yearOpts:   []      // [{ v, label }]

    property string genre:  ""
    property string status: ""
    property string type:   ""
    property int    sort:   0
    property int    year:   0

    signal applied(var draft)
    signal dismissed()

    anchors.fill: parent
    visible: open
    color: Theme.veil
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

    MouseArea {
        anchors.fill: parent
        onClicked: dlg.dismissed()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(620, parent.width - Theme.s8)
        height: Math.min(bodyColumn.implicitHeight + Theme.s12 + 60, parent.height - Theme.s8)
        radius: Theme.rXl
        color: Theme.bgSecondary
        border.color: Theme.borderDefault
        border.width: 1

        scale: dlg.open ? 1.0 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

        // ── Header ───────────────────────────────────────────────────────
        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.margins: Theme.s5
            height: 28

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Filter & Sort"
                color: Theme.textPrimary
                font.family: Theme.displayFont
                font.pixelSize: Theme.tsSection - 4
                font.weight: Font.DemiBold
            }

            Rectangle {
                id: closeBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 28; height: 28; radius: Theme.rSm
                color: closeHover.hovered ? Theme.card : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dFast } }

                Text {
                    anchors.centerIn: parent
                    text: "\uE711"
                    color: Theme.textSecondary
                    font.family: Theme.iconFont
                    font.pixelSize: 12
                }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.dismissed() }

                Accessible.role: Accessible.Button
                Accessible.name: "Close"
                Accessible.onPressAction: dlg.dismissed()
            }
        }

        // ── Groups ───────────────────────────────────────────────────────
        Flickable {
            id: flick
            anchors { top: head.bottom; topMargin: Theme.s4; left: parent.left; right: parent.right; bottom: footer.top; bottomMargin: Theme.s4 }
            anchors.leftMargin: Theme.s5; anchors.rightMargin: Theme.s5
            contentHeight: bodyColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Row {
                id: bodyColumn
                width: flick.width
                spacing: Theme.s6

                FilterGroup { title: "Genre";  opts: dlg.genreOpts;  current: dlg.genre;  width: (flick.width - Theme.s6 * 2) / 3; onPicked: v => dlg.genre = v }
                FilterGroup { title: "Status"; opts: dlg.statusOpts; current: dlg.status; width: (flick.width - Theme.s6 * 2) / 3; onPicked: v => dlg.status = v }

                Column {
                    width: (flick.width - Theme.s6 * 2) / 3
                    spacing: Theme.s5
                    FilterGroup { title: "Type"; opts: dlg.typeOpts; current: dlg.type; width: parent.width; onPicked: v => dlg.type = v }
                    FilterGroup { title: "Sort by"; opts: dlg.sortOpts; current: dlg.sort; width: parent.width; onPicked: v => dlg.sort = v }
                    FilterGroup { title: "Year"; opts: dlg.yearOpts; current: dlg.year; width: parent.width; onPicked: v => dlg.year = v }
                }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.margins: Theme.s5
            height: 44

            Rectangle {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: resetTxt.implicitWidth + Theme.s6
                height: 40
                radius: Theme.rMd
                color: resetHover.hovered ? Theme.card : "transparent"
                border.color: Theme.borderDefault; border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.dFast } }

                Text {
                    id: resetTxt
                    anchors.centerIn: parent
                    text: "Reset"
                    color: Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsBody
                }
                HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        dlg.genre = ""; dlg.status = ""; dlg.type = ""; dlg.sort = 0; dlg.year = 0
                    }
                }
            }

            PrimaryButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Apply"
                implicitWidth: Math.max(110, implicitWidth)
                onClicked: dlg.applied({ genre: dlg.genre, status: dlg.status,
                                        format: dlg.type, sort: dlg.sort, year: dlg.year })
            }
        }
    }

    // Escape closes, matching the shell's own unwind order.
    MouseArea {
        anchors.fill: parent
        enabled: false
        Keys.onEscapePressed: dlg.dismissed()
    }
}
