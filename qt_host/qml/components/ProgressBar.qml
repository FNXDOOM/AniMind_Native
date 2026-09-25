import QtQuick
import ".."

// Accent progress bar. This is one of the few places the red is allowed.
Rectangle {
    id: bar

    property real value: 0.0
    property int  trackHeight: 4
    property bool animate: true

    implicitWidth: 120
    implicitHeight: trackHeight
    radius: trackHeight / 2
    color: Qt.rgba(1, 1, 1, 0.12)

    Rectangle {
        width: bar.width * Math.max(0, Math.min(1, bar.value))
        height: bar.height
        radius: bar.radius
        color: Theme.accent

        Behavior on width {
            enabled: bar.animate
            NumberAnimation { duration: Theme.dSlow; easing.type: Theme.easeOutCubic }
        }
    }

    Accessible.role: Accessible.ProgressBar
    Accessible.name: Math.round(bar.value * 100) + "% watched"
}
