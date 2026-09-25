import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import "../"
import ".."
import "../components"

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

    readonly property var appShell: Window.window

    // ── Public API ────────────────────────────────────────────────────────
    signal seriesSelected(int showId)
    signal browseRequested()

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

    // ── Grid metrics ───────────────────────────────────────────────────────
    // Shared by the Flow delegate and the loading skeleton so the two agree
    // on column count and card width instead of each guessing.
    readonly property int    gutter:   24
    readonly property int    cardGap:  Theme.s4
    readonly property int    gridCols: Math.max(4, Math.min(5, Math.floor(Math.max(400, width - gutter * 2) / 190)))
    readonly property int    cardW:    Math.max(80, Math.floor((Math.max(400, width - gutter * 2) - cardGap * (gridCols - 1)) / gridCols))
    readonly property int    cardH:    Math.round(cardW * 3 / 2) + 68

    // ── Design tokens ─────────────────────────────────────────────────────
    readonly property color clrBackground:         Theme.bg
    readonly property color clrPrimary:            Theme.textPrimary
    readonly property color clrOnSurface:          Theme.textPrimary
    readonly property color clrMuted:              Theme.textSecondary
    readonly property color clrSurface:            Theme.card

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
    EmptyState {
        anchors.centerIn: parent
        visible: !myListPage.isAuthenticated
        glyph: "\uE8FD"
        title: "Sign in to view your list"
        body: "Keep track of the anime you love and pick up right where you left off."
        actionLabel: authManager && authManager.signingIn ? "Signing in" : "Sign in"
        onActionRequested: { if (authManager) authManager.signInWithBrowserBridge() }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Loading — poster-shaped skeletons in the grid's own metrics
    // ─────────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: myListPage.isAuthenticated
                 && (myListPage.shows || []).length === 0
                 && !myListPage.emptyStateVisible

        SkeletonGrid {
            anchors.fill: parent
            anchors.topMargin: Theme.s6
            columns: myListPage.gridCols
            cardWidth: myListPage.cardW
            gap: myListPage.cardGap
            gutter: myListPage.gutter
            rows: 2
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // STATE: Empty — timer fired, list still empty
    // ─────────────────────────────────────────────────────────────────────
    EmptyState {
        anchors.centerIn: parent
        visible: myListPage.isAuthenticated
                 && (myListPage.shows || []).length === 0
                 && myListPage.emptyStateVisible
        glyph: "\uE8FD"
        title: "Your list is empty"
        body: "Browse or search for anime and add them here to keep track of where you are."
        actionLabel: "Browse anime"
        onActionRequested: myListPage.browseRequested()
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
                topMargin: myListPage.gutter
                leftMargin: myListPage.gutter
                rightMargin: myListPage.gutter
            }
            spacing: 24

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "My List"
                    color: myListPage.clrOnSurface
                    font { family: Theme.displayFont; pixelSize: 28; weight: Font.Bold }
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

                    font.family: Theme.bodyFont
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
                                font { family: Theme.bodyFont; pixelSize: 13; weight: isSelected ? Font.DemiBold : Font.Normal }
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
                spacing: myListPage.cardGap

                Repeater {
                    model: myListPage.filteredShows

                    Item {
                        width: myListPage.cardW
                        height: myListPage.cardH

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
                                    if (myListPage.appShell)
                                        myListPage.appShell.notify("Marked as " + newStatus, "success")
                                }
                            }
                            
                            onRemoveClicked: {
                                if (authManager) {
                                    authManager.removeShow(String(modelData.anilist_id || modelData.id || 0))
                                    if (myListPage.appShell)
                                        myListPage.appShell.notify("Removed from My List", "success")
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
            font { family: Theme.bodyFont; pixelSize: 16 }
        }
    }
}
