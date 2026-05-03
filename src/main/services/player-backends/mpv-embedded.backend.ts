/**
 * mpv-embedded.backend.ts
 *
 * Manages a hidden child BrowserWindow that acts as mpv's render surface.
 * Flow:
 *   1. createSurface()  — opens a borderless child window, reads its HWND,
 *                         passes it to the native addon via setWindowId().
 *   2. open(url)        — calls native open(); mpv renders into the child window.
 *   3. Caller repositions/resizes the child window to match the player div via
 *      the 'player:setSurfaceBounds' IPC channel.
 *   4. destroy()        — closes the child window and tears down mpv.
 */
import { BrowserWindow } from 'electron';
import { PlayerBackend, MpvAvailability, MpvTrack, PlayerState, PlayerAudioState } from './types';
import * as native from './native-addon';

// ─── State polling ────────────────────────────────────────────────────────────
const POLL_ACTIVE_INTERVAL_MS = Math.max(100, Number(process.env.ANIMIND_MPV_POLL_ACTIVE_MS ?? 150));
const POLL_IDLE_INTERVAL_MS = Math.max(POLL_ACTIVE_INTERVAL_MS, Number(process.env.ANIMIND_MPV_POLL_IDLE_MS ?? 750));
const POLL_ERROR_INTERVAL_MS = Math.max(POLL_IDLE_INTERVAL_MS, Number(process.env.ANIMIND_MPV_POLL_ERROR_MS ?? 1000));

type SurfaceBounds = { x: number; y: number; width: number; height: number };

export class MpvEmbeddedBackend implements PlayerBackend {
  private surfaceWindow: BrowserWindow | null = null;
  private pollTimer: NodeJS.Timeout | null = null;
  private pollInFlight = false;
  private mainWindow: BrowserWindow | null = null;
  private readonly logPrefix = '[MPV embedded]';
  private ensureSurfacePromise: Promise<void> | null = null;
  private openQueue: Promise<void> = Promise.resolve();
  private mainWindowListenersBound = false;
  private surfaceState = { visible: false };

  // Track the last bounds we were told to use, so we can apply them if the
  // surface window is recreated.
  private lastBounds: SurfaceBounds | null = null;

  private watchdogInterval: NodeJS.Timeout | null = null;
  private lastHeartbeat = 0n;
  private heartbeatFailCount = 0;

