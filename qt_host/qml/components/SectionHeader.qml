import QtQuick
import QtQuick.Controls
import ".."

// Row header: section title plus an optional "See all" affordance. Every
// horizontal rail uses this so the header height and rhythm never drift.
Item {
    id: head

    required property string title
    property string actionLabel: ""
    property int  titleSize: Theme.tsSection

    signal actionRequested()

    implicitWidth: 400
    implicitHeight: Math.max(titleText.implicitHeight, actionRow.implicitHeight)

    Text {
        id: titleText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: head.title
        color: Theme.textPrimary
        font.family: Theme.displayFont
        font.pixelSize: head.titleSize
        font.weight: Font.DemiBold
    }

    Row {
        id: actionRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.s1
        visible: head.actionLabel.length > 0
        opacity: hover.hovered ? 1.0 : 0.62

        Behavior on opacity { NumberAnimation { duration: Theme.dFast } }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: head.actionLabel
            color: Theme.textPrimary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsMeta
            font.weight: Font.Medium
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uE76C"
            color: Theme.textPrimary
            font.family: Theme.iconFont
            font.pixelSize: Theme.tsMeta
        }

        HoverHandler { id: hover }
        TapHandler { onTapped: head.actionRequested() }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: head.title
}
