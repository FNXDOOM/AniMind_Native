import QtQuick
import ".."
import "."

// HeroBanner — the featured title at the top of Home.
//
// Extracted from HomePage. Everything it used to reach for on the page is now
// an input, and its three intentions come out as signals, so it can be hosted
// by any page that has a media object and a layout width.
Item {
    id: banner

    property var    media: null
    property int    gutter: Theme.s8
    property bool   calm: false
    property int    heroSize: 40
    property int    heroColW: 560
    /// Re-render trigger for the airing countdown; bump it once a minute.
    property int    tallyStamp: 0
    /// function(media) -> string
    property var tallyFor:  function(m) { return "" }
    property var courFor:   function(m) { return "" }
    property var formatFor: function(m) { return "" }

    signal seriesPicked(int anilistId)
    signal watchPicked(int anilistId, string title)
    signal addRequested(int anilistId)

            width: parent.width
            height: 520

            Rectangle { anchors.fill: parent; color: Theme.bgSecondary }

            Item {
                id: heroArtHolder
                anchors.fill: parent
                clip: true

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
                    Behavior on opacity { NumberAnimation { duration: banner.calm ? 0 : 520; easing.type: Easing.OutCubic } }

                    transform: Scale {
                        id: artScale
                        xScale: 1.0
                        yScale: 1.0
                        origin.x: heroArt.width * 0.35
                        origin.y: heroArt.height * 0.5
                    }
                }

                // Slow Ken Burns drift. Long and shallow on purpose: it should
                // be felt rather than watched, and it stops for reduced motion.
                SequentialAnimation {
                    id: ambientZoom
                    running: banner.visible && !banner.calm && heroArt.status === Image.Ready
                    loops: Animation.Infinite
                    NumberAnimation { target: artScale; property: "xScale"
                                      from: 1.0; to: 1.055; duration: Theme.dAmbient; easing.type: Easing.InOutSine }
                    NumberAnimation { target: artScale; property: "xScale"
                                      from: 1.055; to: 1.0; duration: Theme.dAmbient; easing.type: Easing.InOutSine }
                }
                ParallelAnimation {
                    running: ambientZoom.running
                    loops: Animation.Infinite
                    NumberAnimation { target: artScale; property: "yScale"
                                      from: 1.0; to: 1.04; duration: Theme.dAmbient * 1.4; easing.type: Easing.InOutSine }
                    NumberAnimation { target: artScale; property: "yScale"
                                      from: 1.04; to: 1.0; duration: Theme.dAmbient * 1.4; easing.type: Easing.InOutSine }
                }
            }

            // Left scrim: stops short of the art's centre so it stays readable
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.00; color: Qt.rgba(0.027, 0.035, 0.047, 0.97) }
                    GradientStop { position: 0.34; color: Qt.rgba(0.027, 0.035, 0.047, 0.74) }
                    GradientStop { position: 0.66; color: Qt.rgba(0.027, 0.035, 0.047, 0.10) }
                    GradientStop { position: 1.00; color: Qt.rgba(0.027, 0.035, 0.047, 0.00) }
                }
            }

            // Bottom scrim carries the hero into the first row
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.58; color: "transparent" }
                    GradientStop { position: 0.86; color: Qt.rgba(0.027, 0.035, 0.047, 0.82) }
                    GradientStop { position: 1.00; color: Theme.bg }
                }
            }

            // Loading tally
            Rectangle {
                id: heroPulse
                anchors.centerIn: parent
                width: 40; height: 40; radius: 20
                color: "transparent"; border.color: Theme.textPrimary; border.width: 2
                visible: loadingHero && heroMedia === null
                SequentialAnimation on opacity {
                    running: heroPulse.visible && !banner.calm
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
                }
            }

            // Hero content
            Column {
                id: heroCopy
                visible: heroMedia !== null
                anchors { left: parent.left; leftMargin: banner.gutter + 12; bottom: parent.bottom }
                width: Math.min(banner.heroColW, banner.width - banner.gutter * 2)
                spacing: 0

                // One orchestrated entrance when the hero data lands
                anchors.bottomMargin: heroMedia ? 44 : 24
                Behavior on anchors.bottomMargin {
                    NumberAnimation { duration: banner.calm ? 0 : 420; easing.type: Easing.OutCubic }
                }
                opacity: heroMedia ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation { duration: banner.calm ? 0 : 420; easing.type: Easing.OutCubic }
                }

                // Eyebrow: what this show is, in anime terms
                Row {
                    spacing: 8
                    visible: banner.media ? (banner.courFor(banner.media) !== "" || banner.formatFor(banner.media) !== "") : false
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            banner.tallyStamp
                            if (!banner.media) return ""
                            return "#1 in Anime Today"
                        }
                        color: "#b3b3b3"
                        font.family: Theme.displayFont
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.3
                    }
                }

                Item { width: 1; height: 10 }

                Text {
                    width: parent.width
                    text: heroMedia ? AniListApi.title(heroMedia) : ""
                    color: Theme.textPrimary
                    font.family: Theme.displayFont
                    font.pixelSize: banner.heroSize
                    font.weight: Font.Bold
                    font.letterSpacing: -0.6
                    lineHeightMode: Text.FixedHeight
                    lineHeight: Math.round(banner.heroSize * 1.08)
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
                        var d = banner.media
                        if (!d) return ""
                        var bits = []
                        if (d.season)
                            bits.push(d.season.charAt(0) + d.season.slice(1).toLowerCase())
                        if (d.genres) bits = bits.concat(d.genres.slice(0, 2))
                        if (d.episodes) bits.push(d.episodes + " Episodes")
                        else if (d.nextAiringEpisode) bits.push("Ongoing")
                        return bits.join("  •  ")
                    }
                    color: "#e6e6e6"
                    font.family: Theme.displayFont
                    font.pixelSize: 13
                    font.letterSpacing: 0.2
                }

                // Score + studio
                Row {
                    spacing: 14
                    visible: heroMedia !== null
                    Text {
                        visible: banner.media ? AniListApi.score(banner.media) !== "" : false
                        text: "\u2605 " + (heroMedia ? AniListApi.score(heroMedia) : "")
                        color: Theme.textPrimary
                        font.family: Theme.displayFont
                        font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 1.0
                    }
                    Text {
                        visible: heroMedia && AniListApi.studio(heroMedia) !== ""
                        text: heroMedia ? AniListApi.studio(heroMedia) : ""
                        color: "#b3b3b3"
                        font.family: Theme.bodyFont; font.pixelSize: 13
                    }
                }

                // ── Signature: the airing tally ──────────────────────
                Item { width: 1; height: 16; visible: tallyChip.visible }

                Rectangle {
                    id: tallyChip
                    visible: banner.media ? banner.tallyFor(banner.media) !== "" : false
                    height: 34; radius: 4
                    width: tallyRow.implicitWidth + 22
                    color: Theme.veilLight
                    border.color: Theme.borderStrong; border.width: 1

                    Row {
                        id: tallyRow
                        anchors.centerIn: parent
                        spacing: 9

                        Rectangle {
                            id: tallyDot
                            width: 7; height: 7; radius: 4
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on scale {
                                running: tallyChip.visible && !banner.calm
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.75; duration: 900; easing.type: Easing.OutCubic }
                                NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutCubic }
                            }
                            SequentialAnimation on opacity {
                                running: tallyChip.visible && !banner.calm
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 900 }
                                NumberAnimation { to: 1.0;  duration: 900 }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                banner.tallyStamp
                                return banner.media ? banner.tallyFor(banner.media) : ""
                            }
                            color: Theme.textPrimary
                            font.family: Theme.displayFont
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
                    font.family: Theme.bodyFont
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
                        id: heroPlay
                        function activate() {
                            if (heroMedia) playRequested(heroMedia.id, AniListApi.title(heroMedia))
                        }
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "Play"
                        Accessible.onPressAction: activate()

                        width: Math.max(150, watchTxt.implicitWidth + 40); height: 44
                        radius: 5
                        color: _wma.pressed ? "#d9d9d9" : _wma.containsMouse ? Theme.textPrimary : "#f5f5f5"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: watchTxt
                            anchors.centerIn: parent
                            text: "▶   Play"
                            color: "#0a0a0a"
                            font.family: Theme.displayFont
                            font.pixelSize: 14; font.weight: Font.DemiBold; font.letterSpacing: 0
                        }
                        Keys.onReturnPressed: activate()
                        Keys.onSpacePressed:  activate()
                        // Outside the pill: a ring drawn inside would vanish against the
                        // button's own white fill.
                        Rectangle {
                            anchors { fill: parent; margins: -3 }
                            radius: 8
                            color: "transparent"
                            border.color: Theme.textPrimary
                            border.width: 2
                            visible: heroPlay.activeFocus
                        }
                        MouseArea {
                            id: _wma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: heroPlay.activate()
                        }
                    }

                    Rectangle {
                        id: heroInfo
                        function activate() { if (heroMedia) seriesClicked(heroMedia.id) }
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: "More info"
                        Accessible.onPressAction: activate()

                        width: Math.max(120, infoTxt.implicitWidth + 32); height: 44
                        radius: 5
                        color: _ima.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                        border.color: Qt.rgba(1,1,1,0.16); border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: infoTxt
                            anchors.centerIn: parent
                            text: "More Info"
                            color: Theme.textPrimary
                            font.family: Theme.displayFont
                            font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.8
                        }
                        Keys.onReturnPressed: activate()
                        Keys.onSpacePressed:  activate()
                        Rectangle {
                            anchors { fill: parent; margins: -3 }
                            radius: 8
                            color: "transparent"
                            border.color: Theme.textPrimary
                            border.width: 2
                            visible: heroInfo.activeFocus
                        }
                        MouseArea {
                            id: _ima
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: heroInfo.activate()
                        }
                    }
                }
            }
        } // hero
