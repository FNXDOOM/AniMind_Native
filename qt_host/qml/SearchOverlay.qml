import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// SearchOverlay — full-screen search overlay
// Triggered by TopBar search icon; z:50 so it sits above all page content.
//
// Public properties:
//   open        : bool    — set true to open, false to close
//   searchQuery : string  — live text field value (two-way bindable)
//
// Signals:
//   closeRequested()         — emitted on Escape or scrim click
//   seriesSelected(anilistId) — emitted when a result card is clicked

Item {
    id: searchOverlay

    // ── Public API ────────────────────────────────────────────────────────
    property bool   open: false
    property string searchQuery: ""

    signal closeRequested()
    signal seriesSelected(int anilistId)

    // ── Internal state ────────────────────────────────────────────────────
    property var    results:    []
    property bool   isLoading:  false
    property string errorText:  ""
    property var    _activeXhr: null

    // ── Visibility / focus management ─────────────────────────────────────
    onOpenChanged: {
        if (open) {
            searchInput.forceActiveFocus()
        } else {
            results    = []
            isLoading  = false
            errorText  = ""
        }
    }

    // ── Keyboard: Escape closes overlay ───────────────────────────────────
    Keys.onEscapePressed: searchOverlay.closeRequested()
    focus: open

    // ── Full-screen scrim ─────────────────────────────────────────────────
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "#000000"
        opacity: 0.60

        MouseArea {
            anchors.fill: parent
            onClicked: searchOverlay.closeRequested()
        }
    }

    // ── Content card ──────────────────────────────────────────────────────
    Rectangle {
        id: contentCard

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 80

        width:  Math.min(parent.width - 48, 720)
        // Height grows with content, capped so it doesn't overflow the window
        height: Math.min(
                    cardCol.implicitHeight + 32,
                    parent.height - anchors.topMargin - 40
                )

        color:        Qt.rgba(0.075, 0.075, 0.075, 0.95)
        border.color: "#1c1b1b"
        border.width: 1
        radius:       12

        // Capture clicks inside the card — prevents scrim from firing
        MouseArea {
            anchors.fill: parent
            onClicked: {}   // absorb clicks
        }

        // ── Inner layout ──────────────────────────────────────────────────
        Column {
            id: cardCol
            anchors {
                top:   parent.top
                left:  parent.left
                right: parent.right
                margins: 16
            }
            spacing: 12

            // ── Search field ──────────────────────────────────────────────
            TextField {
                id: searchInput
                width: parent.width

                placeholderText: "Search anime…"
                placeholderTextColor: "#6a5f5a"

                color:             "#e5e2e1"
                selectionColor:    "#ff6b00"
                selectedTextColor: "#ffffff"

                background: Rectangle {
                    color:        "#1a1919"
                    radius:       8
                    border.color: searchInput.activeFocus ? "#ff6b00" : "#2e2c2c"
                    border.width: 1
                }

                font.family:   "Inter"
                font.pixelSize: 15
                leftPadding:   12
                rightPadding:  12
                topPadding:    10
                bottomPadding: 10

                // Keep the public searchQuery property in sync and restart debounce
                onTextChanged: {
                    searchOverlay.searchQuery = text
                    debounceTimer.restart()
                }

                // Escape propagates upward to the overlay
                Keys.onEscapePressed: searchOverlay.closeRequested()
            }

            // ── Debounce timer ────────────────────────────────────────────
            Timer {
                id: debounceTimer
                interval: 300
                repeat:   false
                onTriggered: {
                    if (searchOverlay.searchQuery.length < 2) {
                        searchOverlay.results   = []
                        searchOverlay.isLoading = false
                        return
                    }
                    if (searchOverlay._activeXhr) {
                        searchOverlay._activeXhr.abort()
                        searchOverlay._activeXhr = null
                    }
                    searchOverlay.isLoading = true
                    searchOverlay.errorText = ""
                    searchOverlay._activeXhr = AniListApi.searchAnime(
                        { search: searchOverlay.searchQuery, page: 1, perPage: 20 },
                        function(mediaArray, pageInfo, errorString) {
                            searchOverlay._activeXhr = null
                            searchOverlay.isLoading  = false
                            if (errorString) {
                                searchOverlay.errorText = errorString
                                return
                            }
                            searchOverlay.results = mediaArray || []
                        }
                    )
                }
            }

            // ── Loading spinner ───────────────────────────────────────────
            BusyIndicator {
                id: loadingSpinner
                anchors.horizontalCenter: parent.horizontalCenter
                visible: searchOverlay.isLoading
                running: searchOverlay.isLoading
                width:  40
                height: 40
                palette.dark: "#ff6b00"
            }

            // ── Idle / empty-state prompt ─────────────────────────────────
            // Shown when the user hasn't typed enough yet and nothing is loading
            Text {
                id: idleText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: searchOverlay.searchQuery.length < 2 && !searchOverlay.isLoading && searchOverlay.errorText.length === 0

                text:  "Type at least 2 characters to search"
                color: "#e2bfb0"
                font { family: "Inter"; pixelSize: 13 }
                topPadding: 8
                bottomPadding: 8
            }

            // ── No-results state ──────────────────────────────────────────
            Text {
                id: noResultsText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: searchOverlay.results.length === 0
                      && !searchOverlay.isLoading
                      && searchOverlay.searchQuery.length >= 2
                      && searchOverlay.errorText.length === 0

                text:  'No results for "' + searchOverlay.searchQuery + '"'
                color: "#e2bfb0"
                font { family: "Inter"; pixelSize: 13 }
                topPadding: 8
                bottomPadding: 8
            }

            // ── Error state ───────────────────────────────────────────────
            Text {
                id: errorLabel
                anchors.horizontalCenter: parent.horizontalCenter
                visible: searchOverlay.errorText.length > 0

                text:  searchOverlay.errorText
                color: "#ff6b6b"
                font { family: "Inter"; pixelSize: 13 }
                wrapMode: Text.Wrap
                width: parent.width
                topPadding: 8
                bottomPadding: 8
            }

            // ── Results grid ──────────────────────────────────────────────
            GridView {
                id: resultsGrid
                width:   parent.width
                // Height fills the remaining card space; clip prevents overflow
                height:  contentCard.height - searchInput.height - 32 - 24
                clip:    true
                visible: searchOverlay.results.length > 0

                model: searchOverlay.results

                // ~5 columns in 720 px → cell width ≈ 136 px
                // poster 2:3 → cellHeight = cellWidth * 1.5 + meta (~48px)
                cellWidth:  Math.floor(width / 5)
                cellHeight: Math.floor(cellWidth * 1.5) + 52

                delegate: Item {
                    width:  resultsGrid.cellWidth
                    height: resultsGrid.cellHeight

                    AnimePosterCard {
                        anchors {
                            fill:    parent
                            margins: 6
                        }

                        posterUrl:  modelData.coverImage
                                    ? (modelData.coverImage.extraLarge
                                       || modelData.coverImage.large
                                       || "")
                                    : ""
                        title:      modelData.title
                                    ? (modelData.title.romaji
                                       || modelData.title.english
                                       || "")
                                    : ""
                        rating:     modelData.averageScore
                                    ? String(modelData.averageScore)
                                    : ""
                        audioLabel: "Sub"

                        onClicked: {
                            searchOverlay.seriesSelected(modelData.id)
                            searchOverlay.closeRequested()
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }
        }
    }
}
