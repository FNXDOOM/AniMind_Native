import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    id: homePage
    color: "#0a0a0f"

    property var  trendingList:  []
    property var  simulcastList: []
    property var  airingList:    []
    property var  heroMedia:     null
    property bool loadingHero:   false
    property string errorMsg:    ""

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
            if (!err && list && list.length > 0) simulcastList = list
        })
        AniListApi.airingNow(12, function(list, err) {
            if (!err && list && list.length > 0) airingList = list
        })
    }

    onVisibleChanged: { if (visible) loadTrendingIfNeeded() }
    Component.onCompleted: loadTrendingIfNeeded()

    // ── Reusable row section component ────────────────────────────────────
    component AnimeRow: Column {
        id: rowRoot

        property string rowTitle:    ""
        property string rowSubtitle: ""
        property string rowBadge:    ""
        property bool   showSeeAll:  false
        property var    rowModel:    []
        property string epTextMode:  "auto"   // "auto" | "ongoing"
        property int    listViewHeight: 290   // poster(~195) + meta(~70) + padding

        width: parent ? parent.width : 0
        spacing: 0
        visible: rowModel.length > 0

        // ── Section header ────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 52

            // Left: title + badge + subtitle
            Column {
                anchors {
                    left: parent.left; leftMargin: 24
                    verticalCenter: parent.verticalCenter
                }
                spacing: 3

                Row {
                    spacing: 10
                    Text {
                        text: rowRoot.rowTitle
                        color: "#f0f0f5"
                        font.family: "Montserrat"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        visible: rowRoot.rowBadge !== ""
                        width: badgeTxt.implicitWidth + 14; height: 20; radius: 4
                        color: Qt.rgba(0.95,0.46,0.13,0.15)
                        border.color: Qt.rgba(0.95,0.46,0.13,0.30); border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: badgeTxt
                            anchors.centerIn: parent
                            text: rowRoot.rowBadge
                            color: "#f47521"
                            font.family: "Inter"; font.pixelSize: 10; font.weight: Font.Bold
                        }
                    }
                }

                Text {
                    visible: rowRoot.rowSubtitle !== ""
                    text: rowRoot.rowSubtitle
                    color: "#8888a0"
                    font.family: "Inter"; font.pixelSize: 13
                }
            }

            // Right: See All + scroll buttons
            Row {
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 12

                Text {
                    visible: rowRoot.showSeeAll
                    text: "See All →"
                    color: "#f47521"
                    font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: leftBtnMa.containsMouse ? Qt.rgba(1,1,1,0.1) : Qt.rgba(1,1,1,0.05)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { text: "<"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                        MouseArea {
                            id: leftBtnMa
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: rowListView.contentX = Math.max(0, rowListView.contentX - 320)
                        }
                    }
                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: rightBtnMa.containsMouse ? Qt.rgba(1,1,1,0.1) : Qt.rgba(1,1,1,0.05)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text { text: ">"; color: "#f0f0f5"; anchors.centerIn: parent; font.pixelSize: 14 }
                        MouseArea {
                            id: rightBtnMa
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: rowListView.contentX = Math.min(
                                Math.max(0, rowListView.contentWidth - rowListView.width),
                                rowListView.contentX + 320)
                        }
                    }
                }
            }
        }

        // ── Horizontal card list ──────────────────────────────────────────
        ListView {
            id: rowListView
            width: parent.width - 48
            x: 24
            height: rowRoot.listViewHeight
            model: rowRoot.rowModel
            orientation: ListView.Horizontal
            spacing: 16
            clip: true
            flickDeceleration: 3500
            maximumFlickVelocity: 3000
            leftMargin: 0
            rightMargin: 0

            delegate: AnimePosterCard {
                width: 180
                title:     AniListApi.title(modelData)
                rating:    AniListApi.score(modelData)
                subtext:   (AniListApi.studio(modelData) ? AniListApi.studio(modelData) + " · " : "")
                           + (modelData.seasonYear ? String(modelData.seasonYear) : "")
                epText:    rowRoot.epTextMode === "ongoing"
                           ? "EP Ongoing"
                           : (AniListApi.isNewEpisode(modelData) ? "NEW EP"
                              : (modelData.episodes ? "EP " + modelData.episodes : ""))
                posterUrl: AniListApi.cover(modelData)
                onClicked: homePage.seriesClicked(modelData.id)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Main scrollable content
    // ═══════════════════════════════════════════════════════════════════════
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: homePage.width
        contentHeight: pageCol.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3500
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: pageCol
            width: homePage.width
            spacing: 0

            // ── Error banner ──────────────────────────────────────────────
            Rectangle {
                width: parent.width - 64
                x: 32
                height: visible ? (eTxt.implicitHeight + 24) : 0
                visible: errorMsg !== ""
                color: Qt.rgba(1, 0.2, 0.2, 0.25); radius: 8
                Text {
                    id: eTxt
                    text: errorMsg; color: "#ff6b6b"; wrapMode: Text.Wrap
                    font.pixelSize: 13; width: parent.width - 32
                    anchors.centerIn: parent
                }
            }

            // ── Hero section ──────────────────────────────────────────────
            Item {
                id: hero
                width: parent.width
                height: 480

                Rectangle { anchors.fill: parent; color: "#0d0d18" }

                // Loading pulse
                Rectangle {
                    anchors.centerIn: parent
                    width: 48; height: 48; radius: 24
                    color: "transparent"; border.color: "#f47521"; border.width: 2
                    visible: loadingHero && heroMedia === null
                    SequentialAnimation on opacity {
                        running: parent.visible; loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                // Banner image
                Image {
                    anchors.fill: parent
                    source: heroMedia ? (heroMedia.bannerImage && heroMedia.bannerImage !== ""
                                         ? heroMedia.bannerImage : AniListApi.cover(heroMedia)) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                // Left gradient
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
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1.00; color: "#0a0a0f" }
                    }
                }

                // Hero text
                Column {
                    visible: heroMedia !== null
                    anchors {
                        left: parent.left; leftMargin: 48
                        bottom: parent.bottom; bottomMargin: 40
                    }
                    width: Math.min(hero.width * 0.50, 540)
                    spacing: 10

                    // Genre tags
                    Row {
                        spacing: 8
                        Repeater {
                            model: heroMedia && heroMedia.genres ? Math.min(heroMedia.genres.length, 3) : 0
                            delegate: Rectangle {
                                height: 22; radius: 4
                                width: _gt.implicitWidth + 16
                                color: Qt.rgba(0.95, 0.46, 0.13, 0.15)
                                border.color: Qt.rgba(0.95, 0.46, 0.13, 0.30); border.width: 1
                                Text {
                                    id: _gt; anchors.centerIn: parent
                                    text: heroMedia.genres[index]
                                    color: "#f47521"; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Medium
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: heroMedia ? AniListApi.title(heroMedia) : ""
                        color: "#f0f0f5"; font.family: "Montserrat"; font.pixelSize: 34
                        font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2
                        elide: Text.ElideRight; lineHeight: 1.15
                    }

                    Row {
                        spacing: 12
                        visible: heroMedia !== null
                        Row {
                            spacing: 4; visible: heroMedia && AniListApi.score(heroMedia) !== ""
                            Text { text: "★"; color: "#ffd700"; font.pixelSize: 13 }
                            Text { text: heroMedia ? AniListApi.score(heroMedia) : ""; color: "#ffd700"; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.Bold }
                        }
                        Text { visible: heroMedia && AniListApi.studio(heroMedia) !== ""; text: heroMedia ? AniListApi.studio(heroMedia) : ""; color: "#8888a0"; font.family: "Inter"; font.pixelSize: 12 }
                        Text { visible: heroMedia && heroMedia.seasonYear; text: heroMedia && heroMedia.seasonYear ? heroMedia.seasonYear.toString() : ""; color: "#8888a0"; font.family: "Inter"; font.pixelSize: 12 }
                    }

                    Text {
                        width: parent.width
                        text: heroMedia ? AniListApi.cleanDesc(heroMedia) : ""
                        color: "#a0a0b8"; font.family: "Inter"; font.pixelSize: 13
                        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.6
                    }

                    Row {
                        spacing: 12; topPadding: 4

                        Rectangle {
                            width: _wr.implicitWidth + 40; height: 42; radius: 8
                            color: _wma.pressed ? "#c4601b" : _wma.containsMouse ? "#e06b1e" : "#f47521"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row { id: _wr; anchors.centerIn: parent; spacing: 8
                                Text { text: "▶"; color: "white"; font.pixelSize: 13 }
                                Text { text: "Watch Now"; color: "white"; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold }
                            }
                            MouseArea { id: _wma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: if (heroMedia) playRequested(heroMedia.id, AniListApi.title(heroMedia)) }
                        }

                        Rectangle {
                            width: _ir.implicitWidth + 32; height: 42; radius: 8
                            color: _ima.pressed ? Qt.rgba(1,1,1,0.15) : _ima.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.07)
                            border.color: Qt.rgba(1,1,1,0.14); border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row { id: _ir; anchors.centerIn: parent; spacing: 8
                                Text { text: "ℹ"; color: "#f0f0f5"; font.pixelSize: 15 }
                                Text { text: "More Info"; color: "#f0f0f5"; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.Medium }
                            }
                            MouseArea { id: _ima; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: if (heroMedia) seriesClicked(heroMedia.id) }
                        }
                    }
                }
            } // hero

            Item { width: 1; height: 24 }

            // ── Trending Now ──────────────────────────────────────────────
            AnimeRow {
                rowTitle:    "Trending Now"
                rowSubtitle: "Hottest picks this week"
                rowBadge:    "HOT"
                showSeeAll:  true
                rowModel:    homePage.trendingList
                epTextMode:  "auto"
            }

            Item { width: 1; height: 16 }

            // ── Simulcasts ────────────────────────────────────────────────
            AnimeRow {
                rowTitle:    "Simulcasts"
                rowSubtitle: "Same day as Japan"
                rowBadge:    "LIVE"
                rowModel:    homePage.simulcastList
                epTextMode:  "ongoing"
            }

            Item { width: 1; height: 16 }

            // ── Currently Airing ──────────────────────────────────────────
            AnimeRow {
                rowTitle:    "Currently Airing"
                rowSubtitle: "New episodes this season"
                rowModel:    homePage.airingList
                epTextMode:  "auto"
            }

            Item { width: 1; height: 16 }

            // ── Top Rated ─────────────────────────────────────────────────
            AnimeRow {
                rowTitle:    "Top Rated"
                rowSubtitle: "Highest rated of all time"
                rowModel: {
                    var arr = homePage.trendingList.slice()
                    arr.sort(function(a, b) { return (b.averageScore || 0) - (a.averageScore || 0) })
                    return arr
                }
                epTextMode: "auto"
            }

            Item { width: 1; height: 48 }
        }
    }
}
