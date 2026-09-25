import QtQuick
import QtQuick.Controls
import ".."

// Solid white pill with black text: the app's one loud affirmative control.
// The red accent is deliberately kept off buttons so it stays meaningful on
// progress and selection.
Rectangle {
    id: btn

    required property string text
    property string glyph: ""
    property int  textSize: Theme.tsBody

    signal clicked()

    implicitWidth: row.implicitWidth + Theme.s8
    implicitHeight: 44
    radius: Theme.rMd
    color: !enabled ? "#2a2f36"
           : btn.pressed ? Theme.textSecondary
           : btn.hovered ? "#ffffff"
           : Theme.textPrimary
    border.width: 0
    opacity: enabled ? 1.0 : 0.55
    activeFocusOnTab: true

    readonly property alias hovered: hover.hovered
    readonly property alias pressed: mouse.pressed

    scale: !enabled ? 1.0 : btn.pressed ? 0.97 : (btn.hovered ? 1.02 : 1.0)

    Behavior on color   { ColorAnimation { duration: Theme.dFast } }
    Behavior on scale   { NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic } }
    Behavior on opacity { ColorAnimation { duration: Theme.dFast } }

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
            color: "#07090C"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.text.length > 0
            text: btn.text
            color: "#07090C"
            font.family: Theme.bodyFont
            font.pixelSize: btn.textSize
            font.weight: Font.DemiBold
        }
    }

    // Focus ring drawn inside the pill so it never changes the control's size.
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
    TapHandler { id: mouse; onTapped: btn.clicked() }

    Keys.onReturnPressed: btn.clicked()
    Keys.onSpacePressed:  btn.clicked()

    Accessible.role: Accessible.Button
    Accessible.name: btn.text
    Accessible.onPressAction: btn.clicked()
}
