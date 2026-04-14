import type { AppSettings, Episode, SessionInfo, Show, ShowDetails, StreamTicket, SubtitleTrack } from './types';

export const desktopApi = {
  getSettings: () => window.animindDesktop.settings.get(),
  saveSettings: (patch: Partial<AppSettings>) => window.animindDesktop.settings.update(patch as Record<string, string>),
  getSetupStatus: () => window.animindDesktop.settings.setupStatus(),
  testMpv: (pathOverride?: string) => window.animindDesktop.settings.testMpv(pathOverride),

  getSession: () => window.animindDesktop.auth.session() as Promise<SessionInfo | null>,
  getAccessToken: () => window.animindDesktop.auth.token() as Promise<string | null>,
  signIn: (email: string, password: string) => window.animindDesktop.auth.signIn(email, password),
  signInWithGoogle: () => window.animindDesktop.auth.signInWithGoogle() as Promise<SessionInfo>,
  signOut: () => window.animindDesktop.auth.signOut(),

  getShows: () => window.animindDesktop.library.getShows() as Promise<Show[]>,
  getShowDetails: (showId: string) => window.animindDesktop.library.getShowDetails(showId) as Promise<ShowDetails>,
  getStreamTicket: (episodeId: string, audioTrackIndex?: number) =>
    window.animindDesktop.library.getStreamTicket(episodeId, audioTrackIndex) as Promise<StreamTicket>,
  getAudioTracks: (episodeId: string) => window.animindDesktop.library.getAudioTracks(episodeId),
  getSubtitles: (episodeId: string) => window.animindDesktop.library.getSubtitles(episodeId) as Promise<SubtitleTrack[]>,

  openPlayer: (url: string, title?: string) => window.animindDesktop.player.open(url, title),
  play: () => window.animindDesktop.player.play(),
  pause: () => window.animindDesktop.player.pause(),
  stop: () => window.animindDesktop.player.stop(),
  seek: (seconds: number) => window.animindDesktop.player.seek(seconds),
  getPlayerState: () => window.animindDesktop.player.getState(),
  isPlayerRunning: () => window.animindDesktop.player.isRunning() as Promise<{ running: boolean }>,
  getTrackList: () => window.animindDesktop.player.getTrackList(),
  setAudioTrack: (trackId: number) => window.animindDesktop.player.setAudioTrack(trackId),
  setSubtitleTrack: (trackId: number | 'no') => window.animindDesktop.player.setSubtitleTrack(trackId),
  addSubtitleContent: (episodeId: string, track: SubtitleTrack) =>
    window.animindDesktop.player.addSubtitleContent(episodeId, track),

  getProgress: (animeId: string, episodeIndex: number) => window.animindDesktop.progress.get(animeId, episodeIndex),
  saveProgress: (animeId: string, episodeIndex: number, timestamp: number) =>
    window.animindDesktop.progress.save(animeId, episodeIndex, timestamp),
};

export type { Episode };
