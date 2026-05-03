/// <reference types="vite/client" />

import type { AudioTrack, PlayerTrack, SubtitleTrack } from './types';

interface AnimindDesktopApi {
  settings: {
    get: () => Promise<{ backendUrl: string; clerkPublishableKey: string; mpvPath: string }>;
    update: (patch: Record<string, string>) => Promise<{ backendUrl: string; clerkPublishableKey: string; mpvPath: string }>;
    setupStatus: () => Promise<{
      settings: { backendUrl: string; clerkPublishableKey: string; mpvPath: string };
      missing: string[];
      ready: boolean;
      mpv: { available: boolean; path: string; version?: string; error?: string };
    }>;
    testMpv: (pathOverride?: string) => Promise<{ available: boolean; path: string; version?: string; error?: string }>;
  };
  auth: {
    session: () => Promise<{ userId: string; email?: string } | null>;
    token: () => Promise<string | null>;
    signIn: (email: string, password: string) => Promise<{ userId: string; email?: string; accessToken: string }>;
    signInWithGoogle: () => Promise<{ userId: string; email?: string; accessToken: string }>;
    signInBrowserBridge: () => Promise<{ ok: boolean }>;
    signOut: () => Promise<{ ok: boolean }>;
    onSessionChanged: (cb: () => void) => () => void;
  };
  library: {
    getShows: () => Promise<any[]>;
    getShowDetails: (showId: string) => Promise<any>;
    getStreamTicket: (episodeId: string, audioTrackIndex?: number, clientType?: 'browser' | 'native') => Promise<any>;
    getAudioTracks: (episodeId: string) => Promise<AudioTrack[]>;
    getSubtitles: (episodeId: string) => Promise<SubtitleTrack[]>;
  };
  player: {
    open: (url: string, title?: string) => Promise<{ ok: boolean }>;
    play: () => Promise<{ ok: boolean }>;
    pause: () => Promise<{ ok: boolean }>;
    stop: () => Promise<{ ok: boolean }>;
    seek: (seconds: number) => Promise<{ ok: boolean }>;
    getState: () => Promise<{ paused: boolean; timePos: number; duration: number }>;
    getAudioState: () => Promise<{ volume: number; muted: boolean }>;
    isRunning: () => Promise<{ running: boolean }>;
    getTrackList: () => Promise<PlayerTrack[]>;
    setAudioTrack: (trackId: number) => Promise<{ ok: boolean }>;
    setSubtitleTrack: (trackId: number | 'no') => Promise<{ ok: boolean }>;
    addSubtitleFile: (path: string) => Promise<{ ok: boolean }>;
    setVolume: (volume: number) => Promise<{ ok: boolean }>;
    setMuted: (muted: boolean) => Promise<{ ok: boolean }>;
    addSubtitleContent: (episodeId: string, track: { id: string; label: string; language: string; content: string }) => Promise<{ ok: boolean; filePath: string }>;
    setSurfaceBounds: (bounds: { x: number; y: number; width: number; height: number; coordinateSpace?: 'content' | 'screen' }) => Promise<{ ok: boolean }>;
    showSurface: () => Promise<{ ok: boolean }>;
    hideSurface: () => Promise<{ ok: boolean }>;
    onStateChanged: (cb: (state: { paused: boolean; timePos: number; duration: number }) => void) => () => void;
  };
  progress: {
    get: (animeId: string, episodeIndex: number) => Promise<number>;
    save: (animeId: string, episodeIndex: number, timestamp: number) => Promise<{ saved: boolean; reason?: 'not-authenticated' | 'local-only' }>;
  };
}

declare global {
  interface Window {
    animindDesktop: AnimindDesktopApi;
  }
}

export {};
