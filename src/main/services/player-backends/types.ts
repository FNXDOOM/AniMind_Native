export interface MpvTrack {
  id: number;
  type: 'audio' | 'sub' | 'video' | string;
  title?: string;
  lang?: string;
  codec?: string;
  selected?: boolean;
}

export interface PlayerState {
  paused: boolean;
  timePos: number;
  duration: number;
}

export interface PlayerAudioState {
  volume: number;
  muted: boolean;
}

export interface MpvAvailability {
  available: boolean;
  path: string;
  version?: string;
  error?: string;
}

export interface PlayerBackend {
  checkAvailability(pathOverride?: string): Promise<MpvAvailability>;
  open(url: string, title?: string): Promise<void>;
  stop(): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  seek(seconds: number): Promise<void>;
  setAudioTrack(trackId: number): Promise<void>;
  setSubtitleTrack(trackId: number | 'no'): Promise<void>;
  setVolume(volume: number): Promise<void>;
  setMuted(muted: boolean): Promise<void>;
  addSubtitleFile(filePath: string): Promise<void>;
  getTrackList(): Promise<MpvTrack[]>;
  getState(): Promise<PlayerState>;
  getAudioState(): Promise<PlayerAudioState>;
  isRunning(): Promise<{ running: boolean }>;
}
