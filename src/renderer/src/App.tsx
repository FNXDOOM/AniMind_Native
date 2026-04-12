import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { desktopApi } from './api';
import { useLibrary } from './hooks/useLibrary';
import { usePlayer } from './hooks/usePlayer';
import type { Episode, SessionInfo, StreamTicket, SubtitleTrack } from './types';
import { LoginPage } from './pages/LoginPage';
import { LibraryPage } from './pages/LibraryPage';
import { PlayerPage } from './pages/PlayerPage';
import { SettingsPage } from './pages/SettingsPage';

type View = 'library' | 'player' | 'settings';

export default function App() {
  const [session, setSession] = useState<SessionInfo | null>(null);
  const [authError, setAuthError] = useState('');
  const [view, setView] = useState<View>('library');

  const [currentAnimeId, setCurrentAnimeId] = useState<string | null>(null);
  const [currentAnimeTitle, setCurrentAnimeTitle] = useState('');
  const [currentEpisode, setCurrentEpisode] = useState<Episode | null>(null);
  const [streamInfo, setStreamInfo] = useState<StreamTicket | null>(null);
  const [playerError, setPlayerError] = useState('');
  const [opening, setOpening] = useState(false);
  const [cloudSubtitles, setCloudSubtitles] = useState<SubtitleTrack[]>([]);

  const { shows, selectedShow, loadingShows, loadingDetails, error, loadShowDetails } = useLibrary();

  const episodeIndex = useMemo(() => {
    if (!selectedShow || !currentEpisode) return null;
    const idx = selectedShow.episodes.findIndex(e => e.id === currentEpisode.id);
    return idx >= 0 ? idx : null;
  }, [selectedShow, currentEpisode]);

  const player = usePlayer(currentAnimeId, episodeIndex);

  useEffect(() => {
    void desktopApi.getSession().then(setSession).catch(() => setSession(null));
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

  const signOut = useCallback(async () => {
    await desktopApi.signOut();
    setSession(null);
    setCurrentEpisode(null);
    setStreamInfo(null);
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
      await desktopApi.openPlayer(ticket.url, `${animeTitle} - Episode ${episode.number}`);

      const subtitles = await desktopApi.getSubtitles(episode.id);
      setCloudSubtitles(subtitles);

      if (episodeIndex !== null) {
        const saved = await desktopApi.getProgress(animeId, episodeIndex);
        if (saved > 0) await desktopApi.seek(saved);
      }

      await player.refresh();
      setView('player');
    } catch (err: any) {
      setPlayerError(err?.message ?? 'Failed to start playback');
    } finally {
      setOpening(false);
    }
  }, [episodeIndex, player]);

  const openSettings = useCallback(() => setView('settings'), []);

  if (!session) {
    return <LoginPage onSubmit={signIn} error={authError} />;
  }

  return (
    <div className="app-shell">
      <header className="app-header">
        <h1>Animind Desktop</h1>
        <div className="row gap-sm align-center">
          <button onClick={() => setView('library')}>Library</button>
          <button onClick={() => setView('player')} disabled={!currentEpisode}>Player</button>
          <button onClick={openSettings}>Settings</button>
          <button className="danger" onClick={() => void signOut()}>Sign Out</button>
        </div>
      </header>

      <main className="app-main">
        {view === 'library' && (
          <LibraryPage
            shows={shows}
            details={selectedShow}
            loadingShows={loadingShows}
            loadingDetails={loadingDetails}
            error={error || playerError}
            onSelectShow={showId => void loadShowDetails(showId)}
            onPlayEpisode={(animeId, animeTitle, episode) => void startEpisode(animeId, animeTitle, episode)}
          />
        )}

        {view === 'player' && currentEpisode && currentAnimeId ? (
          <PlayerPage
            animeId={currentAnimeId}
            animeTitle={currentAnimeTitle}
            episode={currentEpisode}
            streamInfo={streamInfo}
            loading={opening}
            subtitles={cloudSubtitles}
            paused={player.paused}
            timePos={player.timePos}
            duration={player.duration}
            tracks={player.tracks}
            error={player.error || playerError}
            onPlay={() => player.play()}
            onPause={() => player.pause()}
            onSeek={seconds => player.seek(seconds)}
            onRefreshTracks={() => player.refresh()}
            onSetAudioTrack={trackId => player.setAudioTrack(trackId)}
            onSetSubtitleTrack={trackId => player.setSubtitleTrack(trackId)}
            onAddSubtitle={track => desktopApi.addSubtitleContent(currentEpisode.id, track)}
          />
        ) : null}

        {view === 'settings' && (
          <SettingsPage
            onLoad={() => desktopApi.getSettings()}
            onSave={next => desktopApi.saveSettings(next)}
          />
        )}
      </main>
    </div>
  );
}
