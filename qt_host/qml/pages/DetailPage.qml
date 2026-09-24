import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../"

// DetailPage — a series title card.
//
// Full-bleed banner, then the poster straddling the banner's lower edge like a
// print title card, with the slate (the facts a viewer actually scans) set as a
// table beneath it. Values mirror the tokens declared in main.qml.
Rectangle {
    id: detailPage
    color: "#07070d"

    property int seriesId: 0
    property var detail: null
    property bool loading: false
    property string errorMsg: ""

    signal backRequested()
    signal playRequested(int id, string title)
    signal addToListRequested(int id)

    readonly property string displayFont: "Bahnschrift, Segoe UI Variable Display, Segoe UI"
    readonly property string bodyFont:    "Segoe UI Variable Text, Segoe UI"
    readonly property string iconFont:    "Segoe MDL2 Assets"
    readonly property int    gutter:      32
    readonly property bool   calm:        Qt.application.arguments.indexOf("--reduce-motion") !== -1

    // ── Data ─────────────────────────────────────────────────────────────
    function loadDetail() {
        if (seriesId <= 0)
            return
        loading = true
        detail = null
        errorMsg = ""
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

    // The slate: the facts, in the order a viewer scans them.
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: canvas
            width: flick.width
            height: contentCol.y + contentCol.height + 64

            // ══ Banner ═════════════════════════════════════════════════
            Item {
                id: banner
                y: 0
                width: parent.width
                height: 340

                Rectangle { anchors.fill: parent; color: "#0b0c14" }

                Image {
                    id: bannerArt
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
                        GradientStop { position: 0.00; color: Qt.rgba(0.027, 0.027, 0.051, 0.88) }
                        GradientStop { position: 0.55; color: Qt.rgba(0.027, 0.027, 0.051, 0.34) }
                        GradientStop { position: 1.00; color: Qt.rgba(0.027, 0.027, 0.051, 0.00) }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.00; color: Qt.rgba(0.027, 0.027, 0.051, 0.62) }
                        GradientStop { position: 0.30; color: "transparent" }
                        GradientStop { position: 1.00; color: "#07070d" }
                    }
                }
            }

            // Back, over the banner
            Item {
                id: backBtn
                x: detailPage.gutter - 8
                y: 18
                width: backRow.implicitWidth + 18
                height: 34
                activeFocusOnTab: true

                Rectangle {
                    anchors.fill: parent
                    radius: 17
                    color: backMa.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0.016, 0.016, 0.039, 0.55)
                    border.color: backBtn.activeFocus ? "#f47521" : Qt.rgba(1, 1, 1, 0.18)
                    border.width: backBtn.activeFocus ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 130 } }
                }

                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 7
                    Text {
                        text: "\uE76B"
                        color: "#f2f2f7"
                        font.family: detailPage.iconFont
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Back"
                        color: "#f2f2f7"
                        font.family: detailPage.displayFont
                        font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 1.4
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
                Keys.onEnterPressed: detailPage.backRequested()
                Keys.onReturnPressed: detailPage.backRequested()
            }

            // ══ Poster, straddling the banner seam ══════════════════════
            Rectangle {
                id: posterFrame
                x: detailPage.gutter
                y: banner.height - 138
                width: 226
                height: 339
                radius: 6
                color: "#101119"
                border.color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1
                clip: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.62)
                    shadowBlur: 0.6
                    shadowVerticalOffset: 10
                    shadowHorizontalOffset: 0
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
                x: posterFrame.x + posterFrame.width + 26
                y: banner.height - 126
                width: Math.max(280, canvas.width - x - detailPage.gutter)
                spacing: 0

                Text {
                    id: titleTxt
                    width: parent.width
                    text: detailPage.detail ? AniListApi.title(detailPage.detail) : ""
                    color: "#f2f2f7"
                    font.family: detailPage.displayFont
                    font.pixelSize: 42
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 44
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignTop
                    height: Math.min(implicitHeight, 2 * lineHeight)
                }

                Text {
                    id: altTitleTxt
                    width: parent.width
                    visible: text.length > 0
                    text: {
                        var d = detailPage.detail
                        if (!d || !d.title) return ""
                        var main = AniListApi.title(d)
                        var alt = d.title.native || ""
                        if (!alt || alt === main) alt = d.title.romaji || ""
                        return alt === main ? "" : alt
                    }
                    color: "#8b8ba4"
                    font.family: detailPage.bodyFont
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }

                Item { width: 1; height: 16; visible: detailPage.tallyText !== "" }

                // Airing tally — the same signal the home hero uses
                Rectangle {
                    id: tallyChip
                    visible: detailPage.tallyText !== ""
                    height: 34
                    radius: 4
                    width: tallyRow.implicitWidth + 22
                    color: Qt.rgba(0.016, 0.016, 0.039, 0.72)
                    border.color: Qt.rgba(0.95, 0.46, 0.13, 0.34)
                    border.width: 1

                    Row {
                        id: tallyRow
                        anchors.centerIn: parent
                        spacing: 9
                        Rectangle {
                            id: tallyDot
                            width: 7; height: 7; radius: 4
                            color: "#f47521"
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on scale {
                                running: tallyChip.visible && !detailPage.calm
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.75; duration: 900; easing.type: Easing.OutCubic }
                                NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutCubic }
                            }
                            SequentialAnimation on opacity {
                                running: tallyChip.visible && !detailPage.calm
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 900 }
                                NumberAnimation { to: 1.0;  duration: 900 }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailPage.tallyText
                            color: "#f2f2f7"
                            font.family: detailPage.displayFont
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.4
                        }
                    }
                }

                Item { width: 1; height: 18 }

                // ── Actions ─────────────────────────────────────────────
                Row {
                    spacing: 10

                    Rectangle {
                        id: watchBtn
                        width: Math.max(150, watchTxt.implicitWidth + 38)
                        height: 44; radius: 5
                        activeFocusOnTab: true
                        color: watchMa.pressed ? "#c9551a" : watchMa.containsMouse ? "#ff8434" : "#f47521"
                        border.color: watchBtn.activeFocus ? "#ffffff" : "transparent"
                        border.width: watchBtn.activeFocus ? 2 : 0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: watchTxt
                            anchors.centerIn: parent
                            text: "\u25B6   Watch now"
                            color: "white"
                            font.family: detailPage.displayFont
                            font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2
                        }
                        MouseArea {
                            id: watchMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                watchBtn.forceActiveFocus()
                                if (detailPage.detail)
                                    detailPage.playRequested(detailPage.detail.id,
                                                             AniListApi.title(detailPage.detail))
                            }
                        }
                    }

                    Rectangle {
                        id: trailerBtn
                        width: Math.max(104, trailerTxt.implicitWidth + 30)
                        height: 44; radius: 5
                        activeFocusOnTab: true
                        color: trailerMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                        border.color: trailerBtn.activeFocus ? "#f47521" : Qt.rgba(1,1,1,0.16)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: trailerTxt
                            anchors.centerIn: parent
                            text: detailPage.hasTrailer(detailPage.detail) ? "Trailer" : "AniList page"
                            color: "#f2f2f7"
                            font.family: detailPage.displayFont
                            font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.2
                        }
                        MouseArea {
                            id: trailerMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                trailerBtn.forceActiveFocus()
                                var d = detailPage.detail
                                if (!d) return
                                if (detailPage.hasTrailer(d))
                                    Qt.openUrlExternally("https://www.youtube.com/watch?v=" + d.trailer.id)
                                else
                                    Qt.openUrlExternally("https://anilist.co/anime/" + d.id)
                            }
                        }
                    }

                    Rectangle {
                        id: addBtn
                        width: 44; height: 44; radius: 5
                        activeFocusOnTab: true
                        color: addMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                        border.color: addBtn.activeFocus ? "#f47521" : Qt.rgba(1,1,1,0.16)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "\uE710"
                            color: "#f2f2f7"
                            font.family: detailPage.iconFont
                            font.pixelSize: 15
                        }
                        ToolTip.visible: addMa.containsMouse
                        ToolTip.text: "Add to my list"
                        ToolTip.delay: 400
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
                }

                Item { width: 1; height: 16 }

                // ── Genres ──────────────────────────────────────────────
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: detailPage.detail && detailPage.detail.genres
                               ? detailPage.detail.genres.slice(0, 6) : []
                        delegate: Rectangle {
                            radius: 3
                            height: 26
                            width: genreTxt.implicitWidth + 16
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.09)
                            border.width: 1
                            Text {
                                id: genreTxt
                                anchors.centerIn: parent
                                text: modelData
                                color: "#b6b6cc"
                                font.family: detailPage.displayFont
                                font.pixelSize: 12; font.letterSpacing: 1.1
                            }
                        }
                    }
                }

                Item { width: 1; height: 20 }

                    // Synopsis, held to a readable measure
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: synopsisTxt.text.length > 0
                        Text {
                            text: "Synopsis"
                            color: "#f2f2f7"
                            font.family: detailPage.displayFont
                            font.pixelSize: 22; font.weight: Font.Bold
                        }
                        Text {
                            id: synopsisTxt
                            width: Math.min(parent.width, 620)
                            text: detailPage.detail ? AniListApi.cleanDesc(detailPage.detail) : ""
                            color: "#b0b0c6"
                            font.family: detailPage.bodyFont
                            font.pixelSize: 15
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 25
                            wrapMode: Text.WordWrap
                        }
                    }
            }

            // ══ Slate ═══════════════════════════════════════════════════
            Item {
                id: slate
                x: detailPage.gutter
                y: Math.max(posterFrame.y + posterFrame.height,
                            titleCol.y + titleCol.height) + 30
                width: Math.min(canvas.width - detailPage.gutter * 2, 1000)
                height: 62

                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 1; color: Qt.rgba(1, 1, 1, 0.12)
                }
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1; color: Qt.rgba(1, 1, 1, 0.12)
                }

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    Repeater {
                        model: detailPage.slateCells(detailPage.detail)
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: cellCol.implicitWidth + 36
                            height: slate.height
                            Rectangle {
                                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                width: 1
                                color: Qt.rgba(1, 1, 1, 0.09)
                                visible: index > 0
                            }
                            Column {
                                id: cellCol
                                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                                spacing: 4
                                Text {
                                    text: modelData.label
                                    color: "#62627c"
                                    font.family: detailPage.displayFont
                                    font.pixelSize: 10; font.letterSpacing: 1.6
                                }
                                Text {
                                    text: modelData.value
                                    color: "#f2f2f7"
                                    font.family: detailPage.displayFont
                                    font.pixelSize: 17; font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            // ══ Content ════════════════════════════════════════════════
            Column {
                id: contentCol
                x: detailPage.gutter
                y: slate.y + slate.height + 34
                width: Math.min(canvas.width - detailPage.gutter * 2, 1000)
                spacing: 34

                // Main characters
                Column {
                    width: parent.width
                    spacing: 12
                    visible: detailPage.characterList(detailPage.detail).length > 0
                    Text {
                        text: "Main characters"
                        color: "#f2f2f7"
                        font.family: detailPage.displayFont
                        font.pixelSize: 22; font.weight: Font.Bold
                    }
                    Row {
                        spacing: 14
                        Repeater {
                            model: detailPage.characterList(detailPage.detail).slice(0, 7)
                            delegate: Item {
                                required property var modelData
                                width: 118
                                height: 188
                                Rectangle {
                                    y: 0
                                    width: 118; height: 150
                                    radius: 5
                                    color: "#101119"
                                    border.color: Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: modelData && modelData.image ? modelData.image.medium : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                Column {
                                    y: 158
                                    width: 118
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        text: modelData && modelData.name ? modelData.name.full : ""
                                        color: "#e6e6ef"
                                        font.family: detailPage.displayFont
                                        font.pixelSize: 13; font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: (modelData && modelData.role)
                                             ? modelData.role.toLowerCase() : "main"
                                        color: "#62627c"
                                        font.family: detailPage.bodyFont
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                // More like this — selecting one loads it in place
                Column {
                    width: parent.width
                    spacing: 12
                    visible: detailPage.recommendationList(detailPage.detail).length > 0
                    Text {
                        text: "More like this"
                        color: "#f2f2f7"
                        font.family: detailPage.displayFont
                        font.pixelSize: 22; font.weight: Font.Bold
                    }
                    Row {
                        spacing: 16
                        Repeater {
                            model: detailPage.recommendationList(detailPage.detail).slice(0, 7)
                            delegate: Item {
                                id: recCard
                                required property var modelData
                                width: 132
                                height: 222
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: recTitle.text

                                Rectangle {
                                    id: recArt
                                    y: 0
                                    width: 132; height: 198
                                    radius: 5
                                    color: "#101119"
                                    border.color: recCard.activeFocus ? "#f47521" : Qt.rgba(1, 1, 1, 0.07)
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
                                        color: Qt.rgba(0.016, 0.016, 0.039, 0.82)
                                        visible: recScore.text.length > 0
                                        Text {
                                            id: recScore
                                            anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                                            text: {
                                                var m = recCard.modelData.mediaRecommendation
                                                var s = m ? AniListApi.score(m) : ""
                                                return s ? "\u2605 " + s : ""
                                            }
                                            color: "#f2f2f7"
                                            font.family: detailPage.displayFont
                                            font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.6
                                        }
                                    }
                                }

                                Text {
                                    id: recTitle
                                    x: 1; y: 206
                                    width: 132
                                    text: recCard.modelData.mediaRecommendation
                                          ? AniListApi.title(recCard.modelData.mediaRecommendation) : ""
                                    color: recMa.containsMouse ? "#f47521" : "#c9c9dd"
                                    font.family: detailPage.displayFont
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 160 } }
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
            }
        }
    }

    // ── Loading ─────────────────────────────────────────────────────────
    Rectangle {
        id: loadingPane
        anchors.fill: parent
        color: "#07070d"
        visible: detailPage.loading || (detailPage.detail === null && detailPage.errorMsg === "")

        Rectangle {
            id: spinner
            anchors.centerIn: parent
            width: 36; height: 36; radius: 18
            color: "transparent"
            border.color: "#f47521"
            border.width: 2
            opacity: 0.75
            RotationAnimator on rotation {
                from: 0; to: 360; duration: 900
                loops: Animation.Infinite
                running: loadingPane.visible && !detailPage.calm
            }
        }
    }

    // ── Failure: say what happened and what to do ────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 16
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
            width: retryTxt.implicitWidth + 36; height: 40; radius: 5
            color: retryMa.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
            border.color: Qt.rgba(1, 1, 1, 0.18); border.width: 1
            Text {
                id: retryTxt
                anchors.centerIn: parent
                text: "Try again"
                color: "#f2f2f7"
                font.family: detailPage.displayFont
                font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 1.4
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
