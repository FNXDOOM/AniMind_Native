# Embedded libmpv Implementation Plan

## Goal

Replace the current "launch external mpv window" path with an in-app embedded `libmpv` player so the app keeps an in-window player experience while gaining MPV/FFmpeg codec support.

Important clarification:

- `libmpv` can give the app broad codec support
- it cannot make Chromium's HTML5 `<video>` element itself support those codecs

So the end state is:

- same in-app UI
- different playback engine under that UI
- embedded `libmpv` becomes the real primary player

What we want to preserve:

- the existing React player UI
- the current Electron security model (`contextIsolation: true`, `nodeIntegration: false`)
- SyncPlay compatibility
- progress save / restore

## Current Architecture Audit

### What exists today

- The renderer owns the visible player UI and currently renders a single HTML5 `<video>` element in [`src/renderer/src/pages/PlayerPage.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx).
- The app already supports a second playback target called `mpv`, but that target is not embedded. It controls an external `mpv` process through IPC polling and commands.
- The main process exposes player commands through the preload bridge in [`src/preload/index.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/preload/index.ts).
- The main process implements the current external-player behavior in [`src/main/services/player.service.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/services/player.service.ts).
- Stream tickets already distinguish `browser` vs `native` playback in [`src/main/services/library.service.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/services/library.service.ts) and [`src/renderer/src/App.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/App.tsx).

### Key seams we can reuse

- Playback target switching is already modeled in [`src/renderer/src/pages/PlayerPage.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx).
- The preload bridge already isolates the renderer from native/main-process code in [`src/preload/index.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/preload/index.ts).
- Audio track, subtitle download, progress save, and SyncPlay are already separated enough that they can be retargeted instead of redesigned.

## Constraints That Make The Guide Inaccurate For This Repo

### 1. DOM code cannot live in main-process services

The guide proposes a `main/services/mpv-embedded.service.ts` that accepts an `HTMLElement` and calls `document.createElement('canvas')`.

That will not fit this app:

- this app runs with `contextIsolation: true` and `nodeIntegration: false` in [`src/main/index.ts:257`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/index.ts:257)
- renderer DOM objects cannot be passed into main-process services
- the main process has no DOM

### 2. The current MPV API is process-centric, not render-surface-centric

[`src/main/services/player.service.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/services/player.service.ts) assumes:

- `mpv` is launched with `spawn(...)`
- commands go over `--input-ipc-server`
- running state means "child process exists"

Embedded `libmpv` needs a different backend:

- player lifecycle no longer equals child-process lifecycle
- rendering needs a host surface in the BrowserWindow
- event/state flow should be push-based or internal polling, not external socket polling

### 3. Renderer behavior currently assumes one of two modes:

- HTML5 `<video>`
- external MPV controlled by polling

This shows up across `PlayerPage`:

- polling `desktopApi.isPlayerRunning()` and `desktopApi.getPlayerState()` for `mpv`
- HTML5-only resume logic at [`src/renderer/src/pages/PlayerPage.tsx:608`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx:608)
- HTML5-only playback-speed application at [`src/renderer/src/pages/PlayerPage.tsx:758`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx:758)
- subtitle selection only changing local React state at [`src/renderer/src/pages/PlayerPage.tsx:1282`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx:1282) and [`src/renderer/src/pages/PlayerPage.tsx:1288`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx:1288)

An embedded backend can preserve the UI, but the player abstraction needs to be cleaned up first.

### 4. Packaging is not ready for native embedded media dependencies

Current packaging only includes:

- `dist/**/*`
- `package.json`

from [`package.json`](C:/Users/gudiy/Videos/anims/animind-desktop-player/package.json)

That is fine for pure TS/JS, but not for:

- native Node addons
- `libmpv` DLLs / shared libraries
- helper binaries or preload assets for rendering

## Recommended Technical Direction

## Decision

Implement embedded playback as the intended final primary backend behind a unified player interface:

- `html5` for current compatibility during migration
- `mpv-external` as temporary migration bridge
- `mpv-embedded` as the intended long-term default

Do not overwrite the current external MPV path immediately, but do plan to remove it after embedded playback is complete.

## Why this is the safest route

