import type { AppSettings, AudioTrack, Episode, PlayerTrack, Show, ShowDetails, StreamTicket, SubtitleTrack } from './types';

export const desktopApi = {
  getSettings: () => window.animindDesktop.settings.get(),
  saveSettings: (patch: Partial<AppSettings>) => window.animindDesktop.settings.update(patch as Record<string, string>),
  getSetupStatus: () => window.animindDesktop.settings.setupStatus(),
  testMpv: (pathOverride?: string) => window.animindDesktop.settings.testMpv(pathOverride),

  getSession: () => window.animindDesktop.auth.session() as Promise<{ userId: string; email?: string } | null>,
  getAccessToken: () => window.animindDesktop.auth.token() as Promise<string | null>,
  /** Sign in with email + password via Clerk FAPI (main process). */
  signIn: (email: string, password: string) => window.animindDesktop.auth.signIn(email, password),
  signInWithGoogle: () => window.animindDesktop.auth.signInWithGoogle(),
  /** Sign in using the website Clerk flow in an in-app auth window (production-safe). */
  signInBrowserBridge: () => window.animindDesktop.auth.signInBrowserBridge(),
  signOut: () => window.animindDesktop.auth.signOut(),
  onSessionChanged: (cb: () => void) => window.animindDesktop.auth.onSessionChanged(cb),

  getShows: () => window.animindDesktop.library.getShows() as Promise<Show[]>,
  getShowDetails: (showId: string) => window.animindDesktop.library.getShowDetails(showId) as Promise<ShowDetails>,
  getStreamTicket: (episodeId: string, audioTrackIndex?: number, clientType?: 'browser' | 'native') =>
    window.animindDesktop.library.getStreamTicket(episodeId, audioTrackIndex, clientType) as Promise<StreamTicket>,
  getAudioTracks: (episodeId: string) => window.animindDesktop.library.getAudioTracks(episodeId) as Promise<AudioTrack[]>,
  getSubtitles: (episodeId: string) => window.animindDesktop.library.getSubtitles(episodeId) as Promise<SubtitleTrack[]>,

  openPlayer: (url: string, title?: string) => window.animindDesktop.player.open(url, title),
  play: () => window.animindDesktop.player.play(),
  pause: () => window.animindDesktop.player.pause(),
  stop: () => window.animindDesktop.player.stop(),
  seek: (seconds: number) => window.animindDesktop.player.seek(seconds),
  getPlayerState: () => window.animindDesktop.player.getState(),
  getPlayerAudioState: () => window.animindDesktop.player.getAudioState() as Promise<{ volume: number; muted: boolean }>,
  isPlayerRunning: () => window.animindDesktop.player.isRunning() as Promise<{ running: boolean }>,
  getTrackList: () => window.animindDesktop.player.getTrackList() as Promise<PlayerTrack[]>,
  setAudioTrack: async (trackId: number) => {
    const res = await window.animindDesktop.player.setAudioTrack(trackId) as { ok: boolean };
    return res.ok;
  },
  setSubtitleTrack: async (trackId: number | 'no') => {
    const res = await window.animindDesktop.player.setSubtitleTrack(trackId) as { ok: boolean };
    return res.ok;
  },
  addSubtitleFile: async (path: string) => {
    const res = await window.animindDesktop.player.addSubtitleFile(path) as { ok: boolean };
    return res.ok;
  },
  setPlayerVolume: (volume: number) => window.animindDesktop.player.setVolume(volume),
  setPlayerMuted: (muted: boolean) => window.animindDesktop.player.setMuted(muted),
  // Embedded surface management
  setSurfaceBounds: (bounds: { x: number; y: number; width: number; height: number; coordinateSpace?: 'content' | 'screen' }) =>
    window.animindDesktop.player.setSurfaceBounds(bounds),
  showSurface: () => window.animindDesktop.player.showSurface(),
  hideSurface: () => window.animindDesktop.player.hideSurface(),
  addSubtitleContent: (episodeId: string, track: SubtitleTrack) => {
    const { id, label, language, content } = track;
    return window.animindDesktop.player.addSubtitleContent(episodeId, { id, label, language, content });
  },

  getProgress: (animeId: string, episodeIndex: number) => window.animindDesktop.progress.get(animeId, episodeIndex),
  saveProgress: (animeId: string, episodeIndex: number, timestamp: number) =>
    window.animindDesktop.progress.save(animeId, episodeIndex, timestamp),
};

export type { Episode };
