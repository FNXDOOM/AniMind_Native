import QtQuick
import QtQuick.Controls
import ".."

// Episode sidebar for the watch page. Slides in from the right edge over the
// player and dismisses the same way (section 22).
//
// It is a presentation surface only: playback still goes through the shell's
// existing playStreamNow path, and nothing here touches the mpv item.
Item {
    id: sidebar

    property bool open: false
    property var  episodes: []
    property string seriesTitle: ""
    property int    currentIndex: -1
    property bool   calm: false   // shell passes its reduced-motion flag
    property int panelWidth: Math.min(340, parent ? parent.width : 340)

    signal episodePicked(string url, string title, string episodeLabel, string thumbnailUrl)
    signal dismissed()

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: open || panel.x < width
    // The player hides its chrome after inactivity; the sidebar is an explicit
    // request, so it keeps the chrome alive while it is up.
    z: 30

    MouseArea {
        anchors.fill: parent
        enabled: sidebar.open
        onClicked: sidebar.dismissed()
    }

    Rectangle {
        id: panel
        width: sidebar.panelWidth
        height: parent.height
        x: sidebar.open ? parent.width - sidebar.panelWidth : parent.width
        y: 0

        color: Qt.rgba(0.043, 0.055, 0.078, 0.97)
        border.color: Theme.borderDefault
        border.width: 1

        Behavior on x {
            enabled: !sidebar.calm
            NumberAnimation { duration: Theme.dSlow; easing.type: Theme.easeOutQuint }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.dBase } }
        opacity: sidebar.open ? 1.0 : 0.0

        // ── Header ──────────────────────────────────────────────────────
        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.margins: Theme.s4
            height: 40

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "Episode List"
                    color: Theme.textPrimary
                    font.family: Theme.displayFont
                    font.pixelSize: Theme.tsBody + 1
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: text.length > 0
                    text: sidebar.seriesTitle
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsSmall
                }
            }

            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 30; height: 30; radius: Theme.rSm
                color: closeHover.hovered ? Theme.card : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.dFast } }

                Text {
                    anchors.centerIn: parent
                    text: "\uE711"
                    color: Theme.textSecondary
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                }
                HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sidebar.dismissed() }

                Accessible.role: Accessible.Button
                Accessible.name: "Close episode list"
                Accessible.onPressAction: sidebar.dismissed()
            }
        }

        Rectangle {
            anchors { top: head.bottom; left: parent.left; right: parent.right }
            height: 1
            color: Theme.borderSubtle
        }

        // ── Episodes ─────────────────────────────────────────────────────
        ListView {
            id: list
            anchors { top: head.bottom; topMargin: Theme.s3; left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: Theme.s3; anchors.rightMargin: Theme.s3
            model: sidebar.episodes
            clip: true
            spacing: Theme.s2
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Text {
                anchors.centerIn: parent
                visible: sidebar.episodes.length === 0
                text: "No episodes listed for this title."
                color: Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsBody
            }

            delegate: Item {
                id: ep

                required property var modelData
                required property int index

                width: list.width
                height: 62

                // Titles arrive as "Episode 12 - The Price of Power"; the row
                // already shows the number, so only the name is useful here.
                readonly property string name: {
                    var raw = ep.modelData.title || ""
                    var m = raw.match(/^\s*(?:ep(?:isode)?\s*\d+\s*[-:.]\s*)/i)
                    return m ? raw.substring(m[0].length) : raw
                }
                readonly property bool isCurrent: sidebar.currentIndex === ep.index
                readonly property bool playable: !!(ep.modelData && ep.modelData.url)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rMd
                    color: ep.isCurrent ? Theme.surfaceRaised
                         : (epHover.hovered ? Theme.card : "transparent")
                    border.color: ep.isCurrent ? Theme.accent : "transparent"
                    border.width: ep.isCurrent ? 1 : 0
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                }

                Row {
                    anchors { fill: parent; leftMargin: Theme.s2; rightMargin: Theme.s2 }
                    spacing: Theme.s3

                    Rectangle {
                        id: thumbBox
                        width: 80; height: 46
                        radius: Theme.rSm
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.surfaceRaised
                        clip: true

                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: ep.modelData.thumbnail || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: status === Image.Ready
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 22; height: 22; radius: 11
                            color: Theme.veilLight
                            visible: thumb.status !== Image.Ready || epHover.hovered
                            Text {
                                anchors.centerIn: parent
                                text: "\uE102"
                                color: Theme.textPrimary
                                font.family: Theme.iconFont
                                font.pixelSize: 9
                            }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80 - Theme.s3 * 2
                        spacing: 3

                        Text {
                            width: parent.width
                            text: (ep.index + 1) + ". " + (ep.name || "Untitled")
                            color: ep.isCurrent ? Theme.textPrimary : Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsMeta
                            font.weight: ep.isCurrent ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: ep.playable ? "" : "No source linked"
                            color: Theme.textMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsSmall
                        }
                    }
                }

                HoverHandler { id: epHover; cursorShape: ep.playable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler {
                    enabled: ep.playable
                    onTapped: sidebar.episodePicked(ep.modelData.url,
                                                    sidebar.seriesTitle,
                                                    "Episode " + (ep.index + 1),
                                                    ep.modelData.thumbnail || "")
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Episode " + (ep.index + 1) + ": " + ep.name
                Accessible.onPressAction: {
                    if (ep.playable)
                        sidebar.episodePicked(ep.modelData.url, sidebar.seriesTitle,
                                              "Episode " + (ep.index + 1), ep.modelData.thumbnail || "")
                }
            }
        }
    }
}
