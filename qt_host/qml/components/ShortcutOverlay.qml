import QtQuick
import QtQuick.Layouts
import ".."

// ShortcutOverlay — the player's key map, rendered from the same list the key
// handler reads. Every row here has to be a binding that actually exists in
// main.qml's Keys.onPressed; an aspirational shortcut is worse than none.
Rectangle {
    id: overlay

    property bool open: false

    signal dismissed()

    anchors.fill: parent
    visible: opacity > 0.0
    color: Theme.veil
    opacity: open ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

    // [keys, action] — keys are what the handler matches, not what looks tidy.
    readonly property var map: [
        ["Space", "Play / pause"],
        ["\u2190  \u2192", "Seek 10 seconds"],
        ["\u2191  \u2193", "Volume"],
        ["M", "Mute"],
        ["F", "Fullscreen"],
        ["O", "Open a file"],
        ["[  ]", "Previous / next chapter"],
        ["Esc", "Close panel \u00b7 leave player"],
        ["?", "This list"]
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: overlay.dismissed()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(400, parent.width - Theme.s8)
        height: list.implicitHeight + Theme.s12
        radius: Theme.rLg
        color: Theme.glassPanel
        border.color: Theme.glassEdge
        border.width: 1
        scale: overlay.open ? 1.0 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

        ColumnLayout {
            id: list
            x: Theme.s6
            y: Theme.s6
            width: parent.width - Theme.s12
            spacing: Theme.s2

            Text {
                text: "Keyboard"
                color: Theme.textPrimary
                font.family: Theme.displayFont
                font.pixelSize: Theme.tsSection
                font.weight: Theme.wtSemiBold
                Layout.bottomMargin: Theme.s1
            }

            Repeater {
                model: overlay.map

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.s4

                    Rectangle {
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 26
                        radius: Theme.rSm
                        color: Theme.surfaceRaised
                        border.color: Theme.borderDefault
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: modelData[0]
                            color: Theme.textPrimary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsSmall
                            font.weight: Theme.wtMedium
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData[1]
                        color: Theme.textSecondary
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsBody
                    }
                }
            }
        }
    }
}
