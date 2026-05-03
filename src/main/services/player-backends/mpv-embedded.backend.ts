/**
 * mpv-embedded.backend.ts
 *
 * Manages the embedded mpv player surface.
 *
 * ARCHITECTURE (Jellyfin-style, single-window):
 *   mpv renders into a native Win32 child HWND that is created directly as a
 *   child of the Electron main window. There is NO intermediate BrowserWindow.
 *
 *   Flow:
 *     1. ensureSurface() — passes the main window's native HWND to native.initialize().
 *        The C++ addon creates a WS_CHILD window parented to that HWND and hands
 *        it to mpv as its render target.
 *     2. open(url)       — calls native.open(); mpv renders into the child HWND.
 *     3. setSurfaceBounds(bounds) — moves/resizes the native child HWND so it
 *        aligns with the player <div> on screen. Bounds arrive as SCREEN-ABSOLUTE
 *        pixels (already DPI-scaled). The native addon converts them to parent-
 *        client coordinates via ScreenToClient(mainWindowHwnd).
 *     4. destroy()       — tells mpv to stop and destroys the child HWND.
 *
 * Why no BrowserWindow surface?
 *   The previous design created an intermediate BrowserWindow child and passed
 *   its HWND to the addon. The addon then created ANOTHER child HWND inside that
 *   BrowserWindow. This caused a double coordinate conversion (two ScreenToClient
 *   calls), z-order conflicts, and paint gaps that showed as a black rectangle.
 *   The fix mirrors how jellyfin-desktop (CEF + mpv) works: mpv's native child
 *   sits directly under the host window with no intervening BrowserWindow.
 */
import { BrowserWindow } from 'electron';
import { PlayerBackend, MpvAvailability, MpvTrack, PlayerState, PlayerAudioState } from './types';
import * as native from './native-addon';

// ─── State polling ────────────────────────────────────────────────────────────
const POLL_ACTIVE_INTERVAL_MS = Math.max(100, Number(process.env.ANIMIND_MPV_POLL_ACTIVE_MS ?? 150));
const POLL_IDLE_INTERVAL_MS   = Math.max(POLL_ACTIVE_INTERVAL_MS, Number(process.env.ANIMIND_MPV_POLL_IDLE_MS ?? 750));
const POLL_ERROR_INTERVAL_MS  = Math.max(POLL_IDLE_INTERVAL_MS,   Number(process.env.ANIMIND_MPV_POLL_ERROR_MS ?? 1000));

type SurfaceBounds = { x: number; y: number; width: number; height: number };

export class MpvEmbeddedBackend implements PlayerBackend {
  private mainWindow: BrowserWindow | null = null;
  private pollTimer: NodeJS.Timeout | null = null;
  private pollInFlight = false;
  private readonly logPrefix = '[MPV embedded]';
  private initPromise: Promise<void> | null = null;
  private openQueue: Promise<void> = Promise.resolve();
  private mainWindowListenersBound = false;
  private surfaceVisible = false;

  // Last bounds requested by the renderer (screen-absolute, DPI-scaled pixels)
  private lastBounds: SurfaceBounds | null = null;

  private watchdogInterval: NodeJS.Timeout | null = null;
  private lastHeartbeat = 0n;
  private heartbeatFailCount = 0;

  private readonly traceBounds = process.env.ANIMIND_MPV_TRACE_BOUNDS === '1';
  private readonly traceState  = process.env.ANIMIND_MPV_TRACE_STATE  === '1';

  private logBounds(context: string, bounds: SurfaceBounds): void {
    if (!this.traceBounds) return;
    console.log(`${this.logPrefix} ${context}`, bounds);
  }

  // ── Main window lifecycle ─────────────────────────────────────────────────

  /** Called once from main/index.ts after createWindow(). */
  setMainWindow(win: BrowserWindow): void {
    this.mainWindow = win;
    if (this.mainWindowListenersBound) return;
    this.mainWindowListenersBound = true;

    // Re-apply bounds whenever the OS moves or resizes the host window.
    // The mpv child HWND is parented to the main window, so its position is
    // relative to the main window's client area — but we store absolute coords
    // and re-convert on each layout event.
    win.on('move',       () => this.reapplyBounds());
    win.on('resize',     () => this.reapplyBounds());
    win.on('maximize',   () => { this.surfaceVisible = true; this.reapplyBounds(); });
    win.on('unmaximize', () => { this.surfaceVisible = true; this.reapplyBounds(); });
    win.on('restore',    () => { this.surfaceVisible = true; this.reapplyBounds(); });
    win.on('minimize',   () => {
      // Hide the native child while minimised so it doesn't float above the taskbar.
      if (native.getAvailabilityDetails().available) {
        native.setWindowBounds(0, 0, 0, 0); // hide (w=0 h=0 signals hide in addon.cc)
      }
    });
    win.on('closed', () => {
      this.stopPolling();
      this.stopWatchdog();
      this.mainWindow = null;
    });
  }

