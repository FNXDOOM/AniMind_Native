import QtQuick

// WatchParty — the actuation layer between the player and the watch-party socket.
// The server owns the room's clock and the instant to act at, sync_decision.cpp owns the answer,
// and this file owns only the doing: no broadcast is interpreted here on its own.
Item {
    id: party
    visible: false
    width: 0
    height: 0

    property var video: null
    property string statusText: ""
    // Separate from statusText: "1 of 2 ready" is only true while the room is gating.
    property string readyLine: ""
    property string headline: ""
    // The one-line reason for the last correction, naming who caused it.
    property string correctionLine: ""
    property int bufferGoalSeconds: 120
    property bool readySent: false
    property bool applyingRemote: false
    property bool suppressBuffering: false
    property bool hasEmittedBuffering: false
    property real lastSeekEmittedAt: 0
    property real userSpeed: 1.0
    property bool watchingPlayer: false
    // Set while the viewer drags the timeline; the decision layer stands down completely.
    property bool scrubbing: false
    // The rate the correction controller is holding, or 1.0 when idle.
    property real correctionRate: 1.0
    // A user setting, not a policy: how late this display's pipeline is.
    property real extraTimeOffsetMs: 0

    readonly property bool inRoom: syncplay.inRoom
    readonly property bool gateOpen: syncplay.gateOpen
    readonly property bool connected: syncplay.connected
    readonly property int readyCount: syncplay.readyCount
    readonly property int totalPeers: syncplay.totalPeers
    readonly property string roomCode: syncplay.roomCode
    readonly property bool isHost: syncplay.isHost
    readonly property var peers: syncplay.peers
    readonly property string waitingOn: syncplay.waitingOn
    readonly property bool ignoringWait: syncplay.ignoringWait
    readonly property int pingMs: syncplay.pingMs
    readonly property string clockConfidence: syncplay.clockConfidence
    readonly property real driftMs: syncplay.driftMs
    readonly property var activity: syncplay.activity

    // The shell owns the toast stack; the party only asks for one.
    signal toastRequested(string message, string kind)
    // Every "sign in first" dead end routes to the same sheet.
    signal signInRequested()
    function say(message, kind) { toastRequested(message, kind || "info") }

    function hasPlayer() {
        return party.video !== null && typeof party.video !== "undefined"
    }

    function connectIfNeeded() {
        if (syncplay.connected || syncplay.connecting)
            return true
        if (!authManager || !authManager.authenticated) {
            party.say("Sign in to start a watch party.", "error")
            party.signInRequested()
            return false
        }
        syncplay.connectToHost(backendBaseUrl, authManager.accessToken, authManager.userId)
        return true
    }

    // ── Room lifecycle ─────────────────────────────────────────────────────
    function createRoom(episodeId) {
        if (episodeId === undefined || episodeId === null || String(episodeId).length === 0) {
            party.say("This episode has no server id, so it cannot host a party.", "error")
            return
        }
        if (!connectIfNeeded())
            return
        syncplay.createRoom(String(episodeId))
    }

    function joinRoom(code) {
        const upper = String(code || "").trim().toUpperCase()
        if (upper.length < 5) {
            party.say("Room codes are five characters.", "error")
            return
        }
        if (!connectIfNeeded())
            return
        syncplay.joinRoom(upper)
        // A fresh stream buffers while it warms up; reporting that as a stall would gate the room.
        joinGraceTimer.restart()
    }

    function leaveRoom() {
        // No leaveRoom event on this protocol: leaving is disconnecting.
        syncplay.disconnectFromHost()
        party.readySent = false
        party.hasEmittedBuffering = false
        party.correctionRate = 1.0
        party.statusText = "Left the watch party."
    }

    function transferHost(userId) { syncplay.emitTransferHost(userId) }
    function changeEpisode(episodeId) { syncplay.emitChangeEpisode(String(episodeId)) }

    function copyRoomCode() {
        if (syncplay.copyRoomCodeToClipboard())
            party.say("Room code copied")
        else
            party.say("There is no room code to copy yet.", "error")
    }

    // ── Outbound intents ───────────────────────────────────────────────────
    function requestPlay() {
        if (!hasPlayer()) return
        if (!party.inRoom) { applyPaused(false); return }
        if (!connectIfNeeded()) return
        syncplay.emitPlay(video.playbackPosition)
    }

    function requestPause() {
        if (!hasPlayer()) return
        if (!party.inRoom) { applyPaused(true); return }
        syncplay.emitPause(video.playbackPosition)
        applyPaused(true)
    }

    function requestSeek(target) {
        if (!hasPlayer()) return
        applySeek(target)
        const now = Date.now()
        if (party.inRoom && now - party.lastSeekEmittedAt > 200) {
            party.lastSeekEmittedAt = now
            syncplay.emitSeek(target)
        }
    }

    function requestSpeed(rate) {
        party.userSpeed = rate
        // The viewer's own choice always wins: release the correction instead of fighting it.
        party.correctionRate = 1.0
        if (hasPlayer())
            video.command(["set", "speed", rate])
    }

    function setIgnoreWait(ignore) {
        syncplay.emitIgnoreWait(ignore)
        party.headline = ignore ? "Not waiting for the room" : ""
    }

    // Arms the local-intent guard without emitting: a viewer holding a slider has acted.
    function noteLocalAction() { syncplay.noteLocalAction() }

    function applyExtraTimeOffset(ms) {
        party.extraTimeOffsetMs = ms
        syncplay.setExtraTimeOffsetMs(ms)
    }

    // ── Actuation ──────────────────────────────────────────────────────────
    function markRemoteDriven() {
        party.applyingRemote = true
        party.suppressBuffering = true
        party.hasEmittedBuffering = false
        suppressTimer.restart()
        applyingTimer.restart()
    }

    function applyPaused(paused) {
        if (!hasPlayer()) return
        markRemoteDriven()
        video.command(["set", "pause", paused ? "yes" : "no"])
    }

    function applySeek(target) {
        if (!hasPlayer()) return
        markRemoteDriven()
        video.command(["seek", target.toFixed(3), "absolute"])
    }

    // A multiplier on the viewer's own speed, never an absolute: 1.5x must not become 0.95x.
    function applyRate(rate, holdMs, reason) {
        if (!hasPlayer()) return
        const wanted = rate * party.userSpeed
        if (Math.abs(wanted - party.correctionRate) < 0.001)
            return
        party.correctionRate = rate
        markRemoteDriven()
        video.command(["set", "speed", wanted.toFixed(3)])
        if (rate !== 1.0) {
            party.correctionLine = reason
            correctionClearTimer.interval = Math.max(2500, holdMs || 0)
            correctionClearTimer.restart()
            // A nudge that never ends is a bug; this is the safety net.
            correctionWatchdog.interval = Math.max(4000, holdMs || 0)
            correctionWatchdog.restart()
        }
    }

    function releaseRate() {
        if (party.correctionRate === 1.0)
            return
        party.correctionRate = 1.0
        if (hasPlayer())
            video.command(["set", "speed", party.userSpeed])
    }

    function startNow(position) {
        // The agreed instant has arrived, so a position gap here is real information.
        if (hasPlayer() && Math.abs(video.playbackPosition - position) > 1.0)
            applySeek(position)
        applyPaused(false)
        party.headline = ""
        party.readyLine = ""
    }

    // ── The decision pump ──────────────────────────────────────────────────
    // Runs on broadcast arrival (edge) and on a tick (level): drift changes between packets, and a
    // correction that only ran on arrival would wait for a packet a quiet room never sends.
    function pump(why) {
        if (!party.inRoom || !hasPlayer())
            return
        const result = syncplay.evaluate(party.scrubbing, !!video.seeking)
        const outcome = result.outcome
        if (why === "tick" && (outcome === "none" || outcome === "reject-stale"))
            return

        switch (outcome) {
        case "await-schedule": {
            const wait = syncplay.msUntilScheduledStart()
            party.headline = "Starting with the room in " + Math.max(0, Math.round(wait)) + " ms"
            if (wait > 0) {
                startTimer.interval = Math.min(30000, wait + 8)
                startTimer.restart()
            } else {
                party.applyStart()
            }
            break
        }
        case "start":
            party.applyStart()
            break
        case "pause":
            party.correctionLine = result.reason
            correctionClearTimer.restart()
            applyPaused(true)
            party.headline = "Paused with the room"
            break
        case "seek":
            party.correctionLine = result.reason
            correctionClearTimer.restart()
            applySeek(result.targetPosition)
            break
        case "nudge-slow":
            applyRate(result.rate, result.holdMs, result.reason)
            break
        case "nudge-fast":
            applyRate(result.rate, result.holdMs, result.reason)
            break
        case "resume-rate":
            releaseRate()
            break
        case "correct-to-group":
            party.correctionLine = result.reason
            applySeek(result.targetPosition)
            correctionClearTimer.restart()
            break
        case "hold-in-gate":
            party.headline = "Catching up with the room"
            party.correctionLine = result.reason
            correctionClearTimer.restart()
            break
        case "defer-local-intent":
        case "defer-clock-unknown":
        case "reject-stale":
        case "reject-self-echo":
        case "reject-wrong-episode":
            // Deciding not to act is still a decision, and the one a viewer asks about.
            party.statusText = result.reason
            break
        default:
            break
        }
        if (outcome !== "none")
            party.statusText = result.reason + " [" + (why || "event") + "]"
    }

    function applyStart() {
        startTimer.stop()
        const position = syncplay.acceptScheduledStart()
        party.headline = ""
        party.readyLine = ""
        startNow(position)
    }

    // ── Server events ──────────────────────────────────────────────────────
    // Handlers here do room bookkeeping and copy only; playback decisions leave through pump().
    Connections {
        target: syncplay
        function onEventReceived(name, payload) {
            switch (name) {
            case "waitForBufferGoal":
            case "waitForReady":
                party.openGate(payload.currentTime || 0, payload.bufferGoalSeconds)
                party.pump("gate")
                return
            case "allReady":
                party.readyLine = ""
                party.pump("allReady")
                return
            case "syncPlay":
            case "syncPaused":
            case "sync":
            case "pause":
            case "seek":
            case "softCorrect":
            case "speedSeek":
                party.pump(name)
                return
            case "peerReady":
                party.headline = payload.timedOut
                    ? ((payload.displayName || "A peer") + " timed out — starting")
                    : ""
                party.readyLine = (payload.readyCount || 0) + " of " + (payload.totalPeers || 0) + " ready"
                if (payload.timedOut)
                    party.statusText = party.readyLine
                break
            case "peerStalling":
                party.statusText = (payload.displayName || "A peer") + " is buffering"
                break
            case "peerStallRecovered":
                party.statusText = (payload.displayName || "A peer") + " caught up"
                break
            case "hostChanged":
                party.say(party.isHost
                    ? "You are now hosting the watch party."
                    : "Host passed to " + (payload.newHostDisplayName || "another peer"))
                break
            case "syncDenied":
                party.say(payload.reason || "That action was refused.", "error")
                break
            case "episodeChanged":
                party.say("The host switched episode.")
                break
            }
        }
        function onRoomAcked(event, ok, payload) {
            if (!ok) {
                party.say(payload.error || "Could not join that room.", "error")
                return
            }
            if (event === "createRoom") {
                party.headline = ""
                party.statusText = "Room " + (payload.roomCode || "") + " — share the code"
                party.say("Watch party started: " + (payload.roomCode || ""))
            } else if (event === "joinRoom") {
                party.statusText = "Joined " + (payload.roomCode || "")
                party.say("Joined the watch party.")
                if (payload.currentTime !== undefined && party.hasPlayer())
                    party.applySeek(payload.currentTime)
            }
        }
        function onLastErrorChanged() {
            if (syncplay.lastError && syncplay.lastError.length > 0)
                party.say(syncplay.lastError, "error")
        }
        function onConnectedChanged() {
            if (!syncplay.connected && party.inRoom) {
                party.statusText = "Reconnecting…"
            } else if (syncplay.connected) {
                // The client probes on its own schedule: the estimate died with the link.
                timesyncTimer.restart()
            }
        }
        // The hub publishes the cadence, so a room can be retuned without a client release.
        function onHeartbeatIntervalChanged(intervalMs) {
            if (intervalMs > 250)
                heartbeatTimer.interval = intervalMs
        }
    }

    Timer {
        id: timesyncTimer
        interval: 400
        repeat: true
        // Four quick probes on connect: a scheduled start is only as good as the estimate behind it.
        onTriggered: {
            syncplay.emitTimesyncPing()
            if (syncplay.clockConfidence === "trusted")
                stop()
        }
    }

    Timer {
        id: startTimer
        onTriggered: party.applyStart()
    }

    function openGate(time, goalSeconds) {
        party.readySent = false
        party.readyLine = ""
        party.correctionLine = ""
        if (goalSeconds !== undefined && goalSeconds > 0)
            party.bufferGoalSeconds = goalSeconds
        if (hasPlayer() && Math.abs(video.playbackPosition - time) > 0.5)
            applySeek(time)
        applyPaused(true)
        party.headline = "Buffering with the room"
        progressTimer.restart()
    }

    // ── Player observation ─────────────────────────────────────────────────
    onVideoChanged: {
        if (party.watchingPlayer || !party.hasPlayer())
            return
        party.watchingPlayer = true
        party.video.bufferingChanged.connect(party.onBufferingChanged)
        party.video.playbackRateChanged.connect(party.onPlaybackRateChanged)
    }

    // mpv is the source of truth for the viewer's rate: startup paths set speed on the player.
    function onPlaybackRateChanged() {
        if (party.applyingRemote || !(party.video.playbackRate > 0))
            return
        party.userSpeed = party.video.playbackRate
        // A speed change under a running correction: recompute the multiplier.
        if (party.correctionRate !== 1.0)
            video.command(["set", "speed", (party.correctionRate * party.userSpeed).toFixed(3)])
    }

    function onBufferingChanged() {
        if (!party.inRoom) return
        if (party.video.buffering) {
            if (!party.suppressBuffering)
                bufferingDebounce.restart()
        } else {
            if (party.hasEmittedBuffering) {
                party.hasEmittedBuffering = false
                syncplay.emitStallRecovered()
            }
            if (syncplay.gateOpen)
                party.markReady()
        }
    }

    function markReady() {
        if (party.readySent || !party.inRoom) return
        party.readySent = true
        syncplay.emitReady()
    }

    Timer {
        id: bufferingDebounce
        interval: 600
        onTriggered: {
            if (!party.inRoom || party.suppressBuffering) return
            party.hasEmittedBuffering = true
            syncplay.emitBuffering()
        }
    }

    Timer {
        id: suppressTimer
        interval: 1500
        onTriggered: party.suppressBuffering = false
    }

    Timer {
        id: applyingTimer
        interval: 200
        onTriggered: party.applyingRemote = false
    }

    Timer {
        id: joinGraceTimer
        interval: 3000
        // The grace window suppresses new stall reports only; a real stall after it is reported.
        onTriggered: { }
    }

    // A correction outliving its stated hold is a stuck controller.
    Timer {
        id: correctionWatchdog
        interval: 6000
        onTriggered: {
            party.releaseRate()
            party.correctionLine = ""
        }
    }

    Timer {
        id: correctionClearTimer
        interval: 4000
        onTriggered: party.correctionLine = ""
    }

    Timer {
        id: heartbeatTimer
        interval: 3000
        repeat: true
        running: party.inRoom && party.video !== null && !party.video.paused
        onTriggered: {
            if (party.video.buffering) return
            syncplay.emitHeartbeat(video.playbackPosition, party.video.playbackRate,
                                   party.video.bufferedAhead, party.video.duration)
        }
    }

    Timer {
        id: progressTimer
        interval: 1000
        repeat: true
        running: party.inRoom && syncplay.gateOpen
        onTriggered: {
            if (!party.hasPlayer()) return
            const goal = party.bufferGoalSeconds > 0 ? party.bufferGoalSeconds : 120
            const ahead = Math.max(0, party.video.bufferedAhead)
            const percent = Math.min(100, (ahead / goal) * 100)
            syncplay.emitBufferingProgress(ahead, percent)
            if (ahead >= goal || !party.video.buffering)
                party.markReady()
        }
    }

    // The level-triggered half of the pump: finer than the drift, coarser than the frame rate.
    Timer {
        id: driftTimer
        interval: 250
        repeat: true
        running: party.inRoom && party.hasPlayer() && !syncplay.gateOpen
        onTriggered: party.pump("tick")
    }

    // The goal is published, not assumed: the server shrinks it near the end of an episode.
    Connections {
        target: syncplay
        function onGateChanged() {
            if (syncplay.bufferGoalSeconds > 0)
                party.bufferGoalSeconds = syncplay.bufferGoalSeconds
        }
    }
}
