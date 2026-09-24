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
//   loading         : authenticated && (shows || []).length === 0 && !emptyStateVisible
//   empty           : authenticated && (shows || []).length === 0 && emptyStateVisible  (set by 5-s timer)
//   results         : (shows || []).length > 0

Item {
    id: myListPage

    // ── Public API ────────────────────────────────────────────────────────
    signal seriesSelected(int showId)

    // ── Data binding ──────────────────────────────────────────────────────
    // Automatically updates whenever authManager.libraryShowsChanged is emitted
    property var shows: (authManager && authManager.libraryShows) ? authManager.libraryShows : []

    property string currentTab: "All"
    property string searchQuery: ""

    property var filteredShows: {
        var result = []
        var searchLower = searchQuery.toLowerCase().trim()
        var src = myListPage.shows || []
        for (var i = 0; i < src.length; ++i) {
            var item = src[i]
            var status = item.userStatus || item.status || "Plan to Watch"
            
            if (currentTab !== "All" && status !== currentTab) {
                continue
            }
            if (searchLower !== "") {
                var title = (item.title || "").toLowerCase()
                var titleEnglish = (item.title_english || "").toLowerCase()
                var titleRomaji = (item.title_romaji || "").toLowerCase()
                if (title.indexOf(searchLower) === -1 && 
                    titleEnglish.indexOf(searchLower) === -1 && 
                    titleRomaji.indexOf(searchLower) === -1) {
                    continue
                }
            }
            result.push(item)
        }
        return result
    }

    property var tabs: ["All", "Watching", "Completed", "On Hold", "Dropped", "Plan to Watch"]

    // ── State helpers ─────────────────────────────────────────────────────
    property bool emptyStateVisible: false

    readonly property bool isAuthenticated: authManager ? authManager.authenticated : false

    // The watchlist rows carry no watched/total episode count, so this shows
    // only what is actually stored rather than inventing a progress figure.
    function showMeta(item) {
        if (!item) return ""
        var bits = []
        var st = item.userStatus || item.status || ""
        if (st) bits.push(st)
        if (item.seasonYear) bits.push(String(item.seasonYear))
        else if (item.episode_count) bits.push(item.episode_count + " eps")
        return bits.join("  •  ")
    }

    // ── Design tokens ─────────────────────────────────────────────────────
    readonly property color clrBackground: "#0a0a0a"
    readonly property color clrPrimary:    "#e6e6e6"
    readonly property color clrOnSurface:  "#f2f2f2"
    readonly property color clrMuted:      "#b3b3b3"
    readonly property color clrSurface:    "#141414"

    // ── Loading → empty timeout ───────────────────────────────────────────
    Timer {
        id: emptyTimeout
        interval: 5000
        repeat: false
        onTriggered: {
            if ((myListPage.shows || []).length === 0) {
                myListPage.emptyStateVisible = true
            }
        }
    }

    onIsAuthenticatedChanged: {
        if (isAuthenticated && (shows || []).length === 0) {
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
        if (visible && isAuthenticated && (shows || []).length === 0) {
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
            width: Math.max(0, Math.min(parent.width - 64, 360))

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u2605"
                color: Qt.rgba(1, 0.714, 0.576, 0.35)
                font { pixelSize: 64 }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sign in to view your list"
                color: myListPage.clrOnSurface
                font { family: "Segoe UI Variable Display, Segoe UI"; pixelSize: 22; weight: Font.DemiBold }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Keep track of the anime you love and pick up right where you left off."
                color: myListPage.clrMuted
                font { family: "Segoe UI Variable Text, Segoe UI"; pixelSize: 14 }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

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
                    font { family: "Segoe UI Variable Text, Segoe UI"; pixelSize: 14; weight: Font.DemiBold; letterSpacing: 0.5 }
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
    // STATE: Loading — simple spinner (authenticated, empty list, timer not fired)
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: myListPage.isAuthenticated
                 && (myListPage.shows || []).length === 0
                 && !myListPage.emptyStateVisible

        Column {
            anchors.centerIn: parent
            spacing: 16

            // Simple animated spinner without BusyIndicator
            Rectangle {
                id: spinnerRing
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40; height: 40
                radius: 20
                color: "transparent"
                border.color: myListPage.clrPrimary
                border.width: 3
                opacity: 0.7

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

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Loading your list…"
                color: myListPage.clrMuted
                font { family: "Segoe UI Variable Text, Segoe UI"; pixelSize: 14 }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Empty — timer fired, list still empty
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: myListPage.isAuthenticated
                 && (myListPage.shows || []).length === 0
                 && myListPage.emptyStateVisible

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: Math.max(0, Math.min(parent.width - 64, 360))

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
                font { family: "Segoe UI Variable Display, Segoe UI"; pixelSize: 20; weight: Font.DemiBold }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                width: parent.width
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Browse or search for anime and tap the bookmark icon to save them here."
                color: myListPage.clrMuted
                font { family: "Segoe UI Variable Text, Segoe UI"; pixelSize: 14 }
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
        visible: (myListPage.shows || []).length > 0

        // Page header with Tabs and Search
        ColumnLayout {
            id: headerCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 24
                leftMargin: 24
                rightMargin: 24
            }
            spacing: 24

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "My List"
                    color: myListPage.clrOnSurface
                    font { family: "Segoe UI Variable Display, Segoe UI"; pixelSize: 28; weight: Font.Bold }
                }

                TextField {
                    id: searchInput
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 250

                    placeholderText: "Search your list..."
                    placeholderTextColor: "#6a5f5a"
                    text: myListPage.searchQuery
                    onTextChanged: myListPage.searchQuery = text

                    color: myListPage.clrOnSurface
                    selectionColor: myListPage.clrPrimary
                    selectedTextColor: "#ffffff"

                    background: Rectangle {
                        color: "#1a1919"
                        radius: 8
                        border.color: searchInput.activeFocus ? myListPage.clrPrimary : "#2e2c2c"
                        border.width: 1
                    }

                    font.family: "Segoe UI Variable Text, Segoe UI"
                    font.pixelSize: 14
                    leftPadding: 12
                    rightPadding: 12
                    topPadding: 8
                    bottomPadding: 8
                }
            }

            // Tabs
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                contentWidth: tabsRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: tabsRow
                    spacing: 12
                    Repeater {
                        model: myListPage.tabs
                        delegate: Rectangle {
                            property bool isSelected: myListPage.currentTab === modelData
                            
                            width: tabText.implicitWidth + 24
                            height: 36
                            radius: 8
                            color: isSelected ? myListPage.clrPrimary : "#141414"
                            border.color: isSelected ? myListPage.clrPrimary : "#2e2c2c"
                            border.width: 1
                            
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: {
                                    var count = 0;
                                    var src = myListPage.shows || [];
                                    for (var i = 0; i < src.length; ++i) {
                                        var status = src[i].userStatus || src[i].status || "Plan to Watch";
                                        if (modelData === "All" || status === modelData) {
                                            count++;
                                        }
                                    }
                                    return modelData + " (" + count + ")"
                                }
                                color: isSelected ? "#0a0a0a" : myListPage.clrMuted
                                font { family: "Segoe UI Variable Text, Segoe UI"; pixelSize: 13; weight: isSelected ? Font.DemiBold : Font.Normal }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: myListPage.currentTab = modelData
                            }
                        }
                    }
                }
            }
        }

        // Scrollable grid
        Flickable {
            id: resultsFlickable
            anchors {
                top: headerCol.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 16
                leftMargin: 24
                rightMargin: 24
                bottomMargin: 16
            }
            clip: true
            contentHeight: gridFlow.height
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Flow {
                id: gridFlow
                width: parent.width
                spacing: 16

                Repeater {
                    model: myListPage.filteredShows

                    Item {
                        width: {
                            var availW = Math.max(400, resultsFlickable.width)
                            var cols = Math.max(4, Math.min(5, Math.floor(availW / 190)))
                            return Math.max(80, Math.floor((availW - 16 * (cols - 1)) / cols))
                        }
                        height: width * 3 / 2 + 68

                        AnimePosterCard {
                            anchors.fill: parent

                            posterUrl:  modelData.cover_image_url || modelData.coverImage  || modelData.poster_url  || ""
                            title:      modelData.title        || ""
                            rating:     modelData.rating ? String(modelData.rating) : ""
                            subtext:    myListPage.showMeta(modelData)
                            currentStatus: modelData.userStatus || modelData.status || "Plan to Watch"
                            epText:     ""

                            onClicked: myListPage.seriesSelected(modelData.anilist_id || 0)
                            
                            onStatusChanged: function(newStatus) {
                                if (authManager) {
                                    authManager.updateShowStatus(String(modelData.anilist_id || modelData.id || 0), newStatus)
                                }
                            }
                            
                            onRemoveClicked: {
                                if (authManager) {
                                    authManager.removeShow(String(modelData.anilist_id || modelData.id || 0))
                                }
                            }
                        }
                    }
                }
            }
        }

        // Empty state for filtered list
        Text {
            anchors {
                top: headerCol.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            visible: (myListPage.filteredShows || []).length === 0
            text: myListPage.searchQuery ? "No results found for \"" + myListPage.searchQuery + "\"" : "No items found in \"" + myListPage.currentTab + "\"."
            color: myListPage.clrMuted
            font { family: "Segoe UI Variable Text, Segoe UI"; pixelSize: 16 }
        }
    }
}
