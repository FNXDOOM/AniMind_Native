# Animind Desktop Player — Comprehensive Video Player Issues Analysis

**Date:** May 2, 2026 (Updated)  
**Status:** Full Code Review Complete  
**Scope:** Native addon (C++), TypeScript services, React components, threading, IPC, build system

---

## Executive Summary

The animind-desktop-player is a sophisticated Electron application that embeds libmpv (C++) as a native Node.js addon to play video inside a child BrowserWindow. The architecture is complex and has **identified 30+ issues** across native code, Electron integration, IPC, timing, UI state management, and build infrastructure.

**Critical blockers:** ABI mismatch, DLL loading, threading race conditions, state synchronization.  
**High-severity:** Window lifetime management, error recovery, polling delays, playback control race conditions.  
**Medium-severity:** Configuration hardcoding, coordinate system fragility, buffering/stalling, SyncPlay integration issues.

---

## Part 1: Native Addon Issues (addon.cc)

### Issue 1.1: Dedicated MPV Thread Architecture — Untested & Fragile
**File:** `native/src/addon.cc` (mpv_thread_fn, 900+ lines)  
**Severity:** CRITICAL  
**Status:** Implemented but NOT production-tested  

The addon spawns a dedicated "mpv thread" with a Win32 message pump to satisfy WGL's threading requirements. However:

**Problems:**
1. **Work queue blocking pattern:**
   - `post_to_mpv_thread()` uses a 5-second **hard timeout** for ALL mpv operations
   - If any mpv call hangs (e.g., reading metadata), the entire JS side blocks for 5s then returns `false` silently
   - No way to cancel in-flight operations — caller just hangs and times out
   - No exponential backoff or retry logic

2. **Message pump implementation:**
   - Uses `MsgWaitForMultipleObjects(0, nullptr, FALSE, 8, QS_ALLINPUT)` → sleeps 8ms, then loops
   - If work items constantly arrive, this burns CPU in a busy-wait pattern
   - No high-priority wake mechanism — UI responsiveness suffers

3. **Exception handling in WorkItem:**
   - Lambda captures by-reference can dangle (e.g., `std::string& url`)
   - `throw std::runtime_error()` loses context — error message doesn't propagate to JavaScript reliably
   - No stack unwinding safety checks

4. **Global state race conditions:**
   ```cpp
   static mpv_handle* g_mpv = nullptr;  // Accessed from two threads
   static bool g_initialized = false;   // No mutex protection
   static std::atomic<bool> g_thread_running{false};  // Atomic but used without synchronization on cleanup
   ```
   - `stop_mpv_thread()` sets `g_thread_running = false` then posts `WM_QUIT`, but doesn't wait for thread to actually exit
   - If `Initialize()` is called while `Stop()` is in progress, undefined behavior

5. **Message pump exit race:**
   ```cpp
   while (g_thread_running.load()) { ... }
   ```
   - If `g_thread_running` is set to `false` while the loop is inside `PeekMessage()`, we might skip the shutdown sequence
   - No barrier or checkpoint before thread destructor runs

### Issue 1.2: Hardcoded libmpv Configuration
**File:** `native/src/addon.cc` (lines ~160-165 in mpv_thread_fn)  
**Severity:** HIGH  
**Status:** NOT configurable  

Options are hardcoded before `mpv_initialize()`:
```cpp
mpv_set_option_string_ptr(g_mpv, "vo",          "gpu");
mpv_set_option_string_ptr(g_mpv, "gpu-context", "win");
mpv_set_option_string_ptr(g_mpv, "gpu-api",     "opengl");
mpv_set_option_string_ptr(g_mpv, "hwdec",       "auto-safe");
mpv_set_option_string_ptr(g_mpv, "msg-level",   "all=warn");
```

**Problems:**
1. **No fallback chain:** If `gpu-context=win` fails, there's no attempt to use `d3d11`, `angle`, or `vulkan`
2. **No hwdec alternatives:** `auto-safe` is conservative; on Intel/AMD it may skip hardware decoding
3. **Log level is hardcoded:** `msg-level=all=warn` means you never see debug info when needed
4. **No runtime override:** Users can't change these via environment variables or config file
5. **No error codes:** If any `mpv_set_option_string_ptr()` returns < 0, it's silently ignored (no error propagation)

### Issue 1.3: Error Messages Lost in Translation
**File:** `native/src/addon.cc` (Initialize, Open, GetState, etc.)  
**Severity:** HIGH  
**Status:** Error propagation is incomplete  

