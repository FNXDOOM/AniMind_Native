import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Effects

// EpisodeThumbnailCard — 16:9 episode card with progress bar
// Used in Continue Watching and Trending rows
//
// Properties:
//   title        : string  — show title
//   episodeLabel : string  — e.g. "S1: E14 - Privilege of the Young"
//   duration     : string  — e.g. "24:12"
//   progress     : real    — 0.0–1.0, set to -1 to hide progress bar
//   thumbnailUrl : string  — local or network image URL
//
// Signals:
//   clicked()

Item {
    id: card

    property string title:        "Untitled"
    property string episodeLabel: ""
    property string duration:     ""
    property real   progress:     -1      // -1 = hidden
    property string thumbnailUrl: ""

    signal clicked()

    width: 320
    height: thumbArea.height + metaCol.implicitHeight + (progress >= 0 ? progressBar.height + 6 : 0) + 12

    // ── Thumbnail ──────────────────────────────────────────────────────────
    Item {
        id: thumbArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: width * 9 / 16   // 16:9

        // Rounded clip
        Rectangle {
            id: thumbClip
            anchors.fill: parent
            radius: 12
            color: "#201f1f"
            clip: true

            Image {
                id: thumb
                anchors.fill: parent
                source: card.thumbnailUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                scale: cardMa.containsMouse ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            }

            // Hover overlay — dark scrim + play icon
            Rectangle {
                anchors.fill: parent
                color: "#66000000"
                opacity: cardMa.containsMouse ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: "\u25cf"   // filled circle as play placeholder
                    color: "white"
                    font.pixelSize: 44
                    opacity: 0.9
                    // Use Material Symbols play_circle if font is loaded
                    // text: "\ue1c4"
                    // font.family: "Material Symbols Outlined"
                }
            }

            // Duration badge
            Rectangle {
                visible: card.duration !== ""
                anchors { bottom: parent.bottom; right: parent.right; margins: 8 }
                height: 20; radius: 4
                color: "#CC000000"
                width: durLabel.implicitWidth + 10

                Text {
                    id: durLabel
                    anchors.centerIn: parent
                    text: card.duration
                    color: "white"
                    font { family: "Inter"; pixelSize: 10; weight: Font.Medium }
                }
            }
        }

        // Hover glow border (matches stitch group-hover:border-primary/50 + shadow)
        Rectangle {
            anchors.fill: thumbClip
            radius: thumbClip.radius
            color: "transparent"
            border.color: Qt.rgba(1, 0.714, 0.576, cardMa.containsMouse ? 0.5 : 0.0)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 200 } }
        }
    }

    // ── Progress bar ───────────────────────────────────────────────────────
    Item {
        id: progressBar
        anchors { top: thumbArea.bottom; left: parent.left; right: parent.right; topMargin: 6 }
        height: card.progress >= 0 ? 4 : 0
        visible: card.progress >= 0

        Rectangle {
            anchors.fill: parent
            radius: 2
            color: "#353534"   // surface-container-highest

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, card.progress))
                height: parent.height
                radius: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ff6b00" }
                    GradientStop { position: 1.0; color: "#6f00be" }
                }
                // Progress glow (stitch: shadow-[0_0_10px_rgba(255,107,0,0.8)])
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor:   Qt.rgba(1, 0.42, 0, 0.55)
                    shadowBlur:    0.8
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset:   0
                }
            }
        }
    }

    // ── Meta info ──────────────────────────────────────────────────────────
    Column {
        id: metaCol
        anchors {
            top: card.progress >= 0 ? progressBar.bottom : thumbArea.bottom
            topMargin: card.progress >= 0 ? 6 : 10
            left: parent.left; right: parent.right
        }
        spacing: 3

        Text {
            width: parent.width
            text: card.title
            color: cardMa.containsMouse ? "#ffb693" : "#e5e2e1"
            font { family: "Montserrat"; pixelSize: 15; weight: Font.DemiBold }
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            visible: card.episodeLabel !== ""
            width: parent.width
            text: card.episodeLabel
            color: "#e2bfb0"
            font { family: "Inter"; pixelSize: 11; letterSpacing: 0.5 }
            elide: Text.ElideRight
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
