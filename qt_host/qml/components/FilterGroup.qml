import QtQuick
import ".."

// One labelled group of mutually exclusive options inside FilterDialog.
// Values are compared as strings so an int sort index and a string status can
// share the same control.
Column {
    id: group

    required property string title
    property var   opts:    []       // [{ v, label }]
    property var   current: ""

    signal picked(var value)

    spacing: Theme.s2

    Text {
        text: group.title
        color: Theme.textMuted
        font.family: Theme.bodyFont
        font.pixelSize: Theme.tsSmall
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.trackingWide
    }

    Repeater {
        model: group.opts

        delegate: Item {
            id: optRow
            required property var modelData
            width: group.width
            height: 28

            readonly property bool on: String(modelData.v) === String(group.current)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s3

                Rectangle {
                    width: 15; height: 15; radius: 7.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"
                    border.color: optRow.on ? Theme.accent : Theme.borderStrong
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Theme.dFast } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 7; height: 7; radius: 3.5
                        color: Theme.accent
                        visible: optRow.on
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: optRow.on ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsBody
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: group.picked(modelData.v) }

            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.label
            Accessible.checked: optRow.on
            Accessible.onPressAction: group.picked(modelData.v)
        }
    }
}
