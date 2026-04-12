import { app, BrowserWindow, ipcMain } from 'electron';
import path from 'path';
import { authService } from './services/auth.service';
import { settingsService } from './services/settings.service';
import { libraryService } from './services/library.service';
import { playerService } from './services/player.service';
import { subtitleService } from './services/subtitle.service';
import { progressService } from './services/progress.service';

let mainWindow: BrowserWindow | null = null;

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 720,
    title: 'Animind Desktop',
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  const devServerUrl = process.env.VITE_DEV_SERVER_URL;
  if (devServerUrl) {
    void mainWindow.loadURL(devServerUrl);
  } else {
    void mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }
}

function registerIpcHandlers(): void {
  ipcMain.handle('settings:get', async () => settingsService.getSettings());
  ipcMain.handle('settings:update', async (_event, patch: Record<string, string>) => settingsService.saveSettings(patch));

  ipcMain.handle('auth:session', async () => authService.getSessionInfo());
  ipcMain.handle('auth:signin', async (_event, payload: { email: string; password: string }) => {
    const result = await authService.signIn(payload.email, payload.password);
    return {
      userId: result.user.id,
      email: result.user.email ?? undefined,
      accessToken: result.accessToken,
    };
  });
  ipcMain.handle('auth:signout', async () => {
    await authService.signOut();
    return { ok: true };
  });

  ipcMain.handle('library:shows', async () => libraryService.getShows());
  ipcMain.handle('library:showDetails', async (_event, showId: string) => libraryService.getShowDetails(showId));
  ipcMain.handle('library:streamTicket', async (_event, payload: { episodeId: string; audioTrackIndex?: number }) =>
    libraryService.getEpisodeStreamTicket(payload.episodeId, payload.audioTrackIndex)
  );
  ipcMain.handle('library:audioTracks', async (_event, episodeId: string) => libraryService.getEpisodeAudioTracks(episodeId));
  ipcMain.handle('library:subtitles', async (_event, episodeId: string) => libraryService.getEpisodeSubtitles(episodeId));

  ipcMain.handle('player:open', async (_event, payload: { url: string; title?: string }) => {
    await playerService.open(payload.url, payload.title ?? 'Animind Desktop');
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
  ipcMain.handle('player:state', async () => playerService.getState());
  ipcMain.handle('player:trackList', async () => playerService.getTrackList());
  ipcMain.handle('player:setAudioTrack', async (_event, trackId: number) => {
    await playerService.setAudioTrack(trackId);
    return { ok: true };
  });
  ipcMain.handle('player:setSubtitleTrack', async (_event, trackId: number | 'no') => {
    await playerService.setSubtitleTrack(trackId);
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

  ipcMain.handle('progress:get', async (_event, payload: { animeId: string; episodeIndex: number }) =>
    progressService.getProgress(payload.animeId, payload.episodeIndex)
  );
  ipcMain.handle('progress:save', async (_event, payload: { animeId: string; episodeIndex: number; timestamp: number }) => {
    await progressService.saveProgress(payload.animeId, payload.episodeIndex, payload.timestamp);
    return { ok: true };
  });
}

app.whenReady().then(async () => {
  await settingsService.getSettings();
  await authService.restoreSession().catch(() => undefined);
  registerIpcHandlers();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', async () => {
  await playerService.stop().catch(() => undefined);
  if (process.platform !== 'darwin') app.quit();
});
