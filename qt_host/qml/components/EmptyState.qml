import QtQuick
import ".."

// Shared empty / error screen. An empty state is an invitation to act, so it
// always carries an action; the error variant explains what went wrong.
Column {
    id: empty

    required property string title
    property string body: ""
    property string glyph: "\uE71D"
    property string actionLabel: ""
    property bool   isError: false

    signal actionRequested()

    width: Math.min(implicitWidth, 380)
    spacing: Theme.s4

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.glyph
        font.family: Theme.iconFont
        font.pixelSize: 44
        color: empty.isError ? Theme.accent : Qt.rgba(1, 1, 1, 0.13)

        Behavior on color { ColorAnimation { duration: Theme.dBase } }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: empty.title
        color: Theme.textPrimary
        font.family: Theme.displayFont
        font.pixelSize: Theme.tsPage - 8
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        width: parent.width
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: empty.body.length > 0
        text: empty.body
        color: Theme.textSecondary
        font.family: Theme.bodyFont
        font.pixelSize: Theme.tsBody
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        width: parent.width
    }

    Loader {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: empty.actionLabel.length > 0
        sourceComponent: empty.isError ? quietAction : solidAction

        Component {
            id: solidAction
            PrimaryButton {
                text: empty.actionLabel
                onClicked: empty.actionRequested()
            }
        }
        Component {
            id: quietAction
            SecondaryButton {
                text: empty.actionLabel
                onClicked: empty.actionRequested()
            }
        }
    }
}
