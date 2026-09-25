import QtQuick
import ".."

// Loading stand-in for a poster grid. Section 26 asks that a waiting screen
// never be an empty void with a spinner, so this reserves the exact shapes the
// results will land in: 2:3 artwork plus a two-line title slot.
//
// Columns and card width are passed in by the page so the skeleton and the
// real GridView agree instead of drifting.
Item {
    id: grid

    property int columns: 5
    property int rows: 3
    property int cardWidth: 160
    property int gap: Theme.s4
    property int gutter: Theme.s6

    implicitWidth: parent ? parent.width : 0
    implicitHeight: parent ? parent.height : 0

    Grid {
        id: tiles
        x: grid.gutter
        y: grid.gutter
        columns: grid.columns
        spacing: grid.gap

        Repeater {
            model: grid.columns * grid.rows

            Column {
                required property int index
                spacing: Theme.s2
                width: grid.cardWidth

                // Artwork block
                Rectangle {
                    width: parent.width
                    height: parent.width * 3 / 2
                    radius: Theme.rLg
                    color: Theme.surfaceRaised

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rLg
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.035) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        }
                    }
                }

                Item { width: 1; height: Theme.s1 }

                Rectangle { width: parent.width * 0.86; height: 12; radius: Theme.rSm; color: Theme.surfaceRaised }
                Rectangle { width: parent.width * 0.52; height: 10; radius: Theme.rSm; color: Theme.card }
            }
        }
    }

    // One highlight travelling across the whole grid, rather than one per
    // tile: cheaper, and it reads as a single surface catching light.
    Rectangle {
        id: sweep
        width: grid.width * 0.3
        height: grid.height
        x: -width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.035) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }

        SequentialAnimation on x {
            loops: Animation.Infinite
            running: grid.visible
            NumberAnimation { from: -sweep.width; to: grid.width; duration: 1500; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 300 }
        }
    }
}