  // ── PlayerBackend interface ───────────────────────────────────────────────

  async checkAvailability(_pathOverride?: string): Promise<MpvAvailability> {
    const details = native.getAvailabilityDetails();
    if (details.available) {
      return {
        available: true,
        path: details.addonPath,
        version: details.dllDir ? `embedded (${details.dllDir})` : 'embedded',
      };
    }
    return {
      available: false,
      path: details.addonPath,
      error: details.error ?? 'Embedded mpv addon is unavailable. Run `npm run native:rebuild` and verify `vendor/mpv/win-x64` exists.',
    };
  }

  async open(url: string, _title = 'Animind Desktop', authToken?: string): Promise<void> {
    const job = this.openQueue.then(async () => {
      try {
        console.log(`${this.logPrefix} open()`, { url });
        await this.ensureSurface();
        await native.open(url, authToken);
        this.surfaceVisible = true;
        // Flush bounds now that mpv has attached to the HWND — without this the
        // first frame renders at (0,0) inside the main window (top-left corner).
        this.reapplyBounds();
        this.startPolling();
        console.log(`${this.logPrefix} open() ok`);
      } catch (err) {
        console.error(`${this.logPrefix} open() failed`, err);
        throw err;
      }
    });
    this.openQueue = job.catch(() => undefined);
    return job;
  }

  async stop(): Promise<void> {
    this.stopPolling();
    this.stopWatchdog();
    await native.destroy();
    this.initPromise = null;
  }

  async play():  Promise<void> { await native.play(); }
  async pause(): Promise<void> { await native.pause(); }
  async seek(seconds: number): Promise<void> { await native.seek(seconds); }

  async setAudioTrack(trackId: number):           Promise<void> { await native.setAudioTrack(trackId); }
  async setSubtitleTrack(trackId: number | 'no'): Promise<void> { await native.setSubtitleTrack(trackId); }
  async setVolume(volume: number):                Promise<void> { await native.setVolume(volume); }
  async setMuted(muted: boolean):                 Promise<void> { await native.setMuted(muted); }
  async addSubtitleFile(filePath: string):         Promise<void> { await native.addSubtitleFile(filePath); }
  async getTrackList(): Promise<MpvTrack[]>       { return native.getTrackList(); }
  async getState():     Promise<PlayerState>      { return native.getState(); }
  async getAudioState(): Promise<PlayerAudioState> { return native.getAudioState(); }

  async isRunning(): Promise<{ running: boolean }> {
    return { running: this.mainWindow !== null && !this.mainWindow.isDestroyed() };
  }

  // ── Surface bounds ────────────────────────────────────────────────────────

  /**
   * Called from the IPC handler with SCREEN-ABSOLUTE, DPI-scaled pixel coords.
   * (resolveSurfaceBounds in main/index.ts converts content → screen coords.)
   *
   * We just cache them and forward to the native addon, which does
   * ScreenToClient(mainWindowHwnd) to get parent-relative child coords.
   */
  setSurfaceBounds(bounds: SurfaceBounds): void {
    this.lastBounds = {
      x:      Math.round(bounds.x),
      y:      Math.round(bounds.y),
      width:  Math.max(4, Math.round(bounds.width)),
      height: Math.max(4, Math.round(bounds.height)),
    };
    this.logBounds('setSurfaceBounds()', this.lastBounds);
    this.reapplyBounds();
  }

  /** Show the mpv surface (when the player UI becomes visible). */
  showSurface(): void {
    this.surfaceVisible = true;
    if (this.traceBounds) console.log(`${this.logPrefix} showSurface()`);
    this.reapplyBounds();
  }

