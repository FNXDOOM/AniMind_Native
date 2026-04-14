import { contextBridge, ipcRenderer } from 'electron';

const api = {
  settings: {
    get: () => ipcRenderer.invoke('settings:get'),
    update: (patch: Record<string, string>) => ipcRenderer.invoke('settings:update', patch),
    setupStatus: () => ipcRenderer.invoke('settings:setupStatus'),
    testMpv: (pathOverride?: string) => ipcRenderer.invoke('settings:testMpv', pathOverride),
  },
  auth: {
    session: () => ipcRenderer.invoke('auth:session'),
    signIn: (email: string, password: string) => ipcRenderer.invoke('auth:signin', { email, password }),
    signInWithGoogle: () => ipcRenderer.invoke('auth:google'),
    signOut: () => ipcRenderer.invoke('auth:signout'),
    token: () => ipcRenderer.invoke('auth:token'),
  },
  library: {
    getShows: () => ipcRenderer.invoke('library:shows'),
    getShowDetails: (showId: string) => ipcRenderer.invoke('library:showDetails', showId),
    getStreamTicket: (episodeId: string, audioTrackIndex?: number, clientType?: 'browser' | 'native') =>
      ipcRenderer.invoke('library:streamTicket', { episodeId, audioTrackIndex, clientType }),
    getAudioTracks: (episodeId: string) => ipcRenderer.invoke('library:audioTracks', episodeId),
    getSubtitles: (episodeId: string) => ipcRenderer.invoke('library:subtitles', episodeId),
  },
  player: {
    open: (url: string, title?: string) => ipcRenderer.invoke('player:open', { url, title }),
    play: () => ipcRenderer.invoke('player:play'),
    pause: () => ipcRenderer.invoke('player:pause'),
    stop: () => ipcRenderer.invoke('player:stop'),
    seek: (seconds: number) => ipcRenderer.invoke('player:seek', seconds),
    getState: () => ipcRenderer.invoke('player:state'),
    getAudioState: () => ipcRenderer.invoke('player:audioState'),
    isRunning: () => ipcRenderer.invoke('player:isRunning'),
    getTrackList: () => ipcRenderer.invoke('player:trackList'),
    setAudioTrack: (trackId: number) => ipcRenderer.invoke('player:setAudioTrack', trackId),
    setSubtitleTrack: (trackId: number | 'no') => ipcRenderer.invoke('player:setSubtitleTrack', trackId),
    setVolume: (volume: number) => ipcRenderer.invoke('player:setVolume', volume),
    setMuted: (muted: boolean) => ipcRenderer.invoke('player:setMuted', muted),
    addSubtitleContent: (episodeId: string, track: { id: string; label: string; language: string; content: string }) =>
      ipcRenderer.invoke('player:addSubtitleContent', { episodeId, track }),
  },
  progress: {
    get: (animeId: string, episodeIndex: number) => ipcRenderer.invoke('progress:get', { animeId, episodeIndex }),
    save: (animeId: string, episodeIndex: number, timestamp: number) =>
      ipcRenderer.invoke('progress:save', { animeId, episodeIndex, timestamp }),
  },
};

contextBridge.exposeInMainWorld('animindDesktop', api);
