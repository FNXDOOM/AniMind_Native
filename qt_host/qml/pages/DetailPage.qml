import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

Rectangle {
    color: "#050716"

    property int seriesId: 0
    property var detail: null
    property bool loading: false
    property string errorMsg: ""

    signal backRequested()
    signal playRequested(int id, string title)
    signal addToListRequested(int id)

    function loadDetail() {
        if (seriesId <= 0)
            return
        loading = true
        detail = null
        errorMsg = ""
        AniListApi.animeDetail(seriesId, function(media, err) {
            loading = false
            if (err) {
                errorMsg = "Failed to load detail: " + err
                return
            }
            detail = media
        })
    }

    onSeriesIdChanged: loadDetail()
    Component.onCompleted: loadDetail()

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#210a3c" }
            GradientStop { position: 0.5; color: "#0f0d33" }
            GradientStop { position: 1.0; color: "#081c3d" }
        }
        opacity: 0.45
    }

    Flickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: pageCol.implicitHeight + 24

        Column {
            id: pageCol
            width: pageFlick.width
            spacing: 16
            topPadding: 18
            leftPadding: 20
            rightPadding: 20
            bottomPadding: 20

            Button {
                text: "< Back to Browse"
                onClicked: backRequested()
            }

            Rectangle {
                width: parent.width - 40
                height: Math.max(420, posterCol.height + 52)
                radius: 20
                color: "#1c213a"
                clip: true

                Image {
                    anchors.fill: parent
                    source: detail ? (detail.bannerImage || AniListApi.cover(detail)) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: 0.25
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(0.07, 0.05, 0.19, 0.92) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.10, 0.22, 0.75) }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 26
                    spacing: 24

                    Rectangle {
                        id: posterCol
                        width: 260
                        height: 350
                        radius: 16
                        color: "#28324f"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: detail ? AniListApi.cover(detail) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    Item {
                        id: infoPane
                        width: parent.width - 290
                        height: parent.height

                        Column {
                            id: infoTop
                            width: parent.width
                            spacing: 10

                        Text {
                            text: detail ? AniListApi.title(detail) : (loading ? "Loading..." : "")
                            color: "white"
                            font.family: "Montserrat"
                            font.pixelSize: 46
                            font.bold: true
                            width: parent.width
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            text: detail && detail.title && detail.title.native ? detail.title.native : ""
                            color: "#b8bfd3"
                            font.pixelSize: 16
                        }

                        Row {
                            spacing: 14

                            Text {
                                text: detail ? ("\u2605 " + AniListApi.score(detail)) : ""
                                color: "#ffd14a"
                                font.pixelSize: 22
                                font.bold: true
                            }
                            Text {
                                text: detail && detail.seasonYear ? detail.seasonYear : ""
                                color: "#c8cde0"
                                font.pixelSize: 22
                            }
                            Text {
                                text: detail && detail.episodes ? (detail.episodes + " Episodes") : ""
                                color: "#c8cde0"
                                font.pixelSize: 22
                            }
                            Text {
                                text: detail ? AniListApi.statusLabel(detail).toUpperCase() : ""
                                color: "#c8cde0"
                                font.pixelSize: 22
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: detail && detail.genres ? detail.genres.slice(0, 4) : []
                                Rectangle {
                                    radius: 8
                                    color: "#2d3252"
                                    border.color: "#4e5578"
                                    border.width: 1
                                    height: 34
                                    width: genreText.implicitWidth + 18
                                    Text {
                                        id: genreText
                                        anchors.centerIn: parent
                                        text: modelData.toUpperCase()
                                        color: "#e3e7f6"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: detail ? AniListApi.cleanDesc(detail) : ""
                            color: "#d1d5e3"
                            font.pixelSize: 17
                            lineHeight: 1.45
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        }

                    }
                }
            }

            Row {
                width: parent.width - 40
                spacing: 12
                ActionButton {
                    label: "Watch Now"
                    fillColor: "#ff6b00"
                    textColor: "white"
                    onClicked: {
                        if (!detail) return
                        if (detail.trailer && detail.trailer.site && detail.trailer.id
                                && detail.trailer.site.toLowerCase() === "youtube") {
                            Qt.openUrlExternally("https://www.youtube.com/watch?v=" + detail.trailer.id)
                        } else {
                            Qt.openUrlExternally("https://anilist.co/anime/" + detail.id)
                        }
                    }
                }
                ActionButton {
                    label: (detail && detail.trailer && detail.trailer.site
                            && detail.trailer.id
                            && detail.trailer.site.toLowerCase() === "youtube")
                           ? "Watch Trailer"
                           : "Open AniList"
                    fillColor: "#2a3153"
                    textColor: "#f0f3ff"
                    onClicked: {
                        if (!detail) return
                        if (detail.trailer && detail.trailer.site && detail.trailer.id
                                && detail.trailer.site.toLowerCase() === "youtube") {
                            Qt.openUrlExternally("https://www.youtube.com/watch?v=" + detail.trailer.id)
                        } else {
                            Qt.openUrlExternally("https://anilist.co/anime/" + detail.id)
                        }
                    }
                }
                ActionButton {
                    label: "Add to List"
                    fillColor: "#2a3153"
                    textColor: "#f0f3ff"
                    onClicked: if (detail) addToListRequested(detail.id)
                }
            }

            Row {
                width: parent.width - 40
                spacing: 20

                Column {
                    width: Math.floor((parent.width - 20) * 0.68)
                    spacing: 10

                    Text {
                        text: "Main Characters"
                        color: "white"
                        font.family: "Montserrat"
                        font.pixelSize: 34
                        font.bold: true
                    }

                    Repeater {
                        model: detail && detail.characters && detail.characters.nodes ? detail.characters.nodes : []
                        Rectangle {
                            width: parent.width
                            height: 84
                            radius: 12
                            color: "#121a33"
                            border.color: "#233056"
                            border.width: 1

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    width: 62
                                    height: 62
                                    radius: 8
                                    clip: true
                                    color: "#29355a"
                                    Image {
                                        anchors.fill: parent
                                        source: modelData && modelData.image ? modelData.image.medium : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 74
                                    Text {
                                        text: modelData && modelData.name ? modelData.name.full : ""
                                        color: "white"
                                        font.pixelSize: 18
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    Text {
                                        text: "MAIN"
                                        color: "#c9d0e6"
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    width: Math.floor((parent.width - 20) * 0.32)
                    spacing: 10

                    Text {
                        text: "Recommendations"
                        color: "white"
                        font.family: "Montserrat"
                        font.pixelSize: 34
                        font.bold: true
                    }

                    Repeater {
                        model: detail && detail.recommendations && detail.recommendations.nodes ? detail.recommendations.nodes : []
                        delegate: Item {
                            visible: modelData && modelData.mediaRecommendation && modelData.mediaRecommendation.type === "ANIME"
                            width: parent.width
                            height: visible ? 42 : 0
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u25cb  " + (modelData.mediaRecommendation
                                                     ? (modelData.mediaRecommendation.title.english
                                                        || modelData.mediaRecommendation.title.romaji
                                                        || modelData.mediaRecommendation.title.native)
                                                     : "")
                                color: "#edf0f8"
                                font.pixelSize: 16
                                width: parent.width
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                visible: errorMsg !== ""
                text: errorMsg
                color: "#ff7f7f"
                font.pixelSize: 13
            }
        }
    }

    component ActionButton: Rectangle {
        id: btn
        property string label: ""
        property color fillColor: "#2a3153"
        property color textColor: "white"
        signal clicked()

        radius: 10
        height: 46
        width: Math.max(150, textItem.implicitWidth + 28)
        color: ma.pressed ? Qt.darker(btn.fillColor, 1.15) : (ma.containsMouse ? Qt.lighter(btn.fillColor, 1.08) : btn.fillColor)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1

        Text {
            id: textItem
            anchors.centerIn: parent
            text: btn.label
            color: btn.textColor
            font.pixelSize: 18
            font.bold: true
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
