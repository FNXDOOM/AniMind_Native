import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// AnimePosterCard — 2:3 aspect poster card
// Matches stitch: rounded-2xl, rating badge top-right, optional "New Ep" badge top-left,
//                 hover scale-105 + primary border glow, title + sub/dub label below.
//
// Properties:
//   title        : string  — series title
//   rating       : string  — e.g. "9.8"  (empty hides badge)
//   audioLabel   : string  — e.g. "Sub | Dub" or "Sub Only"
//   newEpisode   : bool    — shows orange "New Ep" badge top-left
//   posterUrl    : string  — image source
//
// Signals:
//   clicked()

Item {
    id: card

    property string title:      "Untitled"
    property string rating:     ""
    property string audioLabel: "Sub | Dub"
    property bool   newEpisode: false
    property string posterUrl:  ""

    signal clicked()

    // Width is set by parent (grid); height derived from 2:3 aspect + meta below
    implicitHeight: posterArea.height + metaCol.implicitHeight + 12

    // ── Poster area ────────────────────────────────────────────────────────
    Item {
        id: posterArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: width * 3 / 2   // 2:3

        // Clip container
        Rectangle {
            id: posterClip
            anchors.fill: parent
            radius: 16           // rounded-2xl
            color: "#1c1b1b"     // surface-container-low fallback
            clip: true

            // Poster image
            Image {
                id: posterImg
                anchors.fill: parent
                source: card.posterUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                scale: cardMa.containsMouse ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }

            // Hover bottom gradient
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0;  color: "transparent" }
                    GradientStop { position: 0.65; color: "transparent" }
                    GradientStop { position: 1.0;  color: Qt.rgba(0.039, 0.039, 0.039, 0.9) }
                }
                opacity: cardMa.containsMouse ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 220 } }
            }
        }

        // Hover glow border — primary/50 + shadow (stitch: shadow-[0_0_20px_rgba(255,182,147,0.2)])
        Rectangle {
            anchors.fill: posterClip
            radius: posterClip.radius
            color: "transparent"
            border.color: Qt.rgba(1, 0.714, 0.576, cardMa.containsMouse ? 0.5 : 0.0)
            border.width: 2
            Behavior on border.color { ColorAnimation { duration: 220 } }

            layer.enabled: cardMa.containsMouse
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor:   Qt.rgba(1, 0.714, 0.576, 0.22)
                shadowBlur:    0.9
                shadowHorizontalOffset: 0
                shadowVerticalOffset:   0
            }
        }

        // "New Ep" badge — top-left (orange, solid)
        Rectangle {
            visible: card.newEpisode
            anchors { top: parent.top; left: parent.left; margins: 8 }
            height: 22; radius: 4
            width: newEpTxt.implicitWidth + 12
            color: "#ff6b00"

            Text {
                id: newEpTxt
                anchors.centerIn: parent
                text: "NEW EP"
                color: "white"
                font { family: "Inter"; pixelSize: 10; weight: Font.Bold; letterSpacing: 0.8 }
            }
        }

        // Rating badge — top-right (glass)
        Rectangle {
            visible: card.rating !== ""
            anchors { top: parent.top; right: parent.right; margins: 8 }
            height: 24; radius: 4
            width: ratingRow.implicitWidth + 10
            color: Qt.rgba(0.075, 0.075, 0.075, 0.82)

            Row {
                id: ratingRow
                anchors.centerIn: parent
                spacing: 3

                Text {
                    text: "\u2605"   // ★ filled star
                    color: "#ffb693"
                    font { pixelSize: 11 }
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: card.rating
                    color: "#ffb693"
                    font { family: "Inter"; pixelSize: 11; weight: Font.DemiBold }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Meta info ──────────────────────────────────────────────────────────
    Column {
        id: metaCol
        anchors { top: posterArea.bottom; topMargin: 10; left: parent.left; right: parent.right }
        spacing: 3

        Text {
            width: parent.width
            text: card.title
            color: cardMa.containsMouse ? "#ffb693" : "#e5e2e1"
            font { family: "Montserrat"; pixelSize: 14; weight: Font.DemiBold }
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            width: parent.width
            text: card.audioLabel
            color: "#e2bfb0"
            font { family: "Inter"; pixelSize: 11 }
        }
    }

    // ── Hit area ───────────────────────────────────────────────────────────
    MouseArea {
        id: cardMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
    }
}