  /** Hide the mpv surface (when navigating away from the player). */
  hideSurface(): void {
    this.surfaceVisible = false;
    if (this.traceBounds) console.log(`${this.logPrefix} hideSurface()`);
    if (native.getAvailabilityDetails().available) {
      // w=0,h=0 tells the native addon to move the child HWND off-screen and hide it.
      native.setWindowBounds(0, 0, 0, 0);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /**
   * Initialize mpv on first use.
   *
   * Jellyfin-style: we pass the MAIN window's HWND directly to the addon.
   * The C++ code creates a WS_CHILD HWND under that HWND and gives it to mpv.
   * No intermediate BrowserWindow — that was the source of the black screen.
   */
  private ensureSurface(): Promise<void> {
    if (this.initPromise) return this.initPromise;

    this.initPromise = (async () => {
      if (!this.mainWindow || this.mainWindow.isDestroyed()) {
        throw new Error('Main window not available for embedded player');
      }

      const details = native.getAvailabilityDetails();
      if (!details.available) {
        throw new Error(details.error ?? 'mpv addon not available or libmpv-2.dll missing');
      }

      // Pass the MAIN window's HWND so mpv's child is parented directly to it.
      const hwndBuffer = this.mainWindow.getNativeWindowHandle();
      const hwnd = hwndBuffer.readBigUInt64LE(0);
      console.log(`${this.logPrefix} Initializing with main window HWND:`, hwnd.toString());

      let ok = false;
      try {
        ok = await native.initialize(hwnd);
      } catch (err) {
        console.error(`${this.logPrefix} initialize() threw`, err);
        ok = false;
      }

      if (!ok) {
        this.initPromise = null;
        throw new Error('mpv initialization failed — check libmpv-2.dll is present and GPU drivers are up to date');
      }

      this.startWatchdog();
      console.log(`${this.logPrefix} ensureSurface() ok`);
    })();

    // Clear the promise on failure so the next call can retry.
    this.initPromise.catch(() => { this.initPromise = null; });
    return this.initPromise;
  }

  /**
   * Push the last-known bounds to the native addon.
   *
   * The addon receives SCREEN-ABSOLUTE, DPI-scaled pixels and converts them to
   * parent-client coords internally using ScreenToClient(mainWindowHwnd).
   * No DPI scaling is applied here — the renderer already sent scaled coords.
   */
  private reapplyBounds(): void {
    if (!this.lastBounds || !this.surfaceVisible) return;
    if (!native.getAvailabilityDetails().available) return;

    const { x, y, width, height } = this.lastBounds;
    this.logBounds('reapplyBounds()', { x, y, width, height });
    native.setWindowBounds(x, y, width, height);
  }

  // ── Watchdog ──────────────────────────────────────────────────────────────

  private startWatchdog(): void {
    this.stopWatchdog();
    this.watchdogInterval = setInterval(() => {
      try {
        const current = native.getHeartbeat();
        if (current === this.lastHeartbeat) {
          this.heartbeatFailCount++;
          if (this.heartbeatFailCount >= 5) {
            console.error(`${this.logPrefix} MPV thread seems hung (heartbeat stuck for ~5s).`);
            this.heartbeatFailCount = 0;
          }
        } else {
          this.lastHeartbeat = current;
          this.heartbeatFailCount = 0;
        }
      } catch (e) {
        console.error(`${this.logPrefix} Watchdog error:`, e);
      }
    }, 1000);
  }

  private stopWatchdog(): void {
    if (this.watchdogInterval) {
      clearInterval(this.watchdogInterval);
      this.watchdogInterval = null;
    }
    this.heartbeatFailCount = 0;
  }

  // ── State polling ─────────────────────────────────────────────────────────

  private startPolling(): void {
    this.stopPolling();
    this.scheduleNextPoll(0);
  }

  private stopPolling(): void {
    if (this.pollTimer !== null) {
      clearTimeout(this.pollTimer);
      this.pollTimer = null;
    }
    this.pollInFlight = false;
  }

  private scheduleNextPoll(delayMs: number): void {
    this.pollTimer = setTimeout(() => { void this.pollState(); }, delayMs);
  }

  private async pollState(): Promise<void> {
    if (!this.mainWindow || this.mainWindow.isDestroyed()) {
      this.stopPolling();
      return;
    }
    if (this.pollInFlight) {
      this.scheduleNextPoll(POLL_IDLE_INTERVAL_MS);
      return;
    }

    this.pollInFlight = true;
    let nextDelay = POLL_ERROR_INTERVAL_MS;

    try {
      const state = await native.getState();
      if (this.traceState) console.log(`${this.logPrefix} pollState()`, state);
      if (!this.mainWindow.webContents.isDestroyed()) {
        this.mainWindow.webContents.send('player:stateChanged', state);
      }
      nextDelay = state.paused ? POLL_IDLE_INTERVAL_MS : POLL_ACTIVE_INTERVAL_MS;
    } catch (err) {
      console.warn(`${this.logPrefix} pollState failed`, err);
    } finally {
      this.pollInFlight = false;
      if (this.pollTimer !== null) {
        this.scheduleNextPoll(nextDelay);
      }
    }
  }
}

export const mpvEmbeddedBackend = new MpvEmbeddedBackend();