- It preserves a working path while native embedding is being built.
- It lets us incrementally move UI controls to backend-agnostic commands.
- It avoids a risky "big bang" rewrite of `PlayerPage`.
- It gives us a clean path to retire `mpv-external` once embedded playback is stable.

## Correct Product Framing

The goal is not:

- "make HTML5 support all codecs"

The goal is:

- "keep the same in-window player experience, but replace the underlying playback engine with embedded `libmpv`"

This distinction matters because:

- HTML5 `<video>` uses Chromium codec support
- embedded `libmpv` uses MPV/FFmpeg codec support

So from the user's point of view it still looks like in-app playback, but technically it is no longer HTML5 playback.

## High-Level Design

### Renderer responsibilities

- Own the container element and overlay UI for embedded video.
- Continue owning overlays, controls, gestures, fullscreen, and SyncPlay UI.
- Talk only to preload APIs.
- Never import native/libmpv code directly.

### Main-process responsibilities

- Own embedded player lifecycle.
- Own native module initialization.
- Own load/play/pause/seek/volume/subtitle/audio-track commands.
- Translate native player events into IPC events or a queryable state cache.

### Preload responsibilities

- Expose a backend-neutral player API.
- Expose event subscription helpers for state updates, errors, and readiness.

## Implementation Plan

## Phase 0: Research and dependency spike

### Objective

Choose the actual embedding stack before changing app logic.

### Tasks

- Evaluate the candidate embedded libmpv approach for Electron on Windows first.
- Verify whether the selected package supports:
  - Electron 41
  - Node ABI for your Electron runtime
  - Windows packaging
  - in-window rendering, not just remote control
  - track selection, subtitles, volume, pause/play, seek, events
- Confirm whether the package renders through:
  - a native child window
  - OpenGL/WebGL interop
  - texture/canvas binding

### Deliverable

A short spike note with:

- chosen library/package
- supported OS matrix
- required build toolchain
- required runtime assets (`mpv-2.dll`, etc.)

### Spike result on this repo

- The first implementation attempt used `mpv.js`, an old Pepper/PPAPI plugin approach.
- That path is not viable on this stack. The plugin never reached a ready state in Electron 41 even after bundling runtime DLLs.
- The current repo should treat `mpv.js` as an experiment we are backing away from, not as the production embedding strategy.
- Any future embedded `libmpv` work should use a modern native integration path instead of Pepper plugin registration.

### Exit criteria

Do not begin the deep playback migration until we can prove the embedding library can render inside Electron on Windows.

## Phase 1: Introduce a real player abstraction

### Objective

Separate UI intent from playback backend so the UI no longer assumes HTML5 decoding or an external process.

### New main-process shape

Create a backend-neutral interface, for example:

```ts
export interface PlayerBackend {
  initialize(): Promise<void>;
  destroy(): Promise<void>;
  load(source: PlayerLoadRequest): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  seek(seconds: number): Promise<void>;
  setVolume(volume: number): Promise<void>;
  setMuted(muted: boolean): Promise<void>;
  setSpeed(speed: number): Promise<void>;
  setAudioTrack(trackId: number): Promise<void>;
  setSubtitleTrack(trackId: number | 'no'): Promise<void>;
  addSubtitleFile(filePath: string): Promise<void>;
  getState(): Promise<PlayerState>;
  getAudioState(): Promise<PlayerAudioState>;
  getTrackList(): Promise<MpvTrack[]>;
  getStatus(): Promise<PlayerBackendStatus>;
}
```

### File changes

- Add `src/main/services/player-backends/types.ts`
- Rename or wrap current service logic into `src/main/services/player-backends/mpv-external.backend.ts`
- Add a controller/facade such as `src/main/services/player.service.ts` that delegates to the selected backend

### Notes

- Keep the current external MPV logic mostly intact during this phase.
- `isRunning()` should become more descriptive, for example backend type + ready state, not just a boolean child-process check.
- Design the abstraction around `mpv-embedded` as the destination, not around `mpv-external` as the permanent model.

## Phase 2: Add backend-neutral IPC and renderer API

### Objective

Stop exposing an external-MPV-shaped API to the renderer.

### IPC additions/changes