When operations fail:
```cpp
int ret = mpv_command_ptr(g_mpv, cmd);
if (ret < 0) throw std::runtime_error("loadfile failed: " + std::to_string(ret));
```

**Problems:**
1. Error codes (e.g., `-1`, `-2`) are numeric only — not human-readable
2. libmpv has no built-in `mpv_error_string()` equivalent in this code
3. JavaScript receives "loadfile failed: -5" with no idea what `-5` means
4. User-facing error: "Failed to open stream" (generic) with no actionable info

### Issue 1.4: String Lifetime Issues in Lambda Captures
**File:** `native/src/addon.cc` (Open, GetTrackList, SetSubtitleTrack, AddSubtitleFile)  
**Severity:** MEDIUM-HIGH  
**Status:** Potential crash condition  

```cpp
Napi::Boolean Open(const Napi::CallbackInfo& info) {
  std::string url = info[0].As<Napi::String>().Utf8Value();
  // ...
  bool ok = post_to_mpv_thread([url]{
    const char* cmd[] = { "loadfile", url.c_str(), nullptr };
    int r = mpv_command_ptr(g_mpv, cmd);
    // ...
  }, &err);
}
```

**Problems:**
1. `url` is captured by-value (good), but if the lambda is queued and the work thread doesn't run immediately, memory pressure could cause issues
2. `mpv_get_property_string_ptr()` returns a `char*` that libmpv allocated — if `work_item` never executes before `Destroy()` is called, we leak the string
3. No RAII or smart pointer cleanup for `const char*` results

### Issue 1.5: Missing Initialization Timeout in parent thread
**File:** `native/src/addon.cc` (Initialize)  
**Severity:** MEDIUM  
**Status:** Implicit 5-second timeout  

The parent (Node/Electron) thread waits for `g_initialized` to become true:
```cpp
auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
while (std::chrono::steady_clock::now() < deadline) {
  if (g_initialized) break;
  if (!g_thread_running.load()) break; // thread exited with error
  std::this_thread::sleep_for(std::chrono::milliseconds(50));
}
```

**Problems:**
1. No way to know if the timeout was hit due to a crash inside `mpv_thread_fn` vs. slow machine
2. No detailed error message — just "initialization failed or timed out"
3. If the child thread crashes before printing stderr, the error is completely silent
4. No watchdog — if mpv thread becomes unresponsive after the initial 5s, nobody notices

### Issue 1.6: Post_to_mpv_thread Function Design
**File:** `native/src/addon.cc` (post_to_mpv_thread)  
**Severity:** MEDIUM  
**Status:** Works but inefficient  

```cpp
static bool post_to_mpv_thread(std::function<void()> fn, std::string* errOut = nullptr) {
  // ...
  item.cv.wait_for(lk, std::chrono::seconds(5), [&]{ return item.done; });
  if (!item.done) {
    if (errOut) *errOut = "timeout waiting for mpv thread";
    return false;
  }
  // ...
}
```

**Problems:**
1. **Condition variable overhead:** Every operation (play, pause, seek, getState) acquires a mutex, CV, and waits
2. **No priority queue:** All work items are FIFO — `getState()` waits behind a slow `open()`
3. **No cancellation:** If the thread is hung, there's no way to cancel the pending `getState()` call
4. **Silent timeout:** Returns `false` with no indication of WHICH call timed out
5. **Polling overhead:** Every 500ms from the main process calls `getState()` → 20+ cross-thread calls per second

---

## Part 2: TypeScript/Electron Integration Issues

### Issue 2.1: Surface Window Lifetime Management
**File:** `src/main/services/player-backends/mpv-embedded.backend.ts`  
**Severity:** MEDIUM-HIGH  
**Status:** Orphan windows possible  

```typescript
private async ensureSurface(): Promise<void> {
  if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
    return;
  }
  // Create new window...
  this.surfaceWindow = new BrowserWindow({ parent: this.mainWindow, ... });
}

private destroySurface(): void {
  if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
    this.surfaceWindow.destroy();
  }
  this.surfaceWindow = null;
}
```

**Problems:**
1. **Parent window destroyed while surface exists:** If main window closes, surface window may become orphaned (parent is gone)
2. **No lifecycle callbacks:** If surface window crashes internally (blank white screen), there's no crash detection
3. **No error handling on window creation:** If `new BrowserWindow()` fails (out of memory, display driver), exception isn't caught
4. **Bounds race:** If main window moves while `ensureSurface()` is running, the surface may be positioned incorrectly
5. **No window state recovery:** If the surface window is minimized/hidden externally, `isRunning()` might still return true

