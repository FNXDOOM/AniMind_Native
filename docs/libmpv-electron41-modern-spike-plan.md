# Modern Embedded libmpv Spike Plan (Electron 41)

## Goal

Prove a production-viable embedded `libmpv` strategy for Electron 41 without using Pepper/PPAPI (`mpv.js`).

Success means:

- playback stays inside the app window
- broad codec support comes from `libmpv`
- the integration works with this repo's security model (`contextIsolation: true`, `nodeIntegration: false`)

## Scope

This spike is implementation-focused, not full migration. We only prove feasibility and define the winning path.

In scope:

- choose a modern embedding approach
- build a minimal playable prototype in this repo
- validate runtime and packaging requirements on Windows

Out of scope:

- full `PlayerPage` refactor
- full SyncPlay parity
- removing `mpv-external` in this phase

## Non-Negotiables

- No Pepper plugin registration.
- No `mpv.js` dependency.
- Renderer must not import native code directly.
- Native control path must stay behind main + preload IPC.

## Candidate Integration Paths

## Path A: Native Node addon wrapping libmpv render API

Shape:

- custom N-API addon loaded in main process
- addon hosts `mpv_handle`, `mpv_render_context`
- renderer gets state/events through IPC only

Pros:

- direct control over compatibility and lifecycle
- future-proof compared to abandoned plugin model

Risks:

- highest engineering effort
- C/C++ toolchain and ABI maintenance burden

## Path B: Maintained Electron/Node libmpv binding (if available)

Shape:

- adopt a maintained package that supports modern Electron/Node ABIs
- wrap package behind `playerService` facade

Pros:

- fastest if truly maintained and compatible

Risks:

- package quality or maintenance may be insufficient
- hidden compatibility issues with Electron 41

## Path C: Helper native host process + controlled IPC bridge

Shape:

- native helper process owns `libmpv` and rendering surface
- Electron controls helper over structured IPC

Pros:

- isolates native crashes from Electron main process

Risks:

- more moving parts
- tighter UX constraints for true in-window embedding

## Spike Deliverables

1. Technical decision record:
- selected path (`A`, `B`, or `C`)
- reasons rejected for other paths

2. Minimal prototype:
- load one stream URL
- play/pause/seek/volume
- basic time state updates in renderer

3. Packaging notes:
- required runtime files (`libmpv-2.dll` and companion DLLs)
- where files live in dev and packaged builds

4. Risk register:
- top 5 technical risks with mitigation

## Acceptance Criteria

A path is acceptable only if all are true:

1. Works on Electron 41 dev build on Windows.
2. Renders in-app (not external MPV window).
3. Survives app restart and repeated open/close cycles.
4. Can be packaged and launched from built app.
5. No CSP/security regressions in auth or renderer boundaries.

## Repo Execution Plan

## Phase 0: Branch and scaffold

- Create `src/main/services/player-backends/` skeleton.
- Add backend interface file:
  - `src/main/services/player-backends/types.ts`
- Add placeholder embedded backend file:
  - `src/main/services/player-backends/mpv-embedded.backend.ts`
- Keep current `player.service.ts` behavior intact.

Exit gate:

- app builds unchanged
- no behavior regression

## Phase 1: Probe integration path

- Implement tiny backend constructor/init for chosen path.
- Add explicit capability probe method:
  - `initialize()`
  - `healthcheck()`
- Emit structured startup diagnostics to logs.

Exit gate:

- init succeeds in at least one dev run
- failure mode is explicit and user-readable

## Phase 2: Minimal playback loop

- Wire `load/play/pause/seek/setVolume` only.
- Add internal state ticker or event subscription in main.
- Expose one IPC event channel for state snapshots.

Exit gate:

- can play a known test media URL inside app shell
- no hard crash on stop/reload cycle x5

## Phase 3: Packaging proof

- Add deterministic runtime lookup:
  - dev path
  - packaged resource path
- Include required native files in electron-builder config.

Exit gate:

- packaged app launches and can initialize embedded backend

## Phase 4: Recommendation handoff

- Write decision summary in docs:
  - winning path
  - estimated effort for full migration
  - blockers before deprecating `mpv-external`

Exit gate:

- clear go/no-go recommendation for full implementation

## Test Matrix

Minimum spike matrix:

1. Dev mode:
- `npm run dev`
- open episode
- validate load/play/pause/seek/volume

2. Production build:
- `npm run build`
- launch built app
- replay same flow

3. Stability loop:
- open/close player 5 times
- switch episodes 5 times
- verify no leaked processes or crash

## Observability Requirements

Add temporary structured logs in main for:

- backend selected
- native init success/failure
- runtime DLL path resolution
- first frame / ready timestamp
- teardown status

These logs should be removable behind a single debug flag later.

## Risk Register (Initial)

1. ABI mismatch between Electron runtime and native module.
Mitigation: compile against exact Electron headers in CI/dev.

2. `libmpv` runtime file drift across machines.
Mitigation: pinned runtime bundle + checksum manifest.

3. Render API incompatibility with Chromium GPU path.
Mitigation: test with controlled GPU switches; keep fallback path.

4. Native crash propagation to app.
Mitigation: prefer process isolation or strict lifecycle guards.

5. Regression risk in auth/session flows.
Mitigation: keep changes isolated to player backend and IPC surface.

## Timebox

Recommended spike timebox: 3 working days.

Day 1:
- candidate validation + init proof

Day 2:
- minimal playback loop in dev

Day 3:
- packaging proof + recommendation doc

## Go/No-Go Rule

Go:

- one path passes all acceptance criteria above

No-Go:

- no path can reliably initialize and render in Electron 41 within timebox
- then keep `mpv-external` and reassess architecture before larger rewrite
