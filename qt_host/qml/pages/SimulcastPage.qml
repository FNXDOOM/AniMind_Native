import QtQuick
import QtQuick.Controls
import "../"
import ".."
import "../components"

// My Shows — the synced cloud library.
//
// The file is still SimulcastPage.qml and the shell still routes the
// "simulcast" page key here, but the data has always been
// authManager.libraryShows, which is what the sidebar's "My Shows" promises.
// The heading used to read "Simulcasts", so the nav and the page disagreed
// about what this screen was.
Rectangle {
    id: myShows
    color: Theme.bg

    // Reached through typeof: a bare reference to an out-of-scope context
    // property throws the binding away, and `shows` would then be neither an
    // array nor null — every shows.length below would throw with it.
    readonly property var auth: typeof authManager !== "undefined" ? authManager : null
    property var shows: (auth && auth.libraryShows) ? auth.libraryShows : []

    readonly property var app: Window.window
    readonly property int gutter: width < 640 ? Theme.s4 : Theme.s8
    readonly property int gap: Theme.s4

    signal showSelected(string showId, string showTitle)

    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top
                  margins: myShows.gutter }
        spacing: Theme.s2

        Text {
            text: "My Shows"
            color: Theme.textPrimary
            font.family: Theme.displayFont
            font.pixelSize: 28
            font.weight: Font.Bold
        }
        Text {
            text: myShows.auth && myShows.auth.authenticated
                  ? "Synced with your account"
                  : "Sign in to sync the shows you follow"
            color: Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsBody
        }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right
                  top: head.bottom; bottom: parent.bottom
                  topMargin: Theme.s6; leftMargin: myShows.gutter; rightMargin: myShows.gutter
                  bottomMargin: myShows.gutter }
        contentWidth: width
        contentHeight: grid.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        visible: myShows.shows.length > 0

        Grid {
            id: grid
            width: parent.width
            flow: Grid.LeftToRight
            columns: Math.max(1, Math.floor((width + myShows.gap) / 204))
            columnSpacing: myShows.gap
            rowSpacing: Theme.s5

            Repeater {
                model: myShows.shows
                delegate: AnimePosterCard {
                    required property var modelData
                    width: Math.floor((grid.width - grid.columnSpacing * (grid.columns - 1))
                                      / grid.columns)
                    title: modelData.title || "Untitled"
                    rating: (modelData.rating !== undefined && modelData.rating !== null)
                            ? String(modelData.rating) : ""
                    subtext: "My Shows"
                    epText: (modelData.episode_count !== undefined
                             && modelData.episode_count !== null)
                            ? ("EP " + String(modelData.episode_count)) : ""
                    posterUrl: modelData.cover_image_url || ""
                    onClicked: myShows.showSelected(String(modelData.id || ""),
                                                    modelData.title || "Untitled")
                    onAddClicked: {
                        if (!myShows.auth) return
                        myShows.auth.addToLibrary({
                            "anilist_id": modelData.id || modelData.anilist_id,
                            "title": title,
                            "cover_image_url": posterUrl,
                            "rating": rating
                        })
                    }
                }
            }
        }
    }

    // The old state was 14px #666 text centred inside a #1a1a1a panel — a
    // message too dim to read floating in a void. It now shares the one empty
    // state every other page uses, with an action that goes somewhere.
    EmptyState {
        anchors.centerIn: parent
        visible: myShows.shows.length === 0
        glyph: "\uE7C1"
        title: myShows.auth && myShows.auth.authenticated
               ? "Nothing synced yet"
               : "Sign in to see your shows"
        body: myShows.auth && myShows.auth.authenticated
              ? "Shows you add to your list appear here on every device."
              : "Your list and progress follow you once you are signed in."
        actionLabel: (myShows.auth && myShows.auth.authenticated)
                     ? "Browse anime"
                     : (myShows.auth && myShows.auth.signingIn ? "Signing in" : "Sign in")
        onActionRequested: {
            if (myShows.auth && myShows.auth.authenticated) {
                if (myShows.app) myShows.app.currentPage = "browse"
            } else if (myShows.auth) {
                myShows.auth.signInWithBrowserBridge()
            }
        }
    }
}