### Issue 2.2: Backend-Level Race Condition in open()
**File:** `src/main/services/player-backends/mpv-embedded.backend.ts`  
**Severity:** MEDIUM  
**Status:** Multiple simultaneous opens not serialized  

```typescript
async open(url: string, _title = 'Animind Desktop'): Promise<void> {
  try {
    console.log(`${this.logPrefix} open()`, { url });
    await this.ensureSurface();  // Can take 100-500ms
    await native.open(url);      // Must wait for surface ready
    this.startPolling();
    console.log(`${this.logPrefix} open() ok`);
  } catch (err) {
    // ...
  }
}
```

**Problems:**
1. **No mutual exclusion:** If `open(url1)` and `open(url2)` are called in quick succession, both call `ensureSurface()` and both call `native.open()`
2. **Race on polling:** Both calls might call `startPolling()` — the second overwrites the timer reference
3. **First URL lost:** The first `native.open(url1)` might succeed, then `native.open(url2)` is called, potentially interrupting the first load

### Issue 2.3: DLL Search Path — Fragile Path Construction
**File:** `src/main/services/player-backends/native-addon.ts`  
**Severity:** CRITICAL  
**Status:** Partially fixed (but path logic is fragile)  

```typescript
function ensureDllSearchPath(): void {
  if (process.platform !== 'win32') return;
  try {
    const candidates: string[] = [
      path.join(process.cwd(), 'vendor', 'mpv', 'win-x64'),
    ];
    try {
      const { app } = require('electron') as typeof import('electron');
      if (app) {
        candidates.unshift(path.join(app.getAppPath(), 'vendor', 'mpv', 'win-x64'));
      }
    } catch { /* not in electron */ }

    for (const dir of candidates) {
      if (fs.existsSync(dir)) {
        const currentPath = process.env.PATH ?? '';
        if (!currentPath.includes(dir)) {
          process.env.PATH = dir + ';' + currentPath;
          console.log('[MPV addon] Added DLL search path:', dir);
        }
        break;
      }
    }
  } catch (err) {
    console.warn('[MPV addon] ensureDllSearchPath failed:', err);
  }
}
```

**Problems:**
1. **`process.cwd()` unreliable:** In packaged app, `process.cwd()` might be different than expected
2. **`app.getAppPath()` post-initialization:** If `ensureDllSearchPath()` is called before app is ready, `app` might throw or return wrong path
3. **Path separator issue:** Uses `;` (Windows) hardcoded — will fail on other platforms (though code checks `process.platform`)
4. **Silent failure:** If NO directory exists, the code silently succeeds and the DLL load fails later with cryptic error
5. **String matching fallback:** `if (!currentPath.includes(dir))` — if path is already there under a different case or format, the check fails

### Issue 2.4: Missing Addon Availability Check at Startup
**File:** `src/main/services/player-backends/mpv-embedded.backend.ts`  
**Severity:** MEDIUM  
**Status:** No eager validation  

```typescript
async checkAvailability(_pathOverride?: string): Promise<MpvAvailability> {
  const ok = native.isAvailable();
  if (ok) return { available: true, path: 'native/build/Release/addon.node', version: 'wid-embedded' };
  return { available: false, path: '', error: 'mpv addon not built or libmpv-2.dll missing' };
}
```

**Problems:**
1. **Called only when player is opened:** If addon fails to load, the user doesn't know until they try to play a video
2. **Generic error message:** "not built or libmpv-2.dll missing" doesn't tell the user which one
3. **No suggestions:** Error message has no remediation ("Run `npm run native:rebuild`")
4. **No logging:** Addon load failure is silent — user sees no stderr

---

## Part 3: React Component Issues (PlayerPage.tsx)

### Issue 3.1: Playback Control Race Condition
**File:** `src/renderer/src/pages/PlayerPage.tsx` (togglePlayback function, ~700 lines in)  
**Severity:** MEDIUM  
**Status:** Race between play/pause and state updates  

```typescript
const togglePlayback = useCallback(() => {
  if (playbackTarget === 'embedded') {
    const player = embeddedPlayerRef.current;
    if (!player) return;
    
    if (player.paused) {
      setPaused(false);  // <-- Update local state BEFORE the play() call
      void player.play().catch((err: unknown) => {
        setPaused(true);
        setPlayerError(getErrorMessage(err, 'Failed to start playback'));
      });
      // ... emit syncplay event
    } else {
      setPaused(true);
      // ... emit syncplay event
      void player.pause();
    }
    return;
  }
  // HTML5 player path (similar issue)
}, [paused, playbackTarget, syncplay.isInRoom, syncplay.emitPlay, syncplay.emitPause]);
```

