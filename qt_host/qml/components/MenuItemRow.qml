import QtQuick
import QtQuick.Controls
import ".."

// One row inside a floating menu: glyph, label, hover and keyboard.
Item {
    id: row

    required property string label
    property string glyph: ""

    signal picked()

    width: parent ? parent.width : 0
    height: 36
    activeFocusOnTab: true

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: hover.hovered ? Theme.hoverBg : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dFast } }
    }

    Row {
        anchors { left: parent.left; leftMargin: Theme.s3; verticalCenter: parent.verticalCenter }
        spacing: Theme.s3

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: row.glyph.length > 0
            text: row.glyph
            color: hover.hovered ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.iconFont
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: hover.hovered ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsBody
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: 2; anchors.rightMargin: 2
        height: 2; radius: 1
        color: Theme.accent
        visible: row.activeFocus
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: row.picked() }
    Keys.onReturnPressed: row.picked()
    Keys.onSpacePressed: row.picked()

    Accessible.role: Accessible.Button
    Accessible.name: row.label
    Accessible.onPressAction: row.picked()
}
