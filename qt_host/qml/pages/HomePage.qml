import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import "../"
import "../components"
import ".."

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
    signal continueWatchingRequested()

    // The shell owns the single copy of watch history.
    readonly property var app: Window.window
    readonly property var continueList: app ? app.watchHistory : []

    readonly property string displayFont:           Theme.displayFont
    readonly property string bodyFont:              Theme.bodyFont
    readonly property string iconFont:              Theme.iconFont
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

    // ═════════════════════════════════════════════════════════════════════
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: homePage.width
        contentHeight: pageCol.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3500
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            implicitWidth: 6
            contentItem: Rectangle {
                radius: 3
                color: "#3a3a3a"
                opacity: parent.pressed ? 1 : 0.75
                implicitWidth: 6
            }
            background: Item { }
        }

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
            HeroBanner {
                media:       homePage.heroMedia
                gutter:      homePage.gutter
                calm:        homePage.calm
                heroSize:    homePage.heroSize
                heroColW:    homePage.heroColW
                tallyStamp:  homePage.heroTallyStamp
                tallyFor:    homePage.tally
                courFor:     homePage.cour
                formatFor:   homePage.formatLabel
                onSeriesPicked: homePage.seriesClicked(anilistId)
                onWatchPicked:  homePage.playRequested(anilistId, title)
                onAddRequested: homePage.addToListRequested(anilistId)
            }

            Item { width: 1; height: 28 }

            AnimeRow {
                gutter:      homePage.gutter
                calm:        homePage.calm
                metaFor:     homePage.cardMeta
                onSeriesPicked: homePage.seriesClicked(anilistId)
                onWatchPicked:  homePage.playRequested(anilistId, title)
                rowTitle:    "Trending Now"
                showSeeAll:  true
                rowModel:    homePage.trendingList
                epTextMode:  "auto"
                onSeeAllClicked: homePage.trendingSeeAllRequested()
            }

            // ── Continue Watching (section 5 and 15) ─────────────────────
            Item { width: 1; height: 28; visible: cwList.visible }

            SectionHeader {
                id: cwHead
                // Column only manages y, so the gutter goes on x directly to
                // line this header up with the rows either side of it.
                x: homePage.gutter
                width: homePage.width - homePage.gutter * 2
                visible: homePage.continueList.length > 0
                title: "Continue Watching"
                actionLabel: "See all"
                onActionRequested: homePage.continueWatchingRequested()
            }

            Item { width: 1; height: Theme.s3; visible: cwList.visible }

            ListView {
                id: cwList
                x: homePage.gutter
                width: homePage.width - homePage.gutter * 2
                height: 260 * 9 / 16 + Theme.s3 + 56
                visible: homePage.continueList.length > 0
                orientation: ListView.Horizontal
                spacing: Theme.s4
                model: homePage.continueList
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: ContinueCard {
                    required property var modelData
                    required property int index
                    width: 260
                    height: cwList.height
                    entry: modelData
                    onClicked: {
                        if (modelData && modelData.anilist_id)
                            homePage.seriesClicked(modelData.anilist_id)
                    }
                }
            }

            Item { width: 1; height: 20 }

            AnimeRow {
                gutter:      homePage.gutter
                calm:        homePage.calm
                metaFor:     homePage.cardMeta
                onSeriesPicked: homePage.seriesClicked(anilistId)
                onWatchPicked:  homePage.playRequested(anilistId, title)
                rowTitle:   "Simulcasts"
                rowModel:   homePage.simulcastList
                epTextMode: "ongoing"
            }

            Item { width: 1; height: 20 }

            AnimeRow {
                gutter:      homePage.gutter
                calm:        homePage.calm
                metaFor:     homePage.cardMeta
                onSeriesPicked: homePage.seriesClicked(anilistId)
                onWatchPicked:  homePage.playRequested(anilistId, title)
                rowTitle:   "Currently Airing"
                rowModel:   homePage.airingList
                epTextMode: "auto"
            }

            Item { width: 1; height: 20 }

            AnimeRow {
                gutter:      homePage.gutter
                calm:        homePage.calm
                metaFor:     homePage.cardMeta
                onSeriesPicked: homePage.seriesClicked(anilistId)
                onWatchPicked:  homePage.playRequested(anilistId, title)
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