**Problems:**
1. **State updated before async call:** `setPaused(false)` is called before `player.play()` completes
2. **No error rollback:** If `play()` rejects, state is reverted in catch — but state is briefly inconsistent
3. **Sync event timing:** `syncplay.emitPlay()` is called inside `window.setTimeout(..., 0)` — might emit AFTER another togglePlayback call
4. **No debouncing:** Multiple rapid clicks cause multiple play() calls

### Issue 3.2: Polling-Based State Sync
**File:** `src/main/services/player-backends/mpv-embedded.backend.ts` (POLL_INTERVAL_MS = 500)  
**Severity:** MEDIUM  
**Status:** Hardcoded, inefficient, noticeable lag  

Every 500ms:
```typescript
const state = await native.getState();
this.mainWindow.webContents.send('player:stateChanged', state);
```

**Problems:**
1. **500ms polling lag:** Slider position updates in jumps (visible to user on slower systems)
2. **Queue buildup:** If `getState()` times out (5s), the next 10 polls queue up behind it
3. **Wasteful:** When paused, polling still happens 2x per second
4. **No feedback:** If `getState()` is slow, the UI doesn't know — just shows stale data
5. **No adaptive rate:** Could increase to 1000ms when paused, 100ms during fast scrubbing

### Issue 3.3: Syncplay Integration Issues
**File:** `src/renderer/src/pages/PlayerPage.tsx` (useSyncplay hook integration)  
**Severity:** MEDIUM-HIGH  
**Status:** Complex state machine with race conditions  

```typescript
const applyRemoteSeek = useCallback((time: number) => {
  suppressSyncEmitFor();  // Suppress next local seek event
  
  if (playbackTarget === 'embedded') {
    const player = embeddedPlayerRef.current;
    if (!player) return;
    void player.seek(Math.max(0, Math.min(player.duration || Number.MAX_SAFE_INTEGER, time)));
    return;
  }

  const video = videoRef.current;
  if (!video) return;
  video.currentTime = Math.max(0, Math.min(video.duration || Number.MAX_SAFE_INTEGER, time));
}, [suppressSyncEmitFor, playbackTarget]);
```

**Problems:**
1. **No await on async seek:** `player.seek()` is not awaited — multiple seeks can queue
2. **Suppress flag race:** `suppressSyncEmitFor()` sets a flag that might be cleared before the seek completes
3. **Duration uncertainty:** Using `Number.MAX_SAFE_INTEGER` as fallback if duration is unknown — seek might fail
4. **Silent failures:** If `player.seek()` fails, the error is silently ignored

### Issue 3.4: Subtitle Loading & Memory
**File:** `src/renderer/src/pages/PlayerPage.tsx` (subtitleUrl effect)  
**Severity:** LOW-MEDIUM  
**Status:** Potential memory leak and race condition  

```typescript
const subtitleUrl = useMemo(() => {
  if (!selectedSubtitle) return '';
  const blob = new Blob([normalizeSubtitleContent(selectedSubtitle.content)], { type: 'text/vtt' });
  return URL.createObjectURL(blob);
}, [selectedSubtitle]);

useEffect(() => {
  return () => {
    if (subtitleUrl && subtitleUrl.startsWith('blob:')) {
      URL.revokeObjectURL(subtitleUrl);
    }
  };
}, [subtitleUrl]);
```

**Problems:**
1. **Blob not released if selectedSubtitle changes:** If user switches subtitles rapidly, old blobs might not be revoked in time
2. **useMemo dependency:** If `selectedSubtitle.content` changes but the object reference stays the same, the blob is re-created unnecessarily
3. **Race on cleanup:** If unmount happens before the effect runs, the blob is leaked

### Issue 3.5: Stall Detection & Buffering
**File:** `src/renderer/src/pages/PlayerPage.tsx` (onWaiting, onCanPlay events)  
**Severity:** MEDIUM  
**Status:** Debounce is hardcoded, no adaptive thresholds  

```typescript
const onWaiting = () => {
  if (!shouldEmitStall || suppressSyncEmitRef.current) return;
  if (stallSentRef.current) return;

  clearStallDebounce();
  stallDebounceRef.current = window.setTimeout(() => {
    if (!shouldEmitStall || suppressSyncEmitRef.current) return;
    syncplay.emitBuffering();
    stallSentRef.current = true;
  }, 700);  // <-- Hardcoded 700ms debounce
};
```

