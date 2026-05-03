import { useCallback, useEffect, useRef, useState } from 'react';
import { desktopApi } from '../api';

export interface PlayerController {
  play: () => Promise<void>;
  pause: () => Promise<void>;
  seek: (time: number) => Promise<void>;
  setVolume: (volume: number) => Promise<void>;
  setMuted: (muted: boolean) => Promise<void>;
  setAudioTrack: (id: number) => Promise<boolean>;
  setSubtitleTrack: (id: number | 'no') => Promise<boolean>;
  getTrackList: () => Promise<any[]>;
  stop: () => Promise<void>;
  currentTime: number;
  duration: number;
  paused: boolean;
  volume: number;
  muted: boolean;
  isRunning: boolean;
}

interface UsePlayerControllerOptions {
  autoLoadState?: boolean;
  stateUpdateInterval?: number;
}

/**
 * Hook for controlling the embedded libmpv player.
 * Polls player state from the backend and provides a unified control API.
 */
export function usePlayerController(
  url?: string,
  options: UsePlayerControllerOptions = {}
): PlayerController {
  const { autoLoadState = true, stateUpdateInterval = 500 } = options;
  
  const [paused, setPaused] = useState(true);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(85);
  const [muted, setMuted] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  
  const pollTimerRef = useRef<number | null>(null);
  const urlRef = useRef(url);
  const isLoadedRef = useRef(false);

  // Update ref when url changes
  useEffect(() => {
    urlRef.current = url;
  }, [url]);

  // Load and initialize player when URL is provided
  useEffect(() => {
    if (!url || isLoadedRef.current) return;

    const initPlayer = async () => {
      try {
        await desktopApi.openPlayer(url);
        isLoadedRef.current = true;
        // Start polling state after opening
        startPolling();
      } catch (err) {
        console.error('Failed to open player:', err);
      }
    };

    initPlayer();

    return () => {
      if (pollTimerRef.current) {
        window.clearInterval(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
  }, [url]);

  const pollState = useCallback(async () => {
    try {
      const state = await desktopApi.getPlayerState();
      setPaused(state.paused);
      setCurrentTime(state.timePos || 0);
      setDuration(state.duration || 0);

      const audioState = await desktopApi.getPlayerAudioState();
      setVolume(audioState.volume ?? 85);
      setMuted(audioState.muted ?? false);

      const running = await desktopApi.isPlayerRunning();
      setIsRunning(running.running ?? false);
    } catch (err) {
      console.error('Failed to poll player state:', err);
    }
  }, []);

  const startPolling = useCallback(() => {
    if (pollTimerRef.current !== null) return;

    pollTimerRef.current = window.setInterval(() => {
      void pollState();
    }, stateUpdateInterval);
  }, [pollState, stateUpdateInterval]);

  const stopPolling = useCallback(() => {
    if (pollTimerRef.current !== null) {
      window.clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
  }, []);

  // Start polling if autoLoadState is enabled
  useEffect(() => {
    if (autoLoadState) {
      startPolling();
      return () => stopPolling();
    }
  }, [autoLoadState, startPolling, stopPolling]);

  // Listen for player state changes from main process
  useEffect(() => {
    const handlePlayerStateChange = (event: Event) => {
      const detail = (event as any).detail;
      if (detail) {
        setPaused(detail.paused);
        setCurrentTime(detail.timePos || 0);
        setDuration(detail.duration || 0);
      }
    };

    window.addEventListener('player:stateChanged', handlePlayerStateChange as EventListener);
    return () => {
      window.removeEventListener('player:stateChanged', handlePlayerStateChange as EventListener);
    };
  }, []);

  const play = useCallback(async () => {
    await desktopApi.play();
    setPaused(false);
  }, []);

  const pause = useCallback(async () => {
    await desktopApi.pause();
    setPaused(true);
  }, []);

  const seek = useCallback(async (time: number) => {
    await desktopApi.seek(time);
    setCurrentTime(time);
  }, []);

  const setVolumeCallback = useCallback(async (vol: number) => {
    await desktopApi.setPlayerVolume(vol);
    setVolume(vol);
  }, []);

  const setMutedCallback = useCallback(async (mute: boolean) => {
    await desktopApi.setPlayerMuted(mute);
    setMuted(mute);
  }, []);

  const setAudioTrack = useCallback(async (id: number) => {
    return await desktopApi.setAudioTrack(id);
  }, []);

  const setSubtitleTrack = useCallback(async (id: number | 'no') => {
    return await desktopApi.setSubtitleTrack(id);
  }, []);

  const getTrackList = useCallback(async () => {
    return await desktopApi.getTrackList();
  }, []);

  const stop = useCallback(async () => {
    await desktopApi.stop();
    stopPolling();
    setPaused(true);
    setCurrentTime(0);
    setDuration(0);
    isLoadedRef.current = false;
  }, [stopPolling]);

  return {
    play,
    pause,
    seek,
    setVolume: setVolumeCallback,
    setMuted: setMutedCallback,
    setAudioTrack,
    setSubtitleTrack,
    getTrackList,
    stop,
    get currentTime() {
      return currentTime;
    },
    get duration() {
      return duration;
    },
    get paused() {
      return paused;
    },
    get volume() {
      return volume;
    },
    get muted() {
      return muted;
    },
    get isRunning() {
      return isRunning;
    },
  };
}
