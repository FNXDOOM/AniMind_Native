import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

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

    // ── Internal state ─────────────────────────────────────────────────────
    property var    historyEntries: []
    property bool   isLoading:      false
    property string errorText:      ""

    // ── Design tokens ──────────────────────────────────────────────────────
    readonly property color clrBackground:  "#131313"
    readonly property color clrPrimary:     "#ffb693"
    readonly property color clrMuted:       "#e2bfb0"
    readonly property color clrOnSurface:   "#e5e2e1"
    readonly property color clrOrange:      "#ff6b00"
    readonly property color clrBorder:      "#1c1b1b"
    readonly property color clrSurface:     "#1c1b1b"
    readonly property color clrError:       "#ff6b6b"

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

    // ── Trigger load when the page becomes visible and user is authenticated
    onVisibleChanged: {
        if (visible && authManager && authManager.authenticated) {
            activationDelay.restart()
        }
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

    // ── loadHistory() ─────────────────────────────────────────────────────
    // Issues a GET request to Supabase watch_history for the signed-in user.
    // Uses supabaseUrl and supabaseKey context properties set in main.cpp.
    // Requirements: 3.2, 3.4, 3.5, 3.6
    function loadHistory() {
        if (!authManager || !authManager.authenticated) return
        isLoading = true
        errorText = ""
        var xhr = new XMLHttpRequest()
        var url = supabaseUrl + "/rest/v1/watch_history"
                  + "?user_id=eq." + encodeURIComponent(authManager.userId)
                  + "&order=last_watched.desc&limit=50"
        xhr.open("GET", url, true)
        xhr.setRequestHeader("apikey", supabaseKey)
        xhr.setRequestHeader("Authorization", "Bearer " + supabaseKey)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            isLoading = false
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    historyEntries = JSON.parse(xhr.responseText)
                } catch(e) {
                    errorText = "Failed to parse history data."
                }
            } else {
                errorText = "Failed to load history (HTTP " + xhr.status + ")"
            }
        }
        xhr.onerror = function() {
            isLoading = false
            errorText = "Network error"
        }
        xhr.send()
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
    BusyIndicator {
        id: loadingIndicator
        anchors.centerIn: parent
        width: 56
        height: 56
        visible: root.pageState === "loading"
        running: visible
    }

    // ══════════════════════════════════════════════════════════════════════
    // ERROR STATE — error message + Retry button
    // ══════════════════════════════════════════════════════════════════════
    Column {
        id: errorState
        anchors.centerIn: parent
        spacing: 16
        visible: root.pageState === "error"

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.errorText
            color: root.clrError
            font.family: "Inter"
            font.pixelSize: 14
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            width: Math.min(400, root.width - 48)
        }

        Rectangle {
            id: retryButton
            anchors.horizontalCenter: parent.horizontalCenter
            height: 40
            width: retryLabel.implicitWidth + 32
            radius: 8
            color: retryMa.pressed
                   ? Qt.darker(root.clrOrange, 1.2)
                   : (retryMa.containsMouse ? Qt.lighter(root.clrOrange, 1.1) : root.clrOrange)

            Text {
                id: retryLabel
                anchors.centerIn: parent
                text: "Retry"
                color: "white"
                font.family: "Inter"
                font.pixelSize: 14
                font.bold: true
            }

            MouseArea {
                id: retryMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.loadHistory()
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // EMPTY STATE — "No watch history yet"
    // ══════════════════════════════════════════════════════════════════════
    Column {
        id: emptyState
        anchors.centerIn: parent
        spacing: 8
        visible: root.pageState === "empty"

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No watch history yet"
            color: root.clrOnSurface
            font.family: "Montserrat"
            font.pixelSize: 20
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Watch something to start building your history."
            color: root.clrMuted
            font.family: "Inter"
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // UNAUTHENTICATED STATE — sign-in prompt
    // ══════════════════════════════════════════════════════════════════════
    Column {
        id: unauthState
        anchors.centerIn: parent
        spacing: 20
        visible: root.pageState === "unauthenticated"

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Sign in to see your watch history"
            color: root.clrOnSurface
            font.family: "Montserrat"
            font.pixelSize: 20
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            id: signInButton
            anchors.horizontalCenter: parent.horizontalCenter
            height: 44
            width: signInLabel.implicitWidth + 40
            radius: 10
            color: signInMa.pressed
                   ? Qt.darker(root.clrOrange, 1.2)
                   : (signInMa.containsMouse ? Qt.lighter(root.clrOrange, 1.1) : root.clrOrange)

            Text {
                id: signInLabel
                anchors.centerIn: parent
                text: "Sign In"
                color: "white"
                font.family: "Inter"
                font.pixelSize: 15
                font.bold: true
            }

            MouseArea {
                id: signInMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (authManager) authManager.signInWithBrowserBridge()
                }
            }
        }
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
            font.family: "Montserrat"
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
                required property int index

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
                        color: "#2a2a2a"
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
                            font.family: "Montserrat"
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            width: parent.width
                            text: rowRoot.modelData.episode_label || ""
                            color: root.clrMuted
                            font.family: "Inter"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.relativeTime(rowRoot.modelData.last_watched || "")
                            color: Qt.rgba(0.886, 0.749, 0.690, 0.6)
                            font.family: "Inter"
                            font.pixelSize: 11
                        }
                    }

                    // Progress bar + percentage
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120
                        spacing: 4

                        ProgressBar {
                            width: parent.width
                            value: (rowRoot.modelData.progress_pct || 0) / 100
                            from: 0.0
                            to:   1.0

                            background: Rectangle {
                                implicitWidth: 120
                                implicitHeight: 4
                                color: "#2a2a2a"
                                radius: 2
                            }

                            contentItem: Item {
                                implicitWidth: 120
                                implicitHeight: 4

                                Rectangle {
                                    width: parent.width * (rowRoot.modelData.progress_pct || 0) / 100
                                    height: parent.height
                                    radius: 2
                                    color: root.clrOrange
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: (rowRoot.modelData.progress_pct || 0) + "%"
                            color: root.clrMuted
                            font.family: "Inter"
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

            delegate: HistoryEntryRow {
                modelData: root.historyEntries[index]
                index: model.index !== undefined ? model.index : 0
            }
        }
    }
}
