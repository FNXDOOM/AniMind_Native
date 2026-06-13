import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

// SearchPage — full-page anime search
// Loaded by searchLoader in main.qml when currentPage === "search"
//
// Signal: seriesClicked(int anilistId)

Rectangle {
    id: searchPage
    color: "#0a0a0a"

    signal seriesClicked(int anilistId)

    // ── State ─────────────────────────────────────────────────────────────
    property string searchQuery:    ""
    property var    results:        []
    property bool   isLoading:      false
    property string errorText:      ""
    property var    _activeXhr:     null
    property string sortMode:       "score"   // "score" | "year" | "title"
    property string selectedGenre:  ""
    property bool   showFilters:    false

    property var genreList: [
        "Action","Adventure","Comedy","Drama","Fantasy",
        "Horror","Mystery","Psychological","Romance","Sci-Fi",
        "Slice of Life","Sports","Supernatural"
    ]

    // Sort/filter results locally for instant response
    property var displayResults: (function(res, smode, genre) {
        var arr = res.slice()
        if (genre !== "")
            arr = arr.filter(function(a) { return a.genres && a.genres.indexOf(genre) !== -1 })
        if (smode === "score")
            arr.sort(function(a, b) { return (b.averageScore || 0) - (a.averageScore || 0) })
        else if (smode === "year")
            arr.sort(function(a, b) { return (b.seasonYear || 0) - (a.seasonYear || 0) })
        else if (smode === "title")
            arr.sort(function(a, b) {
                var ta = AniListApi.title(a).toLowerCase()
                var tb = AniListApi.title(b).toLowerCase()
                return ta < tb ? -1 : ta > tb ? 1 : 0
            })
        return arr
    })(results, sortMode, selectedGenre)

    // ── Search function ───────────────────────────────────────────────────
    function doSearch() {
        if (searchQuery.length < 2 && selectedGenre === "") {
            results = []; isLoading = false; errorText = ""; return
        }
        if (_activeXhr) { _activeXhr.abort(); _activeXhr = null }
        isLoading = true; errorText = ""
        var opts = { page: 1, perPage: 50 }
        if (searchQuery.length >= 2) opts.search = searchQuery
        if (selectedGenre !== "") opts.genre = selectedGenre
        if (sortMode === "score")  opts.sort = 3
        else if (sortMode === "year")  opts.sort = 2
        else if (sortMode === "title") opts.sort = 4
        _activeXhr = AniListApi.searchAnime(opts, function(mediaArray, pageInfo, err) {
            _activeXhr = null; isLoading = false
            if (err) { errorText = err; return }
            results = mediaArray || []
        })
    }

    Timer { id: debounce; interval: 350; repeat: false; onTriggered: searchPage.doSearch() }

    onSearchQueryChanged:   debounce.restart()
    onSelectedGenreChanged: debounce.restart()
    onSortModeChanged:      debounce.restart()
    onVisibleChanged:       if (visible) searchInput.forceActiveFocus()

    // ══════════════════════════════════════════════════════════════════════
    // Layout: header Column (fixed height) + Flickable (fills rest)
    // ══════════════════════════════════════════════════════════════════════

    // ── Header controls ───────────────────────────────────────────────────
    Column {
        id: headerCol
        anchors {
            top:   parent.top;   topMargin:   32
            left:  parent.left;  leftMargin:  48
            right: parent.right; rightMargin: 48
        }
        spacing: 0

        // Title
        Text {
            text: "SEARCH ANIME"
            color: "#f0f0f5"
            font.family: "Montserrat"
            font.pixelSize: 32
            font.weight: Font.Bold
            font.letterSpacing: 1.28
            bottomPadding: 24
        }

        // Search bar
        Rectangle {
            id: searchFieldBg
            width: Math.min(672, parent.width)
            height: 52
            radius: 12
            color: "#1c1c28"
            border.color: searchInput.activeFocus ? "rgba(244,117,33,0.5)" : "rgba(255,255,255,0.08)"
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 200 } }

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                spacing: 12

                Text {
                    text: "\uD83D\uDD0D"
                    color: "#8888a0"
                    font.pixelSize: 15
                    Layout.alignment: Qt.AlignVCenter
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#f0f0f5"
                    selectionColor: "#f47521"
                    selectedTextColor: "#ffffff"
                    font.family: "Inter"
                    font.pixelSize: 15
                    clip: true
                    text: searchPage.searchQuery
                    Keys.onEscapePressed: { text = ""; searchPage.searchQuery = "" }
                    onTextChanged: searchPage.searchQuery = text

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search by title, genre..."
                        color: "#8888a0"
                        font.family: "Inter"
                        font.pixelSize: 15
                        visible: searchInput.text.length === 0
                    }
                }

                // Clear button
                MouseArea {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignVCenter
                    cursorShape: Qt.PointingHandCursor
                    visible: searchInput.text.length > 0
                    onClicked: { searchInput.text = ""; searchPage.searchQuery = "" }
                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        color: "#8888a0"
                        font.pixelSize: 14
                    }
                }
            }
        }

        Item { width: 1; height: 16 }

        // Sort + filter toggle row
        Row {
            spacing: 12

            Rectangle {
                width: filterRowContent.width + 32; height: 36; radius: 8
                color: searchPage.showFilters ? "rgba(244,117,33,0.15)" : "#1c1c28"
                border.color: searchPage.showFilters ? "rgba(244,117,33,0.3)" : "rgba(255,255,255,0.08)"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Row {
                    id: filterRowContent
                    anchors.centerIn: parent; spacing: 8
                    Text { text: "\u2261"; color: searchPage.showFilters ? "#f47521" : "#f0f0f5"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "Filters"; color: searchPage.showFilters ? "#f47521" : "#f0f0f5"; font.family: "Inter"; font.pixelSize: 13.5; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: searchPage.showFilters = !searchPage.showFilters }
            }

            Repeater {
                model: [
                    { key: "score", label: "Top Rated" },
                    { key: "year",  label: "Newest" },
                    { key: "title", label: "A\u2013Z" }
                ]
                delegate: Rectangle {
                    id: sortBtn
                    property string sKey: modelData.key
                    width: sortBtnText.implicitWidth + 24; height: 36; radius: 8
                    color: searchPage.sortMode === sKey ? "rgba(244,117,33,0.15)" : "#1c1c28"
                    border.color: searchPage.sortMode === sKey ? "rgba(244,117,33,0.3)" : "rgba(255,255,255,0.08)"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        id: sortBtnText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: searchPage.sortMode === sortBtn.sKey ? "#f47521" : "#8888a0"
                        font.family: "Inter"; font.pixelSize: 13
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: searchPage.sortMode = sortBtn.sKey }
                }
            }
        }

        Item { width: 1; height: searchPage.showFilters ? 16 : 0; Behavior on height { NumberAnimation { duration: 200 } } }

        // Genre filter chips
        Flow {
            width: parent.width
            spacing: 8
            visible: searchPage.showFilters
            height: visible ? implicitHeight : 0
            Behavior on height { NumberAnimation { duration: 200 } }
            clip: true

            Repeater {
                model: searchPage.genreList
                delegate: Rectangle {
                    id: genreChip
                    property string gName: modelData
                    width: genreChipText.implicitWidth + 24; height: 30; radius: 15
                    color: searchPage.selectedGenre === gName ? "#f47521" : "rgba(255,255,255,0.05)"
                    border.color: searchPage.selectedGenre === gName ? "#f47521" : "rgba(255,255,255,0.08)"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        id: genreChipText
                        anchors.centerIn: parent
                        text: modelData
                        color: searchPage.selectedGenre === genreChip.gName ? "#ffffff" : "#8888a0"
                        font.family: "Inter"; font.pixelSize: 12.5; font.weight: Font.Medium
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: searchPage.selectedGenre = (searchPage.selectedGenre === genreChip.gName ? "" : genreChip.gName)
                    }
                }
            }
        }

        Item { width: 1; height: 16 }

        // Result count label
        Text {
            visible: searchPage.searchQuery.length >= 2 || searchPage.selectedGenre !== ""
            text: {
                var t = searchPage.displayResults.length + (searchPage.displayResults.length === 1 ? " result" : " results")
                if (searchPage.searchQuery) t += " for \"" + searchPage.searchQuery + "\""
                if (searchPage.selectedGenre) t += " in " + searchPage.selectedGenre
                return t
            }
            color: "#8888a0"
            font.family: "Inter"; font.pixelSize: 12.5
            bottomPadding: 8
        }
    } // end headerCol

    // ── Loading spinner (centered in remaining space) ─────────────────────
    BusyIndicator {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: headerCol.bottom; anchors.topMargin: 48
        width: 48; height: 48
        visible: searchPage.isLoading
        running: searchPage.isLoading
    }

    // ── Error label ───────────────────────────────────────────────────────
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: headerCol.bottom; anchors.topMargin: 32
        visible: !searchPage.isLoading && searchPage.errorText.length > 0
        text: searchPage.errorText
        color: "#ff6b6b"
        font.family: "Inter"; font.pixelSize: 14
        wrapMode: Text.Wrap
        width: parent.width - 96
        horizontalAlignment: Text.AlignHCenter
    }

    // ── Empty / no-results label ──────────────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: headerCol.bottom; anchors.topMargin: 64
        spacing: 16
        visible: !searchPage.isLoading
                 && searchPage.errorText.length === 0
                 && searchPage.displayResults.length === 0
                 && (searchPage.searchQuery.length >= 2 || searchPage.selectedGenre !== "")

        Text { text: "\uD83D\uDD0D"; font.pixelSize: 48; anchors.horizontalCenter: parent.horizontalCenter }
        Text {
            text: "No anime found. Try a different search."
            color: "#8888a0"
            font.family: "Inter"; font.pixelSize: 15
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // ── Idle prompt ───────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: !searchPage.isLoading
                 && searchPage.errorText.length === 0
                 && searchPage.searchQuery.length < 2
                 && searchPage.selectedGenre === ""
        text: "Type a title or pick a genre to search"
        color: "#44444f"
        font.family: "Inter"; font.pixelSize: 15
    }

    // ── Results grid (Flickable fills space below headerCol) ──────────────
    Flickable {
        id: resultsFlick
        anchors {
            top:    headerCol.bottom; topMargin: 8
            left:   parent.left;  leftMargin:  48
            right:  parent.right; rightMargin: 48
            bottom: parent.bottom; bottomMargin: 24
        }
        visible: searchPage.displayResults.length > 0
        clip: true
        contentWidth: width
        contentHeight: grid.implicitHeight + 32
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Grid {
            id: grid
            width: parent.width
            columns: Math.max(2, Math.floor((width + 20) / 190))
            columnSpacing: 20
            rowSpacing: 24

            Repeater {
                model: searchPage.displayResults
                delegate: AnimePosterCard {
                    width: Math.floor(
                        (grid.width - grid.columnSpacing * (Math.max(1, grid.columns) - 1))
                        / Math.max(1, grid.columns)
                    )
                    posterUrl: AniListApi.cover(modelData)
                    title:     AniListApi.title(modelData)
                    rating:    AniListApi.score(modelData)
                    subtext:   (AniListApi.studio(modelData) ? AniListApi.studio(modelData) + " \u00B7 " : "")
                               + (modelData.seasonYear ? String(modelData.seasonYear) : "")
                    epText:    AniListApi.isNewEpisode(modelData) ? "EP Ongoing"
                               : (modelData.episodes ? "EP " + modelData.episodes : "")
                    onClicked: searchPage.seriesClicked(modelData.id)
                }
            }
        }
    }
}
