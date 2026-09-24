import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

// HomePage — the screening room.
// Colour and type values mirror the tokens declared in main.qml; they are
// repeated here because this page is also loaded standalone.
Rectangle {
    id: homePage
    color: "#0a0a0a"

    property var  trendingList:  []
    property var  simulcastList: []
    property var  airingList:    []
    property var  heroMedia:     null
    property bool loadingHero:   false
    property string errorMsg:    ""

    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal seriesClicked(int id)
    signal trendingSeeAllRequested()

    readonly property string displayFont: "Segoe UI Variable Display, Segoe UI"
    readonly property string bodyFont:    "Segoe UI Variable Text, Segoe UI"
    readonly property string iconFont:    "Segoe MDL2 Assets"
    readonly property int    gutter:      32
    readonly property bool   calm:        Qt.application.arguments.indexOf("--reduce-motion") !== -1

    // clamp() equivalent, measured against this page's own width so the hero
    // stays readable when the window is narrow.
    function fluid(minV, maxV, fromW, toW) {
        var w = homePage.width
        if (w <= fromW) return minV
        if (w >= toW)   return maxV
        return minV + (maxV - minV) * (w - fromW) / (toW - fromW)
    }
    readonly property int heroSize:  Math.round(fluid(28, 46, 520, 1500))
    readonly property int heroLead:  Math.round(heroSize * 1.06)
    readonly property int heroColW:  Math.round(fluid(280, 660, 420, 1500))

    // ── Data ─────────────────────────────────────────────────────────────
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
        // AniList seasons: Winter Dec-Feb, Spring Mar-May, Summer Jun-Aug, Fall Sep-Nov
        var now   = new Date()
        var month = now.getMonth()
        var year  = now.getFullYear()
        var season
        if (month === 11)      { season = "WINTER"; year += 1 }
        else if (month <= 1)   season = "WINTER"
        else if (month <= 4)   season = "SPRING"
        else if (month <= 7)   season = "SUMMER"
        else                   season = "FALL"
        AniListApi.seasonalAnime(season, year, 12, function(list, err) {
            if (!err && list && list.length > 0) simulcastList = list
        })
        AniListApi.airingNow(12, function(list, err) {
            if (!err && list && list.length > 0) airingList = list
        })
    }

    onVisibleChanged: { if (visible) loadTrendingIfNeeded() }
    Component.onCompleted: loadTrendingIfNeeded()

    // ── Hero copy helpers ────────────────────────────────────────────────
    // Reference cards carry "2013  •  87 eps" under the title, not chips.
    function cardMeta(m) {
        if (!m) return ""
        var bits = []
        if (m.seasonYear) bits.push(String(m.seasonYear))
        var eps = m.nextAiringEpisode ? (m.nextAiringEpisode.episode - 1) : m.episodes
        if (eps) bits.push(eps + " eps")
        return bits.join("  •  ")
    }

    function cour(m) {
        if (!m) return ""
        var s = m.season || ""
        var y = m.seasonYear || ""
        if (!s && !y) return ""
        return (s ? s.charAt(0) + s.slice(1).toLowerCase() : "") + (y ? " " + y : "")
    }

    function formatLabel(m) {
        var map = { "TV": "TV", "TV_SHORT": "TV SHORT", "MOVIE": "FILM",
                    "OVA": "OVA", "ONA": "ONA", "SPECIAL": "SPECIAL", "MUSIC": "MUSIC" }
        return map[(m && m.format) || ""] || ""
    }

    function statusLabel(m) {
        var map = { "FINISHED": "COMPLETE", "RELEASING": "NOW AIRING",
                    "NOT_YET_RELEASED": "UPCOMING", "CANCELLED": "CANCELLED", "HIATUS": "ON HIATUS" }
        return map[(m && m.status) || ""] || ""
    }

    // The airing tally: how long until the next episode is out.
    function tally(m) {
        if (!m || !m.nextAiringEpisode) return ""
        var s = m.nextAiringEpisode.timeUntilAiring || 0
        if (s <= 0) return ""
        var d = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        var mi = Math.floor((s % 3600) / 60)
        function p(n) { return (n < 10 ? "0" : "") + n }
        return "EPISODE " + m.nextAiringEpisode.episode + " IN " + p(d) + "D " + p(h) + "H " + p(mi) + "M"
    }

    // Keeps the countdown honest without re-rendering the whole hero.
    Timer {
        interval: 60000; repeat: true; running: homePage.visible && !homePage.calm
        onTriggered: { heroTallyStamp += 1 }
    }
    property int heroTallyStamp: 0

    // ── Row section ──────────────────────────────────────────────────────
    component AnimeRow: Column {
        id: rowRoot

        property string rowTitle: ""
        property var    rowModel: []
        property string epTextMode: "auto"   // "auto" | "ongoing"
        property bool   showSeeAll: false
        property int    cardWidth: 196
        // art (w*1.5) + 10 gap + 38 two-line title slot + 3 + 18 meta line
        property int    listViewHeight: cardWidth * 3 / 2 + 78

        signal seeAllClicked()

        width: parent ? parent.width : 0
        spacing: 0
        visible: rowModel.length > 0

        // Header: title left, controls right, one baseline
        Item {
            id: rowHeader
            width: parent.width
            height: 44

            Text {
                id: rowTitleTxt
                anchors { left: parent.left; leftMargin: homePage.gutter; verticalCenter: parent.verticalCenter }
                text: rowRoot.rowTitle
                color: "#ffffff"
                font.family: homePage.displayFont
                font.pixelSize: 22
                font.weight: Font.Bold
                font.letterSpacing: 0.8
            }

            Row {
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: rowRoot.showSeeAll
                    text: "View all"
                    color: seeAllMa.containsMouse ? "#ffffff" : "#8a8a8a"
                    font.family: homePage.displayFont
                    font.pixelSize: 13
                    font.weight: Font.Normal
                    font.letterSpacing: 0
                    Behavior on color { ColorAnimation { duration: 140 } }
                    MouseArea {
                        id: seeAllMa
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rowRoot.seeAllClicked()
                    }
                }

                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: ["left", "right"]
                        delegate: Rectangle {
                            id: arrow
                            required property string modelData
                            readonly property bool canGo: modelData === "left"
                                                          ? rowListView.contentX > 1
                                                          : rowListView.contentX < rowListView.contentWidth - rowListView.width - 1
                            width: 30; height: 30; radius: 5
                            color: arrowMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.05)
                            border.color: Qt.rgba(1,1,1,0.10); border.width: 1
                            opacity: canGo ? 1.0 : 0.28
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: arrow.modelData === "left" ? "" : ""
                                color: "#c8c8dc"; font.pixelSize: 11
                                font.family: homePage.iconFont
                            }
                            MouseArea {
                                id: arrowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var step = Math.max(240, rowListView.width * 0.7)
                                    if (arrow.modelData === "left")
                                        rowListView.contentX = Math.max(0, rowListView.contentX - step)
                                    else
                                        rowListView.contentX = Math.min(
                                            Math.max(0, rowListView.contentWidth - rowListView.width),
                                            rowListView.contentX + step)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: rowRoot.listViewHeight

            ListView {
                id: rowListView
                anchors { left: parent.left; right: parent.right; leftMargin: homePage.gutter; rightMargin: homePage.gutter }
                height: parent.height
                model: rowRoot.rowModel
                orientation: ListView.Horizontal
                spacing: 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 3500
                maximumFlickVelocity: 3000
                keyNavigationEnabled: true

                delegate: AnimePosterCard {
                    width: rowRoot.cardWidth
                    title:     AniListApi.title(modelData)
                    rating:    ""
                    epText:    ""
                    subtext:   homePage.cardMeta(modelData)
                    posterUrl: AniListApi.cover(modelData)

                    onClicked: homePage.seriesClicked(modelData.id)
                    onWatchClicked: homePage.playRequested(modelData.id, title)

                    onAddClicked: {
                        if (authManager) {
                            var item = {
                                "anilist_id": modelData.id || modelData.anilist_id,
                                "title": title,
                                "cover_image_url": posterUrl,
                                "rating": rating
                            };
                            authManager.addToLibrary(item);
                        }
                    }
                }
            }

            // Edge fades so cards dissolve instead of being sliced
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 44
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#0a0a0a" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                visible: rowListView.contentX > 1
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 64
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#0a0a0a" }
                }
                visible: rowListView.contentWidth > rowListView.width
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
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

            // ── Error banner ─────────────────────────────────────────────
            Rectangle {
                width: parent.width - 64; x: 32
                height: visible ? (eTxt.implicitHeight + 20) : 0
                visible: errorMsg !== ""
                color: Qt.rgba(0.86, 0.15, 0.15, 0.14); radius: 6
                border.color: Qt.rgba(0.86, 0.15, 0.15, 0.4); border.width: 1
                Text {
                    id: eTxt
                    anchors.centerIn: parent
                    text: errorMsg; color: "#ff8a8a"
                    width: parent.width - 24
                    font.family: homePage.bodyFont; font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
            }

            // ── Hero ────────────────────────────────────────────────────
            Item {
                id: hero
                width: parent.width
                height: 520

                Rectangle { anchors.fill: parent; color: "#0b0c14" }

                Image {
                    id: heroArt
                    anchors.fill: parent
                    source: heroMedia ? (heroMedia.bannerImage && heroMedia.bannerImage !== ""
                                         ? heroMedia.bannerImage : AniListApi.cover(heroMedia)) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Fade the art in on load; `visible` is left alone so the
                    // opacity transition can actually play.
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: homePage.calm ? 0 : 520; easing.type: Easing.OutCubic } }
                }

                // Left scrim: stops short of the art's centre so it stays readable
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: Qt.rgba(0.027, 0.027, 0.051, 0.97) }
                        GradientStop { position: 0.34; color: Qt.rgba(0.027, 0.027, 0.051, 0.74) }
                        GradientStop { position: 0.66; color: Qt.rgba(0.027, 0.027, 0.051, 0.10) }
                        GradientStop { position: 1.00; color: Qt.rgba(0.027, 0.027, 0.051, 0.00) }
                    }
                }

                // Bottom scrim carries the hero into the first row
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.58; color: "transparent" }
                        GradientStop { position: 0.86; color: Qt.rgba(0.027, 0.027, 0.051, 0.82) }
                        GradientStop { position: 1.00; color: "#0a0a0a" }
                    }
                }

                // Loading tally
                Rectangle {
                    id: heroPulse
                    anchors.centerIn: parent
                    width: 40; height: 40; radius: 20
                    color: "transparent"; border.color: "#ffffff"; border.width: 2
                    visible: loadingHero && heroMedia === null
                    SequentialAnimation on opacity {
                        running: heroPulse.visible && !homePage.calm
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
                    }
                }

                // Hero content
                Column {
                    id: heroCopy
                    visible: heroMedia !== null
                    anchors { left: parent.left; leftMargin: homePage.gutter + 12; bottom: parent.bottom }
                    width: Math.min(homePage.heroColW, hero.width - homePage.gutter * 2)
                    spacing: 0

                    // One orchestrated entrance when the hero data lands
                    anchors.bottomMargin: heroMedia ? 44 : 24
                    Behavior on anchors.bottomMargin {
                        NumberAnimation { duration: homePage.calm ? 0 : 420; easing.type: Easing.OutCubic }
                    }
                    opacity: heroMedia ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: homePage.calm ? 0 : 420; easing.type: Easing.OutCubic }
                    }

                    // Eyebrow: what this show is, in anime terms
                    Row {
                        spacing: 8
                        visible: homePage.heroMedia ? (homePage.cour(homePage.heroMedia) !== "" || homePage.formatLabel(homePage.heroMedia) !== "") : false
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                homePage.heroTallyStamp
                                if (!homePage.heroMedia) return ""
                                return "#1 in Anime Today"
                            }
                            color: "#b3b3b3"
                            font.family: homePage.displayFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.3
                        }
                    }

                    Item { width: 1; height: 10 }

                    Text {
                        width: parent.width
                        text: heroMedia ? AniListApi.title(heroMedia) : ""
                        color: "#ffffff"
                        font.family: homePage.displayFont
                        font.pixelSize: 52
                        font.weight: Font.Bold
                        font.letterSpacing: -0.6
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 54
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        height: Math.min(implicitHeight, 2 * lineHeight)
                    }

                    Item { width: 1; height: 12 }

                    // Season, genres and length, as the reference states them
                    Text {
                        visible: text.length > 0
                        topPadding: 8
                        width: parent.width
                        text: {
                            var d = homePage.heroMedia
                            if (!d) return ""
                            var bits = []
                            bits.push("S1")
                            if (d.genres) bits = bits.concat(d.genres.slice(0, 2))
                            if (d.episodes) bits.push(d.episodes + " Episodes")
                            else if (d.nextAiringEpisode) bits.push("Ongoing")
                            return bits.join("  •  ")
                        }
                        color: "#e6e6e6"
                        font.family: homePage.displayFont
                        font.pixelSize: 13
                        font.letterSpacing: 0.2
                    }

                    // Score + studio
                    Row {
                        spacing: 14
                        visible: heroMedia !== null
                        Text {
                            visible: homePage.heroMedia ? AniListApi.score(homePage.heroMedia) !== "" : false
                            text: "\u2605 " + (heroMedia ? AniListApi.score(heroMedia) : "")
                            color: "#ffffff"
                            font.family: homePage.displayFont
                            font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 1.0
                        }
                        Text {
                            visible: heroMedia && AniListApi.studio(heroMedia) !== ""
                            text: heroMedia ? AniListApi.studio(heroMedia) : ""
                            color: "#b3b3b3"
                            font.family: homePage.bodyFont; font.pixelSize: 13
                        }
                    }

                    // ── Signature: the airing tally ──────────────────────
                    Item { width: 1; height: 16; visible: tallyChip.visible }

                    Rectangle {
                        id: tallyChip
                        visible: homePage.heroMedia ? homePage.tally(homePage.heroMedia) !== "" : false
                        height: 34; radius: 4
                        width: tallyRow.implicitWidth + 22
                        color: Qt.rgba(0.016, 0.016, 0.039, 0.72)
                        border.color: Qt.rgba(0.95, 0.46, 0.13, 0.34); border.width: 1

                        Row {
                            id: tallyRow
                            anchors.centerIn: parent
                            spacing: 9

                            Rectangle {
                                id: tallyDot
                                width: 7; height: 7; radius: 4
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on scale {
                                    running: tallyChip.visible && !homePage.calm
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1.75; duration: 900; easing.type: Easing.OutCubic }
                                    NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutCubic }
                                }
                                SequentialAnimation on opacity {
                                    running: tallyChip.visible && !homePage.calm
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 900 }
                                    NumberAnimation { to: 1.0;  duration: 900 }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    homePage.heroTallyStamp
                                    return homePage.heroMedia ? homePage.tally(homePage.heroMedia) : ""
                                }
                                color: "#ffffff"
                                font.family: homePage.displayFont
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.6
                            }
                        }
                    }

                    Item { width: 1; height: 14 }

                    Text {
                        width: parent.width
                        text: heroMedia ? AniListApi.cleanDesc(heroMedia) : ""
                        color: "#b3b3b3"
                        font.family: homePage.bodyFont
                        font.pixelSize: 14
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 21
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        height: Math.min(implicitHeight, 2 * lineHeight)
                    }

                    Item { width: 1; height: 22 }

                    // Actions
                    Row {
                        spacing: 10

                        Rectangle {
                            width: Math.max(150, watchTxt.implicitWidth + 40); height: 44
                            radius: 5
                            color: _wma.pressed ? "#d9d9d9" : _wma.containsMouse ? "#ffffff" : "#f5f5f5"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: watchTxt
                                anchors.centerIn: parent
                                text: "▶   Play"
                                color: "#0a0a0a"
                                font.family: homePage.displayFont
                                font.pixelSize: 14; font.weight: Font.DemiBold; font.letterSpacing: 0
                            }
                            MouseArea {
                                id: _wma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (heroMedia) playRequested(heroMedia.id, AniListApi.title(heroMedia))
                            }
                        }

                        Rectangle {
                            width: Math.max(120, infoTxt.implicitWidth + 32); height: 44
                            radius: 5
                            color: _ima.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                            border.color: Qt.rgba(1,1,1,0.16); border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: infoTxt
                                anchors.centerIn: parent
                                text: "More Info"
                                color: "#ffffff"
                                font.family: homePage.displayFont
                                font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.8
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
            } // hero

            Item { width: 1; height: 28 }

            AnimeRow {
                rowTitle:    "Trending Now"
                showSeeAll:  true
                rowModel:    homePage.trendingList
                epTextMode:  "auto"
                onSeeAllClicked: homePage.trendingSeeAllRequested()
            }

            Item { width: 1; height: 20 }

            AnimeRow {
                rowTitle:   "Simulcasts"
                rowModel:   homePage.simulcastList
                epTextMode: "ongoing"
            }

            Item { width: 1; height: 20 }

            AnimeRow {
                rowTitle:   "Currently Airing"
                rowModel:   homePage.airingList
                epTextMode: "auto"
            }

            Item { width: 1; height: 20 }

            AnimeRow {
                rowTitle:   "Top Rated"
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
