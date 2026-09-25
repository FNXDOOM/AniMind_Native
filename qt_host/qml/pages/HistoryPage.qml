import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import ".."

// HistoryPage — Watch history for the signed-in user.
// Loaded by the `historyLoader` Loader in main.qml when currentPage === "history".
//
// Public API:
//   signal seriesSelected(int anilistId)  — emitted when the user taps a history entry
//
// Context properties consumed (set in main.cpp):
//   supabaseUrl  : string
//   supabaseKey  : string
//   authManager  : AuthManager

Item {
    id: root

    // ── Public signal ──────────────────────────────────────────────────────
    signal seriesSelected(int anilistId)
    signal browseRequested()

    // ── Shared state ───────────────────────────────────────────────────────
    // The shell owns the one copy of the watch history so Home's Continue
    // Watching row and this page cannot disagree or double-fetch.
    readonly property var app: Window.window

    property var    historyEntries: app ? app.watchHistory      : []
    property bool   isLoading:      app ? app.watchHistoryLoading : false
    property string errorText:      app ? app.watchHistoryError   : ""

    // ── Design tokens ──────────────────────────────────────────────────────
    readonly property color clrBackground:         Theme.bg
    readonly property color clrPrimary:            Theme.textPrimary
    readonly property color clrMuted:              Theme.textSecondary
    readonly property color clrOnSurface:          Theme.textPrimary
    readonly property color clrAccent:             Theme.textPrimary
    readonly property color clrBorder:             Theme.borderDefault
    readonly property color clrSurface:            Theme.card
    readonly property color clrError:              Theme.accent

    // ── Background ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.clrBackground
    }

    // ── Activation timer (50 ms delay before first load) ───────────────────
    Timer {
        id: activationDelay
        interval: 50
        repeat: false
        onTriggered: loadHistory()
    }

    // ── Ask the shell for a refresh when the page is opened
    onVisibleChanged: {
        if (visible && app)
            activationDelay.restart()
    }

    // ── State helpers ──────────────────────────────────────────────────────
    // Determine which visual state to show.
    readonly property string pageState: {
        if (!authManager || !authManager.authenticated) return "unauthenticated"
        if (isLoading)                                  return "loading"
        if (errorText !== "")                           return "error"
        if (historyEntries.length === 0)                return "empty"
        return "results"
    }

    function loadHistory() {
        if (app) app.refreshWatchHistory(true)
    }

    // ── relativeTime(isoString) ────────────────────────────────────────────
    // Converts a UTC ISO-8601 timestamp to a human-readable relative string.
    // Five ranges (Requirements 3.3):
    //   < 60 s              → "Just now"
    //   60 s – 3599 s       → "X minutes ago"
    //   3600 s – 86399 s    → "X hours ago"
    //   86400 s – 2591999 s → "X days ago"
    //   ≥ 2592000 s         → absolute date in "MMM D, YYYY" (en-US)
    function relativeTime(isoString) {
        if (!isoString) return ""
        var now  = new Date()
        var then = new Date(isoString)
        var diff = Math.floor((now - then) / 1000)   // elapsed seconds
        if (diff < 60)
            return "Just now"
        if (diff < 3600)
            return Math.floor(diff / 60) + " minutes ago"
        if (diff < 86400)
            return Math.floor(diff / 3600) + " hours ago"
        if (diff < 30 * 86400)
            return Math.floor(diff / 86400) + " days ago"
        var opts = { year: "numeric", month: "short", day: "numeric" }
        return then.toLocaleDateString("en-US", opts)
    }

    // ══════════════════════════════════════════════════════════════════════
    // LOADING STATE — centered spinner
    // ══════════════════════════════════════════════════════════════════════
    // ══════════════════════════════════════════════════════════════════════
    // LOADING — row-shaped skeletons, not a spinner in the dark
    // ══════════════════════════════════════════════════════════════════════
    Column {
        id: loadingState
        anchors { top: parent.top; topMargin: Theme.s6; left: parent.left; right: parent.right }
        anchors.leftMargin: Theme.s6; anchors.rightMargin: Theme.s6
        visible: root.pageState === "loading"
        spacing: Theme.s3

        Repeater {
            model: 6
            Skeleton {
                width: loadingState.width
                height: 80
                bars: 1
                barHeight: 80
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // ERROR — names what failed and offers the way out
    // ══════════════════════════════════════════════════════════════════════
    EmptyState {
        id: errorState
        anchors.centerIn: parent
        visible: root.pageState === "error"
        isError: true
        glyph: "\uE783"
        title: root.errorText
        body: "Your watch history stays on the server, so a retry usually brings it back."
        actionLabel: "Retry"
        onActionRequested: root.loadHistory()
    }

    // ══════════════════════════════════════════════════════════════════════
    // EMPTY — an invitation, with somewhere to go
    // ══════════════════════════════════════════════════════════════════════
    EmptyState {
        id: emptyState
        anchors.centerIn: parent
        visible: root.pageState === "empty"
        glyph: "\uE823"
        title: "Nothing watched yet"
        body: "Play an episode and it will show up here so you can pick up where you stopped."
        actionLabel: "Browse anime"
        onActionRequested: root.browseRequested()
    }

    // ══════════════════════════════════════════════════════════════════════
    // UNAUTHENTICATED
    // ══════════════════════════════════════════════════════════════════════
    EmptyState {
        id: unauthState
        anchors.centerIn: parent
        visible: root.pageState === "unauthenticated"
        glyph: "\uE77B"
        title: "Sign in to see your watch history"
        body: "History follows your account, so you can pick up on any device you sign in on."
        actionLabel: authManager && authManager.signingIn ? "Signing in" : "Sign in"
        onActionRequested: { if (authManager) authManager.signInWithBrowserBridge() }
    }

    // ══════════════════════════════════════════════════════════════════════
    // RESULTS STATE — ListView of history entries
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: resultsState
        anchors.fill: parent
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        visible: root.pageState === "results"

        // Page title
        Text {
            id: pageTitle
            anchors {
                top: parent.top
                left: parent.left
                leftMargin: 24
                right: parent.right
                rightMargin: 24
            }
            text: "Watch History"
            color: root.clrOnSurface
            font.family: Theme.displayFont
            font.pixelSize: 26
            font.bold: true
        }

        // History list
        ListView {
            id: historyList
            anchors {
                top: pageTitle.bottom
                topMargin: 16
                left: parent.left
                leftMargin: 16
                right: parent.right
                rightMargin: 16
                bottom: parent.bottom
            }
            clip: true
            spacing: 8
            model: root.historyEntries
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // ── Inline delegate component ──────────────────────────────────
            component HistoryEntryRow: Rectangle {
                id: rowRoot

                required property var modelData

                width: ListView.view ? ListView.view.width : 0
                height: 80
                radius: 10
                color: rowMa.containsMouse
                       ? Qt.rgba(1, 1, 1, 0.05)
                       : Qt.rgba(0, 0, 0, 0)
                border.color: root.clrBorder
                border.width: 1

                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 14

                    // Thumbnail (80 × 45)
                    Rectangle {
                        id: thumbContainer
                        width: 80
                        height: 45
                        radius: 6
                        color: "#1e1e1e"
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: rowRoot.modelData.thumbnail_url || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    // Title, episode, timestamp
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80 - 120 - 28  // thumb + progress + spacing
                        spacing: 4

                        Text {
                            width: parent.width
                            text: rowRoot.modelData.show_title || ""
                            color: rowMa.containsMouse ? root.clrPrimary : root.clrOnSurface
                            font.family: Theme.displayFont
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            width: parent.width
                            text: rowRoot.modelData.episode_label || ""
                            color: root.clrMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.relativeTime(rowRoot.modelData.last_watched || "")
                            color: Qt.rgba(0.886, 0.749, 0.690, 0.6)
                            font.family: Theme.bodyFont
                            font.pixelSize: 11
                        }
                    }

                    // Progress bar + percentage
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120
                        spacing: 4

                        WatchBar {
                            width: parent.width
                            value: (rowRoot.modelData.progress_pct || 0) / 100
                        }

                        Text {
                            width: parent.width
                            text: (rowRoot.modelData.progress_pct || 0) + "%"
                            color: root.clrMuted
                            font.family: Theme.bodyFont
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                // Click handler
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var aid = rowRoot.modelData.anilist_id
                        if (aid) root.seriesSelected(aid)
                    }
                }
            }

            delegate: HistoryEntryRow { }
        }
    }
}
