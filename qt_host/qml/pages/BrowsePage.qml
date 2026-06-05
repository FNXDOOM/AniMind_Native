import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    color: "#0a0a0a"
    
    property var searchResults: []
    property bool loading: false
    property string errorMsg: ""
    property var genreOpts: ["All Genres", "Action", "Adventure", "Comedy", "Drama", "Fantasy"]
    property var sortOpts: ["Popularity", "Trending", "Release Date", "Score"]
    property var seasonOpts: ["Winter", "Spring", "Summer", "Fall"]
    property int selectedSeasonIdx: 0
    property int selectedGenreIdx: 0
    property int selectedSortIdx: 0
    property int lm: 32
    property string clrOrange: "#ff8c00"
    
    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal seriesClicked(int id)
    
    // Load data on page activation
    onVisibleChanged: {
        if (visible && searchResults.length === 0) {
            performSearch()
        }
    }
    Component.onCompleted: performSearch()
    
    function performSearch() {
        loading = true
        var genre = selectedGenreIdx >= 0 && selectedGenreIdx < genreOpts.length ? genreOpts[selectedGenreIdx] : null
        if (genre === "All Genres")
            genre = null
        var sort = selectedSortIdx >= 0 ? selectedSortIdx : 0
        var now = new Date()
        var seasonMap = ["WINTER", "SPRING", "SUMMER", "FALL"]
        var season = seasonMap[Math.max(0, Math.min(3, selectedSeasonIdx))]
        var seasonYear = now.getFullYear()
        errorMsg = ""

        AniListApi.searchAnime({
            genre: genre,
            sort: sort,
            season: season,
            seasonYear: seasonYear,
            page: 1,
            perPage: 24
        }, function(list, pageInfo, err) {
            if (err) {
                errorMsg = "Search failed: " + err
                searchResults = []
                loading = false
            } else if (list) {
                searchResults = list
                loading = false
            } else {
                errorMsg = "No results"
                searchResults = []
                loading = false
            }
        })
    }
    
    Column {
        anchors { fill: parent; margins: 16 }
        spacing: 16

        Text {
            text: "Popular This Season"
            color: "white"
            font.family: "Montserrat"
            font.pixelSize: 24
            font.bold: true
        }
        
        // Error message
        Rectangle {
            visible: errorMsg !== ""
            width: parent.width - 32
            height: errorText.implicitHeight + 12
            color: Qt.rgba(1, 0.2, 0.2, 0.3)
            radius: 6
            anchors.horizontalCenter: parent.horizontalCenter
            
            Text {
                id: errorText
                text: errorMsg
                color: "#ff6b6b"
                width: parent.width - 12
                wrapMode: Text.Wrap
                anchors.centerIn: parent
                font.pixelSize: 11
            }
        }
        
        // Filter bar
        Row {
            spacing: 12
            anchors.horizontalCenter: parent.horizontalCenter
            
            ComboBox {
                model: genreOpts
                currentIndex: selectedGenreIdx
                onActivated: { selectedGenreIdx = currentIndex; performSearch() }
                width: 120
            }
            
            ComboBox {
                model: sortOpts
                currentIndex: selectedSortIdx
                onActivated: { selectedSortIdx = currentIndex; performSearch() }
                width: 140
            }
            
            ComboBox {
                model: seasonOpts
                currentIndex: (new Date().getMonth() <= 2) ? 0 : ((new Date().getMonth() <= 5) ? 1 : ((new Date().getMonth() <= 8) ? 2 : 3))
                onActivated: {
                    selectedSeasonIdx = currentIndex
                    performSearch()
                }
                width: 100
            }
        }
        
        // Results grid
        Rectangle {
            id: resultsPane
            width: parent.width - 32
            height: Math.max(260, parent.height - y)
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#1a1a1a"
            radius: 8
            clip: true
            
            Flickable {
                id: browseFlick
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                contentWidth: width
                contentHeight: browseGrid.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: browseGrid
                    width: browseFlick.width
                    flow: Grid.LeftToRight
                    columns: Math.max(1, Math.floor((width + 14) / 204))
                    columnSpacing: 14
                    rowSpacing: 16

                    Repeater {
                        model: searchResults

                        AnimePosterCard {
                            width: Math.floor((browseGrid.width - (browseGrid.columnSpacing * (browseGrid.columns - 1))) / browseGrid.columns)
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

            Text {
                anchors.centerIn: parent
                visible: searchResults.length === 0 && !loading
                text: "No results"
                color: "#666"
                font.pixelSize: 14
            }
        }
    }
}