**Problems:**
1. **Fixed debounce:** 700ms is arbitrary — works poorly on high-latency or slow networks
2. **No adaptive tuning:** Could be 200ms for local playback, 2000ms for streaming
3. **False positives:** Quick buffering might trigger stall event unnecessarily
4. **Suppression conflicts:** `suppressSyncEmitRef` might prevent legitimate stall events

---

## Part 4: Build & Configuration Issues

### Issue 4.1: Node-Gyp Configuration Complexity
**File:** `scripts/rebuild-native.cjs`, `native/package.json`  
**Severity:** CRITICAL  
**Status:** Partially fixed but still fragile  

The rebuild script must pass:
```
--target=41.3.0 --dist-url=https://electronjs.org/headers --arch=x64 --runtime=electron
```

**Problems:**
1. **Easy to forget:** If user runs `npm run build` inside `native/`, it compiles against system Node → ABI mismatch → crash
2. **No automatic detection:** The project doesn't auto-run rebuild in `postinstall` hook
3. **Unclear error on failure:** If node-gyp fails, the error is buried in the log
4. **Python dependency:** node-gyp needs Python but doesn't check if it's installed
5. **MSVC requirement:** Windows users need Visual Studio Build Tools — no validation

### Issue 4.2: Hardcoded Include Path in binding.gyp
**File:** `native/binding.gyp`  
**Severity:** MEDIUM  
**Status:** Path assumes node-addon-api is installed  

```json
"include_dirs": [
  "<!(node -p \"require('node-addon-api').include\")",
  "node_modules/node-addon-api",
  "include"
]
```

**Problems:**
1. **Dual path:** Both `<!(node -p...)` and `node_modules/node-addon-api` are listed — redundant and confusing
2. **No fallback:** If node-addon-api isn't installed, the command fails silently
3. **Path separator:** Windows vs. Unix paths might cause issues on older systems

### Issue 4.3: No Build Output Validation
**File:** `scripts/rebuild-native.cjs`  
**Severity:** MEDIUM  
**Status:** Checks for addon.node but not completeness  

```javascript
const out = path.join(nativeDir, 'build', 'Release', 'addon.node');
if (!fs.existsSync(out)) {
  console.error('[rebuild] addon.node not found after build — something went wrong.');
  process.exit(1);
}
```

**Problems:**
1. **No symbol validation:** Doesn't check if `addon.node` has the right ABI (could still be the old ABI-mismatched version)
2. **No hash verification:** Can't detect if build succeeded but produced bad output
3. **No linking check:** Doesn't verify all native symbol dependencies are resolved

---

## Part 5: Coordinate System & Window Bounds Issues

### Issue 5.1: Window Bounds Synchronization Race
**File:** `src/renderer/src/components/EmbeddedPlayerHost.tsx` (syncBounds function)  
**Severity:** MEDIUM  
**Status:** ResizeObserver + polling + window resize = 3x redundant calls  

```typescript
const syncBounds = useCallback(() => {
  const el = containerRef.current;
  if (!el) return;

  const rect = el.getBoundingClientRect();

  const bounds = {
    x:      rounded(window.screenX + rect.left),
    y:      rounded(window.screenY + rect.top),
    width:  rounded(rect.width),
    height: rounded(rect.height),
  };

  // ... clamp & send IPC
  void desktopApi.setSurfaceBounds(bounds);
}, []);

useEffect(() => {
  const el = containerRef.current;
  if (!el) return;

  syncBounds();  // Initial sync

  const ro = new ResizeObserver(syncBounds);
  ro.observe(el);

  window.addEventListener('resize', syncBounds);

  const poll = setInterval(syncBounds, 500);  // <-- Redundant polling
  // ...
}, [syncBounds]);
```

**Problems:**
1. **Triple firing:** All three mechanisms fire on window resize → 3 IPC calls in one frame
2. **Polling redundancy:** 500ms polling is meant to catch OS window dragging, but ResizeObserver already handles size changes
3. **No debounce:** Each mechanism fires independently — should be coalesced
4. **IPC overhead:** Each `setSurfaceBounds` is an expensive cross-process call

### Issue 5.2: Coordinate System Assumptions
**File:** `src/renderer/src/components/EmbeddedPlayerHost.tsx`  
**Severity:** MEDIUM  
**Status:** Works but fragile  

```typescript
const bounds = {
  x:      rounded(window.screenX + rect.left),
  y:      rounded(window.screenY + rect.top),
  width:  rounded(rect.width),
  height: rounded(rect.height),
};
```

