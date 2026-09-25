import QtQuick
import ".."

// A single toast (section 35). Slides up and fades in, holds, then fades out;
// the shell owns the queue so several can stack without colliding.
Rectangle {
    id: toast

    required property string message
    property string kind: "info"     // info | success | error
    property bool leaving: false

    signal finished()

    property int holdMs: 2600

    implicitWidth: row.implicitWidth + Theme.s6
    height: row.implicitHeight + Theme.s3 * 2
    radius: Theme.rMd
    color: Theme.surfaceRaised
    border.color: kind === "error" ? Theme.accent : Theme.borderDefault
    border.width: 1

    opacity: leaving ? 0.0 : 1.0
    y: leaving ? 8 : 0

    Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
    Behavior on y { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.s3

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Glyphs confirmed by rendering them: E930 is a check inside a
            // circle, E783 an exclamation inside a circle, E946 an "i" inside
            // a circle. All three share the circle, so the three states read
            // as one family.
            text: toast.kind === "success" ? "\uE930"
                : toast.kind === "error"   ? "\uE783"
                :                            "\uE946"
            color: toast.kind === "error" ? Theme.accent : Theme.textPrimary
            font.family: Theme.iconFont
            font.pixelSize: 14
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: toast.message
            color: Theme.textPrimary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsBody
        }
    }

    // Hold, then start the fade, then report back so the shell can drop it
    // from the stack once it is actually invisible.
    Timer {
        interval: toast.holdMs
        running: toast.visible
        onTriggered: toast.leaving = true
    }
    Timer {
        interval: toast.holdMs + Theme.dBase + 60
        running: toast.visible
        onTriggered: toast.finished()
    }

    Accessible.role: Accessible.Notification
    Accessible.name: toast.message
}
