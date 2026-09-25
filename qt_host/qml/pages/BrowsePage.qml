import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"
import "../components"

// BrowsePage — genre-first discovery, matching the reference: page title, a
// row of genre chips, then a responsive poster grid. The previous filter bar
// used three combo boxes whose labels disagreed with the query they issued.
Rectangle {
    id: browsePage
    color: "#0a0a0a"

    property string genre: "All"
    property var    results: []
    property bool   loading: false
    property bool   expanded: false
    property string errorMsg: ""

    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal seriesClicked(int id)

    readonly property string displayFont: "Segoe UI Variable Display, Segoe UI"
    readonly property string bodyFont:    "Segoe UI Variable Text, Segoe UI"
    readonly property string iconFont:    "Segoe MDL2 Assets"
    readonly property int    gutter:      width < 640 ? 16 : (width < 1024 ? 24 : 32)
    readonly property int    cardGap:     16
    readonly property int    minCard:     width < 640 ? 132 : 152

    readonly property var genres: ["All", "Action", "Adventure", "Comedy", "Drama",
                                   "Fantasy", "Horror", "Romance", "Sci-Fi", "Slice of Life"]

    // Columns follow the available width, so the grid reflows instead of
    // clipping at narrow sizes.
    readonly property int gridCols: Math.max(2, Math.floor((width - gutter * 2 + cardGap) / (minCard + cardGap)))
    readonly property int cardW:    Math.floor((width - gutter * 2 - cardGap * (gridCols - 1)) / gridCols)
    readonly property int cardH:    Math.round(cardW * 3 / 2) + 72
    readonly property int headerH:  176

    function load() {
        loading = true
        errorMsg = ""
        var perPage = expanded ? 48 : 24
        var done = function(list, err) {
            browsePage.loading = false
            if (err) {
                browsePage.errorMsg = "We couldn't load "
                    + (browsePage.genre === "All" ? "titles" : browsePage.genre)
                    + ". Check your connection and try again."
                browsePage.results = []
                return
            }
            browsePage.results = list || []
        }
        if (genre === "All") {
            AniListApi.trendingAnime(perPage, function(list, err) { done(list, err) })
        } else {
            // sort index 1 = POPULARITY_DESC in AniListApi's sortMap
            AniListApi.searchAnime({ genre: genre, sort: 1, page: 1, perPage: perPage },
                                   function(list, pageInfo, err) { done(list, err) })
        }
    }

    function cardMeta(m) {
        if (!m) return ""
        var bits = []
        if (m.seasonYear) bits.push(String(m.seasonYear))
        var eps = m.nextAiringEpisode ? (m.nextAiringEpisode.episode - 1) : m.episodes
        if (eps) bits.push(eps + " eps")
        return bits.join("  •  ")
    }

    onGenreChanged: load()
    onExpandedChanged: load()
    Component.onCompleted: load()

    // ── Header ──────────────────────────────────────────────────────────
    Column {
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: 20; leftMargin: browsePage.gutter; rightMargin: browsePage.gutter }
        width: parent.width - browsePage.gutter * 2
        spacing: 0

        Text {
            text: "Browse"
            color: "#ffffff"
            font.family: browsePage.displayFont
            font.pixelSize: 28
            font.weight: Font.Bold
        }

        Item { width: 1; height: 16 }

        // Genre chips — the active one is a white pill, the only accent allowed
        Flickable {
            width: parent.width
            height: 30
            contentWidth: chipRow.width
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick

            Row {
                id: chipRow
                spacing: 8
                Repeater {
                    model: browsePage.genres
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool isOn: browsePage.genre === modelData
                        height: 30
                        width: chipLabel.implicitWidth + 26
                        radius: 15
                        color: isOn ? "#f5f5f5" : (chipMa.containsMouse ? "#1a1a1a" : "transparent")
                        border.color: isOn ? "#f5f5f5" : "#2e2e2e"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 130 } }

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: isOn ? "#0a0a0a" : "#b3b3b3"
                            font.family: browsePage.bodyFont
                            font.pixelSize: 13
                            font.weight: isOn ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: browsePage.genre = modelData
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 24 }

        Item {
            width: parent.width
            height: 24
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: browsePage.genre === "All" ? "Popular now" : browsePage.genre
                color: "#ffffff"
                font.family: browsePage.displayFont
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Item {
                id: viewAll
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: viewAllInner.implicitWidth
                height: 24
                activeFocusOnTab: true

                Row {
                    id: viewAllInner
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: browsePage.expanded ? "Show fewer" : "View all"
                        color: viewAllMa.containsMouse ? "#ffffff" : "#8a8a8a"
                        font.family: browsePage.bodyFont
                        font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: 130 } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uE76C"
                        color: viewAllMa.containsMouse ? "#ffffff" : "#8a8a8a"
                        font.family: browsePage.iconFont
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: viewAllMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: browsePage.expanded = !browsePage.expanded
                }
                Keys.onEnterPressed: browsePage.expanded = !browsePage.expanded
                Keys.onReturnPressed: browsePage.expanded = !browsePage.expanded
            }
        }
    }

    // ── Grid ────────────────────────────────────────────────────────────
    GridView {
        id: grid
        anchors { top: parent.top; topMargin: browsePage.headerH; left: parent.left
                  right: parent.right; bottom: parent.bottom
                  leftMargin: browsePage.gutter; rightMargin: browsePage.gutter }
        clip: true
        cellWidth: browsePage.cardW + browsePage.cardGap
        cellHeight: browsePage.cardH
        boundsBehavior: Flickable.StopAtBounds
        model: browsePage.results
        visible: browsePage.results.length > 0
        boundsMovement: Flickable.StopAtBounds
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

        delegate: Item {
            width: grid.cellWidth
            height: grid.cellHeight
            AnimePosterCard {
                width: parent.width - browsePage.cardGap
                title:     AniListApi.title(modelData)
                subtext:   browsePage.cardMeta(modelData)
                rating:    ""
                epText:    ""
                posterUrl: AniListApi.cover(modelData)
                onClicked: browsePage.seriesClicked(modelData.id)
                onWatchClicked: browsePage.playRequested(modelData.id, AniListApi.title(modelData))
                onAddClicked: {
                    if (authManager) {
                        authManager.addToLibrary({
                            "anilist_id":      modelData.id || modelData.anilist_id,
                            "title":           AniListApi.title(modelData),
                            "cover_image_url": AniListApi.cover(modelData),
                            "rating":          AniListApi.score(modelData)
                        })
                    }
                }
            }
        }
    }

    // ── Loading ──────────────────────────────────────────────────────────
    Rectangle {
        // Starts where the grid starts, so the page keeps its title and genre
        // chips while loading instead of blanking them out.
        anchors { top: parent.top; topMargin: browsePage.headerH
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        color: Theme.bg
        visible: browsePage.loading

        // Same columns, gutters and card width as the real GridView, so the
        // results replace the placeholders without reflowing.
        SkeletonGrid {
            anchors.fill: parent
            columns: browsePage.gridCols
            cardWidth: browsePage.cardW
            gap: browsePage.cardGap
            gutter: browsePage.gutter
            rows: 3
        }
    }

    // ── Empty and error, both naming the next step ───────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: !browsePage.loading && browsePage.results.length === 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: browsePage.errorMsg !== "" ? browsePage.errorMsg
                 : "No " + browsePage.genre.toLowerCase() + " titles came back."
            color: browsePage.errorMsg !== "" ? "#ff8a8a" : "#8a8a8a"
            font.family: browsePage.bodyFont
            font.pixelSize: 14
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: browseRetryTxt.implicitWidth + 34; height: 38; radius: 8
            color: browseRetryMa.containsMouse ? "#1f1f1f" : "#161616"
            border.color: "#2e2e2e"; border.width: 1
            Text {
                id: browseRetryTxt
                anchors.centerIn: parent
                text: browsePage.errorMsg !== "" ? "Try again" : "Browse all titles"
                color: "#ffffff"
                font.family: browsePage.bodyFont
                font.pixelSize: 13
            }
            MouseArea {
                id: browseRetryMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (browsePage.errorMsg !== "") browsePage.load()
                    else browsePage.genre = "All"
                }
            }
        }
    }
}