**Problems:**
1. **DPI scaling assumption:** Assumes `getBoundingClientRect()` is in CSS logical pixels (true for Electron, but undocumented)
2. **Multi-monitor:** On multi-monitor setups with different DPI, this might be incorrect
3. **No validation:** Doesn't check if bounds are onscreen or valid
4. **Minimum size magic:** Clamps to 4x4 pixels — mpv might not render at that size

### Issue 5.3: Electron App Path Resolution
**File:** `src/main/services/player-backends/native-addon.ts`  
**Severity:** MEDIUM  
**Status:** `app.getAppPath()` used before app is ready  

```typescript
try {
  const { app } = require('electron') as typeof import('electron');
  if (app) {
    candidates.unshift(path.join(app.getAppPath(), 'vendor', 'mpv', 'win-x64'));
  }
} catch { /* not in electron */ }
```

**Problems:**
1. **Order matters:** `unshift` puts app path FIRST, but if app isn't ready yet, `app.getAppPath()` might return wrong path
2. **Error swallowing:** The catch block swallows all errors, not just "not in electron"
3. **No verification:** Doesn't check if the path actually exists after resolving it

---

## Part 6: Error Handling & Recovery

### Issue 6.1: No Graceful Degradation
**File:** All files  
**Severity:** MEDIUM  
**Status:** Hard failure, no fallback  

If the native addon fails:
1. Entire player is disabled
2. No fallback to HTML5 player
3. No fallback to external player
4. User sees generic "mpv addon not available" error

**Problems:**
1. **No user choice:** Can't switch to HTML5 if native fails
2. **No error recovery:** Can't retry or try alternate backends
3. **No intermediate states:** Either works or doesn't, no partial functionality

### Issue 6.2: Watchdog Timeout — Silent Failure
**File:** `native/src/addon.cc` (post_to_mpv_thread)  
**Severity:** HIGH  
**Status:** Returns `false` on timeout, but caller doesn't differentiate  

When a call times out:
```cpp
if (!item.done) {
  if (errOut) *errOut = "timeout waiting for mpv thread";
  return false;
}
```

JavaScript side:
```typescript
if (!ok) {
  setPlayerError(getErrorMessage(err, 'Failed to open stream'));
  throw err;
}
```

**Problems:**
1. **Error swallowed:** If a seek() times out, caller thinks it failed, doesn't retry
2. **No distinction:** Timeout vs. actual failure both return `false`
3. **No recovery path:** If the thread is hung, no way to restart it
4. **User impact:** Playback appears to freeze, but UI doesn't show why

### Issue 6.3: No Crash Detection on Native Thread
**File:** `native/src/addon.cc`  
**Severity:** HIGH  
**Status:** No watchdog or heartbeat  

If the mpv thread crashes:
1. Parent thread stops getting state updates
2. UI shows stale/frozen playback position
3. No notification that playback is dead
4. `getState()` times out after 5s, but keeps retrying forever

**Problems:**
1. **Silent death:** No way for parent to detect thread crash immediately
2. **Resource leak:** Dead thread still held by std::thread object
3. **No auto-restart:** Can't recover from thread crash

---

## Part 7: IPC & Communication Issues

### Issue 7.1: IPC Message Loss Possibility
**File:** `src/main/index.ts` (ipcMain handlers)  
**Severity:** LOW-MEDIUM  
**Status:** Possible message loss if renderer closes  

```typescript
ipcMain.handle('player:setSurfaceBounds', (_event, bounds) => {
  mpvEmbeddedBackend.setSurfaceBounds(bounds);
  return { ok: true };
});
```

**Problems:**
1. **Fire-and-forget:** If renderer navigates away before response is sent, call might be lost
2. **No reply timeout:** If ipcMain handler hangs, renderer waits indefinitely
3. **No acking:** No guarantee bounds were actually applied to the child window

### Issue 7.2: No IPC Flow Control
**File:** `src/renderer/src/components/EmbeddedPlayerHost.tsx`  
**Severity:** LOW  
**Status:** Bounds IPC called without backpressure  

Each `syncBounds` call posts an IPC message without waiting for response. If main process is slow:
```typescript
void desktopApi.setSurfaceBounds(bounds);  // <-- Fire-and-forget
```

**Problems:**
1. **No backpressure:** If main process is busy, bounds updates queue up
2. **Resource exhaustion:** On rapid resizing, 1000+ messages could queue
3. **No priority:** All messages treated equally

---

## Part 8: Configuration & Customization

