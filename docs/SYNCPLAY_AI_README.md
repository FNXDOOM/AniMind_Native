# SyncPlay AI README (Animind Desktop Player)

This file is a machine-friendly context brief for AI tools working on SyncPlay in the desktop app.

## 1) Project Context

- App: Electron desktop player with React renderer
- Folder: `animind-desktop-player`
- Sync backend: existing Socket.IO server from Animind backend (`syncplay.handler.ts`)
- Socket path: `/api/socket.io`
- Auth model: Supabase access token sent in Socket.IO `auth.token`

## 2) Current Implementation Status

### Implemented

- Room lifecycle
  - Create room
  - Join room
  - Leave room
  - Request resync
- Playback sync
  - Play / Pause / Seek emits
  - Remote play / pause / seek handling
- Buffer gate
  - `waitForBufferGoal`, `waitForReady`, `allReady`
  - Buffer progress reporting
  - Ready reporting
- Participant state and control
  - Peer state updates (`participantStates`)
  - Host transfer
- Time sync and reconnect
  - NTP warmup (`timesync_ping` / `timesync_pong`)
  - Reconnect + rejoin + `requestSync`
- Stall pipeline
  - Emit buffering on wait
  - Emit stall recovery on canplay
- Target modes
  - HTML5 embedded video target
  - External MPV target with IPC bridge and running-state detection

### Partially Implemented / Known Gap

- MPV speed-seek parity: simplified to hard seek behavior instead of full temporary playback-rate drift catch-up logic.

## 3) Important Files

### Renderer

- `src/renderer/src/hooks/useSyncplay.ts`
  - Main Socket.IO client hook for SyncPlay
  - Handles connection, events, room actions, emits
- `src/renderer/src/pages/PlayerPage.tsx`
  - Integrates SyncPlay with playback controls and events
  - Handles target selection (`html5` vs `mpv`)
- `src/renderer/src/components/SyncplayPanel.tsx`
  - UI for room code, peer list, host transfer, resync, target switch
- `src/renderer/src/api.ts`
  - Renderer API wrapper for preload bridge
- `src/renderer/src/types.ts`
  - Includes `SyncplayParticipantState`
- `src/renderer/src/vite-env.d.ts`
  - Global `window.animindDesktop` type declarations

### Main / Preload

- `src/main/index.ts`
  - IPC handlers including auth token and player running-state
- `src/main/services/player.service.ts`
  - MPV process + IPC control methods (`play`, `pause`, `seek`, state)
  - Running-state helper for MPV
- `src/preload/index.ts`
  - Exposes IPC bridge to renderer

## 4) Event Contract Summary

### Client -> Server (used)

- `createRoom`
- `joinRoom`
- `play`
- `pause`
- `seek`
- `heartbeat`
- `ready`
- `bufferingProgress`
- `buffering`
- `stallRecovered`
- `transferHost`
- `requestSync`
- `timesync_ping`

### Server -> Client (handled)

- `syncPlay`
- `pause`
- `syncPaused`
- `seek`
- `sync`
- `waitForBufferGoal`
- `waitForReady`
- `allReady`
- `participantStates`
- `peerReady`
- `peerJoined`
- `peerLeft`
- `peerStalling`
- `peerStallRecovered`
- `hostChanged`
- `softCorrect`
- `speedSeek`
- `syncDenied`
- `timesync_pong`

## 5) Runtime Behavior Notes

- Embedded target
  - Uses HTML5 `<video>` for current time, buffer ahead, playback rate
  - Emits sync actions from local controls
- MPV target
  - Uses main-process IPC to control MPV (`desktopApi.play/pause/seek/getPlayerState`)
  - Heartbeat snapshot comes from MPV state when running
  - If MPV is not running, app should safely avoid invalid sync actions
- Sync-safe settings
  - Playback speed and audio track changes are intentionally restricted while inside an active SyncPlay room

## 6) Production Verification Checklist

1. Start backend with Socket.IO SyncPlay enabled
2. Open two desktop clients with different users
3. Create room on client A, join on client B
4. Verify play/pause/seek propagate both ways
5. Verify participant list and ready states update
6. Verify buffer gate opens and closes correctly
7. Verify host transfer updates both clients
8. Verify disconnect/reconnect rejoin + resync
9. Verify MPV target path with external player open
10. Verify behavior when MPV target selected but MPV process is not running

## 7) High-Value Next Improvements

- Full MPV speed-seek parity with temporary playback-rate correction
- Better telemetry/debug overlay (offset, RTT, room state, heartbeat health)
- Automated integration tests for two-client sync scenarios
- Explicit fallback policy when MPV target is selected but MPV exits mid-session

## 8) AI Prompt Starter

Use this prompt for follow-up AI tasks:

"You are working in `animind-desktop-player`. Read `SYNCPLAY_AI_README.md` first. Keep UI layout unchanged unless explicitly requested. Focus on SyncPlay logic reliability, event parity with backend, and production safety. When editing, preserve existing IPC contracts and renderer/main separation."
