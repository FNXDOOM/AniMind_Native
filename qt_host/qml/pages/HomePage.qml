import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    id: homePage
    color: "#0a0a0f"

    property var  trendingList: []
    property var  simulcastList: []
    property var  airingList:   []
    property var  heroMedia:    null
    property bool loadingHero:  false
    property string errorMsg:   ""

    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal seriesClicked(int id)

    function loadTrendingIfNeeded() {
        if (trendingList.length > 0 || loadingHero) return
        loadingHero = true
        errorMsg = ""
        AniListApi.trendingAnime(12, function(list, err) {
            loadingHero = false
            if (err) {
                errorMsg = "Could not load trending: " + err
            } else if (list && list.length > 0) {
                trendingList = list
                heroMedia = list[0]
            } else {
                errorMsg = "No trending data returned"
            }
        })
        AniListApi.seasonalAnime("SPRING", 2024, 12, function(list, err) {
            if (!err && list && list.length > 0) {
                simulcastList = list
            }
        })
        AniListApi.airingNow(12, function(list, err) {
            if (!err && list && list.length > 0) {
                airingList = list
            }
        })
    }

    onVisibleChanged: { if (visible) loadTrendingIfNeeded() }
    Component.onCompleted: loadTrendingIfNeeded()

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: homePage.width
        contentHeight: pageCol.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3500

        Column {
            id: pageCol
            x: 0; y: 0
            width: homePage.width
            spacing: 0

            // ── Error banner ─────────────────────────────────────────────────
            Item {
                width: parent.width
                height: errorMsg !== "" ? (eTxt.implicitHeight + 24) : 0
                visible: errorMsg !== ""
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 0.2, 0.2, 0.25)
                    radius: 8
                    anchors.margins: 32
                    Text {
                        id: eTxt
                        text: errorMsg; color: "#ff6b6b"; wrapMode: Text.Wrap
                        font.pixelSize: 13
                        width: parent.width - 32
                        anchors.centerIn: parent
                    }
                }
            }

            // ── Hero section ─────────────────────────────────────────────────
            Item {
                id: hero
                width: parent.width
                height: 500

                // Always-visible dark bg (no rotation ever applied here)
                Rectangle { anchors.fill: parent; color: "#0d0d18" }

                // Pulsing loading ring (opacity only — NO RotationAnimator)
                Rectangle {
                    anchors.centerIn: parent
                    width: 48; height: 48; radius: 24
                    color: "transparent"
                    border.color: "#f47521"; border.width: 2
                    visible: loadingHero && heroMedia === null
                    SequentialAnimation on opacity {
                        running: parent.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                // Banner image (shown once loaded)
                Image {
                    anchors.fill: parent
                    source: heroMedia
                            ? (heroMedia.bannerImage && heroMedia.bannerImage !== ""
                               ? heroMedia.bannerImage
                               : AniListApi.cover(heroMedia))
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                // Left-to-right dark gradient
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: Qt.rgba(0.039, 0.039, 0.059, 0.97) }
                        GradientStop { position: 0.42; color: Qt.rgba(0.039, 0.039, 0.059, 0.60) }
                        GradientStop { position: 1.00; color: Qt.rgba(0.039, 0.039, 0.059, 0.10) }
                    }
                }

                // Bottom fade
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.00; color: "transparent" }
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1.00; color: "#0a0a0f" }
                    }
                }

                // Hero text block
                Item {
                    id: heroText
                    visible: heroMedia !== null
                    x: 48
                    width: Math.min(hero.width * 0.50, 560)
                    height: heroCol.implicitHeight
                    y: hero.height - heroCol.implicitHeight - 52

                    Column {
                        id: heroCol
                        width: parent.width
                        spacing: 10

                        // Genre tags
                        Row {
                            spacing: 8
                            Repeater {
                                model: heroMedia && heroMedia.genres
                                       ? Math.min(heroMedia.genres.length, 3)
                                       : 0
                                delegate: Rectangle {
                                    height: 22; radius: 4
                                    width: _gt.implicitWidth + 16
                                    color: Qt.rgba(0.95, 0.46, 0.13, 0.15)
                                    border.color: Qt.rgba(0.95, 0.46, 0.13, 0.30)
                                    border.width: 1
                                    Text {
                                        id: _gt
                                        anchors.centerIn: parent
                                        text: heroMedia.genres[index]
                                        color: "#f47521"
                                        font.family: "Inter"
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }

                        // Title
                        Text {
                            width: parent.width
                            text: heroMedia ? AniListApi.title(heroMedia) : ""
                            color: "#f0f0f5"
                            font.family: "Montserrat"
                            font.pixelSize: 36
                            font.weight: Font.Bold
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 1.15
                        }

                        // Meta: score · studio · year
                        Row {
                            spacing: 12
                            visible: heroMedia !== null

                            Row {
                                spacing: 4
                                visible: heroMedia && AniListApi.score(heroMedia) !== ""
                                Text { text: "★"; color: "#ffd700"; font.pixelSize: 13 }
                                Text {
                                    text: heroMedia ? AniListApi.score(heroMedia) : ""
                                    color: "#ffd700"
                                    font.family: "Inter"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                            }
                            Text {
                                visible: heroMedia && AniListApi.studio(heroMedia) !== ""
                                text: heroMedia ? AniListApi.studio(heroMedia) : ""
                                color: "#8888a0"
                                font.family: "Inter"
                                font.pixelSize: 12
                            }
                            Text {
                                visible: heroMedia && heroMedia.seasonYear
                                text: heroMedia && heroMedia.seasonYear ? heroMedia.seasonYear.toString() : ""
                                color: "#8888a0"
                                font.family: "Inter"
                                font.pixelSize: 12
                            }
                        }

                        // Synopsis
                        Text {
                            width: parent.width
                            text: heroMedia ? AniListApi.cleanDesc(heroMedia) : ""
                            color: "#a0a0b8"
                            font.family: "Inter"
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            lineHeight: 1.6
                        }

                        // Buttons
                        Row {
                            spacing: 12
                            topPadding: 4

                            // Watch Now
                            Rectangle {
                                width: _wr.implicitWidth + 40
                                height: 42; radius: 8
                                color: _wma.pressed ? "#c4601b"
                                     : _wma.containsMouse ? "#e06b1e" : "#f47521"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                scale: _wma.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Row {
                                    id: _wr
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { text: "▶"; color: "white"; font.pixelSize: 13 }
                                    Text {
                                        text: "Watch Now"; color: "white"
                                        font.family: "Inter"
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                                MouseArea {
                                    id: _wma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (heroMedia) playRequested(heroMedia.id, AniListApi.title(heroMedia))
                                }
                            }

                            // More Info
                            Rectangle {
                                width: _ir.implicitWidth + 32
                                height: 42; radius: 8
                                color: _ima.pressed ? Qt.rgba(1,1,1,0.15)
                                     : _ima.containsMouse ? Qt.rgba(1,1,1,0.12)
                                     : Qt.rgba(1,1,1,0.07)
                                border.color: Qt.rgba(1,1,1,0.14)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                scale: _ima.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Row {
                                    id: _ir
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { text: "ℹ"; color: "#f0f0f5"; font.pixelSize: 15 }
                                    Text {
                                        text: "More Info"; color: "#f0f0f5"
                                        font.family: "Inter"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                }
                                MouseArea {
                                    id: _ima
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (heroMedia) seriesClicked(heroMedia.id)
                                }
                            }
                        }
                    }
                }
            } // hero

            Item { width: 1; height: 32 }

            // ── Trending Now row ──────────────────────────────────────────────
            Item {
                width: parent.width
                height: trendHeader.implicitHeight + 16 + 350
                visible: trendingList.length > 0

                Item {
                    id: trendHeader
                    x: 24; y: 0
                    width: parent.width - 48
                    height: trendHeaderCol.implicitHeight

                    Column {
                        id: trendHeaderCol
                        spacing: 4
                        Row {
                            spacing: 10
                            Text {
                                text: "Trending Now"
                                color: "#f0f0f5"
                                font.family: "Montserrat"
                                font.pixelSize: 20
                                font.weight: Font.Bold
                            }
                            Rectangle {
                                width: _hot.implicitWidth + 14; height: 20; radius: 4
                                color: Qt.rgba(0.95,0.46,0.13,0.15)
                                border.color: Qt.rgba(0.95,0.46,0.13,0.30); border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: _hot; anchors.centerIn: parent
                                    text: "HOT"; color: "#f47521"
                                    font.family: "Inter"; font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        Text {
                            text: "Hottest picks this week"
                            color: "#8888a0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        
                        Text {
                            text: "See All →"
                            color: "#f47521"
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Row {
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                                Text { text: "<"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: cardList.contentX = Math.max(0, cardList.contentX - 320) }
                            }
                            Rectangle {
                                width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                                Text { text: ">"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: cardList.contentX = Math.min(cardList.contentWidth - cardList.width, cardList.contentX + 320) }
                            }
                        }
                    }
                }

                ListView {
                    id: cardList
                    x: 24
                    y: trendHeader.implicitHeight + 16
                    width: parent.width - 48
                    height: 350
                    model: trendingList
                    orientation: ListView.Horizontal
                    spacing: 16
                    clip: true
                    flickDeceleration: 3500
                    maximumFlickVelocity: 3000

                    delegate: AnimePosterCard {
                        width: 180
                        title: AniListApi.title(modelData)
                        rating: AniListApi.score(modelData)
                        subtext: (AniListApi.studio(modelData) ? AniListApi.studio(modelData) + " · " : "") + (modelData.seasonYear || "")
                        epText: AniListApi.isNewEpisode(modelData) ? "NEW EP" : (modelData.episodes ? "EP " + modelData.episodes : "")
                        posterUrl: AniListApi.cover(modelData)
                        onClicked: seriesClicked(modelData.id)
                    }
                }
            }

            Item { width: 1; height: 32 }

            // ── Simulcasts row ──────────────────────────────────────────────
            Item {
                width: parent.width
                height: simulHeader.implicitHeight + 16 + 350 + 32
                visible: simulcastList.length > 0

                Item {
                    id: simulHeader
                    x: 24; y: 0
                    width: parent.width - 48
                    height: simulHeaderCol.implicitHeight

                    Column {
                        id: simulHeaderCol
                        spacing: 4
                        Row {
                            spacing: 10
                            Text {
                                text: "Simulcasts"
                                color: "#f0f0f5"
                                font.family: "Montserrat"
                                font.pixelSize: 20
                                font.weight: Font.Bold
                            }
                            Rectangle {
                                width: _live.implicitWidth + 14; height: 20; radius: 4
                                color: Qt.rgba(0.95,0.46,0.13,0.15)
                                border.color: Qt.rgba(0.95,0.46,0.13,0.30); border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: _live; anchors.centerIn: parent
                                    text: "LIVE"; color: "#f47521"
                                    font.family: "Inter"; font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        Text {
                            text: "Same day as Japan"
                            color: "#8888a0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                            Text { text: "<"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: simulList.contentX = Math.max(0, simulList.contentX - 320) }
                        }
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                            Text { text: ">"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: simulList.contentX = Math.min(simulList.contentWidth - simulList.width, simulList.contentX + 320) }
                        }
                    }
                }

                ListView {
                    id: simulList
                    x: 24
                    y: simulHeader.implicitHeight + 16
                    width: parent.width - 48
                    height: 350
                    model: simulcastList
                    orientation: ListView.Horizontal
                    spacing: 16
                    clip: true
                    flickDeceleration: 3500
                    maximumFlickVelocity: 3000

                    delegate: AnimePosterCard {
                        width: 180
                        title: AniListApi.title(modelData)
                        rating: AniListApi.score(modelData)
                        subtext: (AniListApi.studio(modelData) ? AniListApi.studio(modelData) + " · " : "") + (modelData.seasonYear || "")
                        epText: "EP Ongoing"
                        posterUrl: AniListApi.cover(modelData)
                        onClicked: seriesClicked(modelData.id)
                    }
                }
            }

            Item { width: 1; height: 32 }

            // ── Currently Airing row ────────────────────────────────────────
            Item {
                width: parent.width
                height: airingHeader.implicitHeight + 16 + 350 + 32
                visible: airingList.length > 0

                Item {
                    id: airingHeader
                    x: 24; y: 0
                    width: parent.width - 48
                    height: airingHeaderCol.implicitHeight

                    Column {
                        id: airingHeaderCol
                        spacing: 4
                        Text {
                            text: "Currently Airing"
                            color: "#f0f0f5"
                            font.family: "Montserrat"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "New episodes this season"
                            color: "#8888a0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                            Text { text: "<"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: airingListView.contentX = Math.max(0, airingListView.contentX - 320) }
                        }
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                            Text { text: ">"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: airingListView.contentX = Math.min(airingListView.contentWidth - airingListView.width, airingListView.contentX + 320) }
                        }
                    }
                }

                ListView {
                    id: airingListView
                    x: 24
                    y: airingHeader.implicitHeight + 16
                    width: parent.width - 48
                    height: 350
                    model: airingList
                    orientation: ListView.Horizontal
                    spacing: 16
                    clip: true
                    flickDeceleration: 3500
                    maximumFlickVelocity: 3000

                    delegate: AnimePosterCard {
                        width: 180
                        title: AniListApi.title(modelData)
                        rating: AniListApi.score(modelData)
                        subtext: (AniListApi.studio(modelData) ? AniListApi.studio(modelData) + " · " : "") + (modelData.seasonYear || "")
                        epText: modelData.nextAiringEpisode ? "EP " + modelData.nextAiringEpisode.episode : ""
                        posterUrl: AniListApi.cover(modelData)
                        onClicked: seriesClicked(modelData.id)
                    }
                }
            }

            Item { width: 1; height: 32 }

            // ── Top Rated row ───────────────────────────────────────────────
            Item {
                width: parent.width
                height: topRatedHeader.implicitHeight + 16 + 350 + 32
                visible: trendingList.length > 0

                property var topRatedList: {
                    var arr = trendingList.slice()
                    arr.sort(function(a, b) { return (b.averageScore || 0) - (a.averageScore || 0) })
                    return arr
                }

                Item {
                    id: topRatedHeader
                    x: 24; y: 0
                    width: parent.width - 48
                    height: topRatedHeaderCol.implicitHeight

                    Column {
                        id: topRatedHeaderCol
                        spacing: 4
                        Text {
                            text: "Top Rated"
                            color: "#f0f0f5"
                            font.family: "Montserrat"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "Highest rated of all time"
                            color: "#8888a0"
                            font.family: "Inter"
                            font.pixelSize: 13
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                            Text { text: "<"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: topRatedListView.contentX = Math.max(0, topRatedListView.contentX - 320) }
                        }
                        Rectangle {
                            width: 32; height: 32; radius: 16; color: Qt.rgba(1,1,1,0.05)
                            Text { text: ">"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: topRatedListView.contentX = Math.min(topRatedListView.contentWidth - topRatedListView.width, topRatedListView.contentX + 320) }
                        }
                    }
                }

                ListView {
                    id: topRatedListView
                    x: 24
                    y: topRatedHeader.implicitHeight + 16
                    width: parent.width - 48
                    height: 350
                    model: parent.topRatedList
                    orientation: ListView.Horizontal
                    spacing: 16
                    clip: true
                    flickDeceleration: 3500
                    maximumFlickVelocity: 3000

                    delegate: AnimePosterCard {
                        width: 180
                        title: AniListApi.title(modelData)
                        rating: AniListApi.score(modelData)
                        subtext: (AniListApi.studio(modelData) ? AniListApi.studio(modelData) + " · " : "") + (modelData.seasonYear || "")
                        epText: modelData.episodes ? "EP " + modelData.episodes : ""
                        posterUrl: AniListApi.cover(modelData)
                        onClicked: seriesClicked(modelData.id)
                    }
                }
            }

            Item { width: 1; height: 48 }
        }
    }
}
