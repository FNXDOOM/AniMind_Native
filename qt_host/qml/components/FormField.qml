import QtQuick
import ".."

// FormField — the shell's one text-input primitive.
//
// A Rectangle around TextInput rather than Controls.TextField: Material's own field draws
// its underline, ripple and placeholder, all of which fight the glass surfaces, and
// TextField has no maxLength/capitalization on this Qt version.
Rectangle {
    id: field

    required property string label
    property string placeholder: ""
    property int echoMode: TextInput.Normal
    property alias text: input.text
    property alias fieldInput: input
    property int fontPixelSize: Theme.tsBody

    signal accepted()

    implicitWidth: 260
    implicitHeight: 60
    radius: Theme.rMd
    color: Theme.input
    border.color: input.activeFocus ? Theme.borderStrong : Theme.borderSubtle
    Behavior on border.color { ColorAnimation { duration: Theme.dFast } }

    // Declared before the Column so the TextInput keeps its own clicks and only the
    // padding around it forwards focus.
    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    Column {
        anchors { fill: parent; leftMargin: Theme.s4; rightMargin: Theme.s4; topMargin: Theme.s2 + 1 }
        spacing: 2

        Text {
            text: field.label.toUpperCase()
            color: input.activeFocus ? Theme.textSecondary : Theme.textMuted
            font.family: Theme.bodyFont
            font.pixelSize: 10
            font.letterSpacing: Theme.trackingWide
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }

        TextInput {
            id: input
            width: parent.width
            color: Theme.textPrimary
            selectedTextColor: Theme.textPrimary
            selectionColor: Theme.accentSoft
            font.family: Theme.bodyFont
            font.pixelSize: field.fontPixelSize
            echoMode: field.echoMode
            clip: true
            onAccepted: field.accepted()

            Text {
                anchors.fill: parent
                visible: input.text.length === 0 && !input.activeFocus
                verticalAlignment: Text.AlignVCenter
                text: field.placeholder
                color: Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: field.fontPixelSize
            }
        }
    }
}
