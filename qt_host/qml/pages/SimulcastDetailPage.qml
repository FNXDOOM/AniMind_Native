import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: page
    color: "#000000"
    readonly property real s: Math.max(0.82, Math.min(1.0, width / 1700))

    property string showId: ""
    property string showTitle: ""
    property var showDetail: ({})
    property var episodes: []
    property bool loading: false
    property string errorMsg: ""

    signal backRequested()
    signal playEpisodeRequested(string streamUrl, string title, string episodeLabel)

    function loadShow() {
        if (!showId || showId.length === 0) return
        loading = true
        errorMsg = ""
        showDetail = {}
        episodes = []
        var payload = authManager ? authManager.getShowDetails(showId) : ({})
        if (!payload || Object.keys(payload).length === 0) {
            loading = false
            errorMsg = "Failed to load show details from server."
            return
        }
        showDetail = payload
        episodes = payload.episodes || []
        loading = false
    }

    function playEpisode(modelData, idx) {
        var epId = String(modelData.id || "")
        if (!epId || !authManager) return
        var ticket = authManager.getStreamTicket(epId, -1, "native")
        if (!ticket || !ticket.url) return
        var epNum = String(modelData.episode_number !== undefined ? modelData.episode_number : (idx + 1))
        playEpisodeRequested(ticket.url, showDetail.title || showTitle || "Show", "Episode " + epNum)
    }

    onShowIdChanged: loadShow()
    Component.onCompleted: loadShow()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: rootCol.implicitHeight + 20
        clip: true

        Column {
            id: rootCol
            width: parent.width
            spacing: 14 * page.s
            topPadding: 10 * page.s
            leftPadding: 12 * page.s
            rightPadding: 12 * page.s
            bottomPadding: 18 * page.s

            Rectangle {
                id: hero
                width: parent.width - 20
                height: 500 * page.s
                radius: 6
                color: "#0b0b0b"
                clip: true

                Image {
                    anchors.fill: parent
                    source: showDetail.cover_image_url || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: 0.48
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#f2000000" }
                        GradientStop { position: 0.42; color: "#de000000" }
                        GradientStop { position: 0.75; color: "#83000000" }
                        GradientStop { position: 1.0; color: "#26000000" }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "#22000000" }
                        GradientStop { position: 0.7; color: "#7a000000" }
                        GradientStop { position: 1.0; color: "#dd000000" }
                    }
                }

                Column {
                    width: Math.min(parent.width * 0.52, 940)
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 34 * page.s
                    spacing: 12 * page.s

                    Button {
                        text: "< Back to Simulcasts"
                        onClicked: backRequested()
                    }

                    Text {
                        text: (showDetail.title || showTitle || "Show").toUpperCase()
                        color: "white"
                        font.family: "Montserrat"
                        font.pixelSize: 48 * page.s
                        font.weight: Font.Black
                        width: parent.width
                        wrapMode: Text.Wrap
                    }

                    Row {
                        spacing: 10
                        Rectangle {
                            color: "#3a3a42"
                            radius: 4
                            height: 28 * page.s
                            width: badgeText.implicitWidth + 16
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: "UA 13+"
                                color: "#d7d7dc"
                                font.pixelSize: 13 * page.s
                                font.bold: true
                            }
                        }
                        Text {
                            text: (showDetail.episode_count !== undefined ? String(showDetail.episode_count) : String(episodes.length)) + " episodes"
                            color: "#dedede"
                            font.pixelSize: 19 * page.s
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: showDetail.synopsis || ""
                        color: "#dddddd"
                        font.pixelSize: 15 * page.s
                        lineHeight: 1.24
                        width: parent.width
                        wrapMode: Text.Wrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 10

                        Rectangle {
                            width: 312 * page.s
                            height: 50 * page.s
                            color: "#ff5a00"
                            radius: 2
                            Text {
                                anchors.centerIn: parent
                                text: episodes.length > 0 ? "CONTINUE WATCHING E1" : "PLAY"
                                color: "black"
                                font.family: "Montserrat"
                                font.pixelSize: 20 * page.s
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: episodes.length > 0
                                onClicked: if (episodes.length > 0) page.playEpisode(episodes[0], 0)
                            }
                        }

                        Rectangle {
                            width: 50 * page.s
                            height: 50 * page.s
                            color: "transparent"
                            border.color: "#ff5a00"
                            border.width: 2
                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                color: "#ff5a00"
                                font.pixelSize: 27 * page.s
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - 20
                height: 1
                color: "#252525"
            }

            Text {
                visible: loading
                text: "Loading episodes..."
                color: "#b8b8b8"
                font.pixelSize: 14 * page.s
            }

            Text {
                visible: errorMsg.length > 0
                text: errorMsg
                color: "#ff8a8a"
                font.pixelSize: 14 * page.s
            }

            Grid {
                id: epGrid
                width: parent.width - 20
                columns: Math.max(1, Math.floor((width + 18) / 370))
                columnSpacing: 16 * page.s
                rowSpacing: 22 * page.s

                Repeater {
                    model: episodes
                    delegate: Item {
                        width: Math.floor((epGrid.width - epGrid.columnSpacing * (epGrid.columns - 1)) / epGrid.columns)
                        height: thumb.height + titleText.implicitHeight + subText.implicitHeight + (16 * page.s)

                        Rectangle {
                            id: thumb
                            width: parent.width
                            height: Math.round(width * 9 / 16)
                            radius: 2
                            color: "#141414"
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: modelData.thumbnail || showDetail.cover_image_url || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: epMa.containsMouse ? "#28000000" : "#3f000000"
                            }

                            Rectangle {
                                width: 92
                                height: 92
                                radius: 46
                                anchors.centerIn: parent
                                color: "#7a303030"
                                border.color: "#7f7f7f"
                                border.width: 1
                                visible: epMa.containsMouse
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u25b6"
                                    color: "white"
                                    font.pixelSize: 42 * page.s
                                }
                            }

                            Rectangle {
                                width: durText.implicitWidth + 12
                                height: 32
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                color: "#b937373a"
                                Text {
                                    id: durText
                                    anchors.centerIn: parent
                                    text: modelData.duration && String(modelData.duration).length > 0 ? String(modelData.duration) : "23m"
                                    color: "white"
                                    font.pixelSize: 18 * page.s
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: epMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.playEpisode(modelData, index)
                            }
                        }

                        Text {
                            id: titleText
                            anchors.top: thumb.bottom
                            anchors.topMargin: 8 * page.s
                            width: parent.width
                            text: "E" + String(modelData.episode_number !== undefined ? modelData.episode_number : (index + 1))
                                  + " \u2013 "
                                  + (modelData.title || ("Episode " + String(index + 1)))
                            color: "white"
                            font.family: "Montserrat"
                            font.pixelSize: 16 * page.s
                            font.bold: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            id: subText
                            anchors.top: titleText.bottom
                            anchors.topMargin: 4 * page.s
                            width: parent.width
                            text: "Subtitled"
                            color: "#b5b5b5"
                            font.pixelSize: 13 * page.s
                        }
                    }
                }
            }
        }
    }
}
