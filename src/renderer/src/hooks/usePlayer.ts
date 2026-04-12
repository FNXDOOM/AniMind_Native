import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { desktopApi } from '../api';
import type { PlayerTrack } from '../types';

export function usePlayer(animeId: string | null, episodeIndex: number | null) {
  const [paused, setPaused] = useState(true);
  const [timePos, setTimePos] = useState(0);
  const [duration, setDuration] = useState(0);
  const [tracks, setTracks] = useState<PlayerTrack[]>([]);
  const [error, setError] = useState('');
  const pollTimer = useRef<number | null>(null);

  const loadState = useCallback(async () => {
    try {
      const state = await desktopApi.getPlayerState();
      setPaused(state.paused);
      setTimePos(state.timePos || 0);
      setDuration(state.duration || 0);

      const list = await desktopApi.getTrackList();
      setTracks(list || []);
    } catch (err: any) {
      setError(err?.message ?? 'Unable to read player state');
    }
  }, []);

  useEffect(() => {
    const isPlayerActive = !!animeId && episodeIndex !== null;
    if (!isPlayerActive) {
      setPaused(true);
      setTimePos(0);
      setDuration(0);
      setTracks([]);
      if (pollTimer.current) {
        window.clearInterval(pollTimer.current);
        pollTimer.current = null;
      }
      return;
    }

    if (pollTimer.current) {
      window.clearInterval(pollTimer.current);
      pollTimer.current = null;
    }

    pollTimer.current = window.setInterval(() => {
      void loadState();
    }, 1500);

    return () => {
      if (pollTimer.current) {
        window.clearInterval(pollTimer.current);
        pollTimer.current = null;
      }
    };
  }, [animeId, episodeIndex, loadState]);

  useEffect(() => {
    if (!animeId || episodeIndex === null) return;

    const saveId = window.setInterval(() => {
      void desktopApi.saveProgress(animeId, episodeIndex, timePos);
    }, 10000);

    return () => window.clearInterval(saveId);
  }, [animeId, episodeIndex, timePos]);

  const audioTracks = useMemo(() => tracks.filter(t => t.type === 'audio'), [tracks]);
  const subtitleTracks = useMemo(() => tracks.filter(t => t.type === 'sub'), [tracks]);

  return {
    paused,
    timePos,
    duration,
    tracks,
    audioTracks,
    subtitleTracks,
    error,
    refresh: loadState,
    play: () => desktopApi.play(),
    pause: () => desktopApi.pause(),
    stop: () => desktopApi.stop(),
    seek: (seconds: number) => desktopApi.seek(seconds),
    setAudioTrack: (trackId: number) => desktopApi.setAudioTrack(trackId),
    setSubtitleTrack: (trackId: number | 'no') => desktopApi.setSubtitleTrack(trackId),
  };
}
