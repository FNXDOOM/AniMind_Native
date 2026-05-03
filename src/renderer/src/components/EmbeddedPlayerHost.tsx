/**
 * EmbeddedPlayerHost.tsx
 *
 * Renders an invisible placeholder div whose screen-space bounds are
 * continuously mirrored to a child BrowserWindow in the main process.
 * mpv renders into that child window so video appears "inside" this div.
 *
 * State (paused / timePos / duration) is received via the preload's
 * onStateChanged subscription which the main process polls every 500 ms.
 */
import React, { forwardRef, useCallback, useEffect, useRef } from 'react';
import { desktopApi } from '../api';

// ─────────────────────────────────────────────────────────────────────────────
// Public handle exposed via forwardRef
// ─────────────────────────────────────────────────────────────────────────────
export interface EmbeddedPlayerHandle {
  play: () => Promise<void>;
  pause: () => Promise<void>;
  seek: (time: number) => Promise<void>;
  setVolume: (volume: number) => Promise<void>;
  setMuted: (muted: boolean) => Promise<void>;
  stop: () => Promise<void>;
  currentTime: number;
  duration: number;
  paused: boolean;
  volume: number;
  muted: boolean;
}

interface Props {
  className?: string;
  streamUrl?: string;
  onStateChange?: (state: { paused: boolean; timePos: number; duration: number }) => void;
  onError?: (error: string) => void;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/** Round to nearest integer — setBounds requires integers. */
function rounded(n: number) { return Math.round(n); }

// ─────────────────────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────────────────────
export const EmbeddedPlayerHost = forwardRef<EmbeddedPlayerHandle, Props>(
  ({ className, streamUrl, onStateChange, onError }, ref) => {
    const containerRef = useRef<HTMLDivElement>(null);
    const boundsSyncFrameRef = useRef<number | null>(null);
    const boundsSyncTimerRef = useRef<number | null>(null);
    const boundsSyncInFlightRef = useRef(false);
    const pendingBoundsRef = useRef<{ x: number; y: number; width: number; height: number; coordinateSpace: 'content' } | null>(null);
    const lastBoundsKeyRef = useRef('');

    // Local state mirror so the imperative handle always has fresh values
    const stateRef = useRef({
      paused: true,
      timePos: 0,
      duration: 0,
      volume: 85,
      muted: false,
    });

    // ── Imperative handle ───────────────────────────────────────────────────
    React.useImperativeHandle(ref, () => ({
      async play() {
        try {
          await desktopApi.play();
          stateRef.current.paused = false;
        } catch (err) {
          onError?.(`Play failed: ${err instanceof Error ? err.message : String(err)}`);
          throw err;
        }
      },
      async pause() {
        try {
          await desktopApi.pause();
          stateRef.current.paused = true;
        } catch (err) {
          onError?.(`Pause failed: ${err instanceof Error ? err.message : String(err)}`);
          throw err;
        }
      },
      async seek(time: number) {
        try {
          await desktopApi.seek(time);
          stateRef.current.timePos = time;
        } catch (err) {
          onError?.(`Seek failed: ${err instanceof Error ? err.message : String(err)}`);
          throw err;
        }
      },
      async setVolume(volume: number) {
        try {
          await desktopApi.setPlayerVolume(volume);
          stateRef.current.volume = volume;
        } catch (err) {
          onError?.(`setVolume failed: ${err instanceof Error ? err.message : String(err)}`);
          throw err;
        }
      },
      async setMuted(muted: boolean) {
        try {
          await desktopApi.setPlayerMuted(muted);
          stateRef.current.muted = muted;
        } catch (err) {
          onError?.(`setMuted failed: ${err instanceof Error ? err.message : String(err)}`);
          throw err;
        }
      },
      async stop() {
        try {
          await desktopApi.stop();
          stateRef.current = { paused: true, timePos: 0, duration: 0, volume: 85, muted: false };
        } catch (err) {
          onError?.(`Stop failed: ${err instanceof Error ? err.message : String(err)}`);
          throw err;
        }
      },
      get currentTime() { return stateRef.current.timePos; },
      get duration()    { return stateRef.current.duration; },
      get paused()      { return stateRef.current.paused; },
      get volume()      { return stateRef.current.volume; },
      get muted()       { return stateRef.current.muted; },
    }), [onError]);

    // ── Bounds sync ─────────────────────────────────────────────────────────
    // Send bounds in renderer-content coordinates (relative to the webContents
    // viewport). Main process maps them to absolute window coordinates.
    const flushBounds = useCallback(async () => {
      if (boundsSyncInFlightRef.current || !pendingBoundsRef.current) return;

      const bounds = pendingBoundsRef.current;
      pendingBoundsRef.current = null;
      const key = JSON.stringify(bounds);
      if (key === lastBoundsKeyRef.current) {
        return;
      }

      boundsSyncInFlightRef.current = true;
      try {
        await desktopApi.setSurfaceBounds(bounds);
        lastBoundsKeyRef.current = key;
      } catch (err) {
        onError?.(`Failed to sync embedded player bounds: ${err instanceof Error ? err.message : String(err)}`);
      } finally {
        boundsSyncInFlightRef.current = false;
        if (pendingBoundsRef.current) {
          window.setTimeout(() => {
            void flushBounds();
          }, 0);
        }
      }
    }, [onError]);

    const queueBoundsSync = useCallback(() => {
      if (boundsSyncFrameRef.current !== null) return;
      boundsSyncFrameRef.current = window.requestAnimationFrame(() => {
        boundsSyncFrameRef.current = null;
        void flushBounds();
      });
    }, [flushBounds]);

    const syncBounds = useCallback(() => {
      const el = containerRef.current;
      if (!el) return;

      const rect = el.getBoundingClientRect();

      const bounds = {
        x:      rounded(rect.left),
        y:      rounded(rect.top),
        width:  rounded(rect.width),
        height: rounded(rect.height),
        coordinateSpace: 'content' as const,
      };

      // Clamp to minimum so the child window is always valid
      if (bounds.width  < 4) bounds.width  = 4;
      if (bounds.height < 4) bounds.height = 4;

      pendingBoundsRef.current = bounds;
      queueBoundsSync();
    }, [queueBoundsSync]);

    // Sync bounds whenever the div size changes (ResizeObserver) or the
    // window itself moves/resizes.
    useEffect(() => {
      const el = containerRef.current;
      if (!el) return;

      // Initial sync
      syncBounds();

      const ro = new ResizeObserver(syncBounds);
      ro.observe(el);

      window.addEventListener('resize', syncBounds);
      window.addEventListener('scroll', syncBounds, true);

      // Poll slowly to catch native window drags where DOM resize events do not fire.
      // (no DOM event fires during an OS drag of the Electron window)
      boundsSyncTimerRef.current = window.setInterval(syncBounds, 1500);

      return () => {
        ro.disconnect();
        window.removeEventListener('resize', syncBounds);
        window.removeEventListener('scroll', syncBounds, true);
        if (boundsSyncTimerRef.current !== null) {
          window.clearInterval(boundsSyncTimerRef.current);
          boundsSyncTimerRef.current = null;
        }
        if (boundsSyncFrameRef.current !== null) {
          window.cancelAnimationFrame(boundsSyncFrameRef.current);
          boundsSyncFrameRef.current = null;
        }
      };
    }, [syncBounds]);

    // ── Show/hide surface with component lifecycle ──────────────────────────
    useEffect(() => {
      void desktopApi.showSurface();
      return () => {
        // Ensure embedded backend does not keep playing audio after unmount.
        void desktopApi.stop();
      };
    }, []);

    // ── Load video when streamUrl changes ───────────────────────────────────
    useEffect(() => {
      if (!streamUrl) return;
      const load = async () => {
        try {
          await desktopApi.openPlayer(streamUrl);
        } catch (err) {
          onError?.(`Failed to open stream: ${err instanceof Error ? err.message : String(err)}`);
        }
      };
      void load();
    }, [streamUrl, onError]);

    // ── Subscribe to state events from main process ─────────────────────────
    useEffect(() => {
      // The preload exposes onStateChanged which maps ipcRenderer → callback.
      // Main process polls native.getState() every 500 ms and pushes via
      // mainWindow.webContents.send('player:stateChanged', state).
      const unsubscribe = window.animindDesktop.player.onStateChanged(
        (state: { paused: boolean; timePos: number; duration: number }) => {
          stateRef.current.paused   = state.paused;
          stateRef.current.timePos  = state.timePos;
          stateRef.current.duration = state.duration;
          onStateChange?.(state);
        },
      );
      return unsubscribe;
    }, [onStateChange]);

    // ── Render ──────────────────────────────────────────────────────────────
    // The div is intentionally transparent / black — the child BrowserWindow
    // (with mpv rendering inside it) sits directly behind this exact rectangle.
    return (
      <div
        ref={containerRef}
        className={className}
        style={{
          width: '100%',
          height: '100%',
          backgroundColor: '#000',
          position: 'relative',
          overflow: 'hidden',
          // No content here — mpv paints behind this via its own child window
        }}
      />
    );
  },
);

EmbeddedPlayerHost.displayName = 'EmbeddedPlayerHost';
