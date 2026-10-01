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
    color: Theme.bg

    Material.theme: Material.Dark

    // Design tokens live in Theme.qml alone; this file re-declares none.

    // ── Responsive scale ──────────────────────────────────────────────────
    // Breakpoints follow content: the sidebar stops fitting at 1024, so the bar covers below it.
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

    // Type scale straight from Theme, so the chrome and the pages can no longer disagree
    // about what a page title or a section header measures.
    readonly property real tsHero:     Theme.tsHero
    readonly property int  tsPage:     Theme.tsPage
    readonly property int  tsSection:  Theme.tsSection
    readonly property int  tsCard:     Theme.tsCardTitle
    readonly property int  tsBody:     Theme.tsBody
    readonly property int  tsMeta:     Theme.tsMeta
    readonly property int  tsSmall:    Theme.tsSmall
    readonly property real trEyebrow:  Theme.trackingEyebrow
    readonly property real trTally:    Theme.trackingWide

    readonly property int radiusCard:  Theme.rMd
    readonly property int radiusCtl:   Theme.rMd
    readonly property int minTouch:    isMobile ? 44 : 32

    // Qt 6 removed Qt.getenv(), so less-movement comes from a launch flag the harness can set.
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
    // One copy of the watch history: Home's rail and HistoryPage share it instead of each GETting.
    property var    watchHistory: []
    property bool   watchHistoryLoading: false
    property string watchHistoryError: ""
    property bool   watchHistoryLoaded: false
    property var    toasts: []
    property int    toastSeq: 0
    property int    playerEpisodesFor: -1
    // The sidebar marks the playing episode by matching its url against this.
    // It was never assigned, so the current episode was never highlighted.
    property string mediaUrl: ""
    property string previousPage: "home"
    property var currentSeriesId: 0
    property string partyEpisodeId: ""
    // ANIMIND_UI_PANEL_PROBE opens the party panel at start-up and writes a render of it
    // to ANIMIND_UI_SHOT, so the Theme.card can be inspected without a click path.
    property bool   partyPanelOpen: uiPanelProbe
    property bool   shortcutsOpen: false
    // ANIMIND_UI_AUTH_PROBE=signin|signup opens the auth sheet at start-up; it needs a click otherwise.
    property bool   authSheetOpen: uiAuthMode.length > 0
    property bool   roomCodeWatch: false   // probe latch: connect once, then host once
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
    // The chrome pill used to read "EN" no matter what was selected, which advertised a
    // subtitle track that might not exist.
    readonly property string currentSubtitleLabel: {
        if (currentSubId <= 0) return "Subs off"
        for (var i = 0; i < subtitleTracks.length; i++)
            if (subtitleTracks[i].id === currentSubId) return subtitleTracks[i].label
        return "Subs"
    }
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
    // Email local-part, else "user_"-stripped userId, else Guest/User; both truncated to 16.
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

    // Chapter markers and step buttons. mpv exposes chapter-list only as a node array, so
    // this needed the list accessor; files without chapters show neither control.
    property var chapters: []
    readonly property bool hasChapters: chapters.length > 1

    function refreshChapters() { chapters = video.getPropertyList("chapter-list") }

    function stepChapter(dir) {
        if (chapters.length < 2) return
        const target = Math.max(0, Math.min(chapters.length - 1,
                                            video.getPropertyDouble("chapter") + dir))
        video.command(["set", "chapter", target.toFixed(0)])
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

    function playStreamNow(url, titleStr, epLabel, thumbUrl, serverEpisodeId) {
        if (!url || url.length === 0)
            return
        root.showTitle = titleStr || "Animind Player"
        root.episodeLabel = epLabel || ""
        root.currentThumbnailUrl = thumbUrl || ""
        // Only a server episode can host a watch party, so every other playback path clears this.
        root.partyEpisodeId = serverEpisodeId || ""
        root.mediaUrl = url
        // The show id and episode index are assigned by the caller right after this
        // returns, so the resume lookup has to wait one turn for them to settle.
        root.resumePendingAt = -1
        root.resumeKey = ""
        Qt.callLater(function() {
            if (!authManager.authenticated || !(root.currentSeriesId > 0) || root.currentEpisodeIndex < 0)
                return
            root.resumeKey = String(root.currentSeriesId) + ":" + root.currentEpisodeIndex
            api.fetchProgress(String(root.currentSeriesId), root.currentEpisodeIndex)
        })
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
        root.recordPlayback()
        video.command(["stop"])
        root.isPlaying = false
        root.currentPage = targetPage || "home"
    }

    // ── Sleep timer ───────────────────────────────────────────────────────
    // 0 = off, -1 = stop at the end of this episode, otherwise minutes.
    property int sleepMinutes: 0
    readonly property bool sleepAtEpisodeEnd: sleepMinutes === -1

    // keep-open (libmpv 0.41) never emits END_FILE and eof-reason reads empty at the last frame,
    // so episode end is detected from properties that do update. The latch stops a double advance.
    property bool endHandled: false

    function handleFileEnd(source) {
        if (root.endHandled) return
        root.endHandled = true
        root.isPlaying = false
        if (root.sleepAtEpisodeEnd) {
            root.sleepMinutes = 0
            root.notify("Sleep timer: stopping here")
            return
        }
        if (!party.inRoom || party.isHost)
            root.stepEpisode(1)
    }

    function setSleep(minutes) {
        root.sleepMinutes = minutes
        if (minutes > 0) { sleepTimer.interval = minutes * 60000; sleepTimer.restart() }
        else sleepTimer.stop()
        root.notify(minutes > 0 ? ("Sleeping in " + minutes + " minutes")
                                : (minutes === -1 ? "Sleeping at the end of this episode"
                                                  : "Sleep timer off"))
    }

    function sleepNow() {
        // One viewer's timer must not pause the room for everyone else.
        if (party.inRoom) party.leaveRoom()
        video.command(["set", "pause", "yes"])
        root.isPlaying = false
        root.notify("Good night")
    }

    Timer { id: sleepTimer; onTriggered: root.sleepNow() }

    // mpv applies both live, and these are the two adjustments fansubs actually need.
    property real subDelay: 0
    property real subSize: 100
    property real audioDelay: 0

    function adjustAudioDelay(delta) {
        audioDelay = Math.max(-30, Math.min(30, Math.round((audioDelay + delta) * 10) / 10))
        video.setProperty("audio-delay", audioDelay)
    }

    function adjustSubDelay(delta) {
        subDelay = Math.max(-30, Math.min(30, Math.round((subDelay + delta) * 10) / 10))
        video.setProperty("sub-delay", subDelay)
    }

    function adjustSubSize(delta) {
        subSize = Math.max(50, Math.min(200, subSize + delta))
        video.setProperty("sub-font-size", subSize)
    }

    // The backend has held a resume position per (show, episode) all along and nothing
    // read it back: every episode restarted at zero.
    property real   resumePendingAt: -1
    property string resumeKey: ""

    function applyResume() {
        // Inside a room the server owns the position; resuming locally would emit a seek
        // that drags everyone else to our bookmark.
        if (party.inRoom) { root.resumePendingAt = -1; return }
        if (root.resumePendingAt <= 0 || !(video.duration > 0))
            return
        const at = root.resumePendingAt
        root.resumePendingAt = -1
        if (Math.abs(video.timePos - at) < 3)
            return
        root.seekTo(at)
        root.notify("Resumed from " + root.fmtTime(at))
    }

    Connections {
        target: api
        function onProgressLoaded(animeId, episodeIndex, timestamp) {
            if (animeId + ":" + episodeIndex !== root.resumeKey)
                return
            // Under 15 s is a mis-click and the last half-minute is the credits: resuming
            // there either hides the start or replays the ending.
            if (timestamp < 15)
                return
            root.resumePendingAt = timestamp
            root.applyResume()
        }
    }

    // History feeds the continue-watching rail; progress is the resume position in seconds.
    function recordPlayback() {
        if (!authManager || !authManager.authenticated) return
        if (!(video.duration > 0)) return
        var pct = Math.max(0, Math.min(100, Math.round(video.timePos / video.duration * 100)))
        api.putHistory({
            show_title:    root.showTitle,
            episode_label: root.episodeLabel,
            thumbnail_url: root.currentThumbnailUrl,
            anilist_id:    root.currentSeriesId,
            progress_pct:  pct
        })
        if (root.currentSeriesId > 0 && root.currentEpisodeIndex >= 0)
            api.putProgress(String(root.currentSeriesId), root.currentEpisodeIndex, video.timePos)
    }

    // Transport intents go through the party controller so the server decides when playback starts.
    function togglePlayback() {
        if (party.inRoom) {
            if (root.isPlaying) party.requestPause()
            else party.requestPlay()
        } else {
            video.command(["cycle", "pause"])
        }
        root.isPlaying = !root.isPlaying
        playFlash.show()
    }

    function seekTo(seconds) {
        const target = Math.max(0, seconds)
        if (party.inRoom) party.requestSeek(target)
        else video.command(["seek", target.toFixed(2), "absolute"])
    }

    function seekBy(delta) {
        root.seekTo((video.playbackPosition || 0) + delta)
    }

    // ── Page-change handler: save progress when navigating away from player ──
    // Programmatic navigation skips stopPlaybackAndExit, so record here too.
    // _wasInPlayer is read before the assignment commits, since the signal fires after.
    onCurrentPageChanged: {
        if (_wasInPlayer && currentPage !== "player")
            root.recordPlayback()
        // Folded into this handler: a second onCurrentPageChanged on one object is fatal.
        // Explicit animation, not a Behavior: two assignments in one turn leave it nothing to play.
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

        // Position comes from the mpv observers, so the transport moves with the clock, not a timer.
        property double timePos: playbackPosition
        property string videoCodec: ""
        property string audioCodec: ""
        property string resolution: ""
        property string hwdec:      ""
        property string fps:        ""

        onPausedChanged: root.isPlaying = !video.paused

        // The saved bookmark usually lands before the file opens; either order works
        // because both sides call the same guarded helper.
        onFileOpened: {
            root.endHandled = false
            root.refreshChapters()
            root.applyResume()
        }

        Timer {
            interval: 1000
            repeat: true
            running: root.inPlayer && video.duration > 0 && video.paused && !video.seeking
                     && video.timePos >= video.duration - 0.25
            onTriggered: root.handleFileEnd("at-end")
        }

        // keep-open leaves the last frame on screen, so the end of a file is an event the
        // chrome has to react to rather than a position that stopped changing.
        onFileFinished: function(reason) {
            if (reason !== "eof") return
            root.handleFileEnd("end-file")
        }

        // Only the information panel's diagnostics are polled, and only while it is shown.
        Timer {
            interval: 1000; running: root.inPlayer && infoPanel.visible; repeat: true
            onTriggered: {
                video.videoCodec = video.getPropertyString("video-codec")   || "None"
                video.audioCodec = video.getPropertyString("audio-codec")   || "None"
                var w = video.getPropertyDouble("width")
                var h = video.getPropertyDouble("height")
                video.resolution = w > 0 ? (w + "x" + h) : "Unknown"
                video.hwdec      = video.getPropertyString("hwdec-current") || "software"
                video.fps        = video.getPropertyDouble("estimated-vf-fps").toFixed(2)
                root.currentAudioId = video.getPropertyDouble("aid")
                root.currentSubId   = video.getPropertyDouble("sid")
            }
        }

        // The bar follows the clock, but never while the user is holding it.
        Connections {
            target: video
            function onPositionChanged() {
                if (video.duration > 0 && !seekBar.pressed)
                    seekBar.value = video.timePos / video.duration
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
        onPartyClicked:   root.partyPanelOpen = !root.partyPanelOpen
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
            // Section 25: a floating control, so it reads as glass over the
            // page instead of a slab welded to the bottom edge.
            color: Theme.glassSurface
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: Theme.glassEdge
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
                            color: tab.isActive ? Theme.chromeText : "#8a8a8a"
                            font.family: Theme.iconFont
                            font.pixelSize: 17
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: tab.isActive ? Theme.chromeText : "#8a8a8a"
                            font.family: Theme.bodyFont
                            font.pixelSize: 10
                            font.weight: tab.isActive ? Font.DemiBold : Font.Normal
                        }
                    }
                    Rectangle {
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                        width: 20; height: 2; radius: 1
                        color: Theme.chromeText
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
        // Right edge of the notification icon (centre + 18) minus the panel width, clamped to the window.
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

        // One animatable card for every page; sized by binding so x is free to animate.
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
                item.showId = Qt.binding(function() { return root.currentCloudShowId })
                item.showTitle = Qt.binding(function() { return root.currentCloudShowTitle })
                if (item.backRequested) {
                    item.backRequested.connect(function() {
                        root.currentPage = "simulcast"
                    })
                }
                if (item.playEpisodeRequested) {
                    item.playEpisodeRequested.connect(function(streamUrl, titleStr, epLabel, episodeId) {
                        root.playStreamNow(streamUrl, titleStr, epLabel, "", episodeId)
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
                if (!item)
                    return
                // A live binding, not a copy: a Loader already active never re-fires onLoaded.
                item.seriesId = Qt.binding(function() { return root.currentSeriesId })
                if (!item.backRequested || !item.playRequested || !item.addToListRequested)
                    return
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
                if (item.initialQuery !== undefined) {
                    // Live, like the detail id: copied once, search could not reach an open page.
                    item.initialQuery = Qt.binding(function() { return root.searchQuery })
                }
                item.seriesClicked.connect(function(anilistId) {
                    root.currentSeriesId = anilistId
                    root.previousPage = root.currentPage
                    root.currentPage = "detail"
                })
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
        // width, not the default-zero implicitWidth, or the pill collapses on its own error.
        width: Math.min(parent.width - 40, errText.implicitWidth + 24)
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
                root.togglePlayback()
            }
            onDoubleClicked: {
                root.visibility === Window.FullScreen ? root.showNormal() : root.showFullScreen()
            }
        }

        Keys.onPressed: function(ev) {
            if (ev.key === Qt.Key_Space) {
                root.togglePlayback()
                ev.accepted = true
            } else if (ev.key === Qt.Key_F || ev.key === Qt.Key_F11) {
                root.visibility === Window.FullScreen ? root.showNormal() : root.showFullScreen()
                ev.accepted = true
            } else if (ev.key === Qt.Key_Right) {
                root.seekBy(10); ev.accepted = true
            } else if (ev.key === Qt.Key_Left) {
                root.seekBy(-10); ev.accepted = true
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
            } else if (ev.key === Qt.Key_BracketLeft) {
                if (root.hasChapters) root.stepChapter(-1)
                ev.accepted = true
            } else if (ev.key === Qt.Key_BracketRight) {
                if (root.hasChapters) root.stepChapter(1)
                ev.accepted = true
            } else if (ev.key === Qt.Key_QuestionMark) {
                root.shortcutsOpen = !root.shortcutsOpen
                ev.accepted = true
            } else if (ev.key === Qt.Key_Escape && root.shortcutsOpen) {
                root.shortcutsOpen = false
                ev.accepted = true
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
            font.family: Theme.iconFont
            color: Theme.chromeText; font.pixelSize: 34
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

    // Keyboard map. No Skip-Intro pill: the backend has no intro markers to act on.
    ShortcutOverlay {
        id: shortcuts
        open: root.shortcutsOpen && root.inPlayer
        z: 50
        onDismissed: root.shortcutsOpen = false
    }

    // Track panel
    Rectangle {
        id: trackPanel
        anchors.right: parent.right; anchors.bottom: playerBottomBar.top
        anchors.rightMargin: 16; anchors.bottomMargin: 8
        width: 440
        height: Math.min(tpRow.implicitHeight + 28, root.height - root.barH - root.topH - 40)
        color: "#EE0D0D0D"; radius: 12; border.color: Theme.chromeRest; border.width: 1
        visible: false; z: 10; clip: true
        MouseArea { anchors.fill: parent; onClicked: {} }
        RowLayout {
            id: tpRow
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            spacing: 0
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                Label { text: "Audio"; color: Theme.chromeText; font.pixelSize: 14; font.bold: true; bottomPadding: 8; topPadding: 4 }
                Repeater {
                    model: root.audioTracks
                    delegate: Item {
                        property var td: modelData
                        Layout.fillWidth: true; width: tpRow.width / 2 - 22; height: 44
                        Rectangle { anchors.fill: parent; radius: 6; color: root.currentAudioId === td.id ? Theme.chromeRest : (ama.containsMouse ? "#11FFFFFF" : "transparent") }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8
                            Label { text: td.label; color: root.currentAudioId === td.id ? Theme.chromeText : Theme.chromeTextDim; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: root.currentAudioId === td.id ? Theme.textPrimary : "transparent"
                                border.color: root.currentAudioId === td.id ? Theme.textPrimary : Theme.chromeRadio; border.width: 2
                                Label { anchors.centerIn: parent; text: "\u2713"; color: Theme.chromeText; font.pixelSize: 11; font.bold: true; visible: root.currentAudioId === td.id }
                            }
                        }
                        MouseArea { id: ama; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { video.command(["set","aid", td.id.toString()]); root.currentAudioId = td.id } }
                    }
                }

                // Audio leads or lags the lips on some fansync rips; mpv fixes it live.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8; Layout.rightMargin: 8
                    Layout.topMargin: 10
                    spacing: 6

                    Label { text: "Sync"; color: Theme.chromeTextDim; font.pixelSize: 12; Layout.preferredWidth: 44 }
                    Label {
                        Layout.fillWidth: true
                        text: (root.audioDelay >= 0 ? "+" : "") + root.audioDelay.toFixed(1) + "s"
                        color: Theme.chromeText; font.pixelSize: 12; font.bold: true
                    }
                    Repeater {
                        model: [-0.1, 0.1]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredWidth: 30; Layout.preferredHeight: 26
                            radius: 5
                            color: audMa.containsMouse ? Theme.chromeHover : "#14FFFFFF"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData < 0 ? "\u2212" : "+"
                                color: Theme.chromeText; font.pixelSize: 14; font.bold: true
                            }
                            MouseArea {
                                id: audMa
                                anchors.fill: parent
                                anchors.margins: -3
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.adjustAudioDelay(modelData)
                            }
                        }
                    }
                }
            }
            Rectangle { width: 1; Layout.fillHeight: true; color: Theme.chromeHover; Layout.leftMargin: 8; Layout.rightMargin: 8 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                Label { text: "Subtitles / CC"; color: Theme.chromeText; font.pixelSize: 14; font.bold: true; bottomPadding: 8; topPadding: 4 }
                Repeater {
                    model: root.subtitleTracks
                    delegate: Item {
                        property var td: modelData
                        Layout.fillWidth: true; width: tpRow.width / 2 - 22; height: 44
                        Rectangle { anchors.fill: parent; radius: 6; color: root.currentSubId === td.id ? Theme.chromeRest : (sma.containsMouse ? "#11FFFFFF" : "transparent") }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8
                            Label { text: td.label; color: root.currentSubId === td.id ? Theme.chromeText : Theme.chromeTextDim; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: root.currentSubId === td.id ? Theme.textPrimary : "transparent"
                                border.color: root.currentSubId === td.id ? Theme.textPrimary : Theme.chromeRadio; border.width: 2
                                Label { anchors.centerIn: parent; text: "\u2713"; color: Theme.chromeText; font.pixelSize: 11; font.bold: true; visible: root.currentSubId === td.id }
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

                // Delay and size: the two adjustments a fansub actually needs, applied by
                // mpv live rather than on the next file load.
                Repeater {
                    model: [
                        { name: "Delay", value: (root.subDelay >= 0 ? "+" : "") + root.subDelay.toFixed(1) + "s",
                          steps: [-0.1, 0.1] },
                        { name: "Size",  value: root.subSize + "%", steps: [-5, 5] }
                    ]
                    delegate: RowLayout {
                        id: subRow
                        required property var modelData
                        required property int index
                        readonly property string kind: modelData.name
                        Layout.fillWidth: true
                        Layout.leftMargin: 8; Layout.rightMargin: 8
                        Layout.topMargin: index === 0 ? 10 : 4
                        spacing: 6

                        Label { text: modelData.name; color: Theme.chromeTextDim; font.pixelSize: 12
                                Layout.preferredWidth: 44 }
                        Label { text: modelData.value; color: Theme.chromeText; font.pixelSize: 12
                                font.bold: true; Layout.fillWidth: true }

                        Repeater {
                            model: modelData.steps
                            delegate: Rectangle {
                                required property var modelData
                                Layout.preferredWidth: 30; Layout.preferredHeight: 26
                                radius: 5
                                color: stepMa.containsMouse ? Theme.chromeHover : "#14FFFFFF"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData < 0 ? "\u2212" : "+"
                                    color: Theme.chromeText; font.pixelSize: 14; font.bold: true
                                }
                                MouseArea {
                                    id: stepMa
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // subRow.kind, not modelData: this modelData is the
                                        // step amount from the inner Repeater.
                                        if (subRow.kind === "Delay") root.adjustSubDelay(modelData)
                                        else root.adjustSubSize(modelData)
                                    }
                                }
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
        width: 260; radius: 10; color: "#CC0D0D0D"; border.color: Theme.chromeRest; border.width: 1
        visible: false; z: 8; height: infoCol.implicitHeight + 24
        ColumnLayout {
            id: infoCol
            anchors { fill: parent; margins: 12 }
            spacing: 5
            Label { text: "Playback Info"; font.bold: true; font.pixelSize: 13; color: Theme.textPrimary; font.family: Theme.displayFont }
            Rectangle { height: 1; Layout.fillWidth: true; color: Theme.chromeHover }
            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 3
                Label { text: "Video:";  color: Theme.textSecondary; font.pixelSize: 12 } Label { text: video.videoCodec; color: Theme.chromeText; font.pixelSize: 12 }
                Label { text: "Audio:";  color: Theme.textSecondary; font.pixelSize: 12 } Label { text: video.audioCodec; color: Theme.chromeText; font.pixelSize: 12 }
                Label { text: "Res:";    color: Theme.textSecondary; font.pixelSize: 12 } Label { text: video.resolution; color: Theme.chromeText; font.pixelSize: 12 }
                Label { text: "FPS:";    color: Theme.textSecondary; font.pixelSize: 12 } Label { text: video.fps;        color: Theme.chromeText; font.pixelSize: 12 }
                Label { text: "HWDec:"; color: Theme.textSecondary; font.pixelSize: 12 } Label { text: video.hwdec;      color: Theme.chromeText; font.pixelSize: 12 }
            }
        }
    }

    // Player top bar
    Rectangle {
        id: playerTopBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.topH; z: 7
        // Restored: a Rectangle defaults to white, so a failed gradient would turn this white.
        color: "transparent"
        // One scrim, one fade: the opacity and its Behavior were declared twice here.
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.veil }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.33) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        visible: root.inPlayer
        opacity: root.chromeVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }

        HoverHandler {
            id: topBarHover
            onHoveredChanged: root.pointerOnChrome = topBarHover.hovered || botBarHover.hovered
        }

        // Section 25: the top overlay reads as a glass layer over the picture,
        // so its fade uses the shared duration and easing tokens.

        Rectangle {
            id: backBtn
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
            width: 36; height: 36; radius: 18
            color: backMa.containsMouse ? Theme.chromeHover : Theme.chromeButton
            border.color: Theme.chromeHover; border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: backMa.pressed ? 0.85 : 1.0
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
            Text { anchors.centerIn: parent; text: "\u2190"; color: Theme.chromeText; font.pixelSize: 18 }
            MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.stopPlaybackAndExit("home") }
        }

        Column {
            anchors { left: backBtn.right; verticalCenter: parent.verticalCenter; leftMargin: 12 }
            spacing: 2
            Text { text: root.showTitle;    color: Theme.chromeText; font.pixelSize: 17; font.bold: true; elide: Text.ElideRight; width: Math.min(implicitWidth, root.width - 260); font.family: Theme.displayFont }
            Text { text: root.episodeLabel; color: Theme.textSecondary; font.pixelSize: 11; font.letterSpacing: 1.2; visible: root.episodeLabel !== "" }
        }

        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 20 }
            spacing: 8
            Rectangle {
                width: 36; height: 36; radius: 18; color: iMa.containsMouse ? Theme.chromeHover : Theme.chromeButton
                border.color: Theme.chromeHover; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: "\u2139"; color: Theme.chromeText; font.pixelSize: 15 }
                MouseArea { id: iMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: infoPanel.visible = !infoPanel.visible }
            }
            Rectangle {
                width: 36; height: 36; radius: 18; color: fMa.containsMouse ? Theme.chromeHover : Theme.chromeButton
                border.color: Theme.chromeHover; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                Text { anchors.centerIn: parent; text: "\u22ef"; color: Theme.chromeText; font.pixelSize: 20 }
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
                GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0.53) }
                GradientStop { position: 1.0; color: Theme.glassPanel }
            }
            // The Theme.borderDefault is what makes it read as a floating layer rather
            // than a fade to black.
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: Theme.glassEdge
            }
        }

        // Seek row
        Item {
            id: seekRow
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 8; leftMargin: 20; rightMargin: 20 }
            height: 28
            Text { id: curTimeLabel; anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                   text: root.fmtTime(video.timePos); color: Theme.chromeText; font.pixelSize: 13; font.bold: true }
            Text { id: totTimeLabel; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                   text: root.fmtTime(video.duration); color: Theme.textSecondary; font.pixelSize: 13 }
            Item {
                anchors { left: curTimeLabel.right; right: totTimeLabel.left; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                height: 28
                Rectangle { id: seekBg; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: "#44FFFFFF" }
                // Buffered ahead of the playhead: mpv reports it as seconds, so the segment
                // is drawn from the playhead forward rather than as an absolute range.
                Rectangle {
                    id: seekBuffered
                    anchors.verticalCenter: parent.verticalCenter; anchors.left: seekBg.left
                    width: video.duration > 0
                           ? Math.min(seekBg.width, seekBar.value * seekBg.width
                                        + video.bufferedAhead / video.duration * seekBg.width) : 0
                    height: 4; radius: 2
                    color: "#7FFFFFFF"
                    visible: width > seekBar.value * seekBg.width
                    Behavior on width { NumberAnimation { duration: Theme.dBase; easing.type: Theme.easeOutCubic } }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; anchors.left: seekBg.left
                    width: seekBar.value * seekBg.width; height: 4; radius: 2
                    color: "#f5f5f5"
                }
                Repeater {
                    id: chapterTicks
                    model: root.hasChapters && video.duration > 0 ? root.chapters : []
                    delegate: Rectangle {
                        required property var modelData
                        width: 2; height: 8; radius: 1
                        color: Theme.chromeEdge
                        anchors.verticalCenter: seekBg.verticalCenter
                        x: seekBg.width * ((modelData.time !== undefined
                                            ? modelData.time : modelData.start) / video.duration)
                    }
                }

                Slider {
                    id: seekBar
                    anchors.fill: parent; from: 0; to: 1; value: 0
                    background: Item {}
                    handle: Rectangle {
                        x: seekBar.leftPadding + seekBar.visualPosition * (seekBar.availableWidth - width)
                        y: seekBar.topPadding + seekBar.availableHeight / 2 - height / 2
                        width:  (seekBar.pressed || seekHov.hovered) ? 16 : 0
                        height: width; radius: width / 2; color: Theme.chromeText
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    onMoved: { if (video.duration > 0) root.seekTo(value * video.duration) }
                    // Without this a mid-drag pause reads as drift and the room fights the finger.
                    // onPressedChanged, not onReleased: a cancelled drag never releases.
                    onPressedChanged: {
                        party.scrubbing = pressed
                        if (pressed)
                            party.noteLocalAction()
                    }
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
                    color: playMa.containsMouse ? "#FAFAFA" : Theme.chromeText
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
                        font.family: Theme.iconFont
                    }
                    MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePlayback() }
                }

                PlayerIconBtn {
                    glyph: "\uE716"; glyphIcon: true; tip: "Watch party"
                    onClicked: root.partyPanelOpen = !root.partyPanelOpen
                }

                PlayerIconBtn {
                    glyph: "Zz"; tip: "Sleep timer"
                    onClicked: sleepMenu.open()
                    Rectangle {
                        anchors { top: parent.top; right: parent.right; margins: 3 }
                        width: 7; height: 7; radius: 4
                        visible: root.sleepMinutes !== 0
                        color: Theme.accent
                    }
                    Menu {
                        id: sleepMenu
                        readonly property var mins: [0, 10, 20, 30, 45, -1]
                        readonly property var lbl: ["Off", "10 minutes", "20 minutes", "30 minutes",
                                                    "45 minutes", "End of episode"]
                        title: "Sleep timer"
                        Repeater {
                            model: sleepMenu.lbl
                            MenuItem {
                                required property var modelData
                                required property int index
                                text: modelData
                                onTriggered: root.setSleep(sleepMenu.mins[index])
                            }
                        }
                    }
                }

                PlayerIconBtn {
                    glyph: "\uE100"; glyphIcon: true; tip: "Previous episode"
                    enabled: root.currentEpisodeIndex > 0
                    onClicked: root.stepEpisode(-1)
                }
                PlayerIconBtn {
                    glyph: "\uE101"; glyphIcon: true; tip: "Next episode"
                    enabled: root.currentEpisodeIndex >= 0
                             && root.currentEpisodeIndex < root.playerEpisodes.length - 1
                    onClicked: root.stepEpisode(1)
                }

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
                            color: Theme.chromeEdge

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * volSlider.value
                                height: parent.height
                                radius: parent.radius
                                color: Theme.chromeText
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
                    border.color: qualityBtn.activeFocus ? Theme.chromeText : "transparent"
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
                            color: Theme.chromeText
                            font.family: Theme.bodyFont; font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\uE70D"
                            color: "#b3b3b3"
                            font.family: Theme.iconFont; font.pixelSize: 9
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
                    width: Math.min(132, langRow.implicitWidth + 16); height: 32; radius: 6
                    color: langMa.containsMouse ? Theme.chromeHover : Theme.chromeRest
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row { id: langRow; anchors.centerIn: parent; spacing: 4
                        Text { text: root.currentSubtitleLabel; color: Theme.chromeText; font.pixelSize: 13; font.bold: true
                               elide: Text.ElideRight; width: Math.min(implicitWidth, 116) } }
                    MouseArea { id: langMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.refreshTracks(); trackPanel.visible = !trackPanel.visible } }
                }

                Rectangle {
                    width: 36; height: 36; radius: 18; color: settMa.containsMouse ? Theme.chromeHover : Theme.chromeButton
                    border.color: Theme.chromeHover; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "\u2699"; color: Theme.chromeText; font.pixelSize: 16 }
                    MouseArea { id: settMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: speedMenu.open() }
                    Menu {
                        id: speedMenu
                        readonly property var spd: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                        readonly property var lbl: ["0.25\u00d7","0.5\u00d7","0.75\u00d7","1\u00d7","1.25\u00d7","1.5\u00d7","2\u00d7"]
                        title: "Playback Speed"
                        Repeater {
                            model: speedMenu.lbl
                            MenuItem {
                                required property var modelData
                                required property int index
                                text: modelData
                                // Through the party controller: a rate it never hears about stays stale.
                                onTriggered: party.requestSpeed(speedMenu.spd[index])
                            }
                        }
                    }
                }

                PlayerIconBtn {
                    glyph: "?"; tip: "Keyboard shortcuts"
                    onClicked: root.shortcutsOpen = !root.shortcutsOpen
                }

                Rectangle {
                    width: epRow.implicitWidth + 20; height: 36; radius: 8
                    color: epMa.containsMouse ? Theme.chromeEdge : Theme.chromeHover
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row { id: epRow; anchors.centerIn: parent; spacing: 6
                        Text { text: "\uE8FD"; font.family: Theme.iconFont; color: Theme.chromeText; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Episodes"; color: Theme.chromeText; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: epMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.episodePanelOpen = !root.episodePanelOpen }
                }

                Rectangle {
                    width: 36; height: 36; radius: 18; color: fsMa.containsMouse ? Theme.chromeHover : Theme.chromeButton
                    border.color: Theme.chromeHover; border.width: 1; Behavior on color { ColorAnimation { duration: 120 } }
                    scale: fsMa.pressed ? 0.88 : 1.0; Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
                    Text { anchors.centerIn: parent; text: root.visibility === Window.FullScreen ? "\uE73F" : "\uE740"; font.family: Theme.iconFont; color: Theme.chromeText; font.pixelSize: 14 }
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
        opacity: pib.enabled ? 1.0 : 0.35
        Rectangle {
            anchors.fill: parent; radius: 18
            color: pibMa.containsMouse ? Theme.chromeHover : Theme.chromeButton
            border.color: Theme.chromeHover; border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
            anchors.centerIn: parent
            text: pib.glyph
            color: Theme.chromeText
            font.pixelSize: 14
            font.family: pib.glyphIcon ? Theme.iconFont : Theme.bodyFont
        }
        MouseArea { id: pibMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pib.clicked() }
        ToolTip.text: pib.tip; ToolTip.visible: pibMa.containsMouse && pib.tip !== ""
    }

    // ─────────────────────────────────────────────────────────────────────
    // SEARCH PAGE loads via pageCanvas/searchLoader; the old overlay is unused.
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
                if (signingIn) root.authSheetOpen = true
                else { authManager.signOut(); root.notify("Signed out") }
            }
        }
    }

    Loader {
        id: authSheet
        z: 65
        active: root.authSheetOpen
        sourceComponent: authSheetComponent
        anchors.fill: parent

        Timer {
            interval: 1600
            running: uiAuthMode.length > 0 && uiShotPath.length > 0
            onTriggered: authSheet.item.grabToImage(function(r) {
                console.log("AUTHSHEET saved=" + r.saveToFile(uiShotPath))
            })
        }
    }

    Component {
        id: authSheetComponent
        AuthSheet {
            open: true
            signup: uiAuthMode === "signup" || uiAuthMode === "autofill"
            probeFill: uiAuthMode === "autofill" || uiAuthMode === "autofail"
            Connections {
                target: authManager
                function onSignInSucceeded() {
                    console.log("AUTHPROBE signed=" + authManager.authenticated
                                + " user=" + authManager.username)
                    root.authSheetOpen = false
                }
            }
            onDismissed: root.authSheetOpen = false
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
    // Invisible: translates socket decisions into mpv commands, player symptoms into events.
    WatchParty {
        id: party
        video: video
        onToastRequested: root.notify(message, kind)
        onSignInRequested: root.authSheetOpen = true
    }

    PartyPanel {
        id: partyPanel
        Timer {
            interval: 2500
            running: uiPanelProbe && uiShotPath.length > 0
            onTriggered: partyPanel.grabToImage(function(r) {
                console.log("PANEL saved=" + r.saveToFile(uiShotPath))
            })
        }

        // Drives the UI's own socket, so the roster, gate and WatchParty are all live.
        Timer {
            interval: 1200
            running: uiPanelProbe && uiRoomToken.length > 0
            onTriggered: {
                syncplay.connectToHost(backendBaseUrl, uiRoomToken, uiRoomUser)
                root.roomCodeWatch = true
            }
        }
        Connections {
            target: syncplay
            function onConnectedChanged() {
                if (!root.roomCodeWatch || !syncplay.connected || uiRoomEpisode.length === 0)
                    return
                root.roomCodeWatch = false
                syncplay.createRoom(uiRoomEpisode)
            }
            function onRoomChanged() {
                if (syncplay.roomCode.length > 0)
                    console.log("UIROOM code=" + syncplay.roomCode + " host=" + syncplay.isHost)
            }
        }

        Timer {
            interval: 13000
            running: uiPanelProbe && uiShotPath.length > 0 && uiRoomToken.length > 0
            onTriggered: {
                console.log("UIROOM peers=" + syncplay.totalPeers + " ready=" + syncplay.readyCount
                            + " gate=" + syncplay.gateOpen + " offset=" + syncplay.clockOffsetMs
                            + " copied=" + syncplay.copyRoomCodeToClipboard())
                partyPanel.grabToImage(function(r) {
                    console.log("PANEL2 saved=" + r.saveToFile(uiShotPath.replace(".png", "-room.png")))
                })
            }
        }

        // ANIMIND_UI_MEDIA loads a real file so the controller is observed driving playback.
        Timer {
            interval: 500
            running: uiPanelProbe && uiMediaPath.length > 0
            onTriggered: {
                // Neither QUrl nor Qt.fromLocalFile is reachable from QML on this Qt build,
                // so the file url is assembled here; mpv takes file:///C:/… directly.
                const path = uiMediaPath.replace(/\\/g, "/")
                // A two-episode queue so the short clip's end has somewhere to advance to.
                root.playStreamNow("file:///" + path, "Party probe", "probe", "", uiRoomEpisode)
            }
        }

        // Injected after the load settles: opening a stream clears the episode list when
        // the show id is not a library one, so assigning it before playStreamNow lost it.
        Timer {
            interval: 1500
            running: uiPanelProbe && uiMediaPath.indexOf("probe6") >= 0
            onTriggered: root.playerEpisodes = [
                { url: "file:///C:/tmp/probe6.wav", title: "One", thumbnail: "" },
                { url: "file:///C:/tmp/probe90.wav", title: "Two", thumbnail: "" }
            ]
        }

        Timer {
            id: playProbe
            property int ticks: 0
            interval: 2000
            repeat: true
            running: uiPanelProbe && uiMediaPath.length > 0
            onTriggered: {
                ticks += 1
                // Exercise the two new mpv options once, against a live player, so the
                // steppers are known to take effect rather than assumed to.
                if (ticks === 3) {
                    root.adjustSubDelay(0.1)
                    root.adjustSubSize(5)
                    root.adjustAudioDelay(0.1)
                }

                if (ticks === 4) {
                    // The C++ node conversion, proved on a node array mpv always has.
                    const tracks = video.getPropertyList("track-list")
                    console.log("NODES tracks=" + tracks.length
                                + " t0type=" + (tracks[0] ? tracks[0].type : "-")
                                + " t0selected=" + (tracks[0] ? tracks[0].selected : "-"))
                    // The chapter UI driven with the shape mpv returns for chapter-list.
                    root.chapters = [{ title: "A", time: 22.5, duration: 22.5 },
                                     { title: "B", time: 45.0, duration: 45.0 },
                                     { title: "C", time: 67.5, duration: 22.5 }]
                    console.log("CHAPTERS has=" + root.hasChapters
                                + " count=" + chapterTicks.count
                                + " x0=" + (chapterTicks.itemAt(0) ? chapterTicks.itemAt(0).x.toFixed(1) : "-")
                                + " x1=" + (chapterTicks.itemAt(1) ? chapterTicks.itemAt(1).x.toFixed(1) : "-")
                                + " x2=" + (chapterTicks.itemAt(2) ? chapterTicks.itemAt(2).x.toFixed(1) : "-")
                                + " trackW=" + seekBg.width.toFixed(1))
                    console.log("SUBOPTS delay=" + video.getPropertyString("sub-delay")
                                + " size=" + video.getPropertyString("sub-font-size")
                                + " audio=" + video.getPropertyString("audio-delay")
                                + " wanted=" + root.subDelay + "/" + root.subSize + "/" + root.audioDelay)
                }
                console.log("PLAYPROBE t=" + (ticks * 2)
                            + " renderer=" + video.rendererReady + " idle=" + video.idle
                            + " dur=" + video.duration + " pos=" + video.playbackPosition
                            + " paused=" + video.paused + " buffering=" + video.buffering
                            + " ahead=" + video.bufferedAhead
                            + " idx=" + root.currentEpisodeIndex
                            + " eps=" + root.playerEpisodes.length
                            + " bufw=" + seekBuffered.width.toFixed(1)
                            + " played=" + (seekBar.value * 100).toFixed(1) + "%"
                            + " gate=" + syncplay.gateOpen + " canonical=" + syncplay.canonicalTime)
            }
        }

        // Resume round-trip: the auth probe signs in at ~3 s, so bookmark at 6 s and read
        // it back at 9 s. The seek shows up as a jump to ~42 in the PLAYPROBE line.
        Timer {
            interval: 6000
            running: uiPanelProbe && uiMediaPath.length > 0
            onTriggered: {
                if (!authManager.authenticated) {
                    console.log("RESUME skipped: not authenticated")
                    return
                }
                root.currentSeriesId = 900000001
                root.resumeKey = "900000001:0"
                api.putProgress("900000001", 0, 42.0)
            }
        }

        Timer {
            interval: 9000
            running: uiPanelProbe && uiMediaPath.length > 0
            onTriggered: api.fetchProgress("900000001", 0)
        }

        Timer {
            interval: 12000
            running: uiPanelProbe && uiShotPath.length > 0 && uiMediaPath.length === 0
            onTriggered: {
                const host = homeLoader.item
                console.log("PAGEITEM present=" + (host !== null) + " w=" + (host ? host.width : 0)
                            + " h=" + (host ? host.height : 0) + " opacity=" + (host ? host.opacity : 0))
                if (host)
                    host.grabToImage(function(r) {
                        console.log("PAGE saved=" + r.saveToFile(uiShotPath.replace(".png", "-page.png")))
                    })
            }
        }

        Timer {
            id: chromeProbe
            interval: 700
            onTriggered: playerBottomBar.grabToImage(function(r) {
                console.log("CHROME saved=" + r.saveToFile(uiShotPath.replace(".png", "-chrome.png")))
            })
        }

        Timer {
            interval: 19600
            running: uiPanelProbe && uiShotPath.length > 0 && uiMediaPath.length > 0
            onTriggered: {
                root.pointerOnChrome = true
                chromeProbe.restart()
            }
        }

        Timer {
            id: keysProbe
            interval: 700
            onTriggered: shortcuts.grabToImage(function(r) {
                console.log("KEYS saved=" + r.saveToFile(uiShotPath.replace(".png", "-keys.png")))
            })
        }

        Timer {
            interval: 19000
            running: uiPanelProbe && uiShotPath.length > 0 && uiMediaPath.length > 0
            onTriggered: {
                root.shortcutsOpen = true
                keysProbe.restart()
            }
        }

        Timer {
            interval: 21000
            running: uiPanelProbe && uiShotPath.length > 0 && uiMediaPath.length > 0
            onTriggered: {
                console.log("UIPLAY gate=" + syncplay.gateOpen + " pos=" + video.playbackPosition
                            + " dur=" + video.duration + " paused=" + video.paused
                            + " ahead=" + video.bufferedAhead + " canonical=" + syncplay.canonicalTime)
                partyPanel.grabToImage(function(r) {
                    console.log("PLAY saved=" + r.saveToFile(uiShotPath.replace(".png", "-late.png")))
                })
            }
        }
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        z: 45
        party: party
        episodeId: root.partyEpisodeId
        open: root.partyPanelOpen
        onCloseRequested: root.partyPanelOpen = false
        onSignInRequested: root.authSheetOpen = true
    }

    EpisodeSidebar {
        id: episodeSidebar
        anchors.fill: parent
        visible: root.inPlayer
        open: root.inPlayer && root.episodePanelOpen
        calm: root.reduceMotion
        episodes: root.playerEpisodes
        seriesTitle: root.showTitle
        currentIndex: root.currentEpisodeIndex
        onDismissed: root.episodePanelOpen = false
        onEpisodePicked: (url, title, label, thumb) => {
            root.playStreamNow(url, title, label, thumb)
            root.episodePanelOpen = false
        }
    }

    // Escape outside the player closes the notification panel or search overlay.
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

    // The sidebar reuses the detail query's streamingEpisodes; nothing here touches mpv.
    // Section 35: the shell owns the queue, each Toast runs its own hold and fade.
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
            watchHistoryLoaded = false
            return
        }
        watchHistoryLoading = true
        watchHistoryError = ""
        api.fetchHistory(50)
    }

    // History arrives as signals from the C++ client rather than a callback, so the
    // loading flag cannot be closed inside refreshWatchHistory itself.
    Connections {
        target: api
        function onHistoryLoaded(rows) {
            root.watchHistory = rows
            root.watchHistoryLoaded = true
            root.watchHistoryLoading = false
        }
        function onRequestFailed(endpoint, status, message) {
            if (endpoint !== "history") return
            root.watchHistoryLoading = false
            root.watchHistoryError = message && message.length
                ? message
                : "We couldn't load your watch history."
        }
    }

    Connections {
        target: authManager
        function onSessionChanged() {
            // Rows from the previous account must not stay on screen after a sign-out.
            if (!authManager.authenticated) {
                root.watchHistory = []
                root.watchHistoryLoaded = false
                root.watchHistoryError = ""
            }
        }
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

    // One lookup shared by the episode sidebar's highlight and the transport's
    // previous/next buttons.
    readonly property int currentEpisodeIndex: {
        for (var i = 0; i < playerEpisodes.length; i++) {
            var e = playerEpisodes[i]
            if (e && e.url && e.url === mediaUrl) return i
        }
        return -1
    }

    function stepEpisode(delta) {
        var i = root.currentEpisodeIndex + delta
        if (root.currentEpisodeIndex < 0 || i < 0 || i >= root.playerEpisodes.length)
            return
        var e = root.playerEpisodes[i]
        if (!e || !e.url) return
        root.playStreamNow(e.url, root.showTitle, "Episode " + (i + 1), e.thumbnail || "")
    }

    function goSearch() {
        // Every other navigation records where it came from; this one did not,
        // so Ctrl+K followed by Escape dropped you on Home from any page.
        if (root.currentPage !== "search")
            root.previousPage = root.currentPage
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