Replace or extend current handlers in [`src/main/index.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/index.ts):

- `player:open` becomes something closer to `player:load`
- add `player:setBackend`
- add `player:setSpeed`
- add `player:getStatus`
- add event channels such as:
  - `player:stateChanged`
  - `player:error`
  - `player:ready`
  - `player:ended`
  - `player:tracksChanged`

### Preload changes

Update [`src/preload/index.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/preload/index.ts) to expose:

- command methods
- subscription methods with unsubscribe cleanup

Example:

```ts
onStateChanged: (cb) => {
  const listener = (_event, state) => cb(state);
  ipcRenderer.on('player:stateChanged', listener);
  return () => ipcRenderer.removeListener('player:stateChanged', listener);
}
```

### Why

Embedded playback should not rely on the renderer polling `isRunning()` every 250ms forever.

## Phase 3: Refactor `PlayerPage` to a backend-agnostic UI

### Objective

Make the renderer speak in playback intents, not in implementation branches.

### Current problems to fix

- A lot of `if (playbackTargetRef.current === 'mpv' && mpvRunning)` branching is spread across the component.
- Resume, speed, and subtitle behavior are not uniformly applied across backends.
- The "external player" button is wired to "launch native player window", not "use the app's primary native playback engine".

### Refactor target

Create a small renderer-side adapter or hook:

- `usePlayerController()`
- `usePlayerBackend()`

It should provide:

- `state`
- `load`
- `play`
- `pause`
- `seek`
- `setVolume`
- `setMuted`
- `setSpeed`
- `selectSubtitle`
- `selectAudioTrack`

### UI container changes

Replace the single `<video>` assumption with:

- HTML5 video element when backend is `html5`
- embedded player host div when backend is `mpv-embedded`
- optional placeholder message when backend is `mpv-external`

### File changes

- Refactor [`src/renderer/src/pages/PlayerPage.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx)
- Add a component such as `src/renderer/src/components/EmbeddedPlayerHost.tsx`
- Optionally add a hook such as `src/renderer/src/hooks/usePlayerController.ts`

## Phase 4: Implement the embedded backend in main

### Objective

Add the real long-term playback backend without disturbing currently working behavior during migration.

### New files

- `src/main/services/player-backends/mpv-embedded.backend.ts`
- any native binding loader/helper files

### Expected behavior

- initialize native libmpv
- bind it to the BrowserWindow/render surface
- load a URL
- surface playback state and events
- expose track list / subtitle / audio selection
- support resume by seek-on-ready

### Important design choice

The renderer should not pass DOM nodes to main.

Instead, choose one of these patterns depending on the library:

- library binds to the current BrowserWindow/webContents directly
- renderer hosts a dedicated element and native code attaches via window handle / child surface identifier
- preload creates a safe narrow bridge if the library truly must operate closer to the DOM side

The exact answer depends on the chosen libmpv package. This is why Phase 0 has to happen first.

## Phase 5: Stream-source and subtitle alignment

### Objective

Use the backend ticketing model correctly for embedded native playback.

### Current behavior

In [`src/renderer/src/App.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/App.tsx), playback starts with a `browser` ticket and only uses `native` behavior for the external MPV case.

### Required change

For `mpv-embedded`:

- request `clientType: 'native'` stream tickets
- keep `browser` tickets only for current compatibility while migration is incomplete
- re-request the proper ticket when switching playback backend

### Subtitle behavior

Today:

- HTML5 subtitles are blob-backed `<track>` elements
- external MPV subtitles are addable as temp `.vtt` files through `player:addSubtitleContent`

For embedded MPV:

- reuse the temp-file path model from [`src/main/services/subtitle.service.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/services/subtitle.service.ts)
- wire subtitle selection UI to actual player commands, not just local state

## Phase 6: SyncPlay alignment

### Objective

Keep the watch-party features working while `mpv-embedded` becomes the main playback engine.

### Current behavior

[`src/renderer/src/hooks/useSyncplay.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/hooks/useSyncplay.ts) already accepts a generic snapshot callback and callback handlers, which is good.

### Required changes

- make embedded backend provide current time, paused state, and optionally buffering metrics
- wire play/pause/seek/speed-correct commands to embedded backend
- decide how "bufferedAhead" is modeled for libmpv

