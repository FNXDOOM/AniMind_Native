import QtQuick
import ".."

// Skeleton placeholder. A block of content-shaped bars with one highlight
// travelling across them, so a loading screen reads as "coming" instead of
// "broken". Cheap: a single animated x offset, no shaders.
Item {
    id: root

    property int  bars: 3
    property int  barHeight: 14
    property int  barGap: Theme.s3
    property real shimmerOpacity: 0.05
    property bool running: true

    implicitWidth: 260
    implicitHeight: bars * barHeight + (bars - 1) * barGap

    Column {
        id: column
        anchors.fill: parent
        spacing: root.barGap

        Repeater {
            model: root.bars
            delegate: Rectangle {
                required property int index
                width: index === root.bars - 1
                       ? parent.width * 0.62
                       : (index === 0 ? parent.width : parent.width * 0.86)
                height: root.barHeight
                radius: Theme.rSm
                color: Theme.surfaceRaised
            }
        }
    }

    Rectangle {
        id: shimmer
        width: parent.width * 0.35
        height: parent.height
        x: -width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, root.shimmerOpacity) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }

        SequentialAnimation on x {
            id: sweep
            loops: Animation.Infinite
            running: root.visible && root.running
            NumberAnimation { from: -shimmer.width; to: root.width; duration: 1400; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 350 }
        }
    }
}
