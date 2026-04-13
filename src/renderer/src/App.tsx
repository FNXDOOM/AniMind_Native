import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { desktopApi } from './api';
import { useLibrary } from './hooks/useLibrary';
import type { AppSettings, AudioTrack, Episode, MpvAvailability, SessionInfo, SetupStatus, StreamTicket, SubtitleTrack } from './types';
import { LoginPage } from './pages/LoginPage';
import { LibraryPage } from './pages/LibraryPage';
import { PlayerPage } from './pages/PlayerPage';
import { SettingsPage } from './pages/SettingsPage';
import { FirstRunSetupPage } from './pages/FirstRunSetupPage';

type View = 'library' | 'player' | 'settings';

export default function App() {
  const [session, setSession] = useState<SessionInfo | null>(null);
  const [authError, setAuthError] = useState('');
  const [view, setView] = useState<View>('library');
  const [setupStatus, setSetupStatus] = useState<SetupStatus | null>(null);
  const [setupInitError, setSetupInitError] = useState('');

  const [currentAnimeId, setCurrentAnimeId] = useState<string | null>(null);
  const [currentAnimeTitle, setCurrentAnimeTitle] = useState('');
  const [currentEpisode, setCurrentEpisode] = useState<Episode | null>(null);
  const [streamInfo, setStreamInfo] = useState<StreamTicket | null>(null);
  const [streamUrl, setStreamUrl] = useState('');
  const [audioTracks, setAudioTracks] = useState<AudioTrack[]>([]);
  const [selectedAudioTrackIndex, setSelectedAudioTrackIndex] = useState<number | null>(null);
  const [resumeFromSeconds, setResumeFromSeconds] = useState(0);
  const [playerError, setPlayerError] = useState('');
  const [opening, setOpening] = useState(false);
  const [cloudSubtitles, setCloudSubtitles] = useState<SubtitleTrack[]>([]);

  const { shows, selectedShow, loadingShows, loadingDetails, error, loadShowDetails, clearSelectedShow } = useLibrary();

  const episodeIndex = useMemo(() => {
    if (!selectedShow || !currentEpisode) return null;
    const idx = selectedShow.episodes.findIndex(e => e.id === currentEpisode.id);
    return idx >= 0 ? idx : null;
  }, [selectedShow, currentEpisode]);

  const loadSetup = useCallback(async () => {
    setSetupInitError('');
    setSetupStatus(null);
    (async () => {
      if (!(window as any).animindDesktop) {
        throw new Error('Preload bridge unavailable. Ensure preload script loaded correctly.');
      }
      const status = await desktopApi.getSetupStatus();
      setSetupStatus(status);
      if (!status.ready) return;
      const sess = await desktopApi.getSession().catch(() => null);
      setSession(sess);
    })().catch((err: any) => {
      const message = err?.message ? String(err.message) : 'Failed to load setup state. Please retry.';
      console.error('[Setup] Initialization failed:', err);
      setSetupInitError(message);
      setSession(null);
    });
  }, []);

  useEffect(() => {
    void loadSetup();
  }, []);

  const signIn = useCallback(async (email: string, password: string) => {
    setAuthError('');
    try {
      const result = await desktopApi.signIn(email, password);
      setSession({ userId: result.userId, email: result.email });
    } catch (err: any) {
      setAuthError(err?.message ?? 'Login failed');
      throw err;
    }
  }, []);

  const signInWithGoogle = useCallback(async () => {
    setAuthError('');
    try {
      const result = await desktopApi.signInWithGoogle();
      setSession({ userId: result.userId, email: result.email });
    } catch (err: any) {
      setAuthError(err?.message ?? 'Google Sign-In failed');
      throw err;
    }
  }, []);

  const signOut = useCallback(async () => {
    await desktopApi.signOut();
    setSession(null);
    setCurrentEpisode(null);
    setStreamInfo(null);
    setStreamUrl('');
    setAudioTracks([]);
    setSelectedAudioTrackIndex(null);
    setResumeFromSeconds(0);
    setView('library');
  }, []);

  const startEpisode = useCallback(async (animeId: string, animeTitle: string, episode: Episode) => {
    setPlayerError('');
    setOpening(true);
    try {
      setCurrentAnimeId(animeId);
      setCurrentAnimeTitle(animeTitle);
      setCurrentEpisode(episode);

      const ticket = await desktopApi.getStreamTicket(episode.id);
      setStreamInfo(ticket);
      setStreamUrl(ticket.url);
      setSelectedAudioTrackIndex(null);

      const [subtitles, tracks] = await Promise.all([
        desktopApi.getSubtitles(episode.id),
        desktopApi.getAudioTracks(episode.id),
      ]);
      setCloudSubtitles(subtitles);
      setAudioTracks(tracks ?? []);

      const selectedIdx = selectedShow?.episodes.findIndex(e => e.id === episode.id) ?? -1;
      if (selectedIdx >= 0) {
        const saved = await desktopApi.getProgress(animeId, selectedIdx);
        setResumeFromSeconds(saved > 0 ? saved : 0);
      } else {
        setResumeFromSeconds(0);
      }
      setView('player');
    } catch (err: any) {
      setPlayerError(err?.message ?? 'Failed to start playback');
    } finally {
      setOpening(false);
    }
  }, [selectedShow]);

  const switchAudioTrack = useCallback(async (streamIndex: number | null, currentTime: number) => {
    if (!currentEpisode) return;

    setPlayerError('');
    setOpening(true);
    try {
      const ticket = streamIndex === null
        ? await desktopApi.getStreamTicket(currentEpisode.id)
        : await desktopApi.getStreamTicket(currentEpisode.id, streamIndex);
      setSelectedAudioTrackIndex(streamIndex);
      setStreamInfo(ticket);
      setStreamUrl(ticket.url);
      setResumeFromSeconds(Math.max(0, currentTime || 0));
    } catch (err: any) {
      setPlayerError(err?.message ?? 'Failed to switch audio track');
    } finally {
      setOpening(false);
    }
  }, [currentEpisode]);

  const saveProgress = useCallback(async (seconds: number) => {
    if (!currentAnimeId || episodeIndex === null) return;
    await desktopApi.saveProgress(currentAnimeId, episodeIndex, seconds);
  }, [currentAnimeId, episodeIndex]);

  const openInExternalPlayer = useCallback(async () => {
    if (!streamUrl || !currentAnimeTitle || !currentEpisode) return;
    await desktopApi.openPlayer(streamUrl, `${currentAnimeTitle} - Episode ${currentEpisode.number}`);
  }, [currentEpisode, currentAnimeTitle, streamUrl]);

  const openSettings = useCallback(() => setView('settings'), []);

  const saveAndValidateSetup = useCallback(async (settings: AppSettings): Promise<SetupStatus> => {
    await desktopApi.saveSettings(settings);
    const status = await desktopApi.getSetupStatus();
    setSetupStatus(status);
    if (status.ready && !session) {
      const sess = await desktopApi.getSession().catch(() => null);
      setSession(sess);
    }
    return status;
  }, [session]);

  const probeMpv = useCallback(async (mpvPath: string): Promise<MpvAvailability> => {
    return desktopApi.testMpv(mpvPath);
  }, []);

  if (!setupStatus) {
    return (
      <div className="center-screen">
        <div className="panel auth-panel">
          <h1>Animind Desktop</h1>
          <p className="muted">Loading setup...</p>
          {setupInitError ? <p className="error">{setupInitError}</p> : null}
          {setupInitError ? <button onClick={() => void loadSetup()}>Retry</button> : null}
        </div>
      </div>
    );
  }

  if (!setupStatus.ready) {
    return (
      <FirstRunSetupPage
        initialStatus={setupStatus}
        onSave={saveAndValidateSetup}
        onProbeMpv={probeMpv}
      />
    );
  }

  if (!session) {
    return <LoginPage onSubmit={signIn} onGoogleSignIn={signInWithGoogle} error={authError} />;
  }

  return (
    <>
      {/* Full-screen immersive player — rendered outside the shell so nothing clips it */}
      {view === 'player' && currentEpisode && currentAnimeId ? (
        <PlayerPage
          animeId={currentAnimeId}
          animeTitle={currentAnimeTitle}
          episode={currentEpisode}
          streamInfo={streamInfo}
          streamUrl={streamUrl}
          audioTracks={audioTracks}
          selectedAudioTrackIndex={selectedAudioTrackIndex}
          resumeFromSeconds={resumeFromSeconds}
          loading={opening}
          subtitles={cloudSubtitles}
          error={playerError}
          onSelectAudioTrack={(trackIndex, timePos) => switchAudioTrack(trackIndex, timePos)}
          onSaveProgress={seconds => saveProgress(seconds)}
          onOpenExternal={() => openInExternalPlayer()}
          onBack={() => setView('library')}
        />
      ) : (
        <div className="app-shell">
          <aside className="bento-sidebar">
            <h1 className="sidebar-brand">ANIMIND TV</h1>

            <nav className="sidebar-nav">
              <button title="Home" className={`nav-icon-btn ${view === 'library' ? 'active' : ''}`} onClick={() => setView('library')}>Home</button>
              <button title="Now Playing" className={`nav-icon-btn ${view === 'player' ? 'active' : ''}`} onClick={() => setView('player')} disabled={!currentEpisode}>Now Playing</button>
              <button title="Settings" className={`nav-icon-btn ${view === 'settings' ? 'active' : ''}`} onClick={openSettings}>Settings</button>
            </nav>

            <div className="sidebar-bottom">
              <button title="Sign Out" className="nav-icon-btn danger-btn" onClick={() => void signOut()}>Sign Out</button>
            </div>
          </aside>

          <main className={`app-main view-${view}`}>
            <div className={`ambient-bg ${view === 'library' && selectedShow ? 'active' : ''}`} style={selectedShow ? { backgroundImage: `url(${selectedShow.anime.imageUrl})` } : undefined} />
            <div className="app-main-content" style={{ position: 'relative', zIndex: 1 }}>
              {view === 'library' && (
                <LibraryPage
                  shows={shows}
                  details={selectedShow}
                  loadingShows={loadingShows}
                  loadingDetails={loadingDetails}
                  error={error || playerError}
                  onSelectShow={showId => void loadShowDetails(showId)}
                  onClearShow={clearSelectedShow}
                  onPlayEpisode={(animeId, animeTitle, episode) => void startEpisode(animeId, animeTitle, episode)}
                />
              )}

              {view === 'settings' && (
                <SettingsPage
                  onLoad={() => desktopApi.getSettings()}
                  onSave={next => saveAndValidateSetup(next as AppSettings)}
                />
              )}
            </div>
          </main>
        </div>
      )}
    </>
  );
}
