import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import Qt.labs.settings
import Animind.Player 1.0
import "."          // picks up qmldir → AniListApi singleton
import "components"
import "."

ApplicationWindow {
    id: root
    width: 1280
    height: 720
    minimumWidth: 380
    minimumHeight: 520
    visible: true
    title: "Animind Player"
    color: bg

    Material.theme: Material.Dark

    // ── Design tokens ─────────────────────────────────────────────────────
    // Values live in Theme.qml. These root aliases exist only so pages that
    // have not been migrated yet keep compiling; each one is removed as its
    // last use is rewritten against Theme directly.
    readonly property color bg:         Theme.bg
    readonly property color surface:    Theme.card
    readonly property color hairline:   Theme.borderDefault

    readonly property color accent:        Theme.accent
    readonly property color accentSoft:    Theme.accentSoft
    readonly property color textPrimary:   Theme.textPrimary
    readonly property color textSecondary: Theme.textSecondary
    readonly property color textMuted:     Theme.textMuted

    // Still-referenced legacy names, held at their current meaning so the
    // palette shift stays reviewable rather than spraying red everywhere.
    readonly property color accentOrange: Theme.textPrimary
    readonly property color clrPrimary:   Theme.textPrimary
    readonly property color clrMuted:     Theme.textSecondary
    readonly property color clrOnSurface: Theme.textPrimary

    // One neutral grotesque throughout; hierarchy comes from weight and size.
    readonly property string displayFont: Theme.displayFont
    readonly property string bodyFont:    Theme.bodyFont
    readonly property string uiFont:      Theme.bodyFont
    readonly property string iconFont:    Theme.iconFont

    // ── Responsive scale ──────────────────────────────────────────────────
    // Breakpoints follow content, not devices: the sidebar stops fitting at
    // 1024, so the bottom bar takes over nav for the whole range below it.
    // Gating the bar on isMobile instead left 640–1023px with neither rail nor
    // tabs, and minimumWidth made isMobile unreachable.
    readonly property int  bpMobile:  640
    readonly property int  bpTablet:  1024
    readonly property bool isMobile:  width < bpMobile
    readonly property bool isCompact: width < bpTablet
    readonly property int  navW:      isCompact ? 0
                                    : (railCollapsed ? Theme.railCollapsedW
                                                           : Theme.railExpandedW)
    readonly property int  headerH:   isMobile ? 56 : 64
    readonly property int  tabH:      isCompact ? 64 : 0
    readonly property int  gutter:    isMobile ? 16 : (isCompact ? 24 : 32)

    // clamp() equivalent: linear between two viewport anchors, then bounded.
    function fluid(minV, maxV, fromW, toW) {
        if (width <= fromW) return minV
        if (width >= toW)   return maxV
        return minV + (maxV - minV) * (width - fromW) / (toW - fromW)
    }

    // Type scale, fluid between a 900px and a 1600px window.
    readonly property real tsHero:     fluid(30, 46, 900, 1600)
    readonly property int  tsPage:     28
    readonly property int  tsSection:  20
    readonly property int  tsCard:     13
    readonly property int  tsBody:     14
    readonly property int  tsMeta:     12
    readonly property int  tsSmall:    11
    readonly property real trEyebrow:  0.4
    readonly property real trTally:    0.4

    readonly property int radiusCard:  8
    readonly property int radiusCtl:   8
    readonly property int minTouch:    isMobile ? 44 : 32

    // Honour an explicit request for less movement. Qt 6 removed Qt.getenv(),
    // so this reads a launch flag instead of an environment variable.
    // Stored as a preference and overridable on the command line, which is how
    // the screenshot harness keeps motion out of its captures.
    property bool   motionReduced: false
    readonly property bool reduceMotion: root.motionReduced
            || Qt.application.arguments.indexOf("--reduce-motion") !== -1

    // ── Navigation state ──────────────────────────────────────────────────
    // Pages: "home" | "browse" | "simulcast" | "simulcastDetail" | "mylist" | "history" | "settings" | "player"
    property string currentPage: "home"
    // Owned here, not by the rail, so navW and the content column follow
    // the same animated value.
    property bool   railCollapsed: false

    // Playback defaults the Settings page edits and the player obeys.
    property real   volumeDefault: 0.5
    property real   speedDefault:  1.0

    Settings {
        id: appSettings
        category: "prefs"
        property bool  reduceMotion: false
        property real  volume:       0.5
        property real  speed:        1.0
    }

    onMotionReducedChanged: appSettings.reduceMotion = motionReduced
    onVolumeDefaultChanged: {
        appSettings.volume = volumeDefault
        video.command(["set", "volume", Math.round(volumeDefault * 100).toString()])
    }
    onSpeedDefaultChanged: {
        appSettings.speed = speedDefault
        video.command(["set", "speed", speedDefault.toString()])
    }
    property bool   episodePanelOpen: false
    property bool   profileMenuOpen: false
    property var    playerEpisodes: []
    // One copy of the watch history for the whole app: the Continue Watching
    // row on Home and the HistoryPage both read this, instead of each issuing
    // their own GET against the same endpoint.
    property var    watchHistory: []
    property bool   watchHistoryLoading: false
    property string watchHistoryError: ""
    property bool   watchHistoryLoaded: false
    property var    toasts: []
    property int    toastSeq: 0
    property int    playerEpisodesFor: -1
    property string previousPage: "home"
    property var currentSeriesId: 0
    property string currentCloudShowId: ""
    property string currentCloudShowTitle: ""
    readonly property bool inPlayer: currentPage === "player"
    readonly property int  sideNavW: 256
    property bool drawerOpen: false
    property string searchQuery: ""
    property bool notifPanelOpen: false

    // ── Search page state (no longer an overlay — navigated as a page) ────
    // searchOverlayOpen kept for Escape-key compat; always false now.
    property bool searchOverlayOpen: false

    // ── Player state ──────────────────────────────────────────────────────
    property bool   isFullscreen:   false
    property bool   isPlaying:      false
    property var    audioTracks:    []
    property var    subtitleTracks: []
    property var    videoTracks:    []
    property int    currentAudioId: -1
    property int    currentSubId:   -1
    property string showTitle:         "Animind Player"
    property string episodeLabel:      ""
    property string currentThumbnailUrl: ""
    property string pendingLoadPath: ""
    property string authErrorText: ""

    readonly property int barH: 72
    readonly property int topH: 64

    onVisibilityChanged: function(visibility) {
        root.isFullscreen = (visibility === Window.FullScreen)
        if (root.isFullscreen) hideTimer.restart()
    }

    Connections {
        target: authManager
        function onLastErrorChanged() {
            if (!authManager || !authManager.lastError || authManager.lastError.length === 0)
                return
            root.authErrorText = authManager.lastError
            authErrorTimer.restart()
        }
    }

    function fmtTime(s) {
        if (isNaN(s) || s < 0) return "0:00"
        var m = Math.floor(s / 60)
        var sec = Math.floor(s % 60)
        return m + ":" + sec.toString().padStart(2, "0")
    }

    // ── Display name derivation ───────────────────────────────────────────
    // Accessible from SideNav.qml and TopBar.qml via the `root` context id.
    // Branch order:
    //   1. Not authenticated → "Guest"
    //   2. Authenticated + email with non-empty local-part → local-part (truncated to 16)
    //   3. Authenticated + non-empty userId → userId stripped of "user_" prefix (truncated to 16)
    //   4. Authenticated but no usable identifier → "User"
    function computeDisplayName(email, userId, authenticated) {
        if (!authenticated) return "Guest"
        if (email && email.indexOf("@") !== -1) {
            var local = email.substring(0, email.indexOf("@"))
            if (local.length === 0) {
                // fall through to userId logic
            } else {
                return local.length > 16 ? local.substring(0, 16) + "\u2026" : local
            }
        }
        if (userId && userId.length > 0) {
            var s = userId.startsWith("user_") ? userId.substring(5) : userId
            return s.length > 16 ? s.substring(0, 16) + "\u2026" : s
        }
        return "User"
    }

    function refreshTracks() {
        var count = video.getPropertyDouble("track-list/count")
        var na = [], ns = [], nv = []
        for (var i = 0; i < count; i++) {
            var type = video.getPropertyString("track-list/" + i + "/type")
            var tid  = video.getPropertyDouble("track-list/" + i + "/id")
            var lang = video.getPropertyString("track-list/" + i + "/lang")
            var ttl  = video.getPropertyString("track-list/" + i + "/title")
            var lbl  = ttl || lang || (type === "audio" ? "Audio " + tid : "Sub " + tid)
            var hgt = video.getPropertyDouble("track-list/" + i + "/height")
            if      (type === "audio") na.push({id: tid, label: lbl})
            else if (type === "sub")   ns.push({id: tid, label: lbl})
            else if (type === "video") nv.push({id: tid, label: hgt > 0 ? (hgt + "p") : ("Track " + tid)})
        }
        ns.unshift({id: 0, label: "Off"})
        audioTracks    = na
        subtitleTracks = ns
        videoTracks    = nv
        currentAudioId = video.getPropertyDouble("aid")
        currentSubId   = video.getPropertyDouble("sid")
    }

    function loadPathNow(path) {
        video.command(["set", "vid", "auto"])
        video.command(["loadfile", path])
        forcePlayTimer.restart()
        trackRefreshTimer.restart()
    }

    function playStreamNow(url, titleStr, epLabel, thumbUrl) {
        if (!url || url.length === 0)
            return
        root.showTitle = titleStr || "Animind Player"
        root.episodeLabel = epLabel || ""
        root.currentThumbnailUrl = thumbUrl || ""
        root.currentPage = "player"
        root.isPlaying = true
        focusSink.forceActiveFocus()
        if (!video.rendererReady) {
            root.pendingLoadPath = url
            loadWhenReadyTimer.start()
        } else {
            Qt.callLater(function() { root.loadPathNow(url) })
        }
    }

    function stopPlaybackAndExit(targetPage) {
        // ── Upsert watch history before leaving the player ────────────────
        // Requirements 3.8, 3.9: record position whenever playback stops or
        // the user navigates away from the player.
        if (authManager && authManager.authenticated && video.duration > 0) {
            var timePos  = video.timePos
            var duration = video.duration
            var rawPct   = Math.round(timePos / duration * 100)
            var progress_pct = Math.max(0, Math.min(100, rawPct))
            upsertWatchHistory({
                user_id:       authManager.userId,
                show_title:    root.showTitle,
                episode_label: root.episodeLabel,
                thumbnail_url: root.currentThumbnailUrl,
                anilist_id:    root.currentSeriesId,
                last_watched:  new Date().toISOString(),
                progress_pct:  progress_pct
            })
        }
        video.command(["stop"])
        root.isPlaying = false
        root.currentPage = targetPage || "home"
    }

    // ── Watch history upsert ──────────────────────────────────────────────
    // Fire-and-forget POST to Supabase watch_history.
    // Requirements 3.8, 3.10: silent discard on any error; no retry, no UI feedback.
    function upsertWatchHistory(payload) {
        if (!authManager || !authManager.authenticated) return
        var xhr = new XMLHttpRequest()
        xhr.open("POST", supabaseUrl + "/rest/v1/watch_history", true)
        xhr.setRequestHeader("apikey",        supabaseKey)
        xhr.setRequestHeader("Authorization", "Bearer " + supabaseKey)
        xhr.setRequestHeader("Content-Type",  "application/json")
        xhr.setRequestHeader("Prefer",        "resolution=merge-duplicates")
        xhr.onerror = function() {}           // silent discard — Req 3.10
        xhr.onreadystatechange = function() {}// silent discard — Req 3.10
        xhr.send(JSON.stringify(payload))
    }

    // ── Page-change handler: save progress when navigating away from player ──
    // Requirement 3.9: when currentPage changes FROM "player" to another page
    // via any path other than stopPlaybackAndExit (e.g. programmatic navigation),
    // record watch history at the current playback position.
    onCurrentPageChanged: {
        // _prevPage is updated AFTER this handler runs, so we compare the
        // incoming new value against the inPlayer-guard: if we just left
        // "player", and the navigation did NOT go through stopPlaybackAndExit
        // (which already calls upsertWatchHistory before changing the page),
        // we must upsert here.
        // We track whether we were in the player by storing the previous page
        // in a private property updated before the assignment takes effect.
        // Because onCurrentPageChanged fires after the new value is committed,
        // we check the helper property _wasInPlayer set in the setter below.
        if (_wasInPlayer && currentPage !== "player") {
            if (authManager && authManager.authenticated && video.duration > 0) {
                var tp   = video.timePos
                var dur  = video.duration
                var raw  = Math.round(tp / dur * 100)
                var pct  = Math.max(0, Math.min(100, raw))
                upsertWatchHistory({
                    user_id:       authManager.userId,
                    show_title:    root.showTitle,
                    episode_label: root.episodeLabel,
                    thumbnail_url: root.currentThumbnailUrl,
                    anilist_id:    root.currentSeriesId,
                    last_watched:  new Date().toISOString(),
                    progress_pct:  pct
                })
            }
        }
        // Section 23: pages must not swap instantly. Folded into the existing
        // handler because a second onCurrentPageChanged on the same object is a
        // fatal duplicate. Explicit animation, not a Behavior: two assignments
        // in one turn leave a Behavior with no net change to play.
        if (currentPage === "history" || currentPage === "home")
            root.refreshWatchHistory(false)

        if (currentPage === "player") {
            // Section 21: the chrome must be up when the player opens, then
            // retire after the pointer goes still.
            hideTimer.restart()
            root.loadPlayerEpisodes()
        }
        else
            root.episodePanelOpen = false

        if (!root.reduceMotion && currentPage !== "player")
            pageIn.restart()

        _wasInPlayer = (currentPage === "player")
    }

    // Tracks whether the player page was active just before the last page change.
    // Initialised to false; set by onCurrentPageChanged.
    property bool _wasInPlayer: false

    Timer { id: hideTimer;         interval: 3500; repeat: false }
    Timer { id: authErrorTimer;    interval: 3500; repeat: false; onTriggered: root.authErrorText = "" }
    Timer { id: trackRefreshTimer; interval: 1200; repeat: false; onTriggered: root.refreshTracks() }
    Timer {
        id: loadWhenReadyTimer
        interval: 100
        repeat: true
        onTriggered: {
            if (!root.pendingLoadPath || !video.rendererReady)
                return
            var path = root.pendingLoadPath
            root.pendingLoadPath = ""
            loadWhenReadyTimer.stop()
            root.loadPathNow(path)
        }
    }
    Timer {
        id: forcePlayTimer
        interval: 300
        repeat: false
        onTriggered: {
            video.command(["set", "pause", "no"])
            root.isPlaying = true
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // MPV SURFACE
    // ─────────────────────────────────────────────────────────────────────
    MpvVideo {
        id: video
        anchors.fill: root.inPlayer ? parent : undefined
        width:   root.inPlayer ? undefined : 0
        height:  root.inPlayer ? undefined : 0
        visible: root.inPlayer
        z: 0

        property double timePos:    0
        property double duration:   0
        property string videoCodec: ""
        property string audioCodec: ""
        property string resolution: ""
        property string hwdec:      ""
        property string fps:        ""

        Timer {
            interval: 500; running: root.inPlayer; repeat: true
            onTriggered: {
                video.timePos  = video.getPropertyDouble("time-pos")
                video.duration = video.getPropertyDouble("duration")
                if (video.duration > 0 && !seekBar.pressed)
                    seekBar.value = video.timePos / video.duration
                video.videoCodec = video.getPropertyString("video-codec")   || "None"
                video.audioCodec = video.getPropertyString("audio-codec")   || "None"
                root.isPlaying = (video.getPropertyString("pause") !== "yes")
                var w = video.getPropertyDouble("width")
                var h = video.getPropertyDouble("height")
                video.resolution = w > 0 ? (w + "x" + h) : "Unknown"
                video.hwdec      = video.getPropertyString("hwdec-current") || "software"
                video.fps        = video.getPropertyDouble("estimated-vf-fps").toFixed(2)
                root.currentAudioId = video.getPropertyDouble("aid")
                root.currentSubId   = video.getPropertyDouble("sid")
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // FILE DIALOG
    // ─────────────────────────────────────────────────────────────────────
    FileDialog {
        id: fileDialog
        nameFilters: ["Video Files (*.mkv *.mp4 *.avi *.webm *.mov)", "All Files (*)"]
        onAccepted: {
            var path = selectedFile.toString()
            if (path.startsWith("file:///"))
                path = Qt.platform.os === "windows" ? path.substring(8) : path.substring(7)
            root.showTitle    = path.split(/[\\\/]/).pop()
            root.episodeLabel = ""
            root.currentPage = "player"
            root.isPlaying   = true
            focusSink.forceActiveFocus()
            
            // Wait for renderer to be ready BEFORE loadfile
            if (!video.rendererReady) {
                console.warn("Player: renderer not yet ready, waiting...")
                root.pendingLoadPath = path
                loadWhenReadyTimer.start()
            } else {
                console.log("Player: renderer ready, loading file immediately")
                Qt.callLater(function() { root.loadPathNow(path) })
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // NAV SHELL
    // ─────────────────────────────────────────────────────────────────────

    // ── Rail: the primary nav on wide windows ────────────────────────────
    Item {
        id: rail
        anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
        width: root.navW
        visible: width > 0 && !root.inPlayer
        clip: true

        Behavior on width {
            NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic }
        }

        SideNav {
            anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
            currentPage: root.currentPage
            collapsed: root.railCollapsed
            onNavigate: (page) => root.currentPage = page
            onToggleRequested: root.railCollapsed = !root.railCollapsed
        }
    }

    // ── Drawer: the same rail, folded away below the tablet breakpoint ───
    Drawer {
        id: navDrawer
        parent: root.overlay
        edge: Qt.LeftEdge
        width: Math.min(240, root.width)
        height: root.height
        modal: true
        dim: true
        interactive: true
        visible: root.drawerOpen && !root.inPlayer
        padding: 0

        background: Rectangle { color: "#0a0a0a" }

        SideNav {
            anchors.fill: parent
            drawerMode: true
            currentPage: root.currentPage
            onNavigate: (page) => { root.drawerOpen = false; root.currentPage = page }
        }
    }

    TopBar {
        id: topBar
        anchors { top: parent.top; left: rail.right; right: parent.right }
        visible: !root.inPlayer
        z: 11
        compact: root.isCompact
        currentPage:  root.currentPage
        onNavLinkClicked: (page) => root.currentPage = page
        onSearchClicked:  root.currentPage = "search"
        onMenuClicked:    root.drawerOpen = !root.drawerOpen
        onProfileClicked: root.profileMenuOpen = !root.profileMenuOpen
        onNotificationsClicked: root.notifPanelOpen = !root.notifPanelOpen
        onQuerySubmitted: (text) => {
            root.searchQuery = text
            root.currentPage = "search"
        }
    }

    // ── Bottom tabs: navigation on phones ────────────────────────────────
    Item {
        id: tabBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.tabH
        visible: height > 0 && !root.inPlayer
        z: 12

        Rectangle {
            anchors.fill: parent
            color: "#0a0a0a"
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: "#1f1f1f"
            }
        }

        Row {
            anchors.fill: parent
            Repeater {
                model: [
                    { page: "home",     icon: "\uE80F", label: "Home" },
                    { page: "browse",   icon: "\uE80A", label: "Browse" },
                    { page: "mylist",   icon: "\uE71D", label: "My List" },
                    { page: "history",  icon: "\uE823", label: "Watching" },
                    { page: "settings", icon: "\uE713", label: "Settings" }
                ]
                delegate: Item {
                    id: tab
                    required property var modelData
                    width: tabBar.width / 5
                    height: tabBar.height
                    readonly property bool isActive: root.currentPage === modelData.page

                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData.label
                    Accessible.focusable: true

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.icon
                            color: tab.isActive ? "#ffffff" : "#8a8a8a"
                            font.family: Theme.iconFont
                            font.pixelSize: 17
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: tab.isActive ? "#ffffff" : "#8a8a8a"
                            font.family: Theme.bodyFont
                            font.pixelSize: 10
                            font.weight: tab.isActive ? Font.DemiBold : Font.Normal
                        }
                    }
                    Rectangle {
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                        width: 20; height: 2; radius: 1
                        color: "#ffffff"
                        visible: tab.isActive
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentPage = modelData.page
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // NOTIFICATION PANEL
    // ─────────────────────────────────────────────────────────────────────

    // Outside-click dismissal — sits below the panel (z:49) so clicks on the
    // panel itself are not captured by this area.
    MouseArea {
        anchors.fill: parent
        z: 49
        enabled: root.notifPanelOpen
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (!notifPanel.contains(notifPanel.mapFromItem(null, mouse.x, mouse.y)))
                root.notifPanelOpen = false
            mouse.accepted = false
        }
    }

    NotificationPanel {
        id: notifPanel
        z: 50
        panelOpen: root.notifPanelOpen
        onCloseRequested: root.notifPanelOpen = false

        // Position: just below the TopBar, right-aligned to the notification icon
        anchors.top:        topBar.bottom
        anchors.topMargin:  8
        // Right-align the panel to the notification icon right edge.
        // topBar.notifIconCenter gives the icon centre in window coords; we
        // shift right by half the icon width (18px) to get the icon right edge,
        // then subtract the panel width to right-align it.
        x: Math.min(
               topBar.notifIconCenter.x + 18 - width,
               root.width - width - 8
           )
    }

    // Page canvas
    Item {
        id: pageCanvas
        anchors {
            top:    topBar.bottom
            left:   rail.right
            right:  parent.right
            bottom: tabBar.top
        }
        visible: !root.inPlayer
        z: 5

        // One animatable surface for every page. The Loaders keep
        // anchors.fill: parent, so the page transition lives here alone.
        // Sized by binding rather than anchored so x is free to animate.
        Item {
            id: pageStage
            width: pageCanvas.width
            height: pageCanvas.height

            ParallelAnimation {
                id: pageIn
                NumberAnimation { target: pageStage; property: "opacity"
                                  from: 0.0; to: 1.0
                                  duration: Theme.dBase; easing.type: Theme.easeOutCubic }
                NumberAnimation { target: pageStage; property: "x"
                                  from: Theme.s6; to: 0
                                  duration: Theme.dBase; easing.type: Theme.easeOutCubic }
            }
        }


        Loader {
            id: homeLoader
            anchors.fill: parent
            active: root.currentPage === "home"
            source: active ? "pages/HomePage.qml" : ""
            onLoaded: {
                if (!item || !item.playRequested || !item.addToListRequested || !item.seriesClicked)
                    return
                item.playRequested.connect(function(anilistId, titleStr) {
                    root.showTitle = titleStr
                    fileDialog.open()   // TODO: resolve stream URL for anilistId
                })
                item.addToListRequested.connect(function(anilistId) {
                    if (!authManager || !authManager.authenticated) {
                        root.notify("Sign in to keep a list.", "error")
                        return
                    }
                    authManager.addToLibrary({ "anilist_id": anilistId })
                    root.notify("Added to My List", "success")
                })
                item.seriesClicked.connect(function(anilistId) {
                    root.currentSeriesId = anilistId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })
                if (item.continueWatchingRequested)
                    item.continueWatchingRequested.connect(function() {
                        root.previousPage = root.currentPage
                        root.currentPage = "history"
                    })
                if (item.trendingSeeAllRequested) {
                    item.trendingSeeAllRequested.connect(function() {
                        root.previousPage = root.currentPage
                        root.currentPage = "trending"
                    })
                }
            }
        }
        Loader {
            id: trendingLoader
            anchors.fill: parent
            active: root.currentPage === "trending"
            source: active ? "pages/TrendingPage.qml" : ""
            onLoaded: {
                if (!item || !item.playRequested || !item.addToListRequested || !item.seriesClicked)
                    return
                item.playRequested.connect(function(anilistId, titleStr) {
                    root.showTitle = titleStr
                    fileDialog.open()
                })
                item.addToListRequested.connect(function(anilistId) {
                    if (!authManager || !authManager.authenticated) {
                        root.notify("Sign in to keep a list.", "error")
                        return
                    }
                    authManager.addToLibrary({ "anilist_id": anilistId })
                    root.notify("Added to My List", "success")
                })
                item.seriesClicked.connect(function(anilistId) {
                    root.currentSeriesId = anilistId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })
            }
        }
        Loader {
            id: browseLoader
            anchors.fill: parent
            active: root.currentPage === "browse"
            source: active ? "pages/BrowsePage.qml" : ""
            onLoaded: {
                if (!item || !item.seriesClicked)
                    return
                item.seriesClicked.connect(function(seriesId) {
                    root.currentSeriesId = seriesId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })
            }
        }
        Loader {
            id: simulcastLoader
            anchors.fill: parent
            active: root.currentPage === "simulcast"
            source: active ? "pages/SimulcastPage.qml" : ""
            onLoaded: {
                if (!item || !item.showSelected)
                    return
                item.showSelected.connect(function(showId, showTitle) {
                    root.currentCloudShowId = showId
                    root.currentCloudShowTitle = showTitle
                    root.previousPage = root.currentPage
                    root.currentPage = "simulcastDetail"
                })
            }
        }
        Loader {
            id: simulcastDetailLoader
            anchors.fill: parent
            active: root.currentPage === "simulcastDetail"
            source: active ? "pages/SimulcastDetailPage.qml" : ""
            onLoaded: {
                if (!item)
                    return
                item.showId = root.currentCloudShowId
                item.showTitle = root.currentCloudShowTitle
                if (item.backRequested) {
                    item.backRequested.connect(function() {
                        root.currentPage = "simulcast"
                    })
                }
                if (item.playEpisodeRequested) {
                    item.playEpisodeRequested.connect(function(streamUrl, titleStr, epLabel) {
                        root.playStreamNow(streamUrl, titleStr, epLabel)
                    })
                }
            }
        }
        Loader {
            id: detailLoader
            anchors.fill: parent
            active: root.currentPage === "detail"
            source: active ? "pages/DetailPage.qml" : ""
            onLoaded: {
                if (!item || !item.backRequested || !item.playRequested || !item.addToListRequested)
                    return
                item.seriesId = root.currentSeriesId
                item.backRequested.connect(function() {
                    root.currentPage = root.previousPage || "home"
                })
                item.playRequested.connect(function(anilistId, titleStr) {
                    root.showTitle = titleStr
                    fileDialog.open()
                })
                item.addToListRequested.connect(function(anilistId) {
                    if (!authManager || !authManager.authenticated) {
                        root.notify("Sign in to keep a list.", "error")
                        return
                    }
                    authManager.addToLibrary({ "anilist_id": anilistId })
                    root.notify("Added to My List", "success")
                })
                if (item.episodePlayRequested) {
                    item.episodePlayRequested.connect(function(url, titleStr, epLabel, thumb) {
                        root.playStreamNow(url, titleStr, epLabel, thumb)
                    })
                }
            }
        }
        Loader {
            id: mylistLoader
            anchors.fill: parent
            active: root.currentPage === "mylist"
            source: active ? "pages/MyListPage.qml" : ""
            onLoaded: {
                if (!item || !item.seriesSelected)
                    return
                item.seriesSelected.connect(function(showId) {
                    root.currentSeriesId = showId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })

                if (item.browseRequested)
                    item.browseRequested.connect(function() { root.currentPage = "browse" })
            }
        }
        Loader {
            id: historyLoader
            anchors.fill: parent
            active: root.currentPage === "history"
            source: active ? "pages/HistoryPage.qml" : ""
            onLoaded: {
                if (!item || !item.seriesSelected)
                    return
                item.seriesSelected.connect(function(anilistId) {
                    root.currentSeriesId = anilistId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })

                if (item.browseRequested)
                    item.browseRequested.connect(function() { root.currentPage = "browse" })
            }
        }
        Loader {
            anchors.fill: parent
            active: root.currentPage === "settings"
            source: active ? "pages/SettingsPage.qml" : ""
        }
        Loader {
            id: searchLoader
            anchors.fill: parent
            active: root.currentPage === "search"
            source: active ? "pages/SearchPage.qml" : ""
            onLoaded: {
                if (!item || !item.seriesClicked) return
                if (item.initialQuery !== undefined) item.initialQuery = root.searchQuery
                item.seriesClicked.connect(function(anilistId) {
                    root.currentSeriesId = anilistId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })
            }
        }

    }

    component PlaceholderPage: Item {
        property string pageTitle: ""
        Rectangle {
            anchors.fill: parent
            color: "#131313"
            Column {
                anchors.centerIn: parent
                spacing: 12
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pageTitle
                    color: "#2a2a2a"
                    font { family: root.displayFont; pixelSize: 48; weight: Font.Black }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Page coming soon"
                    color: "#201f1f"
                    font { family: root.bodyFont; pixelSize: 16 }
                }
            }
        }
    }

    Rectangle {
        visible: root.authErrorText.length > 0 && !root.inPlayer
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        z: 100
        radius: 8
        color: "#402020"
        border.color: "#a05050"
        border.width: 1
        implicitWidth: Math.min(parent.width - 40, errText.implicitWidth + 24)
        height: errText.implicitHeight + 16

        Text {
            id: errText
            anchors.centerIn: parent
            text: root.authErrorText
            color: "#ffd5d5"
            font.pixelSize: 13
            wrapMode: Text.Wrap
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // PLAYER CHROME
    // ─────────────────────────────────────────────────────────────────────

    Item {
        id: focusSink
        anchors.fill: parent
        focus: root.inPlayer
        visible: root.inPlayer
        z: 1

        MouseArea {
            anchors.fill: parent
            anchors.topMargin:    root.topH
            anchors.bottomMargin: root.barH + 36
            onClicked: {
                if (trackPanel.visible) { trackPanel.visible = false; return }
                video.command(["cycle", "pause"])
                root.isPlaying = !root.isPlaying
                playFlash.show()
            }
            onDoubleClicked: {
                root.visibility === Window.FullScreen ? root.showNormal() : root.showFullScreen()
            }
        }

        Keys.onPressed: function(ev) {
            if (ev.key === Qt.Key_Space) {
                video.command(["cycle","pause"])
                root.isPlaying = !root.isPlaying
                playFlash.show()
                ev.accepted = true
            } else if (ev.key === Qt.Key_F || ev.key === Qt.Key_F11) {
                root.visibility === Window.FullScreen ? root.showNormal() : root.showFullScreen()
                ev.accepted = true
            } else if (ev.key === Qt.Key_Right) {
                video.command(["seek", "10"]); ev.accepted = true
            } else if (ev.key === Qt.Key_Left) {
                video.command(["seek", "-10"]); ev.accepted = true
            } else if (ev.key === Qt.Key_Up) {
                volSlider.value = Math.min(1, volSlider.value + 0.05)
                video.command(["set","volume",(volSlider.value*100).toFixed(0)])
                ev.accepted = true
            } else if (ev.key === Qt.Key_Down) {
                volSlider.value = Math.max(0, volSlider.value - 0.05)
                video.command(["set","volume",(volSlider.value*100).toFixed(0)])
                ev.accepted = true
            } else if (ev.key === Qt.Key_M) {
                video.command(["cycle","mute"]); ev.accepted = true
            } else if (ev.key === Qt.Key_O) {
                fileDialog.open(); ev.accepted = true
            } else if (ev.key === Qt.Key_Escape && root.episodePanelOpen) {
                root.episodePanelOpen = false
                ev.accepted = true
            } else if (ev.key === Qt.Key_Escape) {
                if (root.visibility === Window.FullScreen) root.showNormal()
                else root.stopPlaybackAndExit("home")
                ev.accepted = true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        visible: root.inPlayer
        z: 1
        onPositionChanged: hideTimer.restart()
    }

    // An open episode list is an explicit request, so it holds the chrome up
    // even after the pointer has been still long enough to hide it.
    property bool pointerOnChrome: false
    readonly property bool chromeVisible: root.inPlayer
            && (root.episodePanelOpen || root.pointerOnChrome || hideTimer.running)

    // Play flash
    Rectangle {
        id: playFlash
        anchors.centerIn: parent
        width: 80; height: 80; radius: 40
        color: "#99000000"; visible: false; z: 5
        Text {
            anchors.centerIn: parent
            text: root.isPlaying ? "\uE103" : "\uE102"
            font.family: root.iconFont
            color: "white"; font.pixelSize: 34
        }
        function show() { visible = true; pfAnim.restart() }
        SequentialAnimation on opacity {
            id: pfAnim; running: false
            NumberAnimation { to: 1.0; duration: 70 }
            PauseAnimation  { duration: 260 }
            NumberAnimation { to: 0.0; duration: 360 }
            onFinished: playFlash.visible = false
        }
    }

    // Skip Intro
    Rectangle {
        id: skipIntroBtn
        anchors.right: parent.right; anchors.bottom: playerBottomBar.top
        anchors.rightMargin: 24; anchors.bottomMargin: 16
        width: skipRow.implicitWidth + 28; height: 40; radius: 8
        color: skipMa.containsMouse ? "#CC2A2A2A" : "#BB1A1A1A"
        border.color: "#55FFFFFF"; border.width: 1
        visible: false; z: 6
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            id: skipRow; anchors.centerIn: parent; spacing: 8
            Text { text: "\uE101"; color: "white"; font.pixelSize: 15; font.family: root.iconFont; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Skip Intro"; color: "white"; font.pixelSize: 14; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: skipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: skipIntroBtn.visible = false }
    }

    // Track panel
    Rectangle {
        id: trackPanel
        anchors.right: parent.right; anchors.bottom: playerBottomBar.top
        anchors.rightMargin: 16; anchors.bottomMargin: 8
        width: 440
        height: Math.min(tpRow.implicitHeight + 28, root.height - root.barH - root.topH - 40)
        color: "#EE0D0D0D"; radius: 12; border.color: "#22FFFFFF"; border.width: 1
        visible: false; z: 10; clip: true
        MouseArea { anchors.fill: parent; onClicked: {} }
        RowLayout {
            id: tpRow
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            spacing: 0
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                Label { text: "Audio"; color: "white"; font.pixelSize: 14; font.bold: true; bottomPadding: 8; topPadding: 4 }
                Repeater {
                    model: root.audioTracks
                    delegate: Item {
                        property var td: modelData
                        Layout.fillWidth: true; width: tpRow.width / 2 - 22; height: 44
                        Rectangle { anchors.fill: parent; radius: 6; color: root.currentAudioId === td.id ? "#22FFFFFF" : (ama.containsMouse ? "#11FFFFFF" : "transparent") }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8
                            Label { text: td.label; color: root.currentAudioId === td.id ? "white" : "#BBBBBB"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: root.currentAudioId === td.id ? root.accentOrange : "transparent"
                                border.color: root.currentAudioId === td.id ? root.accentOrange : "#555555"; border.width: 2
                                Label { anchors.centerIn: parent; text: "\u2713"; color: "white"; font.pixelSize: 11; font.bold: true; visible: root.currentAudioId === td.id }
                            }
                        }
                        MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { video.command(["set","aid", td.id.toString()]); root.currentAudioId = td.id } }
                    }
                }
            }
            Rectangle { width: 1; Layout.fillHeight: true; color: "#33FFFFFF"; Layout.leftMargin: 8; Layout.rightMargin: 8 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                Label { text: "Subtitles / CC"; color: "white"; font.pixelSize: 14; font.bold: true; bottomPadding: 8; topPadding: 4 }
                Repeater {
                    model: root.subtitleTracks
                    delegate: Item {
                        property var td: modelData
                        Layout.fillWidth: true; width: tpRow.width / 2 - 22; height: 44
                        Rectangle { anchors.fill: parent; radius: 6; color: root.currentSubId === td.id ? "#22FFFFFF" : (sma.containsMouse ? "#11FFFFFF" : "transparent") }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8
                            Label { text: td.label; color: root.currentSubId === td.id ? "white" : "#BBBBBB"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: root.currentSubId === td.id ? root.accentOrange : "transparent"
                                border.color: root.currentSubId === td.id ? root.accentOrange : "#555555"; border.width: 2
                                Label { anchors.centerIn: parent; text: "\u2713"; color: "white"; font.pixelSize: 11; font.bold: true; visible: root.currentSubId === td.id }
                            }
                        }
                        MouseArea {
                            id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (td.id === 0) { video.command(["set","sid","no"]); root.currentSubId = 0 }
                                else { video.command(["set","sid", td.id.toString()]); root.currentSubId = td.id }
                            }
                        }
                    }
                }
            }
        }
    }

    // Playback info panel
    Rectangle {
        id: infoPanel
        anchors.top: playerTopBar.bottom; anchors.right: parent.right; anchors.margins: 16
        width: 260; radius: 10; color: "#CC0D0D0D"; border.color: "#22FFFFFF"; border.width: 1
        visible: false; z: 8; height: infoCol.implicitHeight + 24
        ColumnLayout {
            id: infoCol
            anchors { fill: parent; margins: 12 }
            spacing: 5
            Label { text: "Playback Info"; font.bold: true; font.pixelSize: 13; color: root.clrPrimary; font.family: root.displayFont }
            Rectangle { height: 1; Layout.fillWidth: true; color: "#33FFFFFF" }
            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 3
                Label { text: "Video:";  color: root.clrMuted; font.pixelSize: 12 } Label { text: video.videoCodec; color: "white"; font.pixelSize: 12 }
                Label { text: "Audio:";  color: root.clrMuted; font.pixelSize: 12 } Label { text: video.audioCodec; color: "white"; font.pixelSize: 12 }
                Label { text: "Res:";    color: root.clrMuted; font.pixelSize: 12 } Label { text: video.resolution; color: "white"; font.pixelSize: 12 }
                Label { text: "FPS:";    color: root.clrMuted; font.pixelSize: 12 } Label { text: video.fps;        color: "white"; font.pixelSize: 12 }
                Label { text: "HWDec:"; color: root.clrMuted; font.pixelSize: 12 } Label { text: video.hwdec;      color: "white"; font.pixelSize: 12 }
            }
        }
    }

    // Player top bar
    Rectangle {
        id: playerTopBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.topH; z: 7; color: "transparent"
        visible: root.inPlayer
        opacity: root.chromeVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: topBarHover
            onHoveredChanged: root.pointerOnChrome = topBarHover.hovered || botBarHover.hovered
        }

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#CC000000" }
            GradientStop { position: 0.7; color: "#55000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: root.chromeVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        Rectangle {
            id: backBtn
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
            width: 36; height: 36; radius: 18
            color: backMa.containsMouse ? "#33FFFFFF" : "#14000000"
            border.color: "#33FFFFFF"; border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: backMa.pressed ? 0.85 : 1.0
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
            Text { anchors.centerIn: parent; text: "\u2190"; color: "white"; font.pixelSize: 18 }
            MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.stopPlaybackAndExit("home") }
        }

        Column {
            anchors { left: backBtn.right; verticalCenter: parent.verticalCenter; leftMargin: 12 }
            spacing: 2
            Text { text: root.showTitle;    color: "white"; font.pixelSize: 17; font.bold: true; elide: Text.ElideRight; width: Math.min(implicitWidth, root.width - 260); font.family: root.displayFont }
            Text { text: root.episodeLabel; color: root.clrMuted; font.pixelSize: 11; font.letterSpacing: 1.2; visible: root.episodeLabel !== "" }
        }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 20 }
            spacing: 8
            Rectangle {
                width: 36; height: 36; radius: 18; color: iMa.containsMouse ? "#33FFFFFF" : "#14000000"
                border.color: "#33FFFFFF"; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: "\u2139"; color: "white"; font.pixelSize: 15 }
                MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: infoPanel.visible = !infoPanel.visible }
            }
            Rectangle {
                width: 36; height: 36; radius: 18; color: fMa.containsMouse ? "#33FFFFFF" : "#14000000"
                border.color: "#33FFFFFF"; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: "\u22ef"; color: "white"; font.pixelSize: 20 }
                MouseArea { id: fMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fileDialog.open() }
            }
        }
    }

    // Player bottom bar
    Item {
        id: playerBottomBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.barH + 36; z: 7
        visible: root.inPlayer
        opacity: root.chromeVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.3; color: "#88000000" }
                GradientStop { position: 1.0; color: "#EE000000" }
            }
        }

        // Seek row
        Item {
            id: seekRow
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 8; leftMargin: 20; rightMargin: 20 }
            height: 28
            Text { id: curTimeLabel; anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                   text: root.fmtTime(video.timePos); color: "white"; font.pixelSize: 13; font.bold: true }
            Text { id: totTimeLabel; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                   text: root.fmtTime(video.duration); color: root.clrMuted; font.pixelSize: 13 }
            Item {
                anchors { left: curTimeLabel.right; right: totTimeLabel.left; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                height: 28
                Rectangle { id: seekBg; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#44FFFFFF" }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; anchors.left: seekBg.left
                    width: seekBar.value * seekBg.width; height: 4; radius: 2
                    color: "#f5f5f5"
                }
                Slider {
                    id: seekBar
                    anchors.fill: parent; from: 0; to: 1; value: 0
                    background: Item {}
                    handle: Rectangle {
                        x: seekBar.leftPadding + seekBar.visualPosition * (seekBar.availableWidth - width)
                        y: seekBar.topPadding + seekBar.availableHeight / 2 - height / 2
                        width:  (seekBar.pressed || seekHov.hovered) ? 16 : 0
                        height: width; radius: width / 2; color: "white"
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    onMoved: { if (video.duration > 0) video.command(["seek", (value * video.duration).toFixed(2), "absolute"]) }
                }
                HoverHandler { id: seekHov }
            }
        }

        // Buttons row
        Item {
            anchors { top: seekRow.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 4 }

            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                spacing: 4; z: 10

                // Play/Pause
                Rectangle {
                    id: btnPlay
                    width: 48; height: 48; radius: 24
                    color: playMa.containsMouse ? "#FAFAFA" : "#FFFFFF"
                    scale: playMa.pressed ? 0.88 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor:   Qt.rgba(0, 0, 0, 0.55)
                        shadowBlur:    0.9
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset:   2
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.isPlaying ? "\uE103" : "\uE102"
                        color: "#111111"; font.pixelSize: 17
                        font.family: root.iconFont
                    }
                    MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { video.command(["cycle","pause"]); root.isPlaying = !root.isPlaying } }
                }

                PlayerIconBtn { glyph: "\uE100"; glyphIcon: true; tip: "Previous Episode"; onClicked: {} }
                PlayerIconBtn { glyph: "\uE101"; glyphIcon: true; tip: "Next Episode";     onClicked: {} }

                // Volume (to the right of forward button)
                Item {
                    width: 170; height: 36; anchors.verticalCenter: parent.verticalCenter
                    PlayerIconBtn {
                        id: volBtn
                        width: 36
                        height: 36
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: volSlider.value === 0 ? "\uE74F" : "\uE767"; glyphIcon: true
                        onClicked: {
                            if (volSlider.value > 0) {
                                volSlider.value = 0
                            } else {
                                volSlider.value = 0.5
                            }
                        }
                    }
                    Item {
                        id: volSlider
                        anchors.left: volBtn.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        height: 20
                        property real value: 0.5

                        function clamp(v) { return Math.max(0, Math.min(1, v)) }
                        function setFromX(xpos) {
                            value = clamp(xpos / Math.max(1, track.width))
                        }
                        onValueChanged: video.command(["set","volume",(value * 100).toFixed(0)])

                        Rectangle {
                            id: track
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            radius: 3
                            color: "#55FFFFFF"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * volSlider.value
                                height: parent.height
                                radius: parent.radius
                                color: "#ffffff"
                            }
                        }

                        Rectangle {
                            width: 14
                            height: 14
                            radius: 7
                            color: "#f6f6f6"
                            border.color: "#202020"
                            border.width: 1
                            x: Math.max(0, Math.min(track.width - width, track.width * volSlider.value - width / 2))
                            y: track.y + track.height / 2 - height / 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: volSlider.setFromX(mouse.x)
                            onPositionChanged: if (pressed) volSlider.setFromX(mouse.x)
                            onWheel: function(wheel) {
                                var delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                                volSlider.value = volSlider.clamp(volSlider.value + delta)
                                wheel.accepted = true
                            }
                        }
                    }
                }
            }

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 }
                spacing: 6

                // Quality — only appears when the source really has several
                // video tracks, so it is never a control that does nothing.
                Rectangle {
                    id: qualityBtn
                    visible: root.videoTracks.length > 1
                    width: qRow.implicitWidth + 20; height: 32; radius: 6
                    color: qMa.containsMouse ? Qt.rgba(1,1,1,0.16) : Qt.rgba(1,1,1,0.08)
                    border.color: qualityBtn.activeFocus ? "#ffffff" : "transparent"
                    border.width: 1
                    activeFocusOnTab: true
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: qRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Quality"
                            color: "#ffffff"
                            font.family: root.bodyFont; font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uE70D"
                            color: "#b3b3b3"
                            font.family: root.iconFont; font.pixelSize: 9
                        }
                    }
                    MouseArea {
                        id: qMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { qualityBtn.forceActiveFocus(); qualityMenu.open() }
                    }
                    Menu {
                        id: qualityMenu
                        title: "Quality"
                        Repeater {
                            model: root.videoTracks
                            MenuItem {
                                required property var modelData
                                text: modelData.label
                                onTriggered: {
                                    root.refreshTracks()
                                    video.command(["set", "vid", modelData.id.toString()])
                                }
                            }
                        }
                    }
                }

                PlayerIconBtn {
                    glyph: "CC"; tip: "Subtitles / CC"
                    onClicked: { if (!trackPanel.visible) { root.refreshTracks(); trackPanel.visible = true } else trackPanel.visible = false }
                }

                Rectangle {
                    width: langRow.implicitWidth + 16; height: 32; radius: 6
                    color: langMa.containsMouse ? "#33FFFFFF" : "#22FFFFFF"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row { id: langRow; anchors.centerIn: parent; spacing: 4
                        Text { text: "EN"; color: "white"; font.pixelSize: 13; font.bold: true } }
                    MouseArea { id: langMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.refreshTracks(); trackPanel.visible = !trackPanel.visible } }
                }

                Rectangle {
                    width: 36; height: 36; radius: 18; color: settMa.containsMouse ? "#33FFFFFF" : "#14000000"
                    border.color: "#33FFFFFF"; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "\u2699"; color: "white"; font.pixelSize: 16 }
                    MouseArea { id: settMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: speedMenu.open() }
                    Menu {
                        id: speedMenu
                        readonly property var spd: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                        readonly property var lbl: ["0.25\u00d7","0.5\u00d7","0.75\u00d7","1\u00d7","1.25\u00d7","1.5\u00d7","2\u00d7"]
                        title: "Playback Speed"
                        Repeater {
                            model: speedMenu.lbl
                            MenuItem { text: modelData; onTriggered: video.command(["set","speed", speedMenu.spd[index].toString()]) }
                        }
                    }
                }

                Rectangle {
                    width: epRow.implicitWidth + 20; height: 36; radius: 8
                    color: epMa.containsMouse ? "#55FFFFFF" : "#33FFFFFF"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row { id: epRow; anchors.centerIn: parent; spacing: 6
                        Text { text: "\uE8FD"; font.family: root.iconFont; color: "white"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Episodes"; color: "white"; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: epMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.episodePanelOpen = !root.episodePanelOpen }
                }

                Rectangle {
                    width: 36; height: 36; radius: 18; color: fsMa.containsMouse ? "#33FFFFFF" : "#14000000"
                    border.color: "#33FFFFFF"; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                    scale: fsMa.pressed ? 0.88 : 1.0; Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
                    Text { anchors.centerIn: parent; text: root.visibility === Window.FullScreen ? "\uE73F" : "\uE740"; font.family: root.iconFont; color: "white"; font.pixelSize: 14 }
                    MouseArea { id: fsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.visibility === Window.FullScreen ? root.showNormal() : root.showFullScreen() }
                }
            }
        }
    }

    component PlayerIconBtn: Item {
        id: pib
        width: 36; height: 36
        property string glyph: ""
        property bool   glyphIcon: false
        property string tip:   ""
        signal clicked()
        Rectangle {
            anchors.fill: parent; radius: 18
            color: pibMa.containsMouse ? "#33FFFFFF" : "#14000000"
            border.color: "#33FFFFFF"; border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
            anchors.centerIn: parent
            text: pib.glyph
            color: "white"
            font.pixelSize: 14
            font.family: pib.glyphIcon ? root.iconFont : root.bodyFont
        }
        MouseArea { id: pibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pib.clicked() }
        ToolTip.text: pib.tip; ToolTip.visible: pibMa.containsMouse && pib.tip !== ""
    }

    // ─────────────────────────────────────────────────────────────────────
    // SEARCH PAGE is now loaded via pageCanvas/searchLoader (see above).
    // The old SearchOverlay modal is no longer used.
    // ─────────────────────────────────────────────────────────────────────

    // ── Splash ──────────────────────────────────────────────────────────
    // Shown once while the first requests are in flight, then it lifts away.
    Rectangle {
        id: splash
        anchors.fill: parent
        z: 90
        color: Theme.bg
        visible: opacity > 0.001
        opacity: 1.0

        Column {
            anchors.centerIn: parent
            spacing: Theme.s5

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76; height: 76; radius: Theme.rXl
                color: Theme.card
                border.color: Theme.borderDefault; border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "\uE768"
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: 30
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.s2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Animind"
                    color: Theme.textPrimary
                    font.family: Theme.displayFont
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Your anime, anytime"
                    color: Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.tsBody
                }
            }
        }

        Text {
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: Theme.s10 }
            text: "Built with Qt / QML"
            color: Theme.textMuted
            font.family: Theme.bodyFont
            font.pixelSize: Theme.tsSmall
            font.letterSpacing: Theme.trackingWide
        }

        // A short hold, then a fade. Long enough to register, short enough that
        // nobody watches it.
        SequentialAnimation {
            id: splashOut
            running: false
            PauseAnimation { duration: 900 }
            NumberAnimation { target: splash; property: "opacity"; to: 0.0
                              duration: Theme.dSlow; easing.type: Theme.easeOutCubic }
        }
    }

    // ── Profile menu ────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 54
        enabled: root.profileMenuOpen
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (!profileMenu.contains(profileMenu.mapFromItem(null, mouse.x, mouse.y)))
                root.profileMenuOpen = false
            mouse.accepted = false
        }
    }

    Loader {
        id: profileMenu
        z: 55
        active: root.profileMenuOpen && !root.inPlayer
        sourceComponent: profileMenuComponent
        anchors.top: topBar.bottom
        anchors.topMargin: Theme.s2
        x: root.width - width - Theme.s5
    }

    Component {
        id: profileMenuComponent
        ProfileMenu {
            authenticated: authManager ? authManager.authenticated : false
            displayName: root.accountDisplayName
            detail: authManager && authManager.email ? authManager.email : ""
            onSettingsRequested:   { root.profileMenuOpen = false; root.currentPage = "settings" }
            onMyListRequested:     { root.profileMenuOpen = false; root.currentPage = "mylist" }
            onSignInOutRequested: function(signingIn) {
                root.profileMenuOpen = false
                if (!authManager) return
                if (signingIn) authManager.signInWithBrowserBridge()
                else { authManager.signOut(); root.notify("Signed out") }
            }
        }
    }

    readonly property string accountDisplayName: {
        if (!authManager || !authManager.authenticated) return "Guest"
        var em = authManager.email || ""
        if (em.indexOf("@") !== -1 && em.substring(0, em.indexOf("@")).length > 0)
            return em.substring(0, em.indexOf("@"))
        var uid = (authManager.userId || "").replace("user_", "")
        return uid.length > 0 ? uid : "You"
    }

    // ── Toast stack ─────────────────────────────────────────────────────
    Column {
        id: toastLayer
        z: 60
        anchors { right: parent.right; rightMargin: Theme.s5; bottom: parent.bottom; bottomMargin: root.tabH + Theme.s5 }
        spacing: Theme.s2
        visible: !root.inPlayer

        Repeater {
            model: root.toasts
            delegate: Toast {
                required property var modelData
                width: Math.min(360, implicitWidth)
                message: modelData.message
                kind: modelData.kind
                onFinished: root.dismissToast(modelData.id)
            }
        }
    }

    // ── Episode sidebar (watch page) ────────────────────────────────────
    EpisodeSidebar {
        id: episodeSidebar
        anchors.fill: parent
        visible: root.inPlayer
        open: root.inPlayer && root.episodePanelOpen
        calm: root.reduceMotion
        episodes: root.playerEpisodes
        seriesTitle: root.showTitle
        currentIndex: {
            for (var i = 0; i < root.playerEpisodes.length; i++) {
                var e = root.playerEpisodes[i]
                if (e && e.url && e.url === root.mediaUrl) return i
            }
            return -1
        }
        onDismissed: root.episodePanelOpen = false
        onEpisodePicked: (url, title, label, thumb) => {
            root.playStreamNow(url, title, label, thumb)
            root.episodePanelOpen = false
        }
    }

    // Closes the NotificationPanel (or SearchOverlay) when Escape is pressed
    // outside of the player. The player's own Escape handling lives in focusSink
    // (which is only active/focused when inPlayer is true).
    // ─────────────────────────────────────────────────────────────────────
    Shortcut {
        sequence: "Escape"
        enabled: !root.inPlayer
        onActivated: {
            if (root.notifPanelOpen) {
                root.notifPanelOpen = false
            } else if (root.profileMenuOpen) {
                root.profileMenuOpen = false
            } else if (root.drawerOpen) {
                root.drawerOpen = false
            } else if (root.currentPage !== "home") {
                root.currentPage = root.previousPage || "home"
            }
        }
    }

    // Search is the one action worth a chord on a desktop app.
    Shortcut {
        sequence: "Ctrl+K"
        enabled: !root.inPlayer
        onActivated: root.goSearch()
    }
    Shortcut {
        sequence: "Ctrl+F"
        enabled: !root.inPlayer
        onActivated: root.goSearch()
    }

    Shortcut {
        sequence: "Ctrl+B"
        enabled: !root.inPlayer && !root.isCompact
        onActivated: root.railCollapsed = !root.railCollapsed
    }

    // Reuses the existing detail query; the sidebar shows whatever
    // streamingEpisodes the API lists for this id. Nothing here touches mpv.
    // Section 35. The shell owns the queue; each Toast runs its own hold and
    // fade and reports back, so nothing here needs per-item timers.
    function notify(message, kind) {
        toastSeq += 1
        var next = toasts.concat([{ id: toastSeq, message: message, kind: kind || "info" }])
        // Keep the stack short enough that it never covers the content it is
        // reporting on.
        toasts = next.length > 3 ? next.slice(next.length - 3) : next
    }

    function dismissToast(id) {
        toasts = toasts.filter(function(x) { return x.id !== id })
    }

    function refreshWatchHistory(force) {
        if (watchHistoryLoading) return
        if (watchHistoryLoaded && !force) return
        if (!authManager || !authManager.authenticated) {
            watchHistory = []
            watchHistoryError = ""
            return
        }
        watchHistoryLoading = true
        watchHistoryError = ""
        var xhr = new XMLHttpRequest()
        var url = supabaseUrl + "/rest/v1/watch_history"
                  + "?user_id=eq." + encodeURIComponent(authManager.userId)
                  + "&order=last_watched.desc&limit=50"
        xhr.open("GET", url, true)
        xhr.setRequestHeader("apikey", supabaseKey)
        xhr.setRequestHeader("Authorization", "Bearer " + supabaseKey)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            watchHistoryLoading = false
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    watchHistory = JSON.parse(xhr.responseText)
                    watchHistoryLoaded = true
                } catch (e) {
                    watchHistoryError = "We couldn't read your watch history."
                }
            } else {
                watchHistoryError = "We couldn't load your watch history (HTTP " + xhr.status + ")."
            }
        }
        xhr.onerror = function() {
            watchHistoryLoading = false
            watchHistoryError = "We couldn't reach the network. Check your connection."
        }
        xhr.send()
    }

    function loadPlayerEpisodes() {
        var id = root.currentSeriesId
        if (!id || id <= 0) { root.playerEpisodes = []; root.playerEpisodesFor = -1; return }
        if (root.playerEpisodesFor === id) return
        root.playerEpisodesFor = id
        AniListApi.animeDetail(id, function(media, err) {
            if (err || !media) { root.playerEpisodes = []; return }
            root.playerEpisodes = (media.streamingEpisodes || []).filter(function(e) {
                return e && e.title
            })
        })
    }

    function hideTimerRestart() { hideTimer.restart() }

    function goSearch() {
        root.currentPage = "search"
    }

    // ─────────────────────────────────────────────────────────────────────
    // STARTUP
    // ─────────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        root.motionReduced = appSettings.reduceMotion
        root.volumeDefault = appSettings.volume
        root.speedDefault  = appSettings.speed
        video.command(["set", "volume", Math.round(root.volumeDefault * 100).toString()])
        video.command(["set", "speed", root.speedDefault.toString()])
        focusSink.forceActiveFocus()
        if (root.reduceMotion)
            splash.opacity = 0.0
        else
            splashOut.start()
    }

    Connections {
        target: video
        function onRendererReadyChanged() {
            console.log("Player: video.rendererReady =", video.rendererReady)
            if (!video.rendererReady) {
                console.warn("Player: renderer not ready, deferring playback")
                return
            }
            if (root.pendingLoadPath) {
                var queuedPath = root.pendingLoadPath
                root.pendingLoadPath = ""
                Qt.callLater(function() { root.loadPathNow(queuedPath) })
            }
            if (Qt.application.arguments.length > 1) {
                var path = Qt.application.arguments[1]
                root.showTitle   = path.split(/[\\\/]/).pop()
                root.isPlaying   = true
                root.currentPage = "player"
                console.log("Player: loading file from args:", path)
                // Ensure renderer is fully initialized before loadfile
                Qt.callLater(function() {
                    root.loadPathNow(path)
                })
            }
        }
    }
}
