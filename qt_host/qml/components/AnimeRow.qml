import QtQuick
import QtQuick.Controls
import ".."
import "."

// AnimeRow — a section header plus a horizontally paging strip of posters.
//
// Extracted from HomePage, which used to declare it as an inline `component`
// and reach straight into the page for gutter/calm/meta. Those three now come
// in as inputs and the row's two intentions come out as signals, so the row no
// longer needs to know who is hosting it.
Column {
    id: rowRoot

    property string rowTitle: ""
    property var    rowModel: []
    property string epTextMode: "auto"   // "auto" | "ongoing"
    property bool   showSeeAll: false
    property int    cardWidth: 196
    // art (w*1.5) + 10 gap + 38 two-line title slot + 3 + 18 meta line
    property int    listViewHeight: cardWidth * 3 / 2 + 78

    // Host inputs.
    property int  gutter: Theme.s8
    property bool calm: false
    /// function(modelData) -> string, for the card's meta line.
    property var  metaFor: function(modelData) { return "" }

    signal seeAllClicked()
    signal seriesPicked(int anilistId)
    signal watchPicked(int anilistId, string title)

    // Driven by the row's own HoverHandler; gates the arrow reveal.
    property bool hovered: false

    readonly property var auth: typeof authManager !== "undefined" ? authManager : null

    width: parent ? parent.width : 0
    spacing: 0
    visible: rowModel.length > 0

    // Header: title left, controls right, one baseline
    Item {
        id: rowHeader
        width: parent.width
        height: 44

        // Scoped to the header rather than the whole row: a HoverHandler over
        // the ListView would compete with each card's own hover and flatten the
        // card lift effect.
        //
        // `onHoveredChanged`, not `onChanged`: writing the latter as
        // `onChanged: function (event) { ... }` aborts creation of the entire
        // component under Qt 6.5.3 with no fatal-looking error.
        HoverHandler {
            id: rowHeaderHover
            onHoveredChanged: rowRoot.hovered = rowHeaderHover.hovered
        }

        Text {
            id: rowTitleTxt
            anchors { left: parent.left; leftMargin: rowRoot.gutter
                      verticalCenter: parent.verticalCenter }
            text: rowRoot.rowTitle
            color: Theme.textPrimary
            font.family: Theme.displayFont
            font.pixelSize: 22
            font.weight: Font.Bold
            font.letterSpacing: 0.8
        }

        Row {
            anchors { right: parent.right; rightMargin: rowRoot.gutter
                      verticalCenter: parent.verticalCenter }
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: rowRoot.showSeeAll
                text: "View all"
                color: seeAllMa.containsMouse ? Theme.textPrimary : Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: 13
                font.weight: Font.Normal
                Behavior on color { ColorAnimation { duration: 140 } }
                MouseArea {
                    id: seeAllMa
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rowRoot.seeAllClicked()
                }
            }

            Row {
                id: arrowGroup
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                // Section 14: the arrows are an affordance for someone who has
                // looked at the row, not permanent chrome. Only the arrows fade
                // -- "View all" is a destination and stays put. Row positions
                // invisible children, so the slot is reserved and nothing
                // reflows when they appear.
                opacity: rowRoot.hovered ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity {
                    NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic }
                }

                Repeater {
                    model: ["left", "right"]
                    delegate: Rectangle {
                        id: arrow
                        required property string modelData
                        readonly property bool canGo: modelData === "left"
                                                      ? rowListView.contentX > 1
                                                      : rowListView.contentX < rowListView.contentWidth - rowListView.width - 1
                        width: 30; height: 30; radius: 5
                        color: arrowMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.borderSubtle
                        border.color: Theme.borderSubtle; border.width: 1
                        opacity: canGo ? 1.0 : 0.28
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: arrow.modelData === "left" ? "\uE76B" : "\uE76C"
                            color: Theme.textSecondary; font.pixelSize: 11
                            font.family: Theme.iconFont
                        }
                        MouseArea {
                            id: arrowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var step = Math.max(240, rowListView.width * 0.7)
                                if (arrow.modelData === "left")
                                    rowListView.contentX = Math.max(0, rowListView.contentX - step)
                                else
                                    rowListView.contentX = Math.min(
                                        Math.max(0, rowListView.contentWidth - rowListView.width),
                                        rowListView.contentX + step)
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: rowRoot.listViewHeight

        ListView {
            id: rowListView
            // Section 14: scrolling must be smooth. Without this the arrow
            // buttons teleport a whole page.
            Behavior on contentX {
                enabled: !rowRoot.calm
                NumberAnimation { duration: Theme.dSlow; easing.type: Theme.easeOutCubic }
            }
            anchors { left: parent.left; right: parent.right
                      leftMargin: rowRoot.gutter; rightMargin: rowRoot.gutter }
            height: parent.height
            model: rowRoot.rowModel
            orientation: ListView.Horizontal
            spacing: 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 3500
            maximumFlickVelocity: 3000
            keyNavigationEnabled: true

            delegate: AnimePosterCard {
                required property var modelData
                width: rowRoot.cardWidth
                title:     AniListApi.title(modelData)
                rating:    ""
                epText:    ""
                subtext:   rowRoot.metaFor(modelData)
                posterUrl: AniListApi.cover(modelData)

                onClicked: rowRoot.seriesPicked(modelData.id)
                onWatchClicked: rowRoot.watchPicked(modelData.id, title)

                onAddClicked: {
                    if (!rowRoot.auth) return
                    rowRoot.auth.addToLibrary({
                        "anilist_id": modelData.id || modelData.anilist_id,
                        "title": title,
                        "cover_image_url": posterUrl,
                        "rating": rating
                    })
                }
            }
        }

        // Edge fades so cards dissolve instead of being sliced
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 44
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.bg }
                GradientStop { position: 1.0; color: "transparent" }
            }
            visible: rowListView.contentX > 1
        }
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 64
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.bg }
            }
            visible: rowListView.contentWidth > rowListView.width
        }
    }
}
