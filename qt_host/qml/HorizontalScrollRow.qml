import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// HorizontalScrollRow — section header + horizontal ListView of cards
// Usage:
//   HorizontalScrollRow {
//       sectionTitle: "Continue Watching"
//       model: myModel
//       delegate: EpisodeThumbnailCard { ... }
//       onViewAllClicked: { ... }
//   }

Item {
    id: scrollRow

    property string sectionTitle: ""
    property alias  model:        listView.model
    property alias  delegate:     listView.delegate
    property int    leftMargin:   64    // matches stitch pl-margin-desktop

    signal viewAllClicked()

    implicitHeight: headerRow.height + 16 + listView.height
    width: parent ? parent.width : 800

    // ── Section header ─────────────────────────────────────────────────────
    RowLayout {
        id: headerRow
        anchors { top: parent.top; left: parent.left; leftMargin: scrollRow.leftMargin; right: parent.right; rightMargin: 24 }
        height: 36

        Text {
            Layout.fillWidth: true
            text: scrollRow.sectionTitle
            color: "white"
            font { family: "Montserrat"; pixelSize: 20; weight: Font.DemiBold }
        }

        Text {
            text: "View All"
            color: "#ffb693"
            font { family: "Inter"; pixelSize: 12; letterSpacing: 0.5 }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: scrollRow.viewAllClicked()
                onEntered: parent.font.underline = true
                onExited:  parent.font.underline = false
            }
        }
    }

    // ── Horizontal list ────────────────────────────────────────────────────
    ListView {
        id: listView
        anchors { top: headerRow.bottom; topMargin: 16; left: parent.left; right: parent.right }
        height: contentItem.childrenRect.height + 24   // card height + bottom padding
        leftMargin: scrollRow.leftMargin
        rightMargin: 24
        spacing: 24
        orientation: Qt.Horizontal
        clip: false
        interactive: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        snapMode: ListView.SnapToItem
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }
    }
}
