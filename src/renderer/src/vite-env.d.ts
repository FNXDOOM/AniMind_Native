/// <reference types="vite/client" />

interface AnimindDesktopApi {
  settings: {
    get: () => Promise<{ backendUrl: string; supabaseUrl: string; supabaseAnonKey: string; mpvPath: string }>;
    update: (patch: Record<string, string>) => Promise<{ backendUrl: string; supabaseUrl: string; supabaseAnonKey: string; mpvPath: string }>;
  };
  auth: {
    session: () => Promise<{ userId: string; email?: string } | null>;
    signIn: (email: string, password: string) => Promise<{ userId: string; email?: string; accessToken: string }>;
    signOut: () => Promise<{ ok: boolean }>;
  };
  library: {
    getShows: () => Promise<any[]>;
    getShowDetails: (showId: string) => Promise<any>;
    getStreamTicket: (episodeId: string, audioTrackIndex?: number) => Promise<any>;
    getAudioTracks: (episodeId: string) => Promise<any[]>;
    getSubtitles: (episodeId: string) => Promise<any[]>;
  };
  player: {
    open: (url: string, title?: string) => Promise<{ ok: boolean }>;
    play: () => Promise<{ ok: boolean }>;
    pause: () => Promise<{ ok: boolean }>;
    stop: () => Promise<{ ok: boolean }>;
    seek: (seconds: number) => Promise<{ ok: boolean }>;
    getState: () => Promise<{ paused: boolean; timePos: number; duration: number }>;
    getTrackList: () => Promise<Array<{ id: number; type: string; title?: string; lang?: string; codec?: string; selected?: boolean }>>;
    setAudioTrack: (trackId: number) => Promise<{ ok: boolean }>;
    setSubtitleTrack: (trackId: number | 'no') => Promise<{ ok: boolean }>;
    addSubtitleContent: (episodeId: string, track: { id: string; label: string; language: string; content: string }) => Promise<{ ok: boolean; filePath: string }>;
  };
  progress: {
    get: (animeId: string, episodeIndex: number) => Promise<number>;
    save: (animeId: string, episodeIndex: number, timestamp: number) => Promise<{ ok: boolean }>;
  };
}

declare global {
  interface Window {
    animindDesktop: AnimindDesktopApi;
  }
}

export {};
