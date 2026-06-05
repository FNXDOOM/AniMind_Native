import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    color: "#0a0a0a"

    property var shows: (authManager && authManager.libraryShows) ? authManager.libraryShows : []
    signal showSelected(string showId, string showTitle)

    Column {
        anchors { fill: parent; margins: 16 }
        spacing: 14

        Text {
            text: "Simulcasts"
            color: "white"
            font.family: "Montserrat"
            font.pixelSize: 24
            font.bold: true
        }

        Text {
            text: authManager && authManager.authenticated
                  ? "From your cloud library"
                  : "Sign in to load your cloud library"
            color: "#b8b8b8"
            font.pixelSize: 12
        }

        Rectangle {
            width: parent.width - 32
            height: Math.max(260, parent.height - y)
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#1a1a1a"
            radius: 8
            clip: true

            Flickable {
                id: listFlick
                anchors.fill: parent
                anchors.margins: 12
                contentWidth: width
                contentHeight: showsGrid.implicitHeight
                clip: true

                Grid {
                    id: showsGrid
                    width: listFlick.width
                    flow: Grid.LeftToRight
                    columns: Math.max(1, Math.floor((width + 14) / 204))
                    columnSpacing: 14
                    rowSpacing: 16

                    Repeater {
                        model: shows
                        AnimePosterCard {
                            width: Math.floor((showsGrid.width - (showsGrid.columnSpacing * (showsGrid.columns - 1))) / showsGrid.columns)
                            title: modelData.title || "Untitled"
                            rating: (modelData.rating !== undefined && modelData.rating !== null) ? String(modelData.rating) : ""
                            audioLabel: (modelData.episode_count !== undefined && modelData.episode_count !== null)
                                ? (String(modelData.episode_count) + " episodes")
                                : "Simulcast"
                            newEpisode: false
                            posterUrl: modelData.cover_image_url || ""
                            onClicked: showSelected(String(modelData.id || ""), modelData.title || "Untitled")
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: shows.length === 0
                text: authManager && authManager.authenticated
                      ? "No simulcast shows found in your library."
                      : "Sign in to view simulcasts."
                color: "#666"
                font.pixelSize: 14
            }
        }
    }
}
