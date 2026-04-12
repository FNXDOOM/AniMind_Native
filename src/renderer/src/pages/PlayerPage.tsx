import React, { useMemo, useState } from 'react';
import type { Episode, PlayerTrack, SubtitleTrack } from '../types';
import { VideoPlayerControls } from '../components/VideoPlayerControls';

type Props = {
  animeId: string;
  animeTitle: string;
  episode: Episode;
  streamInfo: { clientType?: 'native' | 'browser'; message?: string } | null;
  loading: boolean;
  subtitles: SubtitleTrack[];
  paused: boolean;
  timePos: number;
  duration: number;
  tracks: PlayerTrack[];
  error: string;
  onPlay: () => Promise<unknown>;
  onPause: () => Promise<unknown>;
  onSeek: (seconds: number) => Promise<unknown>;
  onRefreshTracks: () => Promise<unknown>;
  onSetAudioTrack: (trackId: number) => Promise<unknown>;
  onSetSubtitleTrack: (trackId: number | 'no') => Promise<unknown>;
  onAddSubtitle: (track: SubtitleTrack) => Promise<unknown>;
};

export function PlayerPage(props: Props) {
  const {
    animeTitle,
    episode,
    streamInfo,
    loading,
    subtitles,
    paused,
    timePos,
    duration,
    tracks,
    error,
    onPlay,
    onPause,
    onSeek,
    onRefreshTracks,
    onSetAudioTrack,
    onSetSubtitleTrack,
    onAddSubtitle,
  } = props;

  const audioTracks = useMemo(() => tracks.filter(t => t.type === 'audio'), [tracks]);
  const subtitleTracks = useMemo(() => tracks.filter(t => t.type === 'sub'), [tracks]);
  const [selectedSubtitleId, setSelectedSubtitleId] = useState('');

  return (
    <div className="panel stack-gap">
      <h2>{animeTitle} - Episode {episode.number}</h2>
      <p className="muted">{episode.title}</p>

      {streamInfo ? (
        <div className="badge-row">
          <span className="badge">Client: {streamInfo.clientType ?? 'unknown'}</span>
          {streamInfo.message ? <span className="muted">{streamInfo.message}</span> : null}
        </div>
      ) : null}

      {loading ? <p className="muted">Opening in native mpv window...</p> : null}
      {error ? <p className="error">{error}</p> : null}

      <VideoPlayerControls
        paused={paused}
        timePos={timePos}
        duration={duration}
        onPlay={() => void onPlay()}
        onPause={() => void onPause()}
        onSeek={seconds => void onSeek(seconds)}
      />

      <div className="row gap-md wrap">
        <div className="panel compact">
          <div className="row split align-center">
            <h3>Audio Tracks</h3>
            <button onClick={() => void onRefreshTracks()}>Refresh</button>
          </div>
          <div className="list">
            {audioTracks.map(track => (
              <button key={track.id} className="list-item" onClick={() => void onSetAudioTrack(track.id)}>
                {track.lang || 'Unknown'} {track.codec ? `(${track.codec})` : ''} {track.selected ? '• Active' : ''}
              </button>
            ))}
          </div>
        </div>

        <div className="panel compact">
          <h3>Embedded Subtitles</h3>
          <div className="list">
            <button className="list-item" onClick={() => void onSetSubtitleTrack('no')}>Disable Subtitles</button>
            {subtitleTracks.map(track => (
              <button key={track.id} className="list-item" onClick={() => void onSetSubtitleTrack(track.id)}>
                {track.lang || 'Unknown'} {track.selected ? '• Active' : ''}
              </button>
            ))}
          </div>
        </div>

        <div className="panel compact">
          <h3>Cloud Subtitles</h3>
          <div className="row gap-sm">
            <select value={selectedSubtitleId} onChange={e => setSelectedSubtitleId(e.target.value)}>
              <option value="">Select subtitle track...</option>
              {subtitles.map(s => (
                <option key={s.id} value={s.id}>{s.label} ({s.language})</option>
              ))}
            </select>
            <button
              disabled={!selectedSubtitleId}
              onClick={() => {
                const track = subtitles.find(s => s.id === selectedSubtitleId);
                if (!track) return;
                void onAddSubtitle(track);
              }}
            >
              Add To Player
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