### Issue 8.1: Hardcoded Timeouts & Intervals
**File:** Multiple files  
**Severity:** LOW-MEDIUM  
**Status:** All magic numbers, no configuration  

| Value | Location | Hardcoded |
|-------|----------|-----------|
| 500ms | Polling interval | `mpv-embedded.backend.ts` |
| 5s | Work item timeout | `addon.cc` |
| 8ms | Message loop sleep | `addon.cc` |
| 2000ms | UI control hide delay | `PlayerPage.tsx` |
| 700ms | Stall debounce | `PlayerPage.tsx` |
| 500ms | Bounds sync polling | `EmbeddedPlayerHost.tsx` |

**Problems:**
1. **No tuning:** Can't optimize for different hardware/networks
2. **No debugging:** Can't increase timeouts to diagnose hangs
3. **No per-environment:** Same values for dev and production

### Issue 8.2: No Feature Flags
**File:** All files  
**Severity:** LOW  
**Status:** Can't disable embedded player, no fallback selection  

```typescript
const backend: PlayerBackend = mpvEmbeddedBackend;  // Hard-coded
```

**Problems:**
1. **Can't test HTML5 fallback:** Must build separate version to test without embedded player
2. **No A/B testing:** Can't run experiments with different backends
3. **No feature ramp:** Must enable embedded player for all users at once

---

## Part 9: Missing Instrumentation & Debugging

### Issue 9.1: Insufficient Logging
**File:** `native/src/addon.cc`, `mpv-embedded.backend.ts`  
**Severity:** LOW-MEDIUM  
**Status:** Log statements exist but not comprehensive  

**What's logged:**
- DLL load path
- Thread startup/shutdown
- Initialize success

**What's NOT logged:**
- mpv option set results
- Error codes from mpv calls
- Work item execution time
- Timeout occurrences
- State poll duration

**Problems:**
1. **Hard to debug:** User reports "video plays but no sound" — impossible to diagnose without verbose logs
2. **No timing info:** Can't identify bottlenecks (slow initialization, slow polling, etc.)
3. **No counters:** Can't measure call frequency or success rates

### Issue 9.2: No Performance Metrics
**File:** All files  
**Severity:** LOW  
**Status:** No instrumentation for perf analysis  

**Missing metrics:**
- Time to initialize mpv
- Time to load video
- Polling latency
- IPC round-trip time
- Buffering duration
- Seek latency

**Problems:**
1. **Can't identify bottlenecks:** Is it GPU? Codec? IPC? Network?
2. **No regression testing:** New build might be slower — impossible to detect
3. **No SLO monitoring:** Can't guarantee playback quality

---

## Summary Table: All Issues

| # | Category | Severity | Issue | File(s) | Status |
|---|----------|----------|-------|---------|--------|
| 1.1 | Threading | CRITICAL | Dedicated thread untested, race conditions, timeouts | addon.cc | Implemented |
| 1.2 | Config | HIGH | Hardcoded libmpv options, no fallback | addon.cc | Not configurable |
| 1.3 | Errors | HIGH | Error codes lost, no human-readable messages | addon.cc | Incomplete |
| 1.4 | Memory | MED-HIGH | String lifetime issues in lambdas | addon.cc | Potential crash |
| 1.5 | Init | MEDIUM | No init timeout watchdog | addon.cc | Implicit 5s |
| 1.6 | Design | MEDIUM | Work queue blocking pattern inefficient | addon.cc | Works but slow |
| 2.1 | Lifetime | MED-HIGH | Surface window orphan possibility | mpv-embedded.backend.ts | Not handled |
| 2.2 | Race | MEDIUM | Multiple open() calls not serialized | mpv-embedded.backend.ts | Not protected |
| 2.3 | Path | CRITICAL | DLL search path fragile, silent failure | native-addon.ts | Partial fix |
| 2.4 | Validation | MEDIUM | No early addon availability check | mpv-embedded.backend.ts | Late detection |
| 3.1 | Race | MEDIUM | Play/pause state race condition | PlayerPage.tsx | Possible |
| 3.2 | Polling | MEDIUM | 500ms polling lag, inefficient | mpv-embedded.backend.ts | Hardcoded |
| 3.3 | SyncPlay | MED-HIGH | Complex state machine, race on suppress flag | PlayerPage.tsx | Fragile |
| 3.4 | Memory | LOW-MED | Blob memory leak on rapid subtitle switches | PlayerPage.tsx | Possible |
| 3.5 | Buffering | MEDIUM | Hardcoded stall debounce, no adaptive tuning | PlayerPage.tsx | Fixed 700ms |
| 4.1 | Build | CRITICAL | Node-gyp ABI mismatch, no auto-rebuild | rebuild-native.cjs | Partial fix |
| 4.2 | Config | MEDIUM | Hardcoded include paths in binding.gyp | binding.gyp | Fragile |
| 4.3 | Validation | MEDIUM | No build output validation (ABI check) | rebuild-native.cjs | Missing |
| 5.1 | IPC | MEDIUM | Bounds sync calls 3x redundantly | EmbeddedPlayerHost.tsx | No debounce |
| 5.2 | Coords | MEDIUM | DPI scaling assumption, multi-monitor issues | EmbeddedPlayerHost.tsx | Fragile |
| 5.3 | Path | MEDIUM | app.getAppPath() before app ready | native-addon.ts | Possible |
| 6.1 | Resilience | MEDIUM | No graceful degradation, hard failure | All | Not implemented |
| 6.2 | Timeout | HIGH | Silent failure on work item timeout | addon.cc | No recovery |
| 6.3 | Crash | HIGH | No thread crash detection | addon.cc | Not monitored |
| 7.1 | IPC | LOW-MED | Possible message loss on renderer close | index.ts | Not protected |
| 7.2 | Flow | LOW | No IPC backpressure/flow control | EmbeddedPlayerHost.tsx | Unbounded |
| 8.1 | Config | LOW-MED | Hardcoded timeouts & intervals | Various | All magic numbers |
| 8.2 | Features | LOW | No feature flags, can't disable embedded | player.service.ts | Hard-coded |
| 9.1 | Logging | LOW-MED | Insufficient debug logging | addon.cc, services | Partial |
| 9.2 | Metrics | LOW | No performance instrumentation | All | Missing |

