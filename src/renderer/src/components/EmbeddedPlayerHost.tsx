/**
 * EmbeddedPlayerHost.tsx
 *
 * Renders an invisible placeholder <div> whose screen-space bounds are
 * continuously mirrored to the native mpv child window in the main process.
 *
 * COORDINATE MODEL (Jellyfin-style):
 *   getBoundingClientRect() returns CSS logical pixels relative to the viewport.
 *   We add window.screenX / window.screenY (also logical) to get screen coords.
 *   Then multiply by window.devicePixelRatio to get physical (DPI-scaled) pixels.
 *   The main process receives these physical pixels and forwards them to the
 *   native addon, which calls ScreenToClient(mainWindowHwnd) to convert to
 *   parent-relative child coordinates — no DPI adjustment needed in main.
 *
 * BOUNDS SYNC STRATEGY:
 *   - ResizeObserver fires when the div changes size (layout changes, panel open/close)
 *   - 'resize' event fires when the OS window changes size (maximize, restore)
 *   - A 1500ms fallback poll catches OS window MOVES (no DOM event fires for those)
 *   - A debounce queue avoids redundant IPC calls on rapid resize
 */
import React, { forwardRef, useCallback, useEffect, useRef } from 'react';
import { desktopApi } from '../api';

// ─── Public handle ────────────────────────────────────────────────────────────
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