### Practical note

`bufferedAhead` may not map 1:1 with HTML5 buffered ranges. If true buffer metrics are hard to read from libmpv, start with:

- `bufferedAhead = 0` or a coarse estimate
- retain SyncPlay correctness for play/pause/seek first
- improve buffer-gate sophistication later

## Phase 7: Packaging and distribution

### Objective

Ship native embedding reliably.

### Packaging work

Update [`package.json`](C:/Users/gudiy/Videos/anims/animind-desktop-player/package.json) to include:

- native addon artifacts
- platform-specific `libmpv` runtime files
- any helper DLLs needed by the chosen package

Potential additions:

- `extraFiles`
- `asarUnpack`
- postinstall / rebuild scripts for native modules

### Build validation

Verify:

- `npm run dev`
- `npm run build`
- packaged Windows app from `npm run dist`

### Windows-first reality

Do Windows packaging first, since your current environment and current MPV setup already center on Windows.

## Phase 8: Rollout strategy

### Recommended rollout

1. Keep current HTML5 and external MPV behavior only during migration.
2. Add a hidden or settings-gated `mpv-embedded` implementation as the intended replacement player.
3. Make `mpv-embedded` the default after codec, subtitle, audio-track, and SyncPlay validation.
4. Remove `mpv-external` after:
   - H.264
   - HEVC
   - AV1
   - subtitle selection
   - audio track switching
   - progress restore
   - SyncPlay play/pause/seek
   - packaged Windows build validation
5. Remove or minimize HTML5 usage once embedded playback is proven sufficient for normal playback.

## Proposed File Touch List

### Main process

- [`src/main/index.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/index.ts)
- [`src/main/services/player.service.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/main/services/player.service.ts)
- `src/main/services/player-backends/types.ts`
- `src/main/services/player-backends/mpv-external.backend.ts`
- `src/main/services/player-backends/mpv-embedded.backend.ts`
- possibly `src/main/services/player-events.ts`

### Preload

- [`src/preload/index.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/preload/index.ts)

### Renderer

- [`src/renderer/src/App.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/App.tsx)
- [`src/renderer/src/api.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/api.ts)
- [`src/renderer/src/types.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/types.ts)
- [`src/renderer/src/pages/PlayerPage.tsx`](C:/Users/gudiy/Videos/anims/animind-desktop-player/src/renderer/src/pages/PlayerPage.tsx)
- `src/renderer/src/components/EmbeddedPlayerHost.tsx`
- `src/renderer/src/hooks/usePlayerController.ts`

### Build/package

- [`package.json`](C:/Users/gudiy/Videos/anims/animind-desktop-player/package.json)
- [`electron.vite.config.ts`](C:/Users/gudiy/Videos/anims/animind-desktop-player/electron.vite.config.ts)

## Risks

### High risk

- finding an Electron-compatible embedded libmpv package that really works on Windows with your Electron version
- native module rebuild friction during packaging
- render-surface integration details

### Medium risk

- keeping subtitles and track switching polished across all backends
- keeping SyncPlay buffer-gate logic meaningful for libmpv

### Lower risk

- refactoring preload and renderer APIs
- preserving progress save / resume

## Recommended order of execution

1. Run the dependency spike and prove an embedded libmpv package on Windows.
2. Introduce backend-neutral player interfaces in main.
3. Add push-based player events over preload.
4. Refactor `PlayerPage` around a backend-agnostic controller.
5. Implement `mpv-embedded` behind a feature flag.
6. Hook up native stream-ticket selection and subtitle/audio selection.
7. Make `mpv-embedded` the preferred in-app player.
8. Validate SyncPlay.
9. Package and test Windows distribution.
10. Remove `mpv-external`.

## Bottom line

Embedded `libmpv` is feasible for this repo, but it is not a paste-in library upgrade.

The right implementation is:

- keep the current external MPV path alive only during migration
- refactor playback around a backend abstraction
- add an embedded backend once the chosen native package is proven on Windows
- make embedded playback the real primary in-app player
- remove `mpv-external` after parity is reached

If we do that in phases, this is a realistic project. If we try to directly transplant the guide, we will fight Electron boundaries and packaging issues immediately.
