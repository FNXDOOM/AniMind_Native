import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

// MyListPage — displays the authenticated user's saved anime list
// Public API:
//   signal seriesSelected(int showId)  — emitted when a poster card is clicked
//
// State logic (direct visible bindings, no QML State objects needed):
//   unauthenticated : !authManager || !authManager.authenticated
//   loading         : authenticated && shows.length === 0 && !emptyStateVisible
//   empty           : authenticated && shows.length === 0 && emptyStateVisible  (set by 5-s timer)
//   results         : shows.length > 0

Item {
    id: myListPage

    // ── Public API ────────────────────────────────────────────────────────
    signal seriesSelected(int showId)

    // ── Data binding ──────────────────────────────────────────────────────
    // Automatically updates whenever authManager.libraryShowsChanged is emitted
    property var shows: authManager ? authManager.libraryShows : []

    // ── State helpers ─────────────────────────────────────────────────────
    property bool emptyStateVisible: false

    readonly property bool isAuthenticated: authManager ? authManager.authenticated : false

    // ── Design tokens ─────────────────────────────────────────────────────
    readonly property color clrBackground: "#131313"
    readonly property color clrPrimary:    "#ffb693"
    readonly property color clrOnSurface:  "#e5e2e1"
    readonly property color clrMuted:      "#e2bfb0"
    readonly property color clrSurface:    "#1c1b1b"

    // ── Loading → empty timeout ───────────────────────────────────────────
    // Starts when page becomes visible + authenticated + list is empty.
    // If shows arrive before it fires, it is stopped.
    // If it fires with an empty list, transitions to the empty state.
    Timer {
        id: emptyTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if (myListPage.shows.length === 0) {
                myListPage.emptyStateVisible = true
            }
        }
    }

    // Watch for conditions that should start/stop the timer
    onIsAuthenticatedChanged: {
        if (isAuthenticated && shows.length === 0) {
            emptyStateVisible = false
            emptyTimeout.restart()
        } else {
            emptyTimeout.stop()
        }
    }

    onShowsChanged: {
        if (shows.length > 0) {
            emptyTimeout.stop()
            emptyStateVisible = false
        }
    }

    onVisibleChanged: {
        if (visible && isAuthenticated && shows.length === 0) {
            emptyStateVisible = false
            emptyTimeout.restart()
        } else if (!visible) {
            emptyTimeout.stop()
        }
    }

    // ── Background ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: myListPage.clrBackground
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Unauthenticated — sign-in prompt
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !myListPage.isAuthenticated

        Column {
            anchors.centerIn: parent
            spacing: 20
            width: Math.min(parent.width - 64, 360)

            // Icon
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u2605"
                color: Qt.rgba(1, 0.714, 0.576, 0.35)
                font { pixelSize: 64 }
            }

            // Heading
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sign in to view your list"
                color: myListPage.clrOnSurface
                font { family: "Montserrat"; pixelSize: 22; weight: Font.DemiBold }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

            // Sub-text
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Keep track of the anime you love and pick up right where you left off."
                color: myListPage.clrMuted
                font { family: "Inter"; pixelSize: 14 }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

            // Sign In button
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: signInLabel.implicitWidth + 48
                height: 44
                radius: 10
                color: signInMa.containsMouse
                       ? Qt.rgba(1, 0.714, 0.576, 0.22)
                       : Qt.rgba(1, 0.714, 0.576, 0.13)
                border.color: Qt.rgba(1, 0.714, 0.576, 0.45)
                border.width: 1

                Behavior on color { ColorAnimation { duration: 160 } }

                Text {
                    id: signInLabel
                    anchors.centerIn: parent
                    text: authManager && authManager.signingIn ? "Signing In…" : "Sign In"
                    color: myListPage.clrPrimary
                    font { family: "Inter"; pixelSize: 14; weight: Font.DemiBold; letterSpacing: 0.5 }
                }

                MouseArea {
                    id: signInMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !(authManager && authManager.signingIn)
                    onClicked: {
                        if (authManager) authManager.signInWithBrowserBridge()
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Loading — BusyIndicator (authenticated, empty list, timer not fired)
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: myListPage.isAuthenticated
                 && myListPage.shows.length === 0
                 && !myListPage.emptyStateVisible

        Column {
            anchors.centerIn: parent
            spacing: 16

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: parent.parent.visible
                width: 48; height: 48

                contentItem: Item {
                    anchors.fill: parent

                    Rectangle {
                        id: spinnerRing
                        anchors.centerIn: parent
                        width: 40; height: 40
                        radius: 20
                        color: "transparent"
                        border.color: myListPage.clrPrimary
                        border.width: 3
                        opacity: 0.7

                        // Animate rotation via a child item
                        Rectangle {
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                            width: 6; height: 6; radius: 3
                            color: myListPage.clrPrimary
                            anchors.topMargin: -3
                        }

                        RotationAnimator on rotation {
                            from: 0; to: 360
                            duration: 900
                            loops: Animation.Infinite
                            running: spinnerRing.visible
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Loading your list…"
                color: myListPage.clrMuted
                font { family: "Inter"; pixelSize: 14 }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Empty — timer fired, list still empty
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: myListPage.isAuthenticated
                 && myListPage.shows.length === 0
                 && myListPage.emptyStateVisible

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: Math.min(parent.width - 64, 360)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u2605"
                color: Qt.rgba(1, 0.714, 0.576, 0.25)
                font { pixelSize: 56 }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Your list is empty — add some shows!"
                color: myListPage.clrOnSurface
                font { family: "Montserrat"; pixelSize: 20; weight: Font.DemiBold }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Browse or search for anime and tap the bookmark icon to save them here."
                color: myListPage.clrMuted
                font { family: "Inter"; pixelSize: 14 }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Results — GridView with AnimePosterCard delegates
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: myListPage.shows.length > 0

        // Page header
        Item {
            id: resultsHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64

            Text {
                anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
                text: "My List"
                color: myListPage.clrOnSurface
                font { family: "Montserrat"; pixelSize: 24; weight: Font.Bold }
            }

            Text {
                anchors { right: parent.right; rightMargin: 32; verticalCenter: parent.verticalCenter }
                text: myListPage.shows.length + " show" + (myListPage.shows.length === 1 ? "" : "s")
                color: myListPage.clrMuted
                font { family: "Inter"; pixelSize: 13 }
            }
        }

        // Scrollable grid
        ScrollView {
            id: resultsScroll
            anchors {
                top: resultsHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 24
                rightMargin: 24
                bottomMargin: 16
            }
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            GridView {
                id: showsGrid
                width: resultsScroll.width

                // 4–5 columns: target cell width ~190 px, minimum 4 cols
                readonly property int targetCellW: 190
                readonly property int cols: Math.max(4, Math.min(5, Math.floor(width / targetCellW)))
                readonly property int spacing: 16
                readonly property int cellW: Math.floor((width - spacing * (cols - 1)) / cols)

                cellWidth:  cellW + spacing
                cellHeight: Math.round(cellW * 3 / 2) + 68   // 2:3 poster + ~56 px meta

                model: myListPage.shows

                delegate: Item {
                    width:  showsGrid.cellWidth
                    height: showsGrid.cellHeight

                    AnimePosterCard {
                        anchors {
                            top:    parent.top
                            left:   parent.left
                            right:  parent.right
                            rightMargin: showsGrid.spacing
                            bottom: parent.bottom
                        }

                        posterUrl:  modelData.coverImage  || modelData.poster_url  || ""
                        title:      modelData.title        || ""
                        rating:     modelData.rating ? String(modelData.rating) : ""
                        audioLabel: modelData.audioLabel   || "Sub"

                        onClicked: myListPage.seriesSelected(modelData.id)
                    }
                }
            }
        }
    }
}
