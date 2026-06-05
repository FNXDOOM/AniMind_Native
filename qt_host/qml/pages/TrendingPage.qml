import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    color: "#0a0a0a"

    property var trendingList: []
    property bool loading: false
    property string errorMsg: ""

    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal seriesClicked(int id)

    function loadTrending() {
        if (loading)
            return
        loading = true
        errorMsg = ""
        AniListApi.trendingAnime(30, function(list, err) {
            loading = false
            if (err) {
                errorMsg = "Failed to load trending: " + err
                return
            }
            trendingList = list || []
        })
    }

    onVisibleChanged: if (visible && trendingList.length === 0) loadTrending()
    Component.onCompleted: loadTrending()

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        Text {
            text: "Trending Now"
            color: "white"
            font.family: "Montserrat"
            font.pixelSize: 26
            font.bold: true
        }

        Text {
            visible: errorMsg !== ""
            text: errorMsg
            color: "#ff6b6b"
            font.pixelSize: 12
        }

        Flickable {
            id: trendFlick
            width: parent.width
            height: parent.height - 48
            clip: true
            contentWidth: width
            contentHeight: trendGrid.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: trendGrid
                width: trendFlick.width
                flow: Grid.LeftToRight
                columns: Math.max(1, Math.floor((width - 8) / 188))
                columnSpacing: 18
                rowSpacing: 18

                Repeater {
                    model: trendingList
                    AnimePosterCard {
                        width: Math.floor((trendGrid.width - (trendGrid.columnSpacing * (trendGrid.columns - 1))) / trendGrid.columns)
                        title: AniListApi.title(modelData)
                        rating: AniListApi.score(modelData)
                        audioLabel: AniListApi.audioLabel(modelData)
                        newEpisode: AniListApi.isNewEpisode(modelData)
                        posterUrl: AniListApi.cover(modelData)
                        onClicked: seriesClicked(modelData.id)
                    }
                }
            }
        }
    }
}
