import React, { useMemo, useState } from 'react';
import type { SyncplayParticipantState } from '../types';

type Props = {
  roomCode: string;
  hostUserId: string;
  selfUserId: string;
  peers: SyncplayParticipantState[];
  status: string;
  error: string;
  inBufferGate: boolean;
  readyCount: number;
  totalPeers: number;
  isWorking: boolean;
  onCreateRoom: () => Promise<void>;
  onJoinRoom: (code: string) => Promise<void>;
  onLeaveRoom: () => void;
  onTransferHost: (userId: string) => void;
  onRequestSync: () => void;
  onClearError: () => void;
  playbackTarget: 'html5' | 'mpv';
  onPlaybackTargetChange: (target: 'html5' | 'mpv') => void;
  mpvRunning: boolean;
};

function formatBuffered(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds || 0));
  if (s >= 60) return `${Math.floor(s / 60)}m ${s % 60}s`;
  return `${s}s`;
}

export function SyncplayPanel(props: Props) {
  const {
    roomCode,
    hostUserId,
    selfUserId,
    peers,
    status,
    error,
    inBufferGate,
    readyCount,
    totalPeers,
    isWorking,
    onCreateRoom,
    onJoinRoom,
    onLeaveRoom,
    onTransferHost,
    onRequestSync,
    onClearError,
    playbackTarget,
    onPlaybackTargetChange,
    mpvRunning,
  } = props;

  const [joinCode, setJoinCode] = useState('');

  const inRoom = Boolean(roomCode);
  const normalizedCode = useMemo(() => joinCode.trim().toUpperCase(), [joinCode]);

  return (
    <div className="syncplay-panel">
      <div className="row split align-center">
        <strong>SyncPlay</strong>
        {inRoom ? <span className="badge">Room: {roomCode}</span> : null}
      </div>

      <p className="muted tiny">{status}</p>

      <label className="syncplay-target">
        <span className="muted tiny">Sync target</span>
        <select
          value={playbackTarget}
          onChange={e => onPlaybackTargetChange(e.target.value as 'html5' | 'mpv')}
        >
          <option value="html5">Embedded Player (HTML5)</option>
          <option value="mpv">External MPV</option>
        </select>
        {playbackTarget === 'mpv' ? (
          <span className="muted tiny">{mpvRunning ? 'MPV running' : 'MPV not running yet'}</span>
        ) : null}
      </label>

      {error ? (
        <div className="row split align-center gap-sm">
          <p className="error tiny">{error}</p>
          <button className="syncplay-inline-btn" onClick={onClearError}>Dismiss</button>
        </div>
      ) : null}

      {!inRoom ? (
        <div className="syncplay-actions">
          <div className="row gap-sm">
            <input
              value={joinCode}
              onChange={e => setJoinCode(e.target.value)}
              placeholder="Enter room code"
              maxLength={5}
            />
            <button
              className="primary-btn"
              disabled={isWorking || normalizedCode.length < 5}
              onClick={() => void onJoinRoom(normalizedCode)}
            >
              Join
            </button>
          </div>
          <button
            disabled={isWorking}
            onClick={() => void onCreateRoom()}
          >
            Create Room
          </button>
        </div>
      ) : (
        <div className="syncplay-room">
          <div className="row split align-center">
            <span className="muted tiny">Host: {hostUserId === selfUserId ? 'You' : hostUserId.slice(0, 8)}</span>
            <div className="row gap-sm">
              <button className="syncplay-inline-btn" onClick={onRequestSync}>Resync</button>
              <button onClick={onLeaveRoom}>Leave</button>
            </div>
          </div>

          {inBufferGate ? (
            <p className="muted tiny">Buffer gate active: {readyCount}/{totalPeers} ready</p>
          ) : null}

          <div className="syncplay-peer-list">
            {peers.length === 0 ? <p className="muted tiny">Waiting for participant states...</p> : null}
            {peers.map(peer => (
              <div className="syncplay-peer" key={peer.socketId}>
                <div className="row split align-center">
                  <span>{peer.displayName}{peer.userId === selfUserId ? ' (You)' : ''}</span>
                  <span className="muted tiny">{peer.currentTime.toFixed(1)}s</span>
                </div>
                <div className="row split align-center">
                  <span className="muted tiny">Buffer: {formatBuffered(peer.bufferedAhead)}</span>
                  <span className="muted tiny">{peer.ready ? 'Ready' : peer.readyState}</span>
                </div>
                {hostUserId === selfUserId && peer.userId !== selfUserId ? (
                  <button className="syncplay-host-transfer" onClick={() => onTransferHost(peer.userId)}>
                    Transfer host
                  </button>
                ) : null}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