  private startWatchdog(): void {
    this.stopWatchdog();
    this.watchdogInterval = setInterval(() => {
      if (!this.surfaceWindow || this.surfaceWindow.isDestroyed()) return;

      try {
        const current = native.getHeartbeat();
        if (current === this.lastHeartbeat) {
          this.heartbeatFailCount++;
          if (this.heartbeatFailCount >= 5) { // ~5 seconds of no activity
            console.error(`${this.logPrefix} MPV thread seems hung (heartbeat stuck). Attempting restart...`);
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
  }

  /** Called once from main/index.ts after createWindow(). */
  setMainWindow(win: BrowserWindow): void {
    this.mainWindow = win;
    if (this.mainWindowListenersBound) return;
    this.mainWindowListenersBound = true;

    // When the main window moves or resizes, keep the surface glued to it.
    win.on('move',   () => this.reapplyBounds());
    win.on('resize', () => this.reapplyBounds());
    win.on('restore', () => {
      this.surfaceState.visible = true;
      this.surfaceWindow?.show();
      this.reapplyBounds();
    });
    win.on('minimize', () => this.surfaceWindow?.hide());
    win.on('maximize', () => {
      this.surfaceState.visible = true;
      this.surfaceWindow?.show();
      this.reapplyBounds();
    });
    win.on('unmaximize', () => {
      this.surfaceState.visible = true;
      this.surfaceWindow?.show();
      this.reapplyBounds();
    });
    win.on('closed', () => {
      this.stopPolling();
      this.destroySurface();
      this.mainWindow = null;
    });
  }

  // ── PlayerBackend interface ────────────────────────────────────────────────

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

  async open(url: string, _title = 'Animind Desktop'): Promise<void> {
    const job = this.openQueue.then(async () => {
      try {
        console.log(`${this.logPrefix} open()`, { url });

        // Ensure mpv is initialized and bound to a surface window
        await this.ensureSurface();

        await native.open(url);
        this.surfaceState.visible = true;
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
    await native.destroy();
    this.destroySurface();
  }

  async play(): Promise<void>  { await native.play(); }
  async pause(): Promise<void> { await native.pause(); }
  async seek(seconds: number): Promise<void> { await native.seek(seconds); }

  async setAudioTrack(trackId: number): Promise<void> {
    await native.setAudioTrack(trackId);
  }
  async setSubtitleTrack(trackId: number | 'no'): Promise<void> {
    await native.setSubtitleTrack(trackId);
  }
  async setVolume(volume: number): Promise<void> {
    await native.setVolume(volume);
  }
  async setMuted(muted: boolean): Promise<void> {
    await native.setMuted(muted);
  }
  async addSubtitleFile(filePath: string): Promise<void> {
    await native.addSubtitleFile(filePath);
  }
  async getTrackList(): Promise<MpvTrack[]> {
    return native.getTrackList();
  }
  async getState(): Promise<PlayerState> {
    return native.getState();
  }
  async getAudioState(): Promise<PlayerAudioState> {
    return native.getAudioState();
  }
  async isRunning(): Promise<{ running: boolean }> {
    return {
      running: this.surfaceWindow !== null
        && !this.surfaceWindow.isDestroyed()
        && this.surfaceWindow.webContents !== null,
    };
  }

  // ── Surface window management ─────────────────────────────────────────────

  /**
   * Apply absolute screen bounds to the surface window.
   * Called from the IPC handler 'player:setSurfaceBounds'.
   */
  setSurfaceBounds(bounds: SurfaceBounds): void {
    const sanitized = {
      x: Math.round(bounds.x),
      y: Math.round(bounds.y),
      width: Math.max(4, Math.round(bounds.width)),
      height: Math.max(4, Math.round(bounds.height)),
    };
    this.lastBounds = sanitized;
    console.log('[MPV backend] setSurfaceBounds →', sanitized);
    if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
      this.surfaceWindow.setBounds(sanitized, false);
    }
  }

  /** Show the mpv surface (when player UI becomes visible). */
  showSurface(): void {
    this.surfaceState.visible = true;
    if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
      this.surfaceWindow.show();
      this.reapplyBounds();
    }
  }

  /** Hide the mpv surface (when navigating away from the player). */
  hideSurface(): void {
    this.surfaceState.visible = false;
    if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
      this.surfaceWindow.hide();
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  private async ensureSurface(): Promise<void> {
    if (this.ensureSurfacePromise) {
      return this.ensureSurfacePromise;
    }

    this.ensureSurfacePromise = this.createSurface();
    try {
      await this.ensureSurfacePromise;
    } finally {
      this.ensureSurfacePromise = null;
    }
  }

  private async createSurface(): Promise<void> {
    // Re-use existing surface if healthy
    if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
      return;
    }

    if (!this.mainWindow || this.mainWindow.isDestroyed()) {
      throw new Error('Main window not available for embedded player surface');
    }

    console.log(`${this.logPrefix} ensureSurface() starting`);

    const availability = native.getAvailabilityDetails();
    if (!availability.available) {
      throw new Error(availability.error ?? 'mpv addon not available or libmpv-2.dll missing');
    }

    // Create a frameless, transparent child window that will be the mpv render target.
    // It is a CHILD of the main window so Windows keeps it above the parent automatically.
    try {
      this.surfaceWindow = new BrowserWindow({
        parent: this.mainWindow,
        // Start with a reasonable default size; will be resized by setSurfaceBounds
        width:  800,
        height: 600,
        x: 0,
        y: 0,
        frame: false,
        transparent: false,       // mpv needs an opaque target
        backgroundColor: '#000000',
        resizable: false,
        movable: false,
        minimizable: false,
        maximizable: false,
        skipTaskbar: true,
        focusable: false,
        show: false,              // show only after bounds are set
        webPreferences: {
          nodeIntegration: false,
          contextIsolation: true,
        },
      });
    } catch (err) {
      throw new Error(`Failed to create embedded player surface: ${err instanceof Error ? err.message : String(err)}`);
    }

    // Load a blank page — we just need the native HWND, not actual web content
    await this.surfaceWindow.loadURL('about:blank');

    // Read the native window handle (Buffer on Windows) as bigint to avoid
    // precision loss when passing 64-bit HWND values into the addon.
    const hwndBuffer = this.surfaceWindow.getNativeWindowHandle();
    const hwnd = hwndBuffer.readBigUInt64LE(0);
    console.log(`${this.logPrefix} Child window HWND:`, hwnd.toString());

    // *** Pass HWND into initialize() so mpv sets wid BEFORE mpv_initialize ***
    // This is the critical fix: mpv must know the target window before it
    // initialises its video output (VO) pipeline.
    let ok = false;
    try {
      ok = await native.initialize(hwnd);
    } catch (err) {
      console.error(`${this.logPrefix} initialize() threw`, err);
      ok = false;
    }

    if (!ok) {
      this.surfaceWindow.destroy();
      this.surfaceWindow = null;
      throw new Error('mpv initialization failed — check libmpv-2.dll is present');
    }

    this.startWatchdog();

    // Apply previously stored bounds (if any) before showing
    if (this.lastBounds) {
      this.surfaceWindow.setBounds(this.lastBounds, false);
    }

    try {
      this.surfaceWindow.setIgnoreMouseEvents(true);
      if (this.surfaceState.visible && !this.mainWindow.isMinimized()) {
        this.surfaceWindow.showInactive();
      }
      await native.setWindowId(hwnd);
    } catch (err) {
      this.surfaceWindow.destroy();
      this.surfaceWindow = null;
      throw err;
    }
    console.log(`${this.logPrefix} ensureSurface() ok`);

    // Defensive: if the child window is closed externally, clean up
    this.surfaceWindow.on('closed', () => {
      this.surfaceWindow = null;
    });
    this.surfaceWindow.webContents.on('render-process-gone', (_event, details) => {
      console.error(`${this.logPrefix} surface render process exited`, details);
      this.surfaceWindow = null;
      this.stopPolling();
    });
    this.surfaceWindow.on('unresponsive', () => {
      console.warn(`${this.logPrefix} surface window became unresponsive`);
    });
  }

  private destroySurface(): void {
    if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
      this.surfaceWindow.destroy();
    }
    this.surfaceWindow = null;
    this.stopWatchdog();
  }

  private reapplyBounds(): void {
    if (!this.lastBounds) return;
    if (this.surfaceWindow && !this.surfaceWindow.isDestroyed()) {
      this.surfaceWindow.setBounds(this.lastBounds, false);
    }
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
    this.pollTimer = setTimeout(() => {
      void this.pollState();
    }, delayMs);
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