// ─── Component ────────────────────────────────────────────────────────────────
export const EmbeddedPlayerHost = forwardRef<EmbeddedPlayerHandle, Props>(
  ({ className, streamUrl, onStateChange, onError }, ref) => {
    const containerRef        = useRef<HTMLDivElement>(null);
    const onErrorRef          = useRef(onError);
    const rafRef              = useRef<number | null>(null);
    const pollTimerRef        = useRef<number | null>(null);
    const inFlightRef         = useRef(false);
    const pendingBoundsRef    = useRef<{
      x: number; y: number; width: number; height: number; coordinateSpace: 'screen';
    } | null>(null);
    const lastBoundsKeyRef    = useRef('');

    useEffect(() => { onErrorRef.current = onError; }, [onError]);

    // Local state mirror for the imperative handle
    const stateRef = useRef({ paused: true, timePos: 0, duration: 0, volume: 85, muted: false });

    // ── Imperative handle ─────────────────────────────────────────────────
    React.useImperativeHandle(ref, () => ({
      async play()  {
        try { await desktopApi.play();  stateRef.current.paused = false; }
        catch (err) { onError?.(`Play failed: ${err instanceof Error ? err.message : String(err)}`); throw err; }
      },
      async pause() {
        try { await desktopApi.pause(); stateRef.current.paused = true;  }
        catch (err) { onError?.(`Pause failed: ${err instanceof Error ? err.message : String(err)}`); throw err; }
      },
      async seek(time: number) {
        try { await desktopApi.seek(time); stateRef.current.timePos = time; }
        catch (err) { onError?.(`Seek failed: ${err instanceof Error ? err.message : String(err)}`); throw err; }
      },
      async setVolume(volume: number) {
        try { await desktopApi.setPlayerVolume(volume); stateRef.current.volume = volume; }
        catch (err) { onError?.(`setVolume failed: ${err instanceof Error ? err.message : String(err)}`); throw err; }
      },
      async setMuted(muted: boolean) {
        try { await desktopApi.setPlayerMuted(muted); stateRef.current.muted = muted; }
        catch (err) { onError?.(`setMuted failed: ${err instanceof Error ? err.message : String(err)}`); throw err; }
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

    // ── Bounds sync ───────────────────────────────────────────────────────
    //
    // We compute PHYSICAL (DPI-aware) screen-absolute pixels and send them
    // to the main process. The native addon then does ScreenToClient() against
    // the main window HWND to position the child window correctly.
    //
    const flushBounds = useCallback(async () => {
      if (inFlightRef.current || !pendingBoundsRef.current) return;
      const bounds = pendingBoundsRef.current;
      pendingBoundsRef.current = null;
      const key = `${bounds.x},${bounds.y},${bounds.width},${bounds.height}`;
      if (key === lastBoundsKeyRef.current) return;

      inFlightRef.current = true;
      try {
        await desktopApi.setSurfaceBounds(bounds);
        lastBoundsKeyRef.current = key;
      } catch (err) {
        onErrorRef.current?.(
          `Failed to sync embedded player bounds: ${err instanceof Error ? err.message : String(err)}`
        );
      } finally {
        inFlightRef.current = false;
        // If another bounds update arrived while this one was in-flight, send it now.
        if (pendingBoundsRef.current) {
          window.setTimeout(() => { void flushBounds(); }, 0);
        }
      }
    }, []);

    const queueBoundsSync = useCallback(() => {
      if (rafRef.current !== null) return; // already scheduled this frame
      rafRef.current = window.requestAnimationFrame(() => {
        rafRef.current = null;
        void flushBounds();
      });
    }, [flushBounds]);

    const syncBounds = useCallback(() => {
      const el = containerRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();

      // Convert CSS logical pixels → physical screen pixels (DPI-aware).
      // window.screenX/Y + rect.left/top gives logical screen coords.
      // Multiply by devicePixelRatio for physical pixels.
      const dpr = window.devicePixelRatio || 1;
      const bounds = {
        x:              Math.round((window.screenX + rect.left) * dpr),
        y:              Math.round((window.screenY + rect.top)  * dpr),
        width:          Math.max(4, Math.round(rect.width  * dpr)),
        height:         Math.max(4, Math.round(rect.height * dpr)),
        coordinateSpace: 'screen' as const,
      };

      pendingBoundsRef.current = bounds;
      queueBoundsSync();
    }, [queueBoundsSync]);

    // Attach observers
    useEffect(() => {
      const el = containerRef.current;
      if (!el) return;

      syncBounds(); // initial

      const ro = new ResizeObserver(syncBounds);
      ro.observe(el);
      window.addEventListener('resize', syncBounds);
      window.addEventListener('scroll', syncBounds, true);

      // Fallback poll for OS window moves (no DOM event fires during a native drag)
      pollTimerRef.current = window.setInterval(syncBounds, 1500);

      return () => {
        ro.disconnect();
        window.removeEventListener('resize', syncBounds);
        window.removeEventListener('scroll', syncBounds, true);
        if (pollTimerRef.current !== null) { window.clearInterval(pollTimerRef.current); pollTimerRef.current = null; }
        if (rafRef.current !== null)        { window.cancelAnimationFrame(rafRef.current); rafRef.current = null; }
      };
    }, [syncBounds]);

  useEffect(() => {
    document.documentElement.style.backgroundColor = 'transparent';
    document.body.style.backgroundColor = 'transparent';
    return () => {
      document.documentElement.style.backgroundColor = '';
      document.body.style.backgroundColor = '';
    };
  }, []);

  useEffect(() => {
    void desktopApi.showSurface();
    return () => {
      void desktopApi.hideSurface();
      void desktopApi.stop();
    };
  }, []);

    // ── Load video when streamUrl changes ─────────────────────────────────
    useEffect(() => {
      if (!streamUrl) return;
      const load = async () => {
        try {
          await desktopApi.openPlayer(streamUrl);
          // After mpv opens, push current bounds immediately so the first frame
          // appears in the right place (not the top-left corner of the window).
          syncBounds();
        } catch (err) {
          onErrorRef.current?.(`Failed to open stream: ${err instanceof Error ? err.message : String(err)}`);
        }
      };
      void load();
    }, [streamUrl, syncBounds]);

    // ── Subscribe to playback state events ────────────────────────────────
    useEffect(() => {
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

    // ── Render ────────────────────────────────────────────────────────────
    // This div is an invisible placeholder. mpv paints behind/below it via a
    // native Win32 child window, not inside the DOM.
    return (
      <div
        ref={containerRef}
        className={className}
        style={{
          width: '100%',
          height: '100%',
          backgroundColor: 'transparent',
          position: 'relative',
          overflow: 'hidden',
        }}
      />
    );
  },
);

EmbeddedPlayerHost.displayName = 'EmbeddedPlayerHost';
