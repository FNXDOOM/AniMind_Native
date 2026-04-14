import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { AudioTrack, Episode, SubtitleTrack } from '../types';
import type { PendingSync } from '../App';
import { useSyncplay } from '../hooks/useSyncplay';
import { SyncplayPanel } from '../components/SyncplayPanel';
import { desktopApi } from '../api';

type IconProps = { className?: string };

type Props = {
  currentUserId: string;
  animeId: string;
  animeTitle: string;
  episode: Episode;
  streamInfo: { clientType?: 'native' | 'browser'; message?: string } | null;
  streamUrl: string;
  audioTracks: AudioTrack[];
  selectedAudioTrackIndex: number | null;
  resumeFromSeconds: number;
  loading: boolean;
  subtitles: SubtitleTrack[];
  error: string;
  pendingSync: PendingSync;
  onSyncConsumed: () => void;
  onSelectAudioTrack: (streamIndex: number | null, currentTime: number) => Promise<unknown>;
  onSaveProgress: (seconds: number) => Promise<unknown>;
  onOpenExternal: () => Promise<unknown>;
  onBack: () => void;
};

function normalizeSubtitleContent(content: string): string {
  const trimmed = content.trimStart();
  if (trimmed.startsWith('WEBVTT')) return content;

  const normalized = content
    .replace(/\r\n/g, '\n')
    .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');

  return `WEBVTT\n\n${normalized}`;
}

function sanitizeMediaTime(value: number): number {
  if (!Number.isFinite(value) || Number.isNaN(value)) return 0;
  return Math.max(0, value);
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message) return error.message;
  if (typeof error === 'string' && error.trim()) return error;
  return fallback;
}

function PlayIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M8 6v12l10-6z" />
    </svg>
  );
}

function PauseIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M7 6h4v12H7zM13 6h4v12h-4z" />
    </svg>
  );
}

function RewindIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M11.5 18V6L3 12zM21 18V6l-8.5 6z" />
    </svg>
  );
}

function ForwardIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M12.5 18V6l8.5 6zM3 18V6l8.5 6z" />
    </svg>
  );
}

function VolumeIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M3 9v6h4l5 4V5L7 9zm13.5 3c0-1.77-1-3.29-2.5-4.03v8.05A4.48 4.48 0 0 0 16.5 12m2.5 0c0 3.04-1.72 5.64-4.25 6.92v-1.9A5.99 5.99 0 0 0 17 12a6 6 0 0 0-2.25-4.73v-1.9C17.28 6.36 19 8.96 19 12" />
    </svg>
  );
}

function MuteIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M3 9v6h4l5 4V5L7 9zm13.59 3L19 9.41 17.59 8 15 10.59 12.41 8 11 9.41 13.59 12 11 14.59 12.41 16 15 13.41 17.59 16 19 14.59z" />
    </svg>
  );
}

function SettingsIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M19.14 12.94c.04-.31.06-.63.06-.94s-.02-.63-.07-.94l2.03-1.58a.5.5 0 0 0 .12-.64l-1.92-3.32a.5.5 0 0 0-.6-.22l-2.39.96a7.2 7.2 0 0 0-1.63-.94l-.36-2.54A.5.5 0 0 0 13.9 2h-3.8a.5.5 0 0 0-.49.42l-.36 2.54c-.58.23-1.12.54-1.63.94l-2.39-.96a.5.5 0 0 0-.6.22L2.71 8.48a.5.5 0 0 0 .12.64l2.03 1.58c-.05.31-.08.64-.08.95s.03.63.08.94l-2.03 1.58a.5.5 0 0 0-.12.64l1.92 3.32c.14.24.43.33.69.22l2.39-.96c.5.39 1.05.71 1.63.94l.36 2.54c.04.24.25.42.49.42h3.8c.24 0 .45-.18.49-.42l.36-2.54c.58-.23 1.13-.55 1.63-.94l2.39.96c.26.11.55.02.69-.22l1.92-3.32a.5.5 0 0 0-.12-.64zM12 15.5A3.5 3.5 0 1 1 12 8a3.5 3.5 0 0 1 0 7.5" />
    </svg>
  );
}

function SyncIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M12 5a7 7 0 0 1 6.36 4H16v2h5V6h-2v1.26A9 9 0 0 0 3 12h2a7 7 0 0 1 7-7zm7 7a7 7 0 0 1-7 7 7 7 0 0 1-6.36-4H8v-2H3v5h2v-1.26A9 9 0 0 0 21 12z" />
    </svg>
  );
}

function PopoutIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M4 5h10v2H6v10h10v-8h2v10H4z" />
      <path fill="currentColor" d="M14 4h6v6h-2V7.41l-7.29 7.3-1.42-1.42L16.59 6H14z" />
    </svg>
  );
}

function FullscreenIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M7 14H5v5h5v-2H7zM5 10h2V7h3V5H5zm12 9h-3v-2h3v-3h2v5h-5zm0-12h-3V5h5v5h-2z" />
    </svg>
  );
}

function FullscreenExitIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M15 14h4v4h-2v-2h-2zm-8 0h2v2h2v2H7zm10-8h2v4h-4V8h2zM7 6h4v2H9v2H7z" />
    </svg>
  );
}

export function PlayerPage(props: Props) {
  const {
    currentUserId,
    animeTitle,
    episode,
    streamInfo,
    streamUrl,
    audioTracks,
    selectedAudioTrackIndex,
    resumeFromSeconds,
    loading,
    subtitles,
    error,
    pendingSync,
    onSyncConsumed,
    onSelectAudioTrack,
    onSaveProgress,
    onOpenExternal,
    onBack,
  } = props;

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const shellRef = useRef<HTMLDivElement | null>(null);
  const settingsMenuRef = useRef<HTMLDivElement | null>(null);
  const settingsBtnRef = useRef<HTMLButtonElement | null>(null);
  const hideControlsTimerRef = useRef<number | null>(null);
  const [paused, setPaused] = useState(true);
  const [timePos, setTimePos] = useState(0);
  const [duration, setDuration] = useState(0);
  const [selectedSubtitleId, setSelectedSubtitleId] = useState('');
  const [playerError, setPlayerError] = useState('');
  const [controlsVisible, setControlsVisible] = useState(true);
  const [settingsMenuOpen, setSettingsMenuOpen] = useState(false);
  const [settingsTab, setSettingsTab] = useState<'main' | 'playback' | 'audio' | 'subtitles'>('main');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [volume, setVolume] = useState(85);
  const [speed, setSpeed] = useState(1);
  const [isMuted, setIsMuted] = useState(false);
  const [bufferedUntil, setBufferedUntil] = useState(0);

  const [playbackTarget, setPlaybackTarget] = useState<'html5' | 'mpv'>('html5');
  const [mpvRunning, setMpvRunning] = useState(false);
  const [syncBusy, setSyncBusy] = useState(false);
  const [syncPanelOpen, setSyncPanelOpen] = useState(false);
  const suppressSyncEmitRef = useRef(false);
  const suppressSyncCountRef = useRef(0);
  const playbackTargetRef = useRef<'html5' | 'mpv'>('html5');
  const speedSeekTimerRef = useRef<number | null>(null);
  const stallDebounceRef = useRef<number | null>(null);
  const stallSentRef = useRef(false);

  // Keep ref in sync with state so callbacks always read latest value
  useEffect(() => { playbackTargetRef.current = playbackTarget; }, [playbackTarget]);

  const clearSpeedSeekTimer = useCallback(() => {
    if (speedSeekTimerRef.current !== null) {
      window.clearTimeout(speedSeekTimerRef.current);
      speedSeekTimerRef.current = null;
    }
  }, []);

  const clearStallDebounce = useCallback(() => {
    if (stallDebounceRef.current !== null) {
      window.clearTimeout(stallDebounceRef.current);
      stallDebounceRef.current = null;
    }
  }, []);

  const suppressSyncEmitFor = useCallback((durationMs = 250) => {
    suppressSyncCountRef.current += 1;
    suppressSyncEmitRef.current = true;

    window.setTimeout(() => {
      suppressSyncCountRef.current = Math.max(0, suppressSyncCountRef.current - 1);
      if (suppressSyncCountRef.current === 0) {
        suppressSyncEmitRef.current = false;
      }
    }, durationMs);
  }, []);

  useEffect(() => {
    let timer: number;
    const pollMpv = async () => {
      try {
        const { running } = await desktopApi.isPlayerRunning();
        setMpvRunning(running);
        if (running && playbackTargetRef.current === 'mpv') {
          const state = await desktopApi.getPlayerState();
          setPaused(Boolean(state.paused));
          setTimePos(sanitizeMediaTime(Number(state.timePos ?? 0)));
          setDuration(sanitizeMediaTime(Number(state.duration ?? 0)));
          setBufferedUntil(0);
        } else if (playbackTargetRef.current === 'html5') {
          const video = videoRef.current;
          if (video) {
            setPaused(video.paused);
            setTimePos(sanitizeMediaTime(video.currentTime));
            setDuration(sanitizeMediaTime(video.duration));
          }
        }
      } catch {
        setMpvRunning(false);
      }
      timer = window.setTimeout(pollMpv, 250);
    };
    void pollMpv();
    return () => clearTimeout(timer);
  }, []);

  const getBufferedAhead = useCallback(() => {
    const video = videoRef.current;
    if (!video) return 0;
    try {
      if (!video.buffered.length) return 0;
      const t = video.currentTime;
      for (let i = 0; i < video.buffered.length; i++) {
        if (t >= video.buffered.start(i) && t <= video.buffered.end(i)) {
          return video.buffered.end(i) - t;
        }
      }
      return 0;
    } catch {
      return 0;
    }
  }, []);

  const applyRemoteSeek = useCallback((time: number) => {
    const video = videoRef.current;
    if (!video) return;
    suppressSyncEmitFor();
    video.currentTime = Math.max(0, Math.min(video.duration || Number.MAX_SAFE_INTEGER, time));
  }, [suppressSyncEmitFor]);

  const syncplay = useSyncplay(
    episode.id,
    async () => {
      if (playbackTargetRef.current === 'mpv' && mpvRunning) {
        try {
          const state = await desktopApi.getPlayerState();
          return {
            currentTime: Number(state.timePos ?? 0),
            playbackRate: 1,
            bufferedAhead: 0,
          };
        } catch {
          return {
            currentTime: 0,
            playbackRate: 1,
            bufferedAhead: 0,
          };
        }
      }

      const video = videoRef.current;
      return {
        currentTime: video?.currentTime ?? 0,
        playbackRate: video?.playbackRate ?? 1,
        bufferedAhead: getBufferedAhead(),
      };
    },
    {
      onRemotePlay: (time, scheduledPlayAt) => {
        if (playbackTargetRef.current === 'mpv' && mpvRunning) {
          const delay = Math.max(0, scheduledPlayAt - Date.now());
          window.setTimeout(() => {
            void desktopApi.seek(time)
              .then(() => desktopApi.play())
              .catch(() => undefined);
          }, delay);
          return;
        }

        const video = videoRef.current;
        if (!video) return;
        applyRemoteSeek(time);
        const delay = Math.max(0, scheduledPlayAt - Date.now());
        window.setTimeout(() => {
          suppressSyncEmitFor();
          void video.play().catch(() => undefined);
        }, delay);
      },
      onRemotePause: (time) => {
        if (playbackTargetRef.current === 'mpv' && mpvRunning) {
          void desktopApi.seek(time)
            .then(() => desktopApi.pause())
            .catch(() => undefined);
          return;
        }

        const video = videoRef.current;
        if (!video) return;
        applyRemoteSeek(time);
        suppressSyncEmitFor();
        video.pause();
      },
      onRemoteSeek: (time) => {
        if (playbackTargetRef.current === 'mpv' && mpvRunning) {
          void desktopApi.seek(time).catch(() => undefined);
          return;
        }
        applyRemoteSeek(time);
      },
      onSoftCorrect: (time) => {
        if (playbackTargetRef.current === 'mpv' && mpvRunning) {
          void desktopApi.seek(time).catch(() => undefined);
          return;
        }
        applyRemoteSeek(time);
      },
      onSpeedSeek: (rate, duration, targetTime) => {
        if (playbackTargetRef.current === 'mpv' && mpvRunning) {
          void desktopApi.seek(targetTime).catch(() => undefined);
          return;
        }

        const video = videoRef.current;
        if (!video) return;

        clearSpeedSeekTimer();
        const originalRate = video.playbackRate;
        const originalMuted = video.muted;

        suppressSyncEmitFor(duration + 50);
        video.playbackRate = rate;
        video.muted = true;
        speedSeekTimerRef.current = window.setTimeout(() => {
          applyRemoteSeek(targetTime);
          video.playbackRate = originalRate;
          video.muted = originalMuted;
          speedSeekTimerRef.current = null;
        }, duration);
      },
      onWaitForBufferGoal: (time) => {
        if (playbackTargetRef.current === 'mpv' && mpvRunning) {
          void desktopApi.pause()
            .then(() => desktopApi.seek(time))
            .catch(() => undefined);
          return;
        }

        const video = videoRef.current;
        if (!video) return;
        suppressSyncEmitFor(500);
        video.pause();
        applyRemoteSeek(time);
      },
      onStatusEvent: () => undefined,
    }
  );

  const handleCreateRoom = useCallback(async () => {
    setSyncBusy(true);
    try {
      await syncplay.createRoom();
      setPlayerError('');
    } catch (err: unknown) {
      setPlayerError(getErrorMessage(err, 'Failed to create SyncPlay room'));
    } finally {
      setSyncBusy(false);
    }
  }, [syncplay]);

  const handleJoinRoom = useCallback(async (code: string) => {
    setSyncBusy(true);
    try {
      await syncplay.joinRoom(code);
      setPlayerError('');
    } catch (err: unknown) {
      setPlayerError(getErrorMessage(err, 'Failed to join SyncPlay room'));
    } finally {
      setSyncBusy(false);
    }
  }, [syncplay]);

  useEffect(() => {
    if (pendingSync || syncplay.isInRoom || Boolean(syncplay.error)) {
      setSyncPanelOpen(true);
    }
  }, [pendingSync, syncplay.isInRoom, syncplay.error]);

  useEffect(() => {
    if (!pendingSync) return;
    onSyncConsumed();
    if (pendingSync.type === 'join') {
      void handleJoinRoom(pendingSync.code);
      return;
    }
    void handleCreateRoom();
  }, [pendingSync, onSyncConsumed, handleCreateRoom, handleJoinRoom]);

  const selectedSubtitle = useMemo(
    () => subtitles.find(s => s.id === selectedSubtitleId) ?? null,
    [selectedSubtitleId, subtitles],
  );

  const subtitleUrl = useMemo(() => {
    if (!selectedSubtitle) return '';
    const blob = new Blob([normalizeSubtitleContent(selectedSubtitle.content)], { type: 'text/vtt' });
    return URL.createObjectURL(blob);
  }, [selectedSubtitle]);

  useEffect(() => {
    return () => {
      if (subtitleUrl && subtitleUrl.startsWith('blob:')) {
        URL.revokeObjectURL(subtitleUrl);
      }
    };
  }, [subtitleUrl]);

  useEffect(() => {
    playbackTargetRef.current = playbackTarget;
  }, [playbackTarget]);

  useEffect(() => {
    return () => {
      clearSpeedSeekTimer();
      clearStallDebounce();
    };
  }, [clearSpeedSeekTimer, clearStallDebounce]);

  useEffect(() => {
    if (!syncplay.isInRoom || !syncplay.inBufferGate) return;

    if (playbackTargetRef.current === 'mpv' && mpvRunning) {
      const timer = window.setTimeout(() => {
        syncplay.reportReady();
      }, 500);
      return () => window.clearTimeout(timer);
    }

    let readyReported = false;
    const reportTimer = window.setInterval(() => {
      const ahead = getBufferedAhead();
      const goal = Math.max(1, syncplay.bufferGoalSeconds);
      const percent = Math.min(100, (ahead / goal) * 100);
      syncplay.reportBufferingProgress(ahead, percent);

      if (!readyReported && ahead >= goal) {
        readyReported = true;
        syncplay.reportReady();
      }
    }, 1000);

    return () => {
      window.clearInterval(reportTimer);
    };
  }, [getBufferedAhead, mpvRunning, syncplay]);

  useEffect(() => {
    const onFullscreenChange = () => {
      const fs = document.fullscreenElement;
      setIsFullscreen(Boolean(fs && shellRef.current && fs === shellRef.current));
    };

    document.addEventListener('fullscreenchange', onFullscreenChange);
    return () => document.removeEventListener('fullscreenchange', onFullscreenChange);
  }, []);

  const clearHideControlsTimer = useCallback(() => {
    if (hideControlsTimerRef.current !== null) {
      window.clearTimeout(hideControlsTimerRef.current);
      hideControlsTimerRef.current = null;
    }
  }, []);

  const scheduleHideControls = useCallback(() => {
    clearHideControlsTimer();
    if (paused || settingsMenuOpen || syncPanelOpen) {
      setControlsVisible(true);
      return;
    }

    hideControlsTimerRef.current = window.setTimeout(() => {
      setControlsVisible(false);
    }, 2000);
  }, [clearHideControlsTimer, paused, settingsMenuOpen, syncPanelOpen]);

  const signalInteraction = useCallback(() => {
    setControlsVisible(true);
    scheduleHideControls();
  }, [scheduleHideControls]);

  useEffect(() => {
    scheduleHideControls();
    return () => clearHideControlsTimer();
  }, [clearHideControlsTimer, scheduleHideControls]);

  useEffect(() => {
    if (!settingsMenuOpen) return;

    const onDocumentMouseDown = (event: MouseEvent) => {
      const target = event.target as Node;
      // Don't close if clicking inside the menu OR on the toggle button itself
      if (settingsMenuRef.current?.contains(target)) return;
      if (settingsBtnRef.current?.contains(target)) return;
      setSettingsMenuOpen(false);
    };

    document.addEventListener('mousedown', onDocumentMouseDown);
    return () => document.removeEventListener('mousedown', onDocumentMouseDown);
  }, [settingsMenuOpen]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !streamUrl) return;
    const shouldEmitStall = syncplay.isInRoom && playbackTargetRef.current === 'html5';

    const updateBuffered = () => {
      try {
        if (!video.buffered || video.buffered.length === 0) {
          setBufferedUntil(0);
          return;
        }
        setBufferedUntil(video.buffered.end(video.buffered.length - 1));
      } catch {
        setBufferedUntil(0);
      }
    };

    const onLoadedMetadata = () => {
      if (resumeFromSeconds > 0) {
        video.currentTime = Math.max(0, Math.min(resumeFromSeconds, video.duration || resumeFromSeconds));
      }
      setDuration(sanitizeMediaTime(video.duration));
      updateBuffered();
    };

    const onTimeUpdate = () => {
      setTimePos(sanitizeMediaTime(video.currentTime));
      setDuration(sanitizeMediaTime(video.duration));
      updateBuffered();
    };

    const onDurationChange = () => {
      setDuration(sanitizeMediaTime(video.duration));
    };

    const onPlay = () => setPaused(false);
    const onPlaying = () => setPaused(false);
    const onPause = () => {
      stallSentRef.current = false;
      setPaused(true);
    };
    const onSeeking = () => {
      stallSentRef.current = false;
    };
    const onEnded = () => {
      setPaused(true);
      const finalTime = sanitizeMediaTime(video.duration || video.currentTime || 0);
      void onSaveProgress(finalTime);
    };
    const onWaiting = () => {
      if (!shouldEmitStall || suppressSyncEmitRef.current) return;
      if (stallSentRef.current) return;

      clearStallDebounce();
      stallDebounceRef.current = window.setTimeout(() => {
        if (!shouldEmitStall || suppressSyncEmitRef.current) return;
        syncplay.emitBuffering();
        stallSentRef.current = true;
      }, 700);
    };
    const onCanPlay = () => {
      clearStallDebounce();
      if (!shouldEmitStall) {
        stallSentRef.current = false;
        return;
      }
      if (stallSentRef.current) {
        syncplay.emitStallRecovered();
      }
      stallSentRef.current = false;
    };
    const onError = () => {
      const mediaError = video.error;
      if (!mediaError) {
        setPlayerError('Unknown playback error occurred in embedded player.');
        return;
      }
      const code = mediaError.code;
      const map: Record<number, string> = {
        1: 'Playback was aborted.',
        2: 'Network error while loading video.',
        3: 'Video could not be decoded by the embedded player.',
        4: 'Video format is not supported by the embedded player.',
      };
      setPlayerError(map[code] ?? `Media error (code ${code}): ${mediaError.message || 'unknown error'}`);
    };

    video.addEventListener('loadedmetadata', onLoadedMetadata);
    video.addEventListener('timeupdate', onTimeUpdate);
    video.addEventListener('durationchange', onDurationChange);
    video.addEventListener('play', onPlay);
    video.addEventListener('playing', onPlaying);
    video.addEventListener('pause', onPause);
    video.addEventListener('seeking', onSeeking);
    video.addEventListener('ended', onEnded);
    video.addEventListener('waiting', onWaiting);
    video.addEventListener('canplay', onCanPlay);
    video.addEventListener('error', onError);
    video.addEventListener('progress', updateBuffered);

    setPlayerError('');
    setPaused(true);
    setTimePos(0);
    setDuration(0);
    setBufferedUntil(0);

    return () => {
      video.removeEventListener('loadedmetadata', onLoadedMetadata);
      video.removeEventListener('timeupdate', onTimeUpdate);
      video.removeEventListener('durationchange', onDurationChange);
      video.removeEventListener('play', onPlay);
      video.removeEventListener('playing', onPlaying);
      video.removeEventListener('pause', onPause);
      video.removeEventListener('seeking', onSeeking);
      video.removeEventListener('ended', onEnded);
      video.removeEventListener('waiting', onWaiting);
      video.removeEventListener('canplay', onCanPlay);
      video.removeEventListener('error', onError);
      video.removeEventListener('progress', updateBuffered);
      clearStallDebounce();
    };
  }, [clearStallDebounce, onSaveProgress, resumeFromSeconds, streamUrl, syncplay]);

  const timePosRef = useRef(0);
  useEffect(() => { timePosRef.current = timePos; }, [timePos]);

  useEffect(() => {
    const saveTimer = window.setInterval(() => {
      void onSaveProgress(timePosRef.current);
    }, 10000);

    return () => window.clearInterval(saveTimer);
  }, [onSaveProgress]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.volume = Math.max(0, Math.min(1, volume / 100));
    video.muted = isMuted || volume === 0;
  }, [volume, isMuted]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.playbackRate = speed;
  }, [speed]);

  const formatTime = (seconds: number): string => {
    if (!Number.isFinite(seconds) || Number.isNaN(seconds)) return '0:00';
    const s = Math.max(0, Math.floor(seconds || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const rem = s % 60;
    if (h > 0) {
      return `${h}:${String(m).padStart(2, '0')}:${String(rem).padStart(2, '0')}`;
    }
    return `${m}:${String(rem).padStart(2, '0')}`;
  };

  const activeAudioLabel = useMemo(() => {
    const active = audioTracks.find(track => track.streamIndex === selectedAudioTrackIndex);
    if (!active) return 'Default';
    return active.label || active.language || 'Track';
  }, [audioTracks, selectedAudioTrackIndex]);

  const activeSubtitleLabel = useMemo(() => {
    if (!selectedSubtitleId) return 'Off';
    const active = subtitles.find(track => track.id === selectedSubtitleId);
    return active ? active.label : 'Off';
  }, [selectedSubtitleId, subtitles]);

  const playedPercent = useMemo(() => {
    if (!duration || duration <= 0) return 0;
    return Math.max(0, Math.min(100, (timePos / duration) * 100));
  }, [timePos, duration]);

  const bufferedPercent = useMemo(() => {
    if (!duration || duration <= 0) return 0;
    return Math.max(0, Math.min(100, (bufferedUntil / duration) * 100));
  }, [bufferedUntil, duration]);

  const seekMax = useMemo(() => Math.max(1, Math.ceil(duration || 0)), [duration]);

  const togglePlayback = useCallback(() => {
    if (playbackTargetRef.current === 'mpv' && mpvRunning) {
      const doToggle = async () => {
        try {
          const state = await desktopApi.getPlayerState();
          if (state.paused) {
            await desktopApi.play();
            if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
              syncplay.emitPlay(state.timePos || 0);
            }
            return;
          }

          await desktopApi.pause();
          if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
            syncplay.emitPause(state.timePos || 0);
          }
        } catch {
          setPlayerError('MPV is not running. Open external player first.');
        }
      };
      void doToggle();
      return;
    }

    const video = videoRef.current;
    if (!video) return;

    if (video.paused) {
      setPaused(false);
      void video.play().catch((err: unknown) => {
        setPaused(true);
        setPlayerError(getErrorMessage(err, 'Failed to start playback'));
      });
      // Emit AFTER triggering play so currentTime is accurate
      if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
        window.setTimeout(() => {
          if (videoRef.current && syncplay.isInRoom && !suppressSyncEmitRef.current) {
            syncplay.emitPlay(videoRef.current.currentTime || 0);
          }
        }, 0);
      }
      return;
    }

    if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
      syncplay.emitPause(video.currentTime || 0);
    }
    video.pause();
  }, [mpvRunning, syncplay]);

  const seekBy = useCallback((delta: number) => {
    if (playbackTargetRef.current === 'mpv' && mpvRunning) {
      const doSeek = async () => {
        try {
          const state = await desktopApi.getPlayerState();
          const next = Math.max(0, (state.timePos || 0) + delta);
          await desktopApi.seek(next);
          if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
            syncplay.emitSeek(next);
          }
        } catch {
          setPlayerError('Unable to seek MPV player.');
        }
      };
      void doSeek();
      return;
    }

    const video = videoRef.current;
    if (!video) return;
    const next = Math.max(0, Math.min(video.duration || 0, video.currentTime + delta));
    video.currentTime = next;
    if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
      syncplay.emitSeek(next);
    }
  }, [mpvRunning, syncplay]);

  const toggleFullscreen = useCallback(async () => {
    const shell = shellRef.current;
    if (!shell) return;

    if (document.fullscreenElement === shell) {
      await document.exitFullscreen().catch(() => undefined);
      return;
    }

    await shell.requestFullscreen().catch(() => undefined);
  }, []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName?.toLowerCase();
      if (tag === 'input' || tag === 'select' || tag === 'textarea') {
        return;
      }

      if (event.key === ' ' || event.key.toLowerCase() === 'k') {
        event.preventDefault();
        togglePlayback();
        signalInteraction();
      } else if (event.key === 'ArrowLeft') {
        event.preventDefault();
        seekBy(-10);
        signalInteraction();
      } else if (event.key === 'ArrowRight') {
        event.preventDefault();
        seekBy(10);
        signalInteraction();
      } else if (event.key.toLowerCase() === 'f') {
        event.preventDefault();
        void toggleFullscreen();
      } else if (event.key.toLowerCase() === 'm') {
        event.preventDefault();
        setIsMuted(prev => !prev);
      } else if (event.key === 'Escape') {
        setSettingsMenuOpen(false);
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [seekBy, signalInteraction, toggleFullscreen, togglePlayback]);

  const handleOpenExternalPlayer = useCallback(async () => {
    try {
      await onOpenExternal();
      setPlaybackTarget('mpv');
      const { running } = await desktopApi.isPlayerRunning();
      setMpvRunning(Boolean(running));
      setPlayerError('');
    } catch (err: unknown) {
      setPlayerError(getErrorMessage(err, 'Failed to open external player.'));
    }
  }, [onOpenExternal]);

  const showCenterPlay = paused
    && !loading
    && !error
    && !playerError
    && playbackTargetRef.current === 'html5'
    && Boolean(streamUrl);

  const durationLabel = duration > 0 ? formatTime(duration) : '--:--';

  return (
    <div
      ref={shellRef}
      className={`video-shell ${controlsVisible || settingsMenuOpen || syncPanelOpen ? 'player-controls-visible' : ''}`}
      style={{ position: 'fixed', inset: 0, zIndex: 100, background: '#000', cursor: controlsVisible ? 'default' : 'none' }}
      onMouseMove={signalInteraction}
      onMouseEnter={signalInteraction}
      onMouseLeave={() => { if (!paused && !settingsMenuOpen) setControlsVisible(false); }}
    >
      {loading && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 10, pointerEvents: 'none' }}>
          <span style={{ color: 'rgba(255,255,255,0.7)', fontSize: 18 }}>Loading stream...</span>
        </div>
      )}
      {(error || playerError) && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 10, pointerEvents: 'none' }}>
          <span className="error">{error || playerError}</span>
        </div>
      )}

      <video
        ref={videoRef}
        className="video-element"
        src={streamUrl}
        playsInline
        preload="metadata"
        onClick={togglePlayback}
        onDoubleClick={() => void toggleFullscreen()}
      >
        {subtitleUrl && selectedSubtitle ? (
          <track
            kind="subtitles"
            src={subtitleUrl}
            label={selectedSubtitle.label}
            srcLang={selectedSubtitle.language || 'en'}
            default
          />
        ) : null}
      </video>

      {showCenterPlay ? (
        <button
          className="center-play-btn"
          title="Play"
          aria-label="Play"
          onClick={() => { togglePlayback(); signalInteraction(); }}
          style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 5, background: 'rgba(0,0,0,0.5)', width: 72, height: 72, borderRadius: '50%', border: '2px solid rgba(255,255,255,0.3)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
        >
          <PlayIcon className="control-icon" />
        </button>
      ) : null}

      <div className={`plex-overlay ${controlsVisible ? 'visible' : 'hidden'}`}>
        {/* Top bar */}
        <div className="plex-topbar" style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <button
            onClick={onBack}
            title="Back to Library"
            style={{
              background: 'none', border: 'none', color: '#fff', cursor: 'pointer',
              padding: '4px', display: 'flex', alignItems: 'center', opacity: 0.85,
              transition: 'opacity 0.2s', flexShrink: 0,
            }}
            onMouseEnter={e => (e.currentTarget.style.opacity = '1')}
            onMouseLeave={e => (e.currentTarget.style.opacity = '0.85')}
          >
            <svg viewBox="0 0 24 24" width="28" height="28" fill="currentColor">
              <path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/>
            </svg>
          </button>
          <div>
            <div style={{ color: '#fff', fontSize: 18, fontWeight: 600, lineHeight: 1.2 }}>{animeTitle}</div>
            <div className="muted" style={{ fontSize: 13 }}>Episode {episode.number}{episode.title ? ` — ${episode.title}` : ''}</div>
          </div>
        </div>

        {/* Bottom bar */}
        <div className="plex-bottombar">
          {/* Progress bar first (above controls) */}
          <div className="plex-progress-wrap" title="Seek">
            <div className="plex-progress-track" />
            <div className="plex-progress-buffer" style={{ width: `${bufferedPercent}%` }} />
            <div className="plex-progress-played" style={{ width: `${playedPercent}%` }} />
            <input
              className="plex-progress-input"
              type="range"
              min={0}
              max={seekMax}
              value={Math.min(Math.floor(timePos || 0), seekMax)}
              onChange={e => {
                const next = Number(e.target.value);
                if (playbackTargetRef.current === 'mpv' && mpvRunning) {
                  void desktopApi.seek(next).catch(() => {
                    setPlayerError('Unable to seek MPV player.');
                  });
                } else {
                  const video = videoRef.current;
                  if (!video) return;
                  video.currentTime = next;
                }

                if (syncplay.isInRoom && !suppressSyncEmitRef.current) {
                  syncplay.emitSeek(next);
                }
                signalInteraction();
              }}
            />
          </div>

          {/* Controls row */}
          <div className="plex-controls-row">
            <div className="row gap-sm align-center">
              <button className="ghost-btn" onClick={() => seekBy(-10)} title="Back 10s" style={{ width: 36, height: 36 }}>
                <RewindIcon className="control-icon" />
              </button>
              <button className="ghost-btn" onClick={togglePlayback} title={paused ? 'Play' : 'Pause'} style={{ width: 44, height: 44 }}>
                {paused ? <PlayIcon className="control-icon" /> : <PauseIcon className="control-icon" />}
              </button>
              <button className="ghost-btn" onClick={() => seekBy(10)} title="Forward 10s" style={{ width: 36, height: 36 }}>
                <ForwardIcon className="control-icon" />
              </button>
              <label className="row gap-sm align-center volume-wrap" style={{ marginLeft: 8 }}>
                <button className="ghost-btn" onClick={() => setIsMuted(prev => !prev)} title="Mute" style={{ width: 36, height: 36 }}>
                  {isMuted || volume === 0 ? <MuteIcon className="control-icon" /> : <VolumeIcon className="control-icon" />}
                </button>
                <input
                  className="volume-slider"
                  type="range" min={0} max={100} value={volume}
                  style={{ width: 80, accentColor: 'var(--accent)' }}
                  onChange={e => {
                    const next = Number(e.target.value);
                    setVolume(next);
                    if (next > 0) setIsMuted(false);
                    signalInteraction();
                  }}
                />
              </label>
              <span className="time-readout">{formatTime(timePos)} / {durationLabel}</span>
            </div>

            <div className="row gap-sm align-center">
              <button
                ref={settingsBtnRef}
                className="ghost-btn"
                style={{ width: 36, height: 36 }}
                onClick={() => { setSettingsMenuOpen(v => !v); setSettingsTab('main'); }}
                title="Settings"
              >
                <SettingsIcon className="control-icon" />
              </button>
              <div style={{ position: 'relative', display: 'flex' }}>
                <button
                  className="ghost-btn"
                  style={{ width: 36, height: 36, borderColor: syncPanelOpen ? 'var(--accent)' : undefined }}
                  onClick={() => setSyncPanelOpen(v => !v)}
                  title={syncPanelOpen ? 'Hide SyncPlay' : 'Show SyncPlay'}
                >
                  <SyncIcon className="control-icon" />
                </button>

                {syncPanelOpen ? (
                  <div style={{
                    position: 'absolute',
                    right: 0,
                    bottom: 'calc(100% + 10px)',
                    zIndex: 12,
                    width: 300,
                    maxWidth: 'min(320px, 80vw)',
                    pointerEvents: 'auto',
                  }}>
                    <SyncplayPanel
                      roomCode={syncplay.roomCode}
                      hostUserId={syncplay.hostUserId}
                      selfUserId={currentUserId}
                      peers={syncplay.peers}
                      status={syncplay.status}
                      error={syncplay.error}
                      inBufferGate={syncplay.inBufferGate}
                      readyCount={syncplay.readyCount}
                      totalPeers={syncplay.totalPeers}
                      isWorking={syncBusy}
                      onCreateRoom={handleCreateRoom}
                      onJoinRoom={handleJoinRoom}
                      onLeaveRoom={syncplay.leaveRoom}
                      onTransferHost={syncplay.transferHost}
                      onRequestSync={syncplay.requestSync}
                      onClearError={syncplay.clearError}
                      playbackTarget={playbackTarget}
                      onPlaybackTargetChange={setPlaybackTarget}
                      mpvRunning={mpvRunning}
                    />
                  </div>
                ) : null}
              </div>
              <button className="ghost-btn" style={{ width: 36, height: 36 }} onClick={() => void handleOpenExternalPlayer()} title="External player">
                <PopoutIcon className="control-icon" />
              </button>
              <button className="ghost-btn" style={{ width: 36, height: 36 }} onClick={() => void toggleFullscreen()} title="Fullscreen">
                {isFullscreen ? <FullscreenExitIcon className="control-icon" /> : <FullscreenIcon className="control-icon" />}
              </button>
            </div>
          </div>
        </div>
      </div>

      {settingsMenuOpen ? (
        <div ref={settingsMenuRef} className="player-settings-menu">
          <div className="settings-panel">
            {settingsTab === 'main' ? (
              <div className="settings-option-list">
                <button className="settings-option row split" onClick={() => setSettingsTab('playback')}>
                  <span>Playback Speed</span>
                  <span>{speed.toFixed(speed % 1 === 0 ? 1 : 2)}x</span>
                </button>
                <button className="settings-option row split" onClick={() => setSettingsTab('audio')}>
                  <span>Audio Track</span>
                  <span>{activeAudioLabel}</span>
                </button>
                <button className="settings-option row split" onClick={() => setSettingsTab('subtitles')}>
                  <span>Subtitles</span>
                  <span>{activeSubtitleLabel}</span>
                </button>
              </div>
            ) : null}

            {settingsTab !== 'main' ? (
              <button className="settings-back" onClick={() => setSettingsTab('main')}>Back</button>
            ) : null}

            {settingsTab === 'playback' ? (
              <div className="settings-option-list">
                {syncplay.isInRoom ? <p className="muted" style={{fontSize: 12}}>Playback speed is locked during SyncPlay.</p> : null}
                {[0.75, 1, 1.25, 1.5, 2].map(value => (
                  <button key={value} className={`settings-option ${speed === value ? 'active' : ''}`}
                    disabled={syncplay.isInRoom}
                    onClick={() => { setSpeed(value); setSettingsMenuOpen(false); }}>
                    {value.toFixed(value % 1 === 0 ? 1 : 2)}x
                  </button>
                ))}
              </div>
            ) : null}

            {settingsTab === 'audio' ? (
              <div className="settings-option-list">
                {syncplay.isInRoom ? <p className="muted" style={{fontSize: 12}}>Audio switching disabled during SyncPlay.</p> : null}
                <button className={`settings-option ${selectedAudioTrackIndex === null ? 'active' : ''}`}
                  disabled={syncplay.isInRoom}
                  onClick={() => { void onSelectAudioTrack(null, timePos); setSettingsMenuOpen(false); }}>
                  Default {selectedAudioTrackIndex === null ? '✓' : ''}
                </button>
                {audioTracks.map(track => (
                  <button key={track.id}
                    className={`settings-option ${selectedAudioTrackIndex === track.streamIndex ? 'active' : ''}`}
                    disabled={syncplay.isInRoom}
                    onClick={() => {
                      if (typeof track.streamIndex !== 'number' || track.streamIndex < 0) {
                        setPlayerError('Invalid audio track');
                        return;
                      }
                      void onSelectAudioTrack(track.streamIndex, timePos);
                      setSettingsMenuOpen(false);
                    }}>
                    {track.label || track.language || 'Unknown'} {selectedAudioTrackIndex === track.streamIndex ? '✓' : ''}
                  </button>
                ))}
              </div>
            ) : null}

            {settingsTab === 'subtitles' ? (
              <div className="settings-option-list">
                <button className={`settings-option ${selectedSubtitleId === '' ? 'active' : ''}`}
                  onClick={() => { setSelectedSubtitleId(''); setSettingsMenuOpen(false); }}>
                  Off {selectedSubtitleId === '' ? '✓' : ''}
                </button>
                {subtitles.map(track => (
                  <button key={track.id}
                    className={`settings-option ${selectedSubtitleId === track.id ? 'active' : ''}`}
                    onClick={() => { setSelectedSubtitleId(track.id); setSettingsMenuOpen(false); }}>
                    {track.label}
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        </div>
      ) : null}

    </div>
  );
}
