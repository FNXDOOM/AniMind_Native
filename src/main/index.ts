import { app, BrowserWindow, ipcMain, screen, shell } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';
import { existsSync } from 'fs';
import { authService } from './services/auth.service';
import { settingsService } from './services/settings.service';
import { libraryService } from './services/library.service';
import { playerService } from './services/player.service';
import { mpvEmbeddedBackend } from './services/player-backends/mpv-embedded.backend';
import { subtitleService } from './services/subtitle.service';
import { progressService } from './services/progress.service';

let mainWindow: BrowserWindow | null = null;
const currentDir = path.dirname(fileURLToPath(import.meta.url));
const pendingProtocolUrls: string[] = [];

function focusMainWindow(): void {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
}

function extractProtocolUrl(args: string[]): string | null {
  const value = args.find(arg => typeof arg === 'string' && arg.toLowerCase().startsWith('animind://'));
  return value ?? null;
}

async function handleProtocolUrl(url: string): Promise<void> {
  try {
    const handled = await authService.handleAuthCallback(url);
    if (handled) {
      focusMainWindow();
      // Tell the renderer that auth state has changed so it can refresh its session
      mainWindow?.webContents.send('auth:session-changed');
    }
  } catch (error) {
    console.error('[Auth] Failed to handle protocol callback URL:', error);
  }
}

if (process.defaultApp) {
  if (process.argv.length >= 2) {
    app.setAsDefaultProtocolClient('animind', process.execPath, [path.resolve(process.argv[1])]);
  }
} else {
  app.setAsDefaultProtocolClient('animind');
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

app.on('open-url', (event, url) => {
  event.preventDefault();
  pendingProtocolUrls.push(url);
  if (app.isReady()) {
    void handleProtocolUrl(url);
  }
});

const cacheDir = path.join(app.getPath('userData'), 'ChromiumCache');
app.commandLine.appendSwitch('disk-cache-dir', cacheDir);
app.commandLine.appendSwitch('disable-gpu-shader-disk-cache');

// Disable Direct Composition to allow WS_CHILD window blending with transparent HTML
app.commandLine.appendSwitch('disable-direct-composition');
app.commandLine.appendSwitch('in-process-gpu');

function createWindow(): void {
  const preloadMjsPath = path.join(currentDir, '../preload/index.mjs');
  const preloadJsPath = path.join(currentDir, '../preload/index.js');
  const preloadPath = existsSync(preloadMjsPath) ? preloadMjsPath : preloadJsPath;

  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 720,
    title: 'Animind Desktop',
    backgroundColor: '#00000000',
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
      backgroundThrottling: false,
    },
  });

  mpvEmbeddedBackend.setMainWindow(mainWindow);

  mainWindow.webContents.on('preload-error', (_event, preloadErrPath, error) => {
    console.error('[Preload] Failed to load preload script:', preloadErrPath, error?.message || error);
  });

  mainWindow.webContents.on('did-fail-load', (_event, code, desc, url) => {
    console.error('[Renderer] Failed to load:', { code, desc, url });
  });

  mainWindow.webContents.on('console-message', (_event, level, message) => {
    if (level === 3) console.error('[Renderer Console]', message);
  });

  const devServerUrl = process.env.ELECTRON_RENDERER_URL || process.env.VITE_DEV_SERVER_URL;
  if (devServerUrl) {
    void mainWindow.loadURL(devServerUrl);
  } else {
    void mainWindow.loadFile(path.join(currentDir, '../renderer/index.html'));
  }
}

/**
 * resolveSurfaceBounds
 *
 * Normalises bounds from the renderer into screen-absolute, DPI-scaled physical
 * pixels that can be forwarded to the native addon.
 *
 * 'screen'  — renderer already sent (window.screenX + rect.left) * devicePixelRatio.
 *              No further transformation needed.
 * 'content' — CSS logical pixels relative to viewport (legacy path).
 *              Offset by the window content area origin and scale by DPI.
 */
