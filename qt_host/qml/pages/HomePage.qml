import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    color: "#0a0a0a"
    
    property var trendingList: []
    property var heroMedia: null
    property bool loadingHero: false
    property bool loadingAiring: false
    property var airingList: []
    property string errorMsg: ""
    property int lm: 32
    
    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal seriesClicked(int id)

    function loadTrendingIfNeeded() {
        if (trendingList.length > 0 || loadingHero)
            return

        loadingHero = true
        errorMsg = ""
        AniListApi.trendingAnime(10, function(list, err) {
            if (err) {
                errorMsg = "Failed to load trending: " + err
                loadingHero = false
            } else if (list && list.length > 0) {
                trendingList = list
                heroMedia = list[0]
                loadingHero = false
            } else {
                errorMsg = "No trending data returned"
                loadingHero = false
            }
        })
    }
    
    // Load trending data on page activation
    onVisibleChanged: {
        if (visible)
            loadTrendingIfNeeded()
    }

    Component.onCompleted: loadTrendingIfNeeded()
    
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        
        Column {
            id: col
            width: parent.width
            spacing: 24
            topPadding: 16
            bottomPadding: 32
            
            // Error message display
            Rectangle {
                visible: errorMsg !== ""
                width: parent.width - 64
                height: errorMsgText.implicitHeight + 16
                color: Qt.rgba(1, 0.2, 0.2, 0.3)
                radius: 8
                anchors.horizontalCenter: parent.horizontalCenter
                
                Text {
                    id: errorMsgText
                    text: errorMsg
                    color: "#ff6b6b"
                    width: parent.width - 16
                    wrapMode: Text.Wrap
                    anchors.centerIn: parent
                    font.pixelSize: 12
                }
            }
            
            // Trending/Hero section
            Item {
                width: parent.width
                height: loadingHero ? 300 : (heroMedia ? 400 : 100)
                visible: loadingHero || heroMedia !== null
                
                Rectangle {
                    anchors.fill: parent
                    color: "#1a1a1a"
                    radius: 8
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: heroMedia && heroMedia.bannerImage ? heroMedia.bannerImage
                               : (heroMedia ? AniListApi.cover(heroMedia) : "")
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: 0.35
                    }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
                            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.70) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.85) }
                        }
                    }
                    
                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12
                        
                        Text {
                            text: loadingHero ? "Loading..." : (heroMedia ? AniListApi.title(heroMedia) : "No media")
                            color: "white"
                            font.pixelSize: 40
                            font.bold: true
                        }
                        
                        Text {
                            text: heroMedia ? ("Score: " + AniListApi.score(heroMedia) + " / 10") : ""
                            color: "#aaa"
                            font.pixelSize: 14
                        }
                        
                        Row {
                            spacing: 12
                            
                            Button {
                                text: "Play"
                                onClicked: if (heroMedia) playRequested(heroMedia.id, heroMedia.title.romaji)
                            }
                            
                            Button {
                                text: "Add to List"
                                onClicked: if (heroMedia) addToListRequested(heroMedia.id)
                            }
                        }
                    }
                }
            }
            
            // Trending list
            Rectangle {
                width: parent.width - 64
                anchors.horizontalCenter: parent.horizontalCenter
                height: 340
                color: "#1a1a1a"
                radius: 8
                
                Column {
                    anchors { fill: parent; margins: 16 }
                    spacing: 12
                    
                    Text {
                        text: "Trending Anime"
                        color: "white"
                        font.pixelSize: 16
                        font.bold: true
                    }
                    
                    ScrollView {
                        width: parent.width
                        height: parent.height - 40
                        
                        ListView {
                            id: trendingCards
                            width: parent.width
                            height: parent.height
                            model: trendingList
                            orientation: ListView.Horizontal
                            spacing: 18
                            clip: true

                            delegate: AnimePosterCard {
                                width: 170
                                title: AniListApi.title(modelData)
                                rating: AniListApi.score(modelData)
                                audioLabel: AniListApi.audioLabel(modelData)
                                newEpisode: AniListApi.isNewEpisode(modelData)
                                posterUrl: AniListApi.cover(modelData)
                                onClicked: playRequested(modelData.id, AniListApi.title(modelData))
                            }
                        }
                    }
                }
            }
        }
    }
}