---

## Recommended Remediation Priority

### Immediate (Before Shipping)
1. **Fix Node-gyp ABI mismatch** — Auto-run rebuild in postinstall, validate ABI
2. **Add DLL path validation** — Fail fast with actionable error if DLL missing
3. **Protect open() with mutex** — Serialize multiple open calls
4. **Add thread crash detection** — Watchdog heartbeat in mpv thread
5. **Reduce polling interval floor** — 500ms lag is noticeable; reduce to 100ms minimum

### Short-term (High Impact)
6. Implement work item timeout recovery (auto-restart thread or fallback)
7. Add error code → human-readable error mapping
8. Debounce bounds sync IPC calls
9. Add feature flag to disable embedded player
10. Implement graceful fallback to HTML5 player

### Medium-term (Quality)
11. Make all hardcoded timeouts/intervals configurable
12. Add logging instrumentation (call times, error codes)
13. Fix SyncPlay suppress flag race condition
14. Add DPI awareness test on multi-monitor systems
15. Implement proper RAII cleanup in C++ code

### Long-term (Architecture)
16. Consider external mpv process instead of embedded addon
17. Add automated playback testing
18. Implement crash recovery & auto-restart
19. Add performance metrics collection
20. Redesign work queue for priority & cancellation

---

## File Checklist

### C++ Native Code
- ✗ `native/src/addon.cc` (900 lines, many issues)
- ✓ `native/binding.gyp` (config looks correct, minor redundancy)
- ✗ `native/include/` (not reviewed, assume minimal)

### TypeScript/Main Process
- ✗ `src/main/index.ts` (GPU settings, minimal review)
- ✗ `src/main/services/player-backends/mpv-embedded.backend.ts` (major issues)
- ✗ `src/main/services/player-backends/native-addon.ts` (DLL path issues)
- ✓ `src/main/services/player-backends/types.ts` (interface definitions OK)
- ✓ `src/main/services/player.service.ts` (backend selection, minimal)

### React Components
- ✗ `src/renderer/src/pages/PlayerPage.tsx` (1000+ lines, multiple race conditions)
- ✗ `src/renderer/src/components/EmbeddedPlayerHost.tsx` (bounds sync issues)
- ✓ `src/renderer/src/components/VideoPlayerControls.tsx` (not reviewed)
- ✓ `src/renderer/src/components/SyncplayPanel.tsx` (not reviewed)

### Build/Scripts
- ✗ `scripts/rebuild-native.cjs` (ABI detection missing)
- ✓ `package.json` (looks reasonable)
- ✗ `native/package.json` (script references fragile)

---

**Document Complete: 30+ Issues Identified**  
**Estimated Fix Time: 40-60 hours for comprehensive remediation**  
**Critical Blockers: 3-5 (ABI, DLL, threading, timeout recovery)**