function resolveSurfaceBounds(
  senderWindow: BrowserWindow | null,
  bounds: { x: number; y: number; width: number; height: number; coordinateSpace?: 'content' | 'screen' },
): { x: number; y: number; width: number; height: number } {
  const traceBounds = process.env.ANIMIND_MPV_TRACE_BOUNDS === '1';
  const width  = Math.max(4, Math.round(bounds.width));
  const height = Math.max(4, Math.round(bounds.height));

  // 'screen' — already DPI-scaled physical pixels. Pass through as-is.
  if (bounds.coordinateSpace === 'screen' || !senderWindow) {
    const resolved = { x: Math.round(bounds.x), y: Math.round(bounds.y), width, height };
    if (traceBounds) {
      console.log('[MPV bounds] resolveSurfaceBounds(screen/passthrough)', { input: bounds, resolved });
    }
    return resolved;
  }

  // 'content' (legacy) — CSS logical pixels → physical screen pixels.
  const contentBounds = senderWindow.getContentBounds();
  const display = screen.getDisplayMatching(contentBounds);
  const sf = display.scaleFactor || 1;
  const resolved = {
    x:      Math.round((contentBounds.x + bounds.x) * sf),
    y:      Math.round((contentBounds.y + bounds.y) * sf),
    width:  Math.max(4, Math.round(bounds.width  * sf)),
    height: Math.max(4, Math.round(bounds.height * sf)),
  };
  if (traceBounds) {
    console.log('[MPV bounds] resolveSurfaceBounds(content→screen)', {
      input: bounds, contentBounds, scaleFactor: sf, resolved,
    });
  }
  return resolved;
}

