import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"

// AnimePosterCard — 2:3 artwork with a two-line title slot.
//
// Chip hierarchy: only "NEW EP" is allowed to be a solid pill. Scores and
// episode counts stay glass, so the one loud chip always means something fresh.
//
// No drop shadow: measured against the #07090C ground it is imperceptible, so a
// blurred layer per card would be pure cost. Depth comes from the scale, the
// edge light and the scrim instead.
Item {
    id: card

    property string title:      "Untitled"
    property string rating:     ""
    property string subtext:    ""
    property string epText:     ""
    property string posterUrl:  ""
    property real   progress:   -1.0     // -1 hides the bar; 0..1 fills it

    // Watchlist mode
    property string currentStatus: ""
    property bool inWatchlistMode: currentStatus !== ""
    property var statusOptions: ["Watching", "Completed", "Plan to Watch", "Dropped"]
    property bool isDropdownOpen: false

    signal clicked()
    signal watchClicked()
    signal addClicked()
    signal statusChanged(string newStatus)
    signal removeClicked()

    implicitHeight: posterArea.height + Theme.s3 + metaSlot.height

    // Either the pointer or the keyboard counts. Focus may settle on this Item
    // rather than the inner MouseArea, and a focused card that looks unfocused
    // is worse for keyboard users than no focus ring at all.
    readonly property bool engaged: cardMa.containsMouse || card.activeFocus || cardMa.activeFocus
    readonly property bool focused: card.activeFocus || cardMa.activeFocus

    activeFocusOnTab: true
    Keys.onReturnPressed: card.clicked()
    Keys.onSpacePressed: card.clicked()

    scale: cardMa.pressed ? 0.98 : (card.engaged ? 1.04 : 1.0)
    Behavior on scale {
        NumberAnimation { duration: Theme.dFast; easing.type: Theme.easeOutCubic }
    }

    // ── Artwork ──────────────────────────────────────────────────────────
    Item {
        id: posterArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: width * 3 / 2

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (card.isDropdownOpen) card.isDropdownOpen = false
                else card.clicked()
            }
            onExited: card.isDropdownOpen = false
            Keys.onEnterPressed: card.clicked()
            Keys.onReturnPressed: card.clicked()
            Keys.onSpacePressed: card.clicked()
        }

        Rectangle {
            id: posterClip
            anchors.fill: parent
            radius: Theme.rLg
            color: Theme.surfaceRaised
            clip: true

            Image {
                anchors.fill: parent
                source: card.posterUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 480

                Rectangle {
                    anchors.fill: parent
                    visible: parent.status !== Image.Ready
                    color: Theme.surfaceRaised
                }
            }

            // Bottom scrim, only present on hover, so actions stay legible
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: parent.height * 0.52
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0.027, 0.035, 0.047, 0.94) }
                }
                opacity: card.engaged ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.dFast } }
            }

            // Hover actions
            Row {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: Theme.s3 }
                spacing: Theme.s2
                height: 30
                visible: card.engaged && !card.inWatchlistMode

                Rectangle {
                    width: parent.width - 36
                    height: 30
                    radius: Theme.rSm
                    color: watchMa.pressed ? Theme.textSecondary
                         : (watchMa.containsMouse ? "#ffffff" : Theme.textPrimary)
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    Text {
                        anchors.centerIn: parent
                        text: "Play"
                        color: Theme.bg
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsCardTitle
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: watchMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.watchClicked()
                    }
                }

                Rectangle {
                    width: 30; height: 30
                    radius: Theme.rSm
                    color: addMa.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10)
                    border.color: Theme.borderStrong; border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.dFast } }
                    Text {
                        anchors.centerIn: parent
                        text: "\uE710"
                        color: Theme.textPrimary
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.addClicked()
                    }
                }
            }

            // ── Watch progress: the accent, used where it means something ──
            WatchBar {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.s2 }
                visible: card.progress >= 0
                value: Math.max(0, Math.min(1, card.progress))
                trackHeight: 3
            }
        }

        // Edge light on hover / focus
        Rectangle {
            anchors.fill: posterClip
            anchors.margins: -1
            radius: Theme.rLg + 1
            color: "transparent"
            border.color: card.focused ? Theme.accent
                        : cardMa.containsMouse ? Theme.borderStrong
                        : Theme.borderSubtle
            border.width: card.focused ? 2 : 1
            Behavior on border.color { ColorAnimation { duration: Theme.dFast } }
        }

        // ── Score: quiet glass ───────────────────────────────────────────
        Rectangle {
            visible: card.rating !== "" && !card.inWatchlistMode
            anchors { top: parent.top; left: parent.left; margins: Theme.s2 }
            height: 21; radius: Theme.rSm
            width: ratingRow.implicitWidth + Theme.s3
            color: Theme.veilLight
            border.color: Theme.borderDefault; border.width: 1
            Row {
                id: ratingRow
                anchors.centerIn: parent
                spacing: Theme.s1
                Text {
                    text: "\u2605"; color: Theme.textPrimary; font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: card.rating
                    color: Theme.textPrimary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsMeta; font.weight: Font.Bold; font.letterSpacing: Theme.trackingWide
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Trash (watchlist mode) ───────────────────────────────────────
        Rectangle {
            id: trashBtn
            visible: card.inWatchlistMode && (card.engaged || trashMa.containsMouse || card.isDropdownOpen)
            anchors { top: parent.top; left: parent.left; margins: Theme.s2 }
            width: 26; height: 26; radius: Theme.rSm
            color: trashMa.containsMouse ? Theme.accentPressed : Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
            Text {
                anchors.centerIn: parent
                text: "\uE74D"
                color: Theme.textPrimary
                font.family: Theme.iconFont
                font.pixelSize: 11
            }
            MouseArea {
                id: trashMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.removeClicked()
            }
        }

        // ── Episode chip: glass, or solid only when fresh ────────────────
        Rectangle {
            id: epChip
            visible: card.epText !== ""
            anchors { top: parent.top; right: parent.right; margins: Theme.s2 }
            height: 21; radius: Theme.rSm
            width: epTxt.implicitWidth + Theme.s3
            readonly property bool isFresh: card.epText === "NEW EP"
            // Still the quiet chip, but opaque: veilLight over bright artwork
            // put the episode count at roughly the same luminance as the
            // poster behind it, which made it unreadable on those cards.
            color: isFresh ? Theme.accent : Theme.card
            border.color: isFresh ? Theme.accent : Theme.borderDefault
            border.width: 1
            Text {
                id: epTxt
                anchors.centerIn: parent
                text: card.epText
                color: isFresh ? Theme.textPrimary : Theme.textSecondary
                font.family: Theme.bodyFont
                font.pixelSize: Theme.tsSmall; font.weight: Font.Bold; font.letterSpacing: Theme.trackingWide
            }
        }

        // ── Watchlist status control ─────────────────────────────────────
        Item {
            id: dropdownContainer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: Theme.s2 }
            height: 30
            visible: card.inWatchlistMode && (card.engaged || card.isDropdownOpen)

            Rectangle {
                anchors.fill: parent
                radius: Theme.rSm
                color: Theme.veilLight
                border.color: card.isDropdownOpen ? Theme.accent : Theme.borderDefault
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: Theme.dFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s3; anchors.rightMargin: Theme.s2
                    spacing: Theme.s1
                    Text {
                        Layout.fillWidth: true
                        text: card.currentStatus
                        color: Theme.textPrimary
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.tsMeta; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        text: card.isDropdownOpen ? "\uE70E" : "\uE70D"
                        color: Theme.textSecondary
                        font.pixelSize: 9
                        font.family: Theme.iconFont
                    }
                }

                MouseArea {
                    id: dropdownMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.isDropdownOpen = !card.isDropdownOpen
                }
            }
        }

        Rectangle {
            id: dropdownMenu
            visible: card.isDropdownOpen
            anchors {
                bottom: dropdownContainer.top; bottomMargin: Theme.s1
                left: parent.left; right: parent.right; leftMargin: Theme.s2; rightMargin: Theme.s2
            }
            height: menuCol.implicitHeight + Theme.s2
            radius: Theme.rSm
            color: Theme.surfaceRaised
            border.color: Theme.borderDefault; border.width: 1
            clip: true

            Column {
                id: menuCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.s1 }
                spacing: 0

                Repeater {
                    model: card.statusOptions
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: menuCol.width
                        height: 28
                        radius: Theme.rSm
                        color: statusMa.containsMouse ? Theme.hoverBg
                             : (card.currentStatus === modelData ? Theme.borderSubtle : "transparent")

                        Text {
                            anchors { left: parent.left; leftMargin: Theme.s3; verticalCenter: parent.verticalCenter }
                            text: modelData
                            color: card.currentStatus === modelData ? Theme.textPrimary : Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.tsMeta
                        }

                        MouseArea {
                            id: statusMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                card.isDropdownOpen = false
                                card.statusChanged(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Title slot: fixed two lines so every card in a row aligns ────────
    Item {
        id: metaSlot
        anchors { top: posterArea.bottom; topMargin: Theme.s3; left: parent.left; right: parent.right }
        height: titleTxt.height + (card.subtext !== "" ? metaTxt.height + Theme.s1 : 0)

        Text {
            id: titleTxt
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2 * lineHeight
            text: card.title
            color: card.engaged ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsCardTitle + 1
            font.weight: Font.DemiBold
            lineHeightMode: Text.FixedHeight
            lineHeight: Theme.tsCardTitle + 5
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            Behavior on color { ColorAnimation { duration: Theme.dFast } }
        }

        Text {
            id: metaTxt
            anchors { top: titleTxt.bottom; topMargin: Theme.s1; left: parent.left; right: parent.right }
            visible: card.subtext !== ""
            text: card.subtext
            color: Theme.textMuted
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsMeta
            elide: Text.ElideRight
        }
    }

    Accessible.role: Accessible.Graphic
    Accessible.name: card.title
}
