import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { Episode, Show, ShowDetails } from '../types';

type Props = {
  shows: Show[];
  details: ShowDetails | null;
  loadingShows: boolean;
  loadingDetails: boolean;
  error: string;
  onSelectShow: (showId: string) => void;
  onPlayEpisode: (animeId: string, animeTitle: string, episode: Episode) => void;
};

export function LibraryPage({
  shows,
  details,
  loadingShows,
  loadingDetails,
  error,
  onSelectShow,
  onPlayEpisode,
}: Props) {
  const [query, setQuery] = useState('');
  const [showEpisodes, setShowEpisodes] = useState(false);
  const episodesRef = useRef<HTMLDivElement | null>(null);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return shows;
    return shows.filter(s => s.title.toLowerCase().includes(q));
  }, [shows, query]);

  useEffect(() => {
    setShowEpisodes(false);
  }, [details?.anime.id]);

  const openEpisodes = () => {
    setShowEpisodes(true);
    window.setTimeout(() => {
      episodesRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 60);
  };

  return (
    <div className="library-modern">
      <section className="panel library-top-panel">
        <div className="library-header-row">
          <h2>Discover Anime</h2>
          <input
            className="search-input"
            placeholder="Search anime..."
            value={query}
            onChange={e => setQuery(e.target.value)}
          />
        </div>
        {loadingShows ? <p className="muted">Loading shows...</p> : null}
        {error ? <p className="error">{error}</p> : null}

        <div className="library-card-grid">
          {filtered.map(show => {
            const cover = show.cover_image_url || details?.anime.imageUrl || '';
            return (
              <button
                key={show.id}
                className={`library-card ${details?.anime.id === show.id ? 'active' : ''}`}
                onClick={() => onSelectShow(show.id)}
              >
                <div
                  className="library-card-art"
                  style={cover ? { backgroundImage: `url(${cover})` } : undefined}
                />
                <div className="library-card-overlay">
                  <strong>{show.title}</strong>
                  <span>{show.episode_count ? `${show.episode_count} episodes` : 'Anime'}</span>
                </div>
              </button>
            );
          })}
        </div>
      </section>

      <section className="panel library-content modern-detail-panel">
        {!details && <p className="muted">Select an anime card to open details.</p>}
        {loadingDetails ? <p className="muted">Loading episodes...</p> : null}
        {details ? (
          <>
            <div className="hero-row modern-hero">
              <div
                className="hero-poster"
                style={details.anime.imageUrl ? { backgroundImage: `url(${details.anime.imageUrl})` } : undefined}
              />

              <div className="hero-copy">
                <h2>{details.anime.title}</h2>
                <p className="muted synopsis-copy">{details.anime.synopsis}</p>

                <div className="row gap-sm wrap">
                  <button className="primary-btn" onClick={openEpisodes}>Watch Now</button>
                  <button>Add To List</button>
                </div>
              </div>

              <div className="hero-pill">{details.episodes.length} Episodes</div>
            </div>

            <div ref={episodesRef} className="episodes-block">
              <h3>Episodes</h3>
              {!showEpisodes ? (
                <p className="muted">Click Watch Now to open episodes list.</p>
              ) : (
                <div className="list episode-list">
                  {details.episodes.map(ep => (
                    <div className="row split list-item episode-row" key={ep.id}>
                      <div className="episode-copy">
                        <strong>Episode {ep.number}</strong>
                        <div className="muted">{ep.title}</div>
                        <div className="episode-runtime">{ep.duration || '24:00'}</div>
                      </div>
                      <button className="primary-btn" onClick={() => onPlayEpisode(details.anime.id, details.anime.title, ep)}>
                        Play Episode
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </>
        ) : null}
      </section>
    </div>
  );
}
