import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { io, type Socket } from 'socket.io-client';
import { desktopApi } from '../api';
import type { SyncplayParticipantState } from '../types';

const SYNCPLAY_SOCKET_PATH = '/api/socket.io';
const ACK_TIMEOUT_MS = 10_000;
const HEARTBEAT_INTERVAL_MS = 3_000;
const NTP_WARMUP_SAMPLES = 4;
const NTP_PING_INTERVAL_MS = 500;

type RoomResponse = {
  success: boolean;
  roomCode?: string;
  error?: string;
  hostUserId?: string;
  currentTime?: number;
  isPlaying?: boolean;
};

type Snapshot = {
  currentTime: number;
  playbackRate: number;
  bufferedAhead: number;
};

type SyncplayCallbacks = {
  onRemotePlay: (time: number, scheduledPlayAt: number) => void;
  onRemotePause: (time: number) => void;
  onRemoteSeek: (time: number) => void;
  onSoftCorrect: (time: number) => void;
  onSpeedSeek: (rate: number, duration: number, targetTime: number) => void;
  onWaitForBufferGoal: (time: number, goalSeconds: number) => void;
  onStatusEvent: (message: string) => void;
};

type SyncplayState = {
  status: string;
  error: string;
  roomCode: string;
  hostUserId: string;
  isConnected: boolean;
  peers: SyncplayParticipantState[];
  readyCount: number;
  totalPeers: number;
  inBufferGate: boolean;
  bufferGoalSeconds: number;
};

const INITIAL_STATE: SyncplayState = {
  status: 'SyncPlay idle',
  error: '',
  roomCode: '',
  hostUserId: '',
  isConnected: false,
  peers: [],
  readyCount: 0,
  totalPeers: 0,
  inBufferGate: false,
  bufferGoalSeconds: 120,
};

function normalizeBaseUrl(raw: string): string {
  return raw.replace(/\/+$/, '');
}

