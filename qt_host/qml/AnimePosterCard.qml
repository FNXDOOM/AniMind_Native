import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// AnimePosterCard — 2:3 artwork with a DIN title slot.
//
// Chip hierarchy: only "NEW EP" is allowed to be solid brand orange. Scores and
// episode counts stay glass, so the one loud chip always means something fresh.
Item {
    id: card

    property string title:      "Untitled"
    property string rating:     ""
    property string subtext:    ""
    property string epText:     ""
    property string posterUrl:  ""

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

    implicitHeight: posterArea.height + 10 + metaSlot.height

    // ── Artwork ──────────────────────────────────────────────────────────
    Item {
        id: posterArea
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: width * 3 / 2

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            focus: true
            activeFocusOnTab: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (card.isDropdownOpen) card.isDropdownOpen = false
                else card.clicked()
            }
            onExited: card.isDropdownOpen = false
            Keys.onEnterPressed: card.clicked()
            Keys.onReturnPressed: card.clicked()
        }

        Rectangle {
            id: posterClip
            anchors.fill: parent
            radius: 10
            color: "#141414"
            clip: true
            scale: cardMa.containsMouse ? 1.03 : 1.0
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Image {
                anchors.fill: parent
                source: card.posterUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            // Bottom scrim, only present on hover, so actions stay legible
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: parent.height * 0.52
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0.016, 0.016, 0.039, 0.94) }
                }
                opacity: cardMa.containsMouse ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            // Hover actions
            Row {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10 }
                spacing: 6
                height: 30
                visible: cardMa.containsMouse && !card.inWatchlistMode

                Rectangle {
                    width: parent.width - 36
                    height: 30
                    radius: 5
                    color: watchMa.containsMouse ? "#ffffff" : "#f5f5f5"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "Play"
                        color: "white"
                        font.family: "Segoe UI Variable Display, Segoe UI"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0
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
                    radius: 5
                    color: addMa.containsMouse ? Qt.rgba(1,1,1,0.22) : Qt.rgba(1,1,1,0.10)
                    border.color: Qt.rgba(1,1,1,0.22); border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: "white"; font.pixelSize: 15
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
        }

        // Edge light on hover / focus
        Rectangle {
            anchors.fill: posterClip
            anchors.margins: -1
            radius: 11
            color: "transparent"
            border.color: cardMa.activeFocus ? "#ffffff"
                        : cardMa.containsMouse ? Qt.rgba(1, 1, 1, 0.45)
                        : Qt.rgba(1, 1, 1, 0.07)
            border.width: cardMa.activeFocus ? 2 : 1
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        // ── Score: quiet glass ───────────────────────────────────────────
        Rectangle {
            visible: card.rating !== "" && !card.inWatchlistMode
            anchors { top: parent.top; left: parent.left; margins: 8 }
            height: 21; radius: 4
            width: ratingRow.implicitWidth + 12
            color: Qt.rgba(0.016, 0.016, 0.039, 0.78)
            border.color: Qt.rgba(1,1,1,0.10); border.width: 1
            Row {
                id: ratingRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    text: "\u2605"; color: "#ffffff"; font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: card.rating
                    color: "#f2f2f7"
                    font.family: "Segoe UI Variable Display, Segoe UI"
                    font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 0.6
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Trash (watchlist mode) ───────────────────────────────────────
        Rectangle {
            id: trashBtn
            visible: card.inWatchlistMode && (cardMa.containsMouse || trashMa.containsMouse || card.isDropdownOpen)
            anchors { top: parent.top; left: parent.left; margins: 8 }
            width: 26; height: 26; radius: 5
            color: trashMa.containsMouse ? "#dc2626" : Qt.rgba(0.86, 0.15, 0.15, 0.9)
            Text {
                anchors.centerIn: parent
                text: "\uE74D"
                color: "white"; font.pixelSize: 11
                font.family: "Segoe MDL2 Assets"
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
            visible: card.epText !== ""
            anchors { top: parent.top; right: parent.right; margins: 8 }
            height: 21; radius: 4
            width: epTxt.implicitWidth + 12
            readonly property bool isFresh: card.epText === "NEW EP"
            color: isFresh ? "#ffffff" : Qt.rgba(0, 0, 0, 0.62)
            border.color: isFresh ? "#ffffff" : Qt.rgba(1,1,1,0.12)
            border.width: 1
            Text {
                id: epTxt
                anchors.centerIn: parent
                text: card.epText
                color: parent.isFresh ? "#0a0a0a" : "#d4d4d4"
                font.family: "Segoe UI Variable Display, Segoe UI"
                font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.1
            }
        }

        // ── Watchlist status control ─────────────────────────────────────
        Item {
            id: dropdownContainer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 8 }
            height: 30
            visible: card.inWatchlistMode && (cardMa.containsMouse || card.isDropdownOpen)

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: Qt.rgba(0.016, 0.016, 0.039, card.isDropdownOpen ? 0.97 : 0.86)
                border.color: card.isDropdownOpen ? "#ffffff" : Qt.rgba(1,1,1,0.16)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10; anchors.rightMargin: 8
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: card.currentStatus
                        color: "#f2f2f7"
                        font.family: "Segoe UI Variable Display, Segoe UI"
                        font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 0.8
                        elide: Text.ElideRight
                    }
                    Text {
                        text: card.isDropdownOpen ? "\uE70E" : "\uE70D"
                        color: "#9a9ab2"; font.pixelSize: 9
                        font.family: "Segoe MDL2 Assets"
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
                bottom: dropdownContainer.top; bottomMargin: 4
                left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8
            }
            height: menuCol.implicitHeight + 8
            radius: 6
            color: "#141414"
            border.color: Qt.rgba(1,1,1,0.12); border.width: 1
            clip: true

            Column {
                id: menuCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 4 }
                spacing: 0

                Repeater {
                    model: card.statusOptions
                    delegate: Rectangle {
                        width: menuCol.width
                        height: 28
                        radius: 4
                        color: statusMa.containsMouse ? "#1c1e2a"
                             : (card.currentStatus === modelData ? Qt.rgba(1,1,1,0.14) : "transparent")

                        Text {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: modelData
                            color: card.currentStatus === modelData ? "#ffffff" : "#c8c8dc"
                            font.family: "Segoe UI Variable Display, Segoe UI"
                            font.pixelSize: 12; font.letterSpacing: 0.6
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
        anchors { top: posterArea.bottom; topMargin: 10; left: parent.left; right: parent.right }
        height: titleTxt.height + (card.subtext !== "" ? metaTxt.height + 3 : 0)

        Text {
            id: titleTxt
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 2 * lineHeight
            text: card.title
            color: cardMa.containsMouse ? "#ffffff" : "#f2f2f2"
            font.family: "Segoe UI Variable Display, Segoe UI"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            lineHeightMode: Text.FixedHeight
            lineHeight: 19
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        Text {
            id: metaTxt
            anchors { top: titleTxt.bottom; topMargin: 3; left: parent.left; right: parent.right }
            visible: card.subtext !== ""
            text: card.subtext
            color: "#9a9ab2"
            font.family: "Segoe UI Variable Text, Segoe UI"
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }
}
