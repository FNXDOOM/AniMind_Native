import QtQuick
import QtQuick.Controls
import "../components"
import QtQuick.Layouts
import QtQuick.Effects
import "../"
import ".."

// DetailPage — a series title card with tabbed detail below.
//
// Full-bleed banner, the poster straddling the banner's lower edge, then
// Episodes / Details / More like this. Values mirror the tokens in main.qml.
Rectangle {
    id: detailPage
    color: "#0a0a0a"

    property int seriesId: 0
    property var detail: null
    property bool loading: false
    property string errorMsg: ""
    property string tab: "episodes"      // episodes | details | similar
    // Where the sliding underline sits; each tab publishes its own geometry.
    property real   tabIndX: 0
    property real   tabIndW: 0

    signal backRequested()
    signal playRequested(int id, string title)
    signal addToListRequested(int id)
    signal episodePlayRequested(string url, string title, string episodeLabel, string thumbnailUrl)

    readonly property string displayFont:           Theme.displayFont
    readonly property string bodyFont:              Theme.bodyFont
    readonly property string iconFont:              Theme.iconFont
    readonly property int    gutter:      width < 640 ? 16 : (width < 1024 ? 24 : 32)
    readonly property bool   calm:        Qt.application.arguments.indexOf("--reduce-motion") !== -1

    function fluid(minV, maxV, fromW, toW) {
        if (width <= fromW) return minV
        if (width >= toW)   return maxV
        return minV + (maxV - minV) * (width - fromW) / (toW - fromW)
    }
    readonly property int titleSize: Math.round(fluid(28, 44, 560, 1500))
    readonly property int bannerH:   Math.round(fluid(260, 360, 560, 1500))
    readonly property int posterW:   Math.round(fluid(132, 210, 560, 1500))

    // ── Data ────────────────────────────────────────────────────────────
    // Dates come back as {year, month, day}; a missing end date means the show
    // is still airing, so the range says so rather than trailing off.
    readonly property var monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    function fmtDate(d) {
        if (!d || !d.year) return ""
        var mo = (d.month && d.month >= 1 && d.month <= 12) ? monthNames[d.month - 1] : ""
        return mo + " " + (d.day || 1) + ", " + d.year
    }

    function factRows() {
        var m = detailPage.detail
        if (!m) return []
        var out = []
        var romaji = (m.title && m.title.romaji) ? m.title.romaji : ""
        if (romaji !== "") out.push({ k: "Original title", v: romaji })
        var from = detailPage.fmtDate(m.startDate)
        var to = detailPage.fmtDate(m.endDate)
        if (from !== "")
            out.push({ k: "Aired", v: to !== "" ? from + " - " + to : from + " - present" })
        out.push({ k: "Episodes", v: m.episodes ? String(m.episodes) : "Ongoing" })
        var st = AniListApi.statusLabel(m)
        if (st !== "") out.push({ k: "Status", v: st })
        return out
    }

    function loadDetail() {
        if (seriesId <= 0)
            return
        loading = true
        detail = null
        errorMsg = ""
        tab = "episodes"
        AniListApi.animeDetail(seriesId, function(media, err) {
            loading = false
            if (err) {
                errorMsg = "We couldn't load this title. Check your connection and try again."
                return
            }
            detail = media
            flick.contentY = 0
        })
    }

    onTabChanged: if (!detailPage.calm) tabSwitch.restart()

    onSeriesIdChanged: loadDetail()
    Component.onCompleted: loadDetail()

    // ── Derived copy ─────────────────────────────────────────────────────
    function hasTrailer(d) {
        return !!(d && d.trailer && d.trailer.id && d.trailer.site
                  && d.trailer.site.toLowerCase() === "youtube")
    }

    function statusLabel(d) {
        var map = { "FINISHED": "Finished", "RELEASING": "Airing",
                    "NOT_YET_RELEASED": "Not yet released", "CANCELLED": "Cancelled",
                    "HIATUS": "On hiatus" }
        return map[(d && d.status) || ""] || ""
    }

    function formatLabel(d) {
        var map = { "TV_SHORT": "TV short", "MOVIE": "Film", "SPECIAL": "Special",
                    "OVA": "OVA", "ONA": "ONA", "MUSIC": "Music" }
        var f = (d && d.format) || ""
        return map[f] || f
    }

    function airedOn(d) {
        if (!d) return ""
        if (d.season && d.seasonYear)
            return d.season.charAt(0) + d.season.slice(1).toLowerCase() + " " + d.seasonYear
        return d.seasonYear ? String(d.seasonYear) : ""
    }

    function slateCells(d) {
        if (!d) return []
        var out = []
        function add(label, value) { if (value) out.push({ label: label, value: String(value) }) }
        add("Score",    AniListApi.score(d))
        add("Format",   formatLabel(d))
        add("Episodes", d.episodes)
        add("Length",   d.duration ? d.duration + " min" : "")
        add("Status",   statusLabel(d))
        add("Aired",    airedOn(d))
        add("Studio",   AniListApi.studio(d))
        add("Source",   d.source || "")
        return out
    }

    function characterList(d) {
        if (!d || !d.characters || !d.characters.nodes) return []
        return d.characters.nodes
    }

    function recommendationList(d) {
        if (!d || !d.recommendations || !d.recommendations.nodes) return []
        return d.recommendations.nodes.filter(function(n) {
            return n && n.mediaRecommendation && n.mediaRecommendation.type === "ANIME"
        })
    }

    function episodeList(d) {
        if (!d || !d.streamingEpisodes) return []
        return d.streamingEpisodes.filter(function(e) { return e && e.title })
    }

    function heroMeta(d) {
        if (!d) return ""
        var bits = []
        if (d.genres) bits = bits.concat(d.genres.slice(0, 2))
        if (d.episodes) bits.push(d.episodes + " Episodes")
        else if (d.nextAiringEpisode) bits.push("Ongoing")
        return bits.join("  •  ")
    }

    // ── Airing tally, shared with the home hero ──────────────────────────
    property int tallyTick: 0
    Timer {
        interval: 60000; repeat: true
        running: detailPage.visible && detailPage.detail !== null && !detailPage.calm
        onTriggered: { detailPage.tallyTick += 1 }
    }

    function tally(d) {
        detailPage.tallyTick
        if (!d || !d.nextAiringEpisode) return ""
        var s = d.nextAiringEpisode.timeUntilAiring || 0
        if (s <= 0) return ""
        function p(n) { return (n < 10 ? "0" : "") + n }
        return "EPISODE " + d.nextAiringEpisode.episode + " IN "
             + p(Math.floor(s / 86400)) + "D "
             + p(Math.floor((s % 86400) / 3600)) + "H "
             + p(Math.floor((s % 3600) / 60)) + "M"
    }

    readonly property string tallyText: tally(detail)

    // ─────────────────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: canvas.height
        boundsBehavior: Flickable.StopAtBounds
        visible: !detailPage.loading && detailPage.detail !== null
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            implicitWidth: 6
            contentItem: Rectangle { radius: 3; color: "#3a3a3a"; implicitWidth: 6 }
            background: Item { }
        }

        Item {
            id: canvas
            width: flick.width
            height: contentCol.y + contentCol.height + 64

            // ══ Banner ═════════════════════════════════════════════════
            Item {
                id: banner
                y: 0
                width: parent.width
                height: detailPage.bannerH

                Rectangle { anchors.fill: parent; color: "#101010" }

                Image {
                    anchors.fill: parent
                    source: detailPage.detail
                            ? ((detailPage.detail.bannerImage && detailPage.detail.bannerImage !== "")
                               ? detailPage.detail.bannerImage : AniListApi.cover(detailPage.detail))
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: detailPage.calm ? 0 : 480; easing.type: Easing.OutCubic }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: Qt.rgba(0.04, 0.04, 0.04, 0.90) }
                        GradientStop { position: 0.55; color: Qt.rgba(0.04, 0.04, 0.04, 0.34) }
                        GradientStop { position: 1.00; color: Qt.rgba(0.04, 0.04, 0.04, 0.00) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.00; color: Qt.rgba(0.04, 0.04, 0.04, 0.55) }
                        GradientStop { position: 0.35; color: "transparent" }
                        GradientStop { position: 1.00; color: "#0a0a0a" }
                    }
                }
            }

            // Reference panel 2: a summary rail over the right of the banner, so
            // the facts that answer "should I start this?" are on screen without
            // opening the Details tab. Hidden below 900px, where the banner has
            // no room for it.
            Rectangle {
                id: infoRail
                anchors { top: banner.top; right: banner.right
                          topMargin: Theme.s6; rightMargin: Theme.gutterFor(detailPage.width) }
                width: railCol.width + Theme.s6 * 2
                height: railCol.height + Theme.s6 * 2
                radius: Theme.rLg
                // Over a banner that can be any colour at any brightness the
                // rail needs its own surface; the labels were unreadable
                // sitting directly on the artwork.
                color: Theme.glassPanel
                border.color: Theme.borderSubtle; border.width: 1
                visible: detailPage.detail !== null && detailPage.width >= 900
                opacity: detailPage.detail ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation { duration: detailPage.calm ? 0 : Theme.dSlow
                                                      easing.type: Theme.easeOutCubic }
                }

                Column {
                    id: railCol
                    x: Theme.s6; y: Theme.s6
                    width: 240
                    spacing: Theme.s5

                Column {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: "Genres"
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.trackingWide
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: detailPage.detail && detailPage.detail.genres
                                   ? detailPage.detail.genres.slice(0, 3) : []
                            delegate: Rectangle {
                                required property var modelData
                                height: 26
                                width: genreTxt.implicitWidth + 20
                                radius: Theme.rPill
                                color: Theme.glassPanel
                                border.color: Theme.borderDefault; border.width: 1
                                Text {
                                    id: genreTxt
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Theme.textSecondary
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.tsSmall
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: "Studio"
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.trackingWide
                    }
                    Text {
                        width: parent.width
                        text: detailPage.detail ? AniListApi.studio(detailPage.detail) : ""
                        visible: text.length > 0
                        color: Theme.textPrimary
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsBody
                        elide: Text.ElideRight
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: "More info"
                        color: Theme.textMuted
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsSmall
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.trackingWide
                    }
                    Column {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: detailPage.factRows()
                            delegate: Row {
                                required property var modelData
                                width: parent.width
                                spacing: Theme.s3
                                Text {
                                    width: 92
                                    text: modelData.k
                                    color: Theme.textMuted
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.tsSmall
                                }
                                Text {
                                    width: parent.width - 92 - parent.spacing
                                    text: modelData.v
                                    color: Theme.textSecondary
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.tsSmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }

                }

            // Back, over the banner
            Item {
                id: backBtn
                x: detailPage.gutter - 8
                y: 14
                width: backRow.implicitWidth + 18
                height: 34
                activeFocusOnTab: true

                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: backMa.containsMouse ? "#242424" : Qt.rgba(0, 0, 0, 0.5)
                    border.color: backBtn.activeFocus ? "#ffffff" : "#3a3a3a"
                    border.width: backBtn.activeFocus ? 2 : 1
                }
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        text: "\uE76B"
                        color: "#ffffff"; font.family: detailPage.iconFont; font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Back"
                        color: "#ffffff"; font.family: detailPage.bodyFont; font.pixelSize: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: backMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { backBtn.forceActiveFocus(); detailPage.backRequested() }
                }
                Keys.onEnterPressed:  detailPage.backRequested()
                Keys.onReturnPressed: detailPage.backRequested()
            }

            // ══ Poster, straddling the banner seam ══════════════════════
            Rectangle {
                id: posterFrame
                x: detailPage.gutter
                y: banner.height - Math.round(detailPage.posterW * 0.42)
                width: detailPage.posterW
                height: Math.round(detailPage.posterW * 3 / 2)
                radius: 8
                color: "#141414"
                border.color: "#2e2e2e"; border.width: 1
                clip: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.62)
                    shadowBlur: 0.6
                    shadowVerticalOffset: 10
                }
                Image {
                    anchors.fill: parent
                    source: detailPage.detail ? AniListApi.cover(detailPage.detail) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            // ══ Title block ═════════════════════════════════════════════
            Column {
                id: titleCol
                x: posterFrame.x + posterFrame.width + 22
                y: banner.height - Math.round(detailPage.posterW * 0.40)
                width: Math.max(240, canvas.width - x - detailPage.gutter)
                spacing: 0

                Text {
                    width: parent.width
                    text: detailPage.detail ? AniListApi.title(detailPage.detail) : ""
                    color: "#ffffff"
                    font.family: detailPage.displayFont
                    font.pixelSize: detailPage.titleSize
                    font.weight: Font.Bold
                    font.letterSpacing: -0.5
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(detailPage.titleSize * 1.06)
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignTop
                    height: Math.min(implicitHeight, 2 * lineHeight)
                }

                Text {
                    visible: text.length > 0
                    topPadding: 4
                    width: parent.width
                    text: {
                        var d = detailPage.detail
                        if (!d || !d.title) return ""
                        var main = AniListApi.title(d)
                        var alt = d.title.native || ""
                        if (!alt || alt === main) alt = d.title.romaji || ""
                        return alt === main ? "" : alt
                    }
                    color: "#9a9a9a"
                    font.family: detailPage.bodyFont
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    visible: text.length > 0
                    topPadding: 8
                    text: detailPage.heroMeta(detailPage.detail)
                    color: "#e6e6e6"
                    font.family: detailPage.bodyFont
                    font.pixelSize: 13
                }

                Item { width: 1; height: 12; visible: detailPage.tallyText !== "" }

                Rectangle {
                    id: tallyChip
                    visible: detailPage.tallyText !== ""
                    height: 30
                    radius: 4
                    width: tallyRow.implicitWidth + 20
                    color: Qt.rgba(0, 0, 0, 0.55)
                    border.color: "#3a3a3a"; border.width: 1
                    Row {
                        id: tallyRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                running: tallyChip.visible && !detailPage.calm
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 900 }
                                NumberAnimation { to: 1.0;  duration: 900 }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailPage.tallyText
                            color: "#ffffff"
                            font.family: detailPage.displayFont
                            font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 1.2
                        }
                    }
                }

                Item { width: 1; height: 16 }

                // ── Actions ─────────────────────────────────────────────
                Row {
                    spacing: 10
                    Rectangle {
                        id: watchBtn
                        width: Math.max(116, watchTxt.implicitWidth + 36)
                        height: 42; radius: 8
                        activeFocusOnTab: true
                        color: watchMa.pressed ? "#d9d9d9" : watchMa.containsMouse ? "#ffffff" : "#f5f5f5"
                        border.color: watchBtn.activeFocus ? "#ffffff" : "transparent"
                        border.width: watchBtn.activeFocus ? 2 : 0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: watchTxt
                            anchors.centerIn: parent
                            text: "\u25B6   Play"
                            color: "#0a0a0a"
                            font.family: detailPage.bodyFont
                            font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: watchMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                watchBtn.forceActiveFocus()
                                var eps = detailPage.episodeList(detailPage.detail)
                                if (detailPage.detail && eps.length > 0 && eps[0].url) {
                                    detailPage.episodePlayRequested(eps[0].url,
                                        AniListApi.title(detailPage.detail),
                                        "Episode 1", eps[0].thumbnail || "")
                                } else if (detailPage.detail) {
                                    detailPage.playRequested(detailPage.detail.id,
                                                             AniListApi.title(detailPage.detail))
                                }
                            }
                        }
                    }
                    Rectangle {
                        id: addBtn
                        width: Math.max(108, addTxt.implicitWidth + 30)
                        height: 42; radius: 8
                        activeFocusOnTab: true
                        color: addMa.containsMouse ? "#222222" : "#181818"
                        border.color: addBtn.activeFocus ? "#ffffff" : "#2e2e2e"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: addTxt
                            anchors.centerIn: parent
                            text: "+   My List"
                            color: "#ffffff"
                            font.family: detailPage.bodyFont
                            font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                addBtn.forceActiveFocus()
                                if (detailPage.detail) detailPage.addToListRequested(detailPage.detail.id)
                            }
                        }
                    }
                    Rectangle {
                        id: trailerBtn
                        visible: detailPage.hasTrailer(detailPage.detail)
                        width: Math.max(92, trailerTxt.implicitWidth + 30)
                        height: 42; radius: 8
                        activeFocusOnTab: true
                        color: trailerMa.containsMouse ? "#222222" : "#181818"
                        border.color: trailerBtn.activeFocus ? "#ffffff" : "#2e2e2e"
                        border.width: 1
                        Text {
                            id: trailerTxt
                            anchors.centerIn: parent
                            text: "Trailer"
                            color: "#ffffff"
                            font.family: detailPage.bodyFont
                            font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: trailerMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                trailerBtn.forceActiveFocus()
                                var d = detailPage.detail
                                if (d) Qt.openUrlExternally("https://www.youtube.com/watch?v=" + d.trailer.id)
                            }
                        }
                    }
                }
            }

            // ══ Tabs ════════════════════════════════════════════════════
            Item {
                id: tabBar
                x: detailPage.gutter
                y: Math.max(posterFrame.y + posterFrame.height,
                            titleCol.y + titleCol.height) + 24
                width: Math.min(canvas.width - detailPage.gutter * 2, 1000)
                height: 38

                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1f1f1f"
                }

                // One underline that slides between tabs instead of a separate
                // bar per tab, so the change reads as movement rather than a blink.
                Rectangle {
                    id: tabIndicator
                    anchors.bottom: parent.bottom
                    x: tabRow.x + detailPage.tabIndX
                    width: detailPage.tabIndW
                    height: 2; radius: 1
                    color: Theme.textPrimary
                    Behavior on x { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
                    Behavior on width { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
                }

                Row {
                    id: tabRow
                    anchors { left: parent.left; bottom: parent.bottom }
                    spacing: 26
                    Repeater {
                        model: [
                            { key: "episodes", label: "Episodes" },
                            { key: "details",  label: "Details" },
                            { key: "similar",  label: "More like this" }
                        ]
                        delegate: Item {
                            id: tabItem
                            required property var modelData
                            width: tabLabel.implicitWidth
                            height: 38
                            activeFocusOnTab: true
                            readonly property bool isOn: detailPage.tab === modelData.key

                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.label

                            Text {
                                id: tabLabel
                                anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 9 }
                                text: modelData.label
                                color: tabItem.isOn ? "#ffffff" : (tabMa.containsMouse ? "#cfcfcf" : "#8a8a8a")
                                font.family: detailPage.bodyFont
                                font.pixelSize: 14
                                font.weight: tabItem.isOn ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }
                            // Publish geometry while active so the shared underline
                            // can slide to it.
                            onIsOnChanged: {
                                if (tabItem.isOn) {
                                    detailPage.tabIndX = tabItem.x
                                    detailPage.tabIndW = tabItem.width
                                }
                            }
                            Component.onCompleted: {
                                if (tabItem.isOn) {
                                    detailPage.tabIndX = tabItem.x
                                    detailPage.tabIndW = tabItem.width
                                }
                            }
                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { tabItem.forceActiveFocus(); detailPage.tab = modelData.key }
                            }
                            Keys.onEnterPressed:  detailPage.tab = modelData.key
                            Keys.onReturnPressed: detailPage.tab = modelData.key
                        }
                    }
                }
            }

            // ══ Tab content ═════════════════════════════════════════════
            Column {
                id: contentCol
                x: detailPage.gutter
                y: tabBar.y + tabBar.height + 22
                width: Math.min(canvas.width - detailPage.gutter * 2, 1000)
                spacing: 28

                transform: Translate { id: contentShift; y: 0 }

                // Only the incoming panel animates. Fading the outgoing one in
                // place would need it to stay visible, and the Column lays out
                // visible children, so the page would jump mid-transition.
                SequentialAnimation {
                    id: tabSwitch
                    ParallelAnimation {
                        NumberAnimation { target: contentCol; property: "opacity"
                                          from: 0.0; to: 1.0
                                          duration: Theme.dBase; easing.type: Theme.easeOutCubic }
                        NumberAnimation { target: contentShift; property: "y"
                                          from: Theme.s4; to: 0
                                          duration: Theme.dBase; easing.type: Theme.easeOutCubic }
                    }
                }

                // ── Episodes ────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: detailPage.tab === "episodes"
                    Text {
                        visible: text.length > 0
                        text: {
                            var n = detailPage.episodeList(detailPage.detail).length
                            if (n === 0) return ""
                            return n === 1 ? "1 episode" : n + " episodes"
                        }
                        color: "#8a8a8a"
                        font.family: detailPage.bodyFont
                        font.pixelSize: 13
                    }
                    Flickable {
                        width: parent.width
                        height: 198
                        visible: detailPage.episodeList(detailPage.detail).length > 0
                        contentWidth: epRow.width
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        Row {
                            id: epRow
                            spacing: 14
                            Repeater {
                                model: detailPage.episodeList(detailPage.detail)
                                delegate: Item {
                                    id: epCard
                                    required property var modelData
                                    required property int index
                                    width: 220
                                    height: 198
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: epTitle.text

                                    Rectangle {
                                        id: epThumb
                                        width: 220; height: 124
                                        radius: 8
                                        color: "#141414"
                                        border.color: epCard.activeFocus ? "#ffffff" : "#242424"
                                        border.width: epCard.activeFocus ? 2 : 1
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: epCard.modelData.thumbnail || ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            color: epMa.containsMouse ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(0, 0, 0, 0.45)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 38; height: 38; radius: 19
                                            color: Qt.rgba(0, 0, 0, 0.6)
                                            border.color: "#ffffff"; border.width: 1
                                            opacity: epMa.containsMouse ? 1 : 0.75
                                            Text {
                                                anchors.centerIn: parent
                                                anchors.horizontalCenterOffset: 1
                                                text: "\u25B6"
                                                color: "#ffffff"; font.pixelSize: 13
                                            }
                                        }
                                    }
                                    Text {
                                        id: epTitle
                                        anchors { top: epThumb.bottom; topMargin: 8; left: parent.left; right: parent.right }
                                        text: (epCard.index + 1) + ". " + (epCard.modelData.title || ("Episode " + (epCard.index + 1)))
                                        color: "#e6e6e6"
                                        font.family: detailPage.bodyFont
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignTop
                                        lineHeightMode: Text.FixedHeight
                                        lineHeight: 18
                                        height: 36
                                    }
                                    Text {
                                        anchors { top: epTitle.bottom; left: parent.left }
                                        text: detailPage.detail && detailPage.detail.duration
                                              ? detailPage.detail.duration + "m" : ""
                                        color: "#6e6e6e"
                                        font.family: detailPage.bodyFont
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: epMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            epCard.forceActiveFocus()
                                            var u = epCard.modelData.url
                                            if (!u) return
                                            detailPage.episodePlayRequested(
                                                u,
                                                detailPage.detail ? AniListApi.title(detailPage.detail) : "",
                                                "Episode " + (epCard.index + 1),
                                                epCard.modelData.thumbnail || "")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: detailPage.episodeList(detailPage.detail).length === 0
                        text: "AniList has no episodes listed for this title. Open Details for more, or watch the trailer."
                        color: "#8a8a8a"
                        font.family: detailPage.bodyFont
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }

                // ── Details ─────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 24
                    visible: detailPage.tab === "details"

                    Item {
                        width: parent.width
                        height: 62
                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 1; color: "#262626"
                        }
                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                            height: 1; color: "#262626"
                        }
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            Repeater {
                                model: detailPage.slateCells(detailPage.detail)
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    width: cellCol.implicitWidth + 36
                                    height: 62
                                    Rectangle {
                                        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                        width: 1; color: "#262626"
                                        visible: index > 0
                                    }
                                    Column {
                                        id: cellCol
                                        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                                        spacing: 4
                                        Text {
                                            text: modelData.label
                                            color: "#6e6e6e"
                                            font.family: detailPage.displayFont
                                            font.pixelSize: 10; font.letterSpacing: 1.2
                                        }
                                        Text {
                                            text: modelData.value
                                            color: "#ffffff"
                                            font.family: detailPage.displayFont
                                            font.pixelSize: 16; font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 10
                        visible: synopsisTxt.text.length > 0
                        Text {
                            text: "Synopsis"
                            color: "#ffffff"
                            font.family: detailPage.displayFont
                            font.pixelSize: 18; font.weight: Font.DemiBold
                        }
                        Text {
                            id: synopsisTxt
                            width: Math.min(parent.width, 680)
                            text: detailPage.detail ? AniListApi.cleanDesc(detailPage.detail) : ""
                            color: "#b3b3b3"
                            font.family: detailPage.bodyFont
                            font.pixelSize: 14
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 23
                            wrapMode: Text.WordWrap
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: detailPage.detail && detailPage.detail.genres
                                 ? detailPage.detail.genres.length > 0 : false
                        Repeater {
                            model: detailPage.detail && detailPage.detail.genres
                                   ? detailPage.detail.genres : []
                            delegate: Rectangle {
                                radius: 14
                                height: 28
                                width: gTxt.implicitWidth + 22
                                color: "#141414"
                                border.color: "#2e2e2e"; border.width: 1
                                Text {
                                    id: gTxt
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: "#b3b3b3"
                                    font.family: detailPage.bodyFont
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 12
                        visible: detailPage.characterList(detailPage.detail).length > 0
                        Text {
                            text: "Main characters"
                            color: "#ffffff"
                            font.family: detailPage.displayFont
                            font.pixelSize: 18; font.weight: Font.DemiBold
                        }
                        Row {
                            spacing: 14
                            Repeater {
                                model: detailPage.characterList(detailPage.detail).slice(0, 7)
                                delegate: Item {
                                    required property var modelData
                                    width: 112
                                    height: 182
                                    Rectangle {
                                        width: 112; height: 144
                                        radius: 8
                                        color: "#141414"
                                        border.color: "#242424"; border.width: 1
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: modelData && modelData.image ? modelData.image.medium : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                    }
                                    Column {
                                        y: 152
                                        width: 112
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: modelData && modelData.name ? modelData.name.full : ""
                                            color: "#e6e6e6"
                                            font.family: detailPage.bodyFont
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Main"
                                            color: "#6e6e6e"
                                            font.family: detailPage.bodyFont
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── More like this ──────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 12
                    visible: detailPage.tab === "similar"
                    Flickable {
                        width: parent.width
                        height: 236
                        visible: detailPage.recommendationList(detailPage.detail).length > 0
                        contentWidth: recRow.width
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        Row {
                            id: recRow
                            spacing: 16
                            Repeater {
                                model: detailPage.recommendationList(detailPage.detail).slice(0, 10)
                                delegate: Item {
                                    id: recCard
                                    required property var modelData
                                    width: 132
                                    height: 222
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.Button
                                    Accessible.name: recTitle.text

                                    Rectangle {
                                        y: 0
                                        width: 132; height: 198
                                        radius: 8
                                        color: "#141414"
                                        border.color: recCard.activeFocus ? "#ffffff" : "#242424"
                                        border.width: recCard.activeFocus ? 2 : 1
                                        clip: true
                                        scale: recMa.containsMouse ? 1.03 : 1.0
                                        Behavior on scale {
                                            NumberAnimation { duration: detailPage.calm ? 0 : 220
                                                                easing.type: Easing.OutCubic }
                                        }
                                        Image {
                                            anchors.fill: parent
                                            source: recCard.modelData.mediaRecommendation
                                                    ? AniListApi.cover(recCard.modelData.mediaRecommendation) : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        Rectangle {
                                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                            height: 22
                                            color: Qt.rgba(0, 0, 0, 0.62)
                                            visible: recScore.text.length > 0
                                            Text {
                                                id: recScore
                                                anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                                                text: {
                                                    var m = recCard.modelData.mediaRecommendation
                                                    var sc = m ? AniListApi.score(m) : ""
                                                    return sc ? "\u2605 " + sc : ""
                                                }
                                                color: "#ffffff"
                                                font.family: detailPage.displayFont
                                                font.pixelSize: 11; font.weight: Font.Bold
                                            }
                                        }
                                    }
                                    Text {
                                        id: recTitle
                                        x: 1; y: 206
                                        width: 132
                                        text: recCard.modelData.mediaRecommendation
                                              ? AniListApi.title(recCard.modelData.mediaRecommendation) : ""
                                        color: recMa.containsMouse ? "#ffffff" : "#b3b3b3"
                                        font.family: detailPage.bodyFont
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    MouseArea {
                                        id: recMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            recCard.forceActiveFocus()
                                            var m = recCard.modelData.mediaRecommendation
                                            if (m && m.id) detailPage.seriesId = m.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: detailPage.recommendationList(detailPage.detail).length === 0
                        text: "AniList has no recommendations for this title yet."
                        color: "#8a8a8a"
                        font.family: detailPage.bodyFont
                        font.pixelSize: 13
                    }
                }
            }
        }
    }

    // ── Loading ─────────────────────────────────────────────────────────
    // A hero-shaped skeleton, not a spinner: it previews the layout the
    // response fills in, so nothing jumps when the data lands (section 26).
    Rectangle {
        id: loadingPane
        anchors.fill: parent
        color: Theme.bg
        visible: detailPage.loading || (detailPage.detail === null && detailPage.errorMsg === "")
        clip: true

        Rectangle {
            id: skHero
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: Math.max(240, Math.min(parent.height * 0.58, 360))
            color: Theme.card

            Rectangle {
                id: skPoster
                anchors { left: parent.left; leftMargin: Theme.s8; bottom: parent.bottom
                          bottomMargin: Theme.s8 }
                width: 148; height: 210
                color: Theme.surfaceRaised
            }
            Column {
                anchors { left: skPoster.right; right: parent.right
                          bottom: skPoster.bottom; leftMargin: Theme.s6; rightMargin: Theme.s8 }
                spacing: Theme.s3
                Skeleton {
                    width: parent.width * 0.72; bars: 2; barHeight: 26
                    running: loadingPane.visible && !detailPage.calm
                }
                Skeleton {
                    width: parent.width * 0.44; bars: 1; barHeight: 14
                    running: loadingPane.visible && !detailPage.calm
                }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: skHero.bottom
                      topMargin: Theme.s8; leftMargin: Theme.s8; rightMargin: Theme.s8 }
            spacing: Theme.s6
            Skeleton {
                width: parent.width; bars: 3; barHeight: 13
                running: loadingPane.visible && !detailPage.calm
            }
            SkeletonGrid { columns: 5; rows: 1; cardWidth: 160; gutter: 0 }
        }
    }

    // ── Failure ─────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 14
        visible: detailPage.errorMsg !== "" && !detailPage.loading
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: detailPage.errorMsg
            color: "#ff8a8a"
            font.family: detailPage.bodyFont
            font.pixelSize: 14
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: retryTxt.implicitWidth + 34; height: 38; radius: 8
            color: retryMa.containsMouse ? "#222222" : "#181818"
            border.color: "#2e2e2e"; border.width: 1
            Text {
                id: retryTxt
                anchors.centerIn: parent
                text: "Try again"
                color: "#ffffff"
                font.family: detailPage.bodyFont
                font.pixelSize: 13
            }
            MouseArea {
                id: retryMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: detailPage.loadDetail()
            }
        }
    }
}