function registerIpcHandlers(): void {
  // ── Settings ──────────────────────────────────────────────────────────────
  ipcMain.handle('settings:get', async () => settingsService.getSettings());
  ipcMain.handle('settings:update', async (_event, patch: Record<string, string>) => settingsService.saveSettings(patch));
  ipcMain.handle('settings:setupStatus', async () => {
    const settings = await settingsService.getSettings();
    const settingsValidation = settingsService.validateSettings(settings);
    const mpv = settingsValidation.missing.includes('mpvPath')
      ? { available: false, path: settings.mpvPath, error: 'mpv path is missing.' }
      : await playerService.checkAvailability(settings.mpvPath);

    return {
      settings,
      missing: settingsValidation.missing,
      ready: settingsValidation.ready && mpv.available,
      mpv,
    };
  });
  ipcMain.handle('settings:testMpv', async (_event, pathOverride?: string) => playerService.checkAvailability(pathOverride));

  // ── Auth ──────────────────────────────────────────────────────────────────
  ipcMain.handle('auth:session', async () => authService.getSessionInfo());

  ipcMain.handle('auth:signin', async (_event, payload: { email: string; password: string }) => {
    const result = await authService.signIn(payload.email, payload.password);
    return {
      userId: result.userId,
      email: result.email ?? undefined,
      accessToken: result.accessToken,
    };
  });

  ipcMain.handle('auth:google', async () => {
    const result = await authService.signInWithGoogle(async (url: string) => {
      await shell.openExternal(url);
    });
    return {
      userId: result.userId,
      email: result.email ?? undefined,
      accessToken: result.accessToken,
    };
  });

  ipcMain.handle('auth:signin:browser-bridge', async () => {
    const result = await authService.signInBrowserBridge(async (url: string) => {
      await shell.openExternal(url);
    });
    return {
      userId: result.userId,
      email: result.email ?? undefined,
      accessToken: result.accessToken,
    };
  });

  ipcMain.handle('auth:signout', async () => {
    await authService.signOut();
    return { ok: true };
  });

  ipcMain.handle('auth:token', async () => authService.getAccessToken());

  // ── Library ───────────────────────────────────────────────────────────────
  ipcMain.handle('library:shows', async () => libraryService.getShows());
  ipcMain.handle('library:showDetails', async (_event, showId: string) => libraryService.getShowDetails(showId));
  ipcMain.handle(
    'library:streamTicket',
    async (_event, payload: { episodeId: string; audioTrackIndex?: number; clientType?: 'browser' | 'native' }) =>
      libraryService.getEpisodeStreamTicket(payload.episodeId, payload.audioTrackIndex, payload.clientType ?? 'browser')
  );
  ipcMain.handle('library:audioTracks', async (_event, episodeId: string) => libraryService.getEpisodeAudioTracks(episodeId));
  ipcMain.handle('library:subtitles', async (_event, episodeId: string) => libraryService.getEpisodeSubtitles(episodeId));

  // ── Player ────────────────────────────────────────────────────────────────
  ipcMain.handle('player:open', async (_event, payload: { url: string; title?: string }) => {
    const token = await authService.getAccessToken().catch(() => null);
    await playerService.open(payload.url, payload.title ?? 'Animind Desktop', token ?? undefined);
    return { ok: true };
  });
  ipcMain.handle('player:play', async () => {
    await playerService.play();
    return { ok: true };
  });
  ipcMain.handle('player:pause', async () => {
    await playerService.pause();
    return { ok: true };
  });
  ipcMain.handle('player:stop', async () => {
    await playerService.stop();
    return { ok: true };
  });
  ipcMain.handle('player:seek', async (_event, seconds: number) => {
    await playerService.seek(seconds);
    return { ok: true };
  });
  ipcMain.handle('player:state', async () => {
    try {
      return await playerService.getState();
    } catch {
      return { paused: true, timePos: 0, duration: 0 };
    }
  });
  ipcMain.handle('player:audioState', async () => {
    try {
      return await playerService.getAudioState();
    } catch {
      return { volume: 100, muted: false };
    }
  });
  ipcMain.handle('player:isRunning', async () => playerService.isRunning());
  ipcMain.handle('player:trackList', async () => {
    try {
      return await playerService.getTrackList();
    } catch {
      return [];
    }
  });
  ipcMain.handle('player:setAudioTrack', async (_event, trackId: number) => {
    await playerService.setAudioTrack(trackId);
    return { ok: true };
  });
  ipcMain.handle('player:setSubtitleTrack', async (_event, trackId: number | 'no') => {
    await playerService.setSubtitleTrack(trackId);
    return { ok: true };
  });
  ipcMain.handle('player:addSubtitleFile', async (_event, path: string) => {
    await playerService.addSubtitleFile(path);
    return { ok: true };
  });
  ipcMain.handle('player:setVolume', async (_event, volume: number) => {
    await playerService.setVolume(volume);
    return { ok: true };
  });
  ipcMain.handle('player:setMuted', async (_event, muted: boolean) => {
    await playerService.setMuted(muted);
    return { ok: true };
  });
  ipcMain.handle(
    'player:addSubtitleContent',
    async (_event, payload: { episodeId: string; track: { id: string; label: string; language: string; content: string } }) => {
      const filePath = await subtitleService.writeTrackToTempFile(payload.episodeId, payload.track);
      await playerService.addSubtitleFile(filePath);
      return { ok: true, filePath };
    }
  );
  ipcMain.handle(
    'player:setSurfaceBounds',
    async (event, bounds: { x: number; y: number; width: number; height: number; coordinateSpace?: 'content' | 'screen' }) => {
      const values = [bounds.x, bounds.y, bounds.width, bounds.height];
      if (values.some(value => !Number.isFinite(value))) {
        throw new Error('Invalid surface bounds payload.');
      }

      const senderWindow = BrowserWindow.fromWebContents(event.sender);
      mpvEmbeddedBackend.setSurfaceBounds(resolveSurfaceBounds(senderWindow, bounds));
      return { ok: true };
    },
  );
  ipcMain.handle('player:showSurface', async () => {
    mpvEmbeddedBackend.showSurface();
    return { ok: true };
  });
  ipcMain.handle('player:hideSurface', async () => {
    mpvEmbeddedBackend.hideSurface();
    return { ok: true };
  });

  // ── Progress ──────────────────────────────────────────────────────────────
  ipcMain.handle('progress:get', async (_event, payload: { animeId: string; episodeIndex: number }) =>
    progressService.getProgress(payload.animeId, payload.episodeIndex)
  );
  ipcMain.handle('progress:save', async (_event, payload: { animeId: string; episodeIndex: number; timestamp: number }) => {
    return progressService.saveProgress(payload.animeId, payload.episodeIndex, payload.timestamp);
  });
}

app.whenReady().then(async () => {
  await settingsService.getSettings();
  await authService.restoreSession().catch(() => undefined);
  registerIpcHandlers();
  createWindow();

  void playerService.checkAvailability().then(result => {
    if (!result.available) {
      console.warn('[Player] Startup availability check failed:', result.error ?? 'Unknown player startup failure');
    }
  }).catch(error => {
    console.warn('[Player] Startup availability check crashed:', error);
  });

  const startupProtocolUrl = extractProtocolUrl(process.argv);
  if (startupProtocolUrl) {
    void handleProtocolUrl(startupProtocolUrl);
  }

  if (pendingProtocolUrls.length > 0) {
    const urls = [...pendingProtocolUrls];
    pendingProtocolUrls.length = 0;
    for (const url of urls) {
      void handleProtocolUrl(url);
    }
  }

  app.on('second-instance', (_event, commandLine) => {
    focusMainWindow();
    const protocolUrl = extractProtocolUrl(commandLine);
    if (protocolUrl) {
      void handleProtocolUrl(protocolUrl);
    }
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', async () => {
  await playerService.stop().catch(() => undefined);
  if (process.platform !== 'darwin') app.quit();
});
