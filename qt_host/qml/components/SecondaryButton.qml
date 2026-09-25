import QtQuick
import QtQuick.Controls
import ".."

// Quiet companion to PrimaryButton: translucent surface, hairline border.
// Used for every secondary action so the white pill stays singular.
Rectangle {
    id: btn

    required property string text
    property string glyph: ""
    property int  textSize: Theme.tsBody

    signal clicked()

    implicitWidth: row.implicitWidth + Theme.s6
    implicitHeight: 44
    radius: Theme.rMd
    color: btn.pressed ? Theme.surfaceRaised : (btn.hovered ? Theme.card : Theme.bgSecondary)
    border.color: btn.hovered ? Theme.borderStrong : Theme.borderDefault
    border.width: 1
    opacity: enabled ? 1.0 : 0.45
    activeFocusOnTab: true

    readonly property alias hovered: hover.hovered
    readonly property alias pressed: tap.pressed

    scale: btn.pressed ? 0.97 : (btn.hovered ? 1.02 : 1.0)

    Behavior on color       { ColorAnimation { duration: Theme.dFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.dFast } }
    Behavior on scale       { NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.s2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.glyph.length > 0
            text: btn.glyph
            font.family: Theme.iconFont
            font.pixelSize: btn.textSize
            color: Theme.textPrimary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: Theme.textPrimary
            font.family: Theme.bodyFont
            font.pixelSize: btn.textSize
            font.weight: Font.Medium
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: btn.radius - 2
        color: "transparent"
        border.color: Theme.accent
        border.width: 2
        visible: btn.activeFocus
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: btn.clicked() }

    Keys.onReturnPressed: btn.clicked()
    Keys.onSpacePressed:  btn.clicked()

    Accessible.role: Accessible.Button
    Accessible.name: btn.text
    Accessible.onPressAction: btn.clicked()
}