export function useSyncplay(episodeId: string, getSnapshot: () => Snapshot | Promise<Snapshot>, callbacks: SyncplayCallbacks) {
  const [state, setState] = useState<SyncplayState>(INITIAL_STATE);
  const socketRef = useRef<Socket | null>(null);
  const getSnapshotRef = useRef(getSnapshot);
  const callbacksRef = useRef(callbacks);
  const roomCodeRef = useRef('');
  const bufferGoalRef = useRef(120);
  const heartbeatRef = useRef<number | null>(null);
  const ntpRef = useRef<number | null>(null);
  const ntpCountRef = useRef(0);
  const clockOffsetRef = useRef(0);

  useEffect(() => {
    getSnapshotRef.current = getSnapshot;
  }, [getSnapshot]);

  useEffect(() => {
    callbacksRef.current = callbacks;
  }, [callbacks]);

  const stopHeartbeat = useCallback(() => {
    if (heartbeatRef.current !== null) {
      window.clearInterval(heartbeatRef.current);
      heartbeatRef.current = null;
    }
  }, []);

  const startHeartbeat = useCallback(() => {
    stopHeartbeat();
    heartbeatRef.current = window.setInterval(() => {
      const socket = socketRef.current;
      if (!socket?.connected) return;
      if (!roomCodeRef.current) return;

      void Promise.resolve(getSnapshotRef.current())
        .then((snap) => {
          socket.emit('heartbeat', {
            currentTime: snap.currentTime,
            playbackRate: snap.playbackRate,
            bufferedAhead: snap.bufferedAhead,
          });
        })
        .catch(() => {
          // Ignore transient heartbeat snapshot errors (e.g., MPV not ready).
        });
    }, HEARTBEAT_INTERVAL_MS);
  }, [stopHeartbeat]);

  const stopNtp = useCallback(() => {
    if (ntpRef.current !== null) {
      window.clearInterval(ntpRef.current);
      ntpRef.current = null;
    }
  }, []);

  const startNtp = useCallback(() => {
    stopNtp();
    ntpCountRef.current = 0;
    ntpRef.current = window.setInterval(() => {
      const socket = socketRef.current;
      if (!socket?.connected) {
        stopNtp();
        return;
      }

      if (ntpCountRef.current >= NTP_WARMUP_SAMPLES) {
        stopNtp();
        return;
      }

      socket.emit('timesync_ping', { clientSendTime: Date.now() });
      ntpCountRef.current += 1;
    }, NTP_PING_INTERVAL_MS);
  }, [stopNtp]);

  const disconnect = useCallback(() => {
    stopHeartbeat();
    stopNtp();

    if (socketRef.current) {
      socketRef.current.removeAllListeners();
      socketRef.current.disconnect();
      socketRef.current = null;
    }

    roomCodeRef.current = '';

    setState(INITIAL_STATE);
  }, [stopHeartbeat, stopNtp]);

  const ensureConnected = useCallback(async (): Promise<Socket> => {
    const existing = socketRef.current;
    if (existing?.connected) return existing;

    if (existing) {
      existing.removeAllListeners();
      existing.disconnect();
      socketRef.current = null;
    }

    const [settings, token] = await Promise.all([
      desktopApi.getSettings(),
      desktopApi.getAccessToken(),
    ]);

    if (!token) {
      throw new Error('Missing auth session for SyncPlay. Please sign in again.');
    }

    const baseUrl = normalizeBaseUrl(settings.backendUrl);
    const socket = io(baseUrl, {
      path: SYNCPLAY_SOCKET_PATH,
      auth: { token },
      transports: ['websocket', 'polling'],
      timeout: ACK_TIMEOUT_MS,
      reconnectionAttempts: 5,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 8000,
    });

    socketRef.current = socket;

    socket.on('connect', () => {
      setState(prev => ({ ...prev, isConnected: true, status: 'SyncPlay connected', error: '' }));
      startNtp();
      startHeartbeat();

      if (roomCodeRef.current) {
        socket.timeout(ACK_TIMEOUT_MS).emit('joinRoom', { roomCode: roomCodeRef.current }, (_err: unknown, res: RoomResponse) => {
          if (!res?.success) return;
          setState(prev => ({
            ...prev,
            hostUserId: res.hostUserId ?? prev.hostUserId,
            status: `Rejoined room ${roomCodeRef.current}`,
            error: '',
          }));
          socket.emit('requestSync');
        });
      }
    });

    socket.on('connect_error', (err) => {
      setState(prev => ({ ...prev, error: err?.message ?? 'Socket connect failed', status: 'SyncPlay connection error' }));
    });

    socket.on('disconnect', (reason) => {
      stopHeartbeat();
      setState(prev => ({
        ...prev,
        isConnected: false,
        status: `Disconnected: ${reason}`,
      }));
    });

    socket.on('reconnect', () => {
      setState(prev => ({ ...prev, status: 'Reconnected to SyncPlay' }));
      startNtp();
      startHeartbeat();
    });

    socket.on('timesync_pong', (payload: { clientSendTime: number; serverTime?: number; serverReceiveTime?: number }) => {
      const serverTime = payload.serverTime ?? payload.serverReceiveTime;
      if (typeof payload.clientSendTime !== 'number' || typeof serverTime !== 'number') return;

      const now = Date.now();
      const rtt = now - payload.clientSendTime;
      const oneWay = rtt / 2;
      const offset = serverTime + oneWay - now;
      const sampleWeight = 1 / Math.min(ntpCountRef.current + 1, 8);
      clockOffsetRef.current = clockOffsetRef.current * (1 - sampleWeight) + offset * sampleWeight;
    });

    socket.on('syncPlay', (data: { currentTime?: number; sentAt?: number; scheduledPlayAt?: number }) => {
      const t = typeof data.currentTime === 'number' ? data.currentTime : 0;
      const playAtServer = typeof data.scheduledPlayAt === 'number'
        ? data.scheduledPlayAt
        : (typeof data.sentAt === 'number' ? data.sentAt + 180 : Date.now() + 180);
      const localAt = Math.max(0, playAtServer - clockOffsetRef.current);
      callbacksRef.current.onRemotePlay(t, localAt);
      setState(prev => ({ ...prev, inBufferGate: false }));
    });

    socket.on('pause', (data: { currentTime?: number }) => {
      callbacksRef.current.onRemotePause(typeof data.currentTime === 'number' ? data.currentTime : 0);
    });

    socket.on('syncPaused', (data: { currentTime?: number }) => {
      callbacksRef.current.onRemotePause(typeof data.currentTime === 'number' ? data.currentTime : 0);
    });

    socket.on('seek', (data: { time?: number }) => {
      callbacksRef.current.onRemoteSeek(typeof data.time === 'number' ? data.time : 0);
    });

    socket.on('softCorrect', (data: { currentTime?: number }) => {
      callbacksRef.current.onSoftCorrect(typeof data.currentTime === 'number' ? data.currentTime : 0);
    });

    socket.on('speedSeek', (data: { rate?: number; duration?: number; targetTime?: number }) => {
      const rate = typeof data.rate === 'number' ? data.rate : 1;
      const duration = typeof data.duration === 'number' ? data.duration : 3000;
      const targetTime = typeof data.targetTime === 'number' ? data.targetTime : 0;
      callbacksRef.current.onSpeedSeek(rate, duration, targetTime);
    });

    socket.on('waitForBufferGoal', (data: { currentTime?: number; bufferGoalSeconds?: number; totalPeers?: number; readyCount?: number }) => {
      const currentTime = typeof data.currentTime === 'number' ? data.currentTime : 0;
      const goal = typeof data.bufferGoalSeconds === 'number' ? data.bufferGoalSeconds : 120;
      setState(prev => ({
        ...prev,
        status: 'Buffering to sync...',
        inBufferGate: true,
        bufferGoalSeconds: goal,
        readyCount: typeof data.readyCount === 'number' ? data.readyCount : prev.readyCount,
        totalPeers: typeof data.totalPeers === 'number' ? data.totalPeers : prev.totalPeers,
      }));
      bufferGoalRef.current = goal;
      callbacksRef.current.onWaitForBufferGoal(currentTime, goal);
    });

    socket.on('waitForReady', (data: { currentTime?: number; totalPeers?: number; readyCount?: number }) => {
      const currentTime = typeof data.currentTime === 'number' ? data.currentTime : 0;
      setState(prev => ({
        ...prev,
        status: 'Waiting for peers to become ready...',
        inBufferGate: true,
        readyCount: typeof data.readyCount === 'number' ? data.readyCount : prev.readyCount,
        totalPeers: typeof data.totalPeers === 'number' ? data.totalPeers : prev.totalPeers,
      }));
      callbacksRef.current.onWaitForBufferGoal(currentTime, bufferGoalRef.current);
    });

    socket.on('allReady', (data: { currentTime?: number; scheduledPlayAt?: number }) => {
      const t = typeof data.currentTime === 'number' ? data.currentTime : 0;
      const playAtServer = typeof data.scheduledPlayAt === 'number' ? data.scheduledPlayAt : Date.now() + 200;
      callbacksRef.current.onRemotePlay(t, Math.max(0, playAtServer - clockOffsetRef.current));
      setState(prev => ({ ...prev, inBufferGate: false, status: 'All peers ready' }));
    });

    socket.on('participantStates', (data: { peers?: SyncplayParticipantState[] }) => {
      const peers = Array.isArray(data.peers) ? data.peers : null;
      if (!peers) return;
      setState(prev => ({ ...prev, peers: [...peers] }));
    });

    socket.on('peerReady', (data: { readyCount?: number; totalPeers?: number }) => {
      setState(prev => ({
        ...prev,
        readyCount: typeof data.readyCount === 'number' ? data.readyCount : prev.readyCount,
        totalPeers: typeof data.totalPeers === 'number' ? data.totalPeers : prev.totalPeers,
      }));
    });

    socket.on('peerJoined', (data: { displayName?: string }) => {
      const message = `${data.displayName ?? 'A peer'} joined the room`;
      setState(prev => ({ ...prev, status: message }));
      callbacksRef.current.onStatusEvent(message);
    });

    socket.on('peerLeft', (data: { displayName?: string }) => {
      const message = `${data.displayName ?? 'A peer'} left the room`;
      setState(prev => ({ ...prev, status: message }));
      callbacksRef.current.onStatusEvent(message);
    });

    socket.on('peerStalling', (data: { displayName?: string }) => {
      const message = `${data.displayName ?? 'A peer'} is buffering`;
      setState(prev => ({ ...prev, status: message }));
      callbacksRef.current.onStatusEvent(message);
    });

    socket.on('peerStallRecovered', (data: { displayName?: string }) => {
      const message = `${data.displayName ?? 'A peer'} recovered`;
      setState(prev => ({ ...prev, status: message }));
      callbacksRef.current.onStatusEvent(message);
    });

    socket.on('sync', (data: { currentTime?: number; isPlaying?: boolean }) => {
      const t = typeof data.currentTime === 'number' ? data.currentTime : 0;
      if (data.isPlaying) {
        callbacksRef.current.onRemotePlay(t, Date.now() + 180);
      } else {
        callbacksRef.current.onRemotePause(t);
      }
    });

    socket.on('hostChanged', (data: { newHostUserId?: string; newHostDisplayName?: string }) => {
      const host = typeof data.newHostUserId === 'string' ? data.newHostUserId : '';
      const name = typeof data.newHostDisplayName === 'string' ? data.newHostDisplayName : host;
      setState(prev => ({ ...prev, hostUserId: host, status: `Host: ${name}` }));
    });

    socket.on('syncDenied', (data: { reason?: string }) => {
      setState(prev => ({ ...prev, error: data.reason ?? 'Sync action denied by server.' }));
    });

    return socket;
  }, [startHeartbeat, startNtp, stopHeartbeat]);

  const emitWithAckOrDisconnect = useCallback(<TResponse,>(
    socket: Socket,
    eventName: string,
    payload: Record<string, unknown>,
  ): Promise<TResponse> => {
    return new Promise<TResponse>((resolve, reject) => {
      let settled = false;

      const finish = (cb: () => void) => {
        if (settled) return;
        settled = true;
        socket.off('disconnect', onDisconnect);
        cb();
      };

      const onDisconnect = () => {
        finish(() => reject(new Error(`Socket disconnected during ${eventName}`)));
      };

      socket.once('disconnect', onDisconnect);
      socket.timeout(ACK_TIMEOUT_MS).emit(eventName, payload, (err: unknown, res: TResponse) => {
        finish(() => {
          if (err) {
            reject(new Error(err instanceof Error ? err.message : `${eventName} failed`));
            return;
          }
          resolve(res);
        });
      });
    });
  }, []);

  const createRoom = useCallback(async () => {
    const socket = await ensureConnected();

    const response = await emitWithAckOrDisconnect<RoomResponse>(socket, 'createRoom', { episodeId });

    if (!response.success || !response.roomCode) {
      throw new Error(response.error ?? 'Failed to create room');
    }

    setState(prev => ({
      ...prev,
      roomCode: response.roomCode ?? '',
      hostUserId: response.hostUserId ?? '',
      status: `Room ${response.roomCode} created`,
      error: '',
    }));
    roomCodeRef.current = response.roomCode ?? '';
  }, [emitWithAckOrDisconnect, ensureConnected, episodeId]);

  const joinRoom = useCallback(async (roomCode: string) => {
    const socket = await ensureConnected();

    const response = await emitWithAckOrDisconnect<RoomResponse>(socket, 'joinRoom', { roomCode });

    if (!response.success) {
      throw new Error(response.error ?? 'Failed to join room');
    }

    setState(prev => ({
      ...prev,
      roomCode: roomCode.trim().toUpperCase(),
      hostUserId: response.hostUserId ?? prev.hostUserId,
      status: `Joined room ${roomCode.trim().toUpperCase()}`,
      error: '',
    }));
    roomCodeRef.current = roomCode.trim().toUpperCase();

    if (typeof response.currentTime === 'number') {
      callbacksRef.current.onRemoteSeek(response.currentTime);
    }
    if (response.isPlaying && typeof response.currentTime === 'number') {
      callbacksRef.current.onRemotePlay(response.currentTime, Date.now() + 150);
    }

    startHeartbeat();
  }, [emitWithAckOrDisconnect, ensureConnected, startHeartbeat]);

  const leaveRoom = useCallback(() => {
    disconnect();
  }, [disconnect]);

  const emitPlay = useCallback((currentTime: number) => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('play', { currentTime });
  }, []);

  const emitPause = useCallback((currentTime: number) => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('pause', { currentTime });
  }, []);

  const emitSeek = useCallback((time: number) => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('seek', { time });
  }, []);

  const reportBufferingProgress = useCallback((bufferedSeconds: number, percent: number) => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('bufferingProgress', { bufferedSeconds, percent });
  }, []);

  const reportReady = useCallback(() => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('ready');
  }, []);

  const transferHost = useCallback((targetUserId: string) => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('transferHost', { targetUserId });
  }, []);

  const emitBuffering = useCallback(() => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('buffering');
  }, []);

  const emitStallRecovered = useCallback(() => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('stallRecovered');
  }, []);

  const requestSync = useCallback(() => {
    const socket = socketRef.current;
    if (!socket?.connected || !roomCodeRef.current) return;
    socket.emit('requestSync');
  }, []);

  const clearError = useCallback(() => {
    setState(prev => ({ ...prev, error: '' }));
  }, []);

  useEffect(() => {
    return () => {
      disconnect();
    };
  }, [disconnect]);

  const isInRoom = useMemo(() => Boolean(state.roomCode), [state.roomCode]);

  return {
    ...state,
    isInRoom,
    createRoom,
    joinRoom,
    leaveRoom,
    emitPlay,
    emitPause,
    emitSeek,
    reportBufferingProgress,
    reportReady,
    transferHost,
    emitBuffering,
    emitStallRecovered,
    requestSync,
    clearError,
  };
}

