import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: card

    property string title:      "Untitled"
    property string rating:     ""
    property string subtext:    ""
    property string epText:     ""
    property string posterUrl:  ""

    signal clicked()
    signal watchClicked()
    signal addClicked()

    implicitHeight: posterArea.height + metaCol.implicitHeight + 12

    // ── Poster area ────────────────────────────────────────────────────────
    Item {
        id: posterArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: width * 3 / 2

        Rectangle {
            id: posterClip
            anchors.fill: parent
            radius: 12
            color: "#1c1b1b"
            clip: true

            Image {
                id: posterImg
                anchors.fill: parent
                source: card.posterUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                scale: cardMa.containsMouse ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0;  color: "transparent" }
                    GradientStop { position: 0.5;  color: "transparent" }
                    GradientStop { position: 1.0;  color: Qt.rgba(0.039, 0.039, 0.039, 0.95) }
                }
                opacity: cardMa.containsMouse ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
            
            // Hover buttons
            Row {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12 }
                spacing: 8
                height: 32
                visible: cardMa.containsMouse
                
                Rectangle {
                    width: parent.width - 40
                    height: parent.height
                    radius: 8
                    color: watchMa.containsMouse ? "#e06b1e" : "#f47521"
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Text { text: "▶"; color: "white"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Watch"; color: "white"; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: watchMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.watchClicked()
                    }
                }
                Rectangle {
                    width: 32
                    height: parent.height
                    radius: 8
                    color: addMa.containsMouse ? Qt.rgba(1,1,1,0.3) : Qt.rgba(1,1,1,0.2)
                    Text { text: "+"; color: "white"; anchors.centerIn: parent; font.pixelSize: 16 }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.addClicked()
                    }
                }
            }
        }

        // Rating badge — top-left (glass)
        Rectangle {
            visible: card.rating !== ""
            anchors { top: parent.top; left: parent.left; margins: 8 }
            height: 22; radius: 4
            width: ratingRow.implicitWidth + 12
            color: Qt.rgba(0.075, 0.075, 0.075, 0.82)
            Row {
                id: ratingRow
                anchors.centerIn: parent
                spacing: 4
                Text { text: "★"; color: "#ffd700"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                Text { text: card.rating; color: "#f0f0f5"; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            }
        }

        // EP badge — top-right (orange)
        Rectangle {
            visible: card.epText !== ""
            anchors { top: parent.top; right: parent.right; margins: 8 }
            height: 22; radius: 4
            width: epTxt.implicitWidth + 12
            color: "#f47521"
            Text {
                id: epTxt
                anchors.centerIn: parent
                text: card.epText
                color: "white"
                font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Bold
            }
        }
        
        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: card.clicked()
            // Make sure the hover buttons can be clicked by letting the MouseArea not block them
            // or we put the Hover buttons OVER the MouseArea!
        }
    }

    // ── Meta info ──────────────────────────────────────────────────────────
    Column {
        id: metaCol
        anchors { top: posterArea.bottom; topMargin: 10; left: parent.left; right: parent.right }
        spacing: 4

        Text {
            width: parent.width
            text: card.title
            color: cardMa.containsMouse ? "#f47521" : "#f0f0f5"
            font.family: "Montserrat"; font.pixelSize: 14; font.weight: Font.DemiBold
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            lineHeight: 1.1
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            width: parent.width
            text: card.subtext
            color: "#8888a0"
            font.family: "Inter"; font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
}
