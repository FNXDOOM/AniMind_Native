import QtQuick
import ".."

// Continue Watching card (section 15): landscape artwork, title, where you
// stopped, and how far through it you got.
//
// The brief also asks for remaining time. The watch_history row stores a
// percentage and an episode label but no runtime, so showing minutes here
// would be invented. Percentage and "when" are real and stay.
Item {
    id: card

    required property var entry     // one watch_history row

    signal clicked()

    readonly property int artHeight: Math.round(width * 9 / 16)

    implicitWidth: 240
    implicitHeight: artHeight + Theme.s3 + metaCol.implicitHeight

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: card.clicked() }
    activeFocusOnTab: true
    Keys.onReturnPressed: card.clicked()
    Keys.onSpacePressed: card.clicked()

    scale: hover.hovered ? 1.03 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic } }

    Rectangle {
        id: art
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: card.artHeight
        radius: Theme.rLg
        color: Theme.surfaceRaised
        border.color: hover.hovered ? Theme.borderStrong : Theme.borderSubtle
        border.width: 1
        clip: true

        Image {
            id: art_img
            anchors.fill: parent
            source: card.entry ? (card.entry.thumbnail_url || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
        }

        // Resume affordance, so the card reads as "keep going" not "watch again"
        Rectangle {
            anchors.centerIn: parent
            width: 40; height: 40; radius: 20
            color: Qt.rgba(0.027, 0.035, 0.047, 0.72)
            border.color: Theme.borderStrong; border.width: 1
            opacity: hover.hovered ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Theme.dFast } }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1
                text: "\uE102"
                color: Theme.textPrimary
                font.family: Theme.iconFont
                font.pixelSize: 14
            }
        }

        WatchBar {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 3
            trackHeight: 3
            value: card.entry ? (card.entry.progress_pct || 0) / 100 : 0
        }
    }

    Column {
        id: metaCol
        anchors { top: art.bottom; topMargin: Theme.s3; left: parent.left; right: parent.right }
        spacing: Theme.s1

        Text {
            width: parent.width
            text: card.entry ? (card.entry.show_title || "") : ""
            color: hover.hovered ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsCardTitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }

        Row {
            width: parent.width
            spacing: Theme.s2

            Text {
                width: parent.width - pct.implicitWidth - Theme.s2
                text: card.entry ? (card.entry.episode_label || "") : ""
                color: Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsMeta
                elide: Text.ElideRight
            }
            Text {
                id: pct
                anchors.verticalCenter: parent.verticalCenter
                text: (card.entry ? (card.entry.progress_pct || 0) : 0) + "%"
                color: Theme.textMuted
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsMeta
            }
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: (card.entry ? (card.entry.show_title || "") : "")
                     + ", " + (card.entry ? (card.entry.progress_pct || 0) : 0) + "% watched"
    Accessible.onPressAction: card.clicked()
}
