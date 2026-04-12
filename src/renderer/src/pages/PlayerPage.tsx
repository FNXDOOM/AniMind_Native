import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { AudioTrack, Episode, SubtitleTrack } from '../types';

type IconProps = { className?: string };

type Props = {
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
  onSelectAudioTrack: (streamIndex: number | null, currentTime: number) => Promise<unknown>;
  onSaveProgress: (seconds: number) => Promise<unknown>;
  onOpenExternal: () => Promise<unknown>;
};

function normalizeSubtitleContent(content: string): string {
  const trimmed = content.trimStart();
  if (trimmed.startsWith('WEBVTT')) return content;

  const normalized = content
    .replace(/\r\n/g, '\n')
    .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');

  return `WEBVTT\n\n${normalized}`;
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
    onSelectAudioTrack,
    onSaveProgress,
    onOpenExternal,
  } = props;

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const shellRef = useRef<HTMLDivElement | null>(null);
  const settingsMenuRef = useRef<HTMLDivElement | null>(null);
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
      if (subtitleUrl) URL.revokeObjectURL(subtitleUrl);
    };
  }, [subtitleUrl]);

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
    if (paused || settingsMenuOpen) {
      setControlsVisible(true);
      return;
    }

    hideControlsTimerRef.current = window.setTimeout(() => {
      setControlsVisible(false);
    }, 2000);
  }, [clearHideControlsTimer, paused, settingsMenuOpen]);

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
      if (!settingsMenuRef.current) return;
      if (settingsMenuRef.current.contains(event.target as Node)) return;
      setSettingsMenuOpen(false);
    };

    document.addEventListener('mousedown', onDocumentMouseDown);
    return () => document.removeEventListener('mousedown', onDocumentMouseDown);
  }, [settingsMenuOpen]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !streamUrl) return;

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
      updateBuffered();
    };

    const onTimeUpdate = () => {
      setTimePos(video.currentTime || 0);
      updateBuffered();
    };

    const onDurationChange = () => {
      setDuration(video.duration || 0);
    };

    const onPlay = () => setPaused(false);
    const onPause = () => setPaused(true);
    const onEnded = () => setPaused(true);
    const onError = () => {
      const mediaError = video.error;
      const code = mediaError?.code;
      const map: Record<number, string> = {
        1: 'Playback was aborted.',
        2: 'Network error while loading video.',
        3: 'Video could not be decoded by the embedded player.',
        4: 'Video format is not supported by the embedded player.',
      };
      setPlayerError(map[code ?? 0] ?? 'Unable to play this stream in the embedded player.');
    };

    video.addEventListener('loadedmetadata', onLoadedMetadata);
    video.addEventListener('timeupdate', onTimeUpdate);
    video.addEventListener('durationchange', onDurationChange);
    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);
    video.addEventListener('ended', onEnded);
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
      video.removeEventListener('pause', onPause);
      video.removeEventListener('ended', onEnded);
      video.removeEventListener('error', onError);
      video.removeEventListener('progress', updateBuffered);
    };
  }, [streamUrl, resumeFromSeconds]);

  useEffect(() => {
    const saveTimer = window.setInterval(() => {
      void onSaveProgress(timePos);
    }, 10000);

    return () => window.clearInterval(saveTimer);
  }, [onSaveProgress, timePos]);

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

  const togglePlayback = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;

    if (video.paused) {
      void video.play().catch((err: any) => {
        setPlayerError(err?.message ?? 'Failed to start playback');
      });
      return;
    }

    video.pause();
  }, []);

  const seekBy = useCallback((delta: number) => {
    const video = videoRef.current;
    if (!video) return;
    video.currentTime = Math.max(0, Math.min(video.duration || 0, video.currentTime + delta));
  }, []);

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

  return (
    <div className="panel stack-gap player-page">
      <div className="player-header">
        <h2>{animeTitle}</h2>
        <p className="muted">Episode {episode.number}: {episode.title}</p>
      </div>

      {loading ? <p className="muted">Loading stream...</p> : null}
      {error ? <p className="error">{error}</p> : null}
      {playerError ? <p className="error">{playerError}</p> : null}

      <div
        ref={shellRef}
        className="video-shell plex-shell modern-player-shell"
        onMouseMove={() => {
          signalInteraction();
        }}
        onMouseEnter={() => signalInteraction()}
        onMouseLeave={() => {
          if (!paused && !settingsMenuOpen) {
            setControlsVisible(false);
          }
        }}
      >
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

        {paused ? (
          <button
            className="center-play-btn"
            title="Play"
            aria-label="Play"
            onClick={() => {
              togglePlayback();
              signalInteraction();
            }}
          >
            <PlayIcon className="control-icon center-play-icon" />
          </button>
        ) : null}

        <div className={`plex-overlay modern-overlay ${controlsVisible ? 'visible' : 'hidden'}`}>
          <div className="plex-topbar">
            <span className="muted">{animeTitle} - Episode {episode.number}</span>
          </div>

          <div className="plex-bottombar">
            <div className="yt-progress-wrap" title="Seek">
              <div className="yt-progress-track" />
              <div className="yt-progress-buffer" style={{ width: `${bufferedPercent}%` }} />
              <div className="yt-progress-played" style={{ width: `${playedPercent}%` }} />
              <input
                className="plex-progress yt-progress-input"
                type="range"
                min={0}
                max={Math.max(1, Math.floor(duration || 0))}
                value={Math.min(Math.floor(timePos || 0), Math.max(1, Math.floor(duration || 0)))}
                onChange={e => {
                  const video = videoRef.current;
                  if (!video) return;
                  const next = Number(e.target.value);
                  video.currentTime = next;
                  signalInteraction();
                }}
              />
            </div>

            <div className="plex-controls-row modern-controls-row">
              <div className="row gap-sm align-center control-cluster-left">
                <button className="ghost-btn yt-btn transport-btn" onClick={() => seekBy(-10)} title="Back 10 seconds" aria-label="Back 10 seconds">
                  <RewindIcon className="control-icon" />
                </button>
                <button className="ghost-btn yt-btn transport-btn play-btn" onClick={togglePlayback} title={paused ? 'Play' : 'Pause'} aria-label={paused ? 'Play' : 'Pause'}>
                  {paused ? <PlayIcon className="control-icon" /> : <PauseIcon className="control-icon" />}
                </button>
                <button className="ghost-btn yt-btn transport-btn" onClick={() => seekBy(10)} title="Forward 10 seconds" aria-label="Forward 10 seconds">
                  <ForwardIcon className="control-icon" />
                </button>
                <span className="time-readout">{formatTime(timePos)} / {formatTime(duration)}</span>
                <span className="muted tiny">-{formatTime(Math.max(0, duration - timePos))}</span>
              </div>

              <div className="row gap-sm align-center control-cluster-right wrap">
                <label className="row gap-sm align-center volume-wrap">
                  <button className="ghost-btn yt-btn mute-btn" onClick={() => setIsMuted(prev => !prev)} title="Mute" aria-label="Toggle mute">
                    {isMuted || volume === 0 ? <MuteIcon className="control-icon" /> : <VolumeIcon className="control-icon" />}
                  </button>
                  <input
                    className="volume-slider"
                    type="range"
                    min={0}
                    max={100}
                    value={volume}
                    onChange={e => {
                      const next = Number(e.target.value);
                      setVolume(next);
                      if (next > 0) setIsMuted(false);
                      signalInteraction();
                    }}
                  />
                </label>
                <button
                  className="ghost-btn yt-btn settings-trigger"
                  onClick={() => {
                    setSettingsMenuOpen(v => !v);
                    setSettingsTab('main');
                  }}
                  title="Settings"
                  aria-label="Open player settings"
                >
                  <SettingsIcon className="control-icon" />
                </button>
                <button className="ghost-btn yt-btn" onClick={() => void onOpenExternal()} title="Open external player" aria-label="Open external player">
                  <PopoutIcon className="control-icon" />
                </button>
                <button className="ghost-btn yt-btn" onClick={() => void toggleFullscreen()} title="Fullscreen" aria-label="Toggle fullscreen">
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
                  {[0.75, 1, 1.25, 1.5, 2].map(value => (
                    <button
                      key={value}
                      className={`settings-option ${speed === value ? 'active' : ''}`}
                      onClick={() => {
                        setSpeed(value);
                        setSettingsMenuOpen(false);
                      }}
                    >
                      {value.toFixed(value % 1 === 0 ? 1 : 2)}x
                    </button>
                  ))}
                </div>
              ) : null}

              {settingsTab === 'audio' ? (
                <div className="settings-option-list">
                  <button
                    className={`settings-option ${selectedAudioTrackIndex === null ? 'active' : ''}`}
                    onClick={() => {
                      void onSelectAudioTrack(null, timePos);
                      setSettingsMenuOpen(false);
                    }}
                  >
                    Default {selectedAudioTrackIndex === null ? 'Active' : ''}
                  </button>
                  {audioTracks.map(track => (
                    <button
                      key={track.id}
                      className={`settings-option ${selectedAudioTrackIndex === track.streamIndex ? 'active' : ''}`}
                      onClick={() => {
                        void onSelectAudioTrack(track.streamIndex, timePos);
                        setSettingsMenuOpen(false);
                      }}
                    >
                      {track.label || track.language || 'Unknown'} {selectedAudioTrackIndex === track.streamIndex ? 'Active' : ''}
                    </button>
                  ))}
                </div>
              ) : null}

              {settingsTab === 'subtitles' ? (
                <div className="settings-option-list">
                  <button
                    className={`settings-option ${selectedSubtitleId === '' ? 'active' : ''}`}
                    onClick={() => {
                      setSelectedSubtitleId('');
                      setSettingsMenuOpen(false);
                    }}
                  >
                    Off {selectedSubtitleId === '' ? 'Active' : ''}
                  </button>
                  {subtitles.map(track => (
                    <button
                      key={track.id}
                      className={`settings-option ${selectedSubtitleId === track.id ? 'active' : ''}`}
                      onClick={() => {
                        setSelectedSubtitleId(track.id);
                        setSettingsMenuOpen(false);
                      }}
                    >
                      {track.label}
                    </button>
                  ))}
                </div>
              ) : null}
            </div>
          </div>
        ) : null}
      </div>

      <div className="row split align-center">
        <p className="muted">Audio: {activeAudioLabel}</p>
        <p className="muted">Subtitles: {activeSubtitleLabel}</p>
      </div>

      {streamInfo ? (
        <div className="badge-row">
          <span className="badge">Client: {streamInfo.clientType ?? 'unknown'}</span>
          {streamInfo.message ? <span className="muted">{streamInfo.message}</span> : null}
        </div>
      ) : null}
    </div>
  );
}
