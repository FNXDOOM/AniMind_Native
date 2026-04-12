import React from 'react';

type Props = {
  paused: boolean;
  timePos: number;
  duration: number;
  onPlay: () => void;
  onPause: () => void;
  onSeek: (seconds: number) => void;
};

function formatTime(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds || 0));
  const m = Math.floor(s / 60);
  const rem = s % 60;
  return `${m}:${String(rem).padStart(2, '0')}`;
}

export function VideoPlayerControls({ paused, timePos, duration, onPlay, onPause, onSeek }: Props) {
  const progress = duration > 0 ? Math.min(100, Math.max(0, (timePos / duration) * 100)) : 0;

  return (
    <div className="panel controls">
      <div className="row gap-sm">
        {paused ? (
          <button onClick={onPlay}>Play</button>
        ) : (
          <button onClick={onPause}>Pause</button>
        )}
      </div>

      <div className="row gap-sm align-center">
        <span>{formatTime(timePos)}</span>
        <input
          type="range"
          min={0}
          max={100}
          value={progress}
          onChange={e => {
            const pct = Number(e.target.value);
            onSeek((pct / 100) * (duration || 0));
          }}
        />
        <span>{formatTime(duration)}</span>
      </div>
    </div>
  );
}
