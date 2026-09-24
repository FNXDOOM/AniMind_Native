import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

// SearchPage — results with type tabs and a filters rail.
//
// The rail's controls are single-select because that is what AniList's
// `format` and `status` arguments accept; presenting them as checkboxes would
// promise a multi-select the API cannot honour.
Rectangle {
    id: searchPage
    color: "#0a0a0a"

    property string initialQuery: ""
    property string query: ""
    property var    anime: []
    property var    chars: []
    property bool   loading: false
    property string errorMsg: ""
    property string tab: "all"            // all | anime | characters | genres

    // Filters
    property string fFormat: ""           // TV | MOVIE | OVA | SPECIAL
    property string fStatus: ""           // RELEASING | FINISHED
    property int    fYear: 0
    property string fGenre: ""

    signal seriesClicked(int anilistId)

    readonly property string displayFont: "Segoe UI Variable Display, Segoe UI"
    readonly property string bodyFont:    "Segoe UI Variable Text, Segoe UI"
    readonly property string iconFont:    "Segoe MDL2 Assets"
    readonly property int    gutter:      width < 640 ? 16 : (width < 1024 ? 24 : 32)
    readonly property bool   showRail:    width >= 1100
    readonly property int    railW:       240

    readonly property var typeOpts:   [ { v: "",         label: "Any" },
                                        { v: "TV",       label: "TV series" },
                                        { v: "MOVIE",    label: "Movie" },
                                        { v: "OVA",      label: "OVA" },
                                        { v: "SPECIAL",  label: "Special" } ]
    readonly property var statusOpts: [ { v: "",          label: "Any" },
                                        { v: "RELEASING", label: "Airing" },
                                        { v: "FINISHED",  label: "Finished" } ]
    readonly property var genreOpts:  ["Action", "Adventure", "Comedy", "Drama", "Fantasy",
                                       "Horror", "Mystery", "Romance", "Sci-Fi",
                                       "Slice of Life", "Sports", "Supernatural"]
    readonly property var yearOpts:   {
        var out = [0], y = new Date().getFullYear()
        for (var i = 0; i <= 30; i++) out.push(y - i)
        return out
    }

    readonly property bool hasFilters: fFormat !== "" || fStatus !== "" || fYear !== 0 || fGenre !== ""
    readonly property bool idle: query.length < 2 && !hasFilters

    function resetFilters() {
        fFormat = ""; fStatus = ""; fYear = 0; fGenre = ""
    }

    function run() {
        if (idle) { anime = []; chars = []; loading = false; errorMsg = ""; return }
        loading = true
        errorMsg = ""
        var pending = 2
        function finish() { pending -= 1; if (pending <= 0) searchPage.loading = false }

        var opts = { page: 1, perPage: 50, sort: 1 }
        if (query.length >= 2)  opts.search = query
        if (fGenre !== "")      opts.genre = fGenre
        if (fFormat !== "")     opts.format = fFormat
        if (fStatus !== "")     opts.status = fStatus
        if (fYear !== 0)        opts.seasonYear = fYear

        AniListApi.searchAnime(opts, function(list, pageInfo, err) {
            if (err) searchPage.errorMsg = "We couldn't finish this search. Check your connection and try again."
            else searchPage.anime = list || []
            finish()
        })

        if (query.length >= 2) {
            AniListApi.searchCharacters(query, function(list, err) {
                searchPage.chars = (!err && list) ? list : []
                finish()
            })
        } else {
            searchPage.chars = []
            finish()
        }
    }

    function meta(m) {
        if (!m) return ""
        var bits = []
        if (m.seasonYear) bits.push(String(m.seasonYear))
        var eps = m.nextAiringEpisode ? (m.nextAiringEpisode.episode - 1) : m.episodes
        if (eps) bits.push(eps + " eps")
        if (m.status === "RELEASING") bits.push("airing")
        else if (m.format) bits.push(m.format.toLowerCase().replace("_", " "))
        return bits.join("  •  ")
    }

    function clip(s, n) {
        if (!s) return ""
        var t = s.replace(/\n/g, " ").replace(/<[^>]+>/g, "").trim()
        return t.length > n ? t.substring(0, n).trim() + "…" : t
    }

    onQueryChanged: debounce.restart()
    onFFormatChanged: run()
    onFStatusChanged: run()
    onFYearChanged: run()
    onFGenreChanged: run()
    onInitialQueryChanged: { if (initialQuery !== query) { query = initialQuery; searchInput.text = initialQuery } }

    Timer {
        id: debounce
        interval: 350; repeat: false
        onTriggered: searchPage.run()
    }

    Component.onCompleted: {
        if (initialQuery.length > 0) { query = initialQuery; searchInput.text = initialQuery }
        run()
    }
    onVisibleChanged: if (visible) { searchInput.forceActiveFocus(); run() }

    // ── Header ──────────────────────────────────────────────────────────
    Column {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: 20; leftMargin: searchPage.gutter; rightMargin: searchPage.gutter }
        width: parent.width - searchPage.gutter * 2
        spacing: 14

        Text {
            text: searchPage.query.length >= 2
                  ? "Search results for \u201C" + searchPage.query + "\u201D"
                  : (searchPage.hasFilters ? "Filtered results" : "Search anime")
            color: "#ffffff"
            font.family: searchPage.displayFont
            font.pixelSize: 24
            font.weight: Font.Bold
            visible: !searchPage.idle
        }

        Row {
            spacing: 22
            Repeater {
                model: [ { k: "all", l: "All" }, { k: "anime", l: "Anime" },
                         { k: "characters", l: "Characters" }, { k: "genres", l: "Genres" } ]
                delegate: Item {
                    id: t
                    required property var modelData
                    width: tl.implicitWidth
                    height: 28
                    activeFocusOnTab: true
                    readonly property bool on: searchPage.tab === modelData.k
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.l
                    Text {
                        id: tl
                        anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 6 }
                        text: modelData.l
                        color: t.on ? "#ffffff" : "#8a8a8a"
                        font.family: searchPage.bodyFont
                        font.pixelSize: 13
                        font.weight: t.on ? Font.DemiBold : Font.Normal
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 2; radius: 1; color: "#ffffff"; visible: t.on
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { t.forceActiveFocus(); searchPage.tab = modelData.k }
                    }
                }
            }
        }
    }

    // ── Filters rail ────────────────────────────────────────────────────
    Rectangle {
        id: rail
        visible: searchPage.showRail
        anchors { top: head.bottom; topMargin: 22; right: parent.right; rightMargin: searchPage.gutter }
        width: searchPage.railW
        height: railCol.implicitHeight + 32
        radius: 10
        color: "#111111"
        border.color: "#242424"; border.width: 1

        Column {
            id: railCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 16
            width: parent.width - 32

            Text {
                text: "Filters"
                color: "#ffffff"
                font.family: searchPage.displayFont
                font.pixelSize: 15; font.weight: Font.DemiBold
            }

            Repeater {
                model: [
                    { title: "Type",   opts: searchPage.typeOpts,   cur: searchPage.fFormat,  role: "format" },
                    { title: "Status", opts: searchPage.statusOpts, cur: searchPage.fStatus,  role: "status" }
                ]
                delegate: Column {
                    id: filterGroup
                    required property var modelData
                    readonly property string groupRole: modelData.role
                    width: parent.width
                    spacing: 6
                    Text {
                        text: modelData.title
                        color: "#8a8a8a"
                        font.family: searchPage.bodyFont
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: modelData.opts
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 26
                            activeFocusOnTab: true
                            readonly property bool on: modelData.v === (filterGroup.groupRole === "format"
                                                                       ? searchPage.fFormat : searchPage.fStatus)
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 9
                                Rectangle {
                                    width: 15; height: 15; radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: parent.parent.on ? "#f5f5f5" : "transparent"
                                    border.color: parent.parent.on ? "#f5f5f5" : "#3a3a3a"
                                    border.width: 1
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: parent.parent.on ? "#ffffff" : "#b3b3b3"
                                    font.family: searchPage.bodyFont
                                    font.pixelSize: 13
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (filterGroup.groupRole === "format") searchPage.fFormat = modelData.v
                                    else searchPage.fStatus = modelData.v
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: "Year"
                    color: "#8a8a8a"
                    font.family: searchPage.bodyFont
                    font.pixelSize: 12
                }
                Flickable {
                    width: parent.width
                    height: 104
                    contentHeight: yearCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Column {
                        id: yearCol
                        width: parent.width
                        Repeater {
                            model: searchPage.yearOpts
                            delegate: Item {
                                required property var modelData
                                width: yearCol.width
                                height: 24
                                readonly property bool on: searchPage.fYear === modelData
                                Text {
                                    anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                                    text: modelData === 0 ? "Any year" : String(modelData)
                                    color: on ? "#ffffff" : "#b3b3b3"
                                    font.family: searchPage.bodyFont
                                    font.pixelSize: 13
                                }
                                Rectangle {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    width: 2; height: 14; radius: 1; color: "#ffffff"
                                    visible: on
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: searchPage.fYear = modelData
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 8
                color: resetMa.containsMouse ? "#222222" : "#181818"
                border.color: "#2e2e2e"; border.width: 1
                enabled: searchPage.hasFilters
                opacity: enabled ? 1 : 0.45
                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    color: "#ffffff"
                    font.family: searchPage.bodyFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: resetMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: searchPage.resetFilters()
                }
            }
        }
    }

    // ── Results ─────────────────────────────────────────────────────────
    Flickable {
        id: list
        anchors { top: head.bottom; topMargin: 22; left: parent.left; bottom: parent.bottom
                  leftMargin: searchPage.gutter; bottomMargin: 20 }
        width: searchPage.showRail
               ? parent.width - searchPage.gutter * 2 - searchPage.railW - 24
               : parent.width - searchPage.gutter * 2
        clip: true
        contentHeight: listCol.height
        boundsBehavior: Flickable.StopAtBounds
        visible: !searchPage.idle

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            implicitWidth: 6
            contentItem: Rectangle { radius: 3; color: "#3a3a3a"; implicitWidth: 6 }
            background: Item { }
        }

        Column {
            id: listCol
            width: parent.width
            spacing: 6

            // Anime rows
            Repeater {
                model: (searchPage.tab === "all" || searchPage.tab === "anime") ? searchPage.anime : []
                delegate: Item {
                    required property var modelData
                    width: listCol.width
                    height: 118
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: rowTitle.text

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: 104
                        radius: 8
                        color: rowMa.containsMouse ? "#161616" : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    Row {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Rectangle {
                            width: 68; height: 96
                            radius: 6
                            color: "#141414"
                            border.color: "#242424"; border.width: 1
                            clip: true
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.fill: parent
                                source: AniListApi.cover(modelData)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        Column {
                            width: listCol.width - 68 - 60
                            spacing: 3
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: rowTitle
                                width: parent.width
                                text: AniListApi.title(modelData)
                                color: "#ffffff"
                                font.family: searchPage.bodyFont
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                text: searchPage.meta(modelData)
                                color: "#8a8a8a"
                                font.family: searchPage.bodyFont
                                font.pixelSize: 12
                            }
                            Text {
                                width: parent.width
                                text: searchPage.clip(modelData.description, 150)
                                color: "#9a9a9a"
                                font.family: searchPage.bodyFont
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                height: 2 * 17
                                lineHeightMode: Text.FixedHeight
                                lineHeight: 17
                            }
                        }
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: "\uE76C"
                        color: "#6e6e6e"
                        font.family: searchPage.iconFont
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchPage.seriesClicked(modelData.id)
                    }
                }
            }

            // Character rows
            Repeater {
                model: (searchPage.tab === "all" || searchPage.tab === "characters") ? searchPage.chars : []
                delegate: Item {
                    required property var modelData
                    width: listCol.width
                    height: 76
                    Row {
                        anchors { fill: parent; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Rectangle {
                            width: 48; height: 48; radius: 24
                            color: "#141414"
                            border.color: "#242424"; border.width: 1
                            clip: true
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.fill: parent
                                source: modelData && modelData.image ? modelData.image.medium : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        Column {
                            width: listCol.width - 48 - 40
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                text: modelData && modelData.name ? modelData.name.full : ""
                                color: "#ffffff"
                                font.family: searchPage.bodyFont
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: searchPage.clip(modelData ? modelData.description : "", 120)
                                color: "#9a9a9a"
                                font.family: searchPage.bodyFont
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // Genre shortcuts
            Flow {
                width: parent.width
                spacing: 8
                visible: searchPage.tab === "genres"
                Repeater {
                    model: searchPage.genreOpts
                    delegate: Rectangle {
                        radius: 16
                        height: 34
                        width: gLabel.implicitWidth + 28
                        color: searchPage.fGenre === modelData ? "#f5f5f5" : "#141414"
                        border.color: searchPage.fGenre === modelData ? "#f5f5f5" : "#2e2e2e"
                        border.width: 1
                        Text {
                            id: gLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: searchPage.fGenre === modelData ? "#0a0a0a" : "#b3b3b3"
                            font.family: searchPage.bodyFont
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchPage.fGenre = (searchPage.fGenre === modelData ? "" : modelData)
                        }
                    }
                }
            }
        }
    }

    // ── In-page search field (the page is also reachable without the header)
    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 20; rightMargin: searchPage.showRail ? searchPage.gutter + searchPage.railW + 24 : searchPage.gutter }
        visible: !searchPage.showRail
        width: 260; height: 36; radius: 18
        color: "#141414"
        border.color: searchInput.activeFocus ? "#4a4a4a" : "#262626"
        border.width: 1
        TextInput {
            id: searchInput
            anchors { fill: parent; leftMargin: 14; rightMargin: 14; verticalCenter: parent.verticalCenter }
            verticalAlignment: TextInput.AlignVCenter
            color: "#ffffff"
            font.family: searchPage.bodyFont
            font.pixelSize: 13
            cursorVisible: true
            clip: true
            onTextChanged: searchPage.query = text
        }
    }

    // ── States ──────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#0a0a0a"
        visible: searchPage.loading
        Rectangle {
            anchors.centerIn: parent
            width: 32; height: 32; radius: 16
            color: "transparent"
            border.color: "#ffffff"; border.width: 2
            opacity: 0.7
            RotationAnimator on rotation {
                from: 0; to: 360; duration: 900
                loops: Animation.Infinite
                running: parent.visible
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: searchPage.idle && !searchPage.loading
        text: "Type at least two characters, or set a filter."
        color: "#8a8a8a"
        font.family: searchPage.bodyFont
        font.pixelSize: 14
    }

    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !searchPage.loading && !searchPage.idle
                 && (searchPage.errorMsg !== ""
                     || (searchPage.anime.length === 0 && searchPage.chars.length === 0
                         && searchPage.tab !== "genres"))
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: searchPage.errorMsg !== "" ? searchPage.errorMsg
                 : "Nothing matched. Try fewer words, or clear a filter."
            color: searchPage.errorMsg !== "" ? "#ff8a8a" : "#8a8a8a"
            font.family: searchPage.bodyFont
            font.pixelSize: 14
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: searchPage.hasFilters
            width: sRetryTxt.implicitWidth + 34; height: 36; radius: 8
            color: sRetryMa.containsMouse ? "#222222" : "#181818"
            border.color: "#2e2e2e"; border.width: 1
            Text {
                id: sRetryTxt
                anchors.centerIn: parent
                text: "Clear filters"
                color: "#ffffff"
                font.family: searchPage.bodyFont
                font.pixelSize: 13
            }
            MouseArea {
                id: sRetryMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: searchPage.resetFilters()
            }
        }
    }
}
