import React, { useMemo, useState } from 'react';
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

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return shows;
    return shows.filter(s => s.title.toLowerCase().includes(q));
  }, [shows, query]);

  return (
    <div className="layout-two-col">
      <aside className="panel">
        <h2>Library</h2>
        <input
          placeholder="Search anime..."
          value={query}
          onChange={e => setQuery(e.target.value)}
        />
        {loadingShows ? <p className="muted">Loading shows...</p> : null}
        {error ? <p className="error">{error}</p> : null}
        <div className="list">
          {filtered.map(show => (
            <button key={show.id} className="list-item" onClick={() => onSelectShow(show.id)}>
              {show.title}
            </button>
          ))}
        </div>
      </aside>

      <section className="panel">
        {!details && <p className="muted">Select an anime to view episodes.</p>}
        {loadingDetails ? <p className="muted">Loading episodes...</p> : null}
        {details ? (
          <>
            <h2>{details.anime.title}</h2>
            <p className="muted">{details.anime.synopsis}</p>
            <div className="list">
              {details.episodes.map(ep => (
                <div className="row split list-item" key={ep.id}>
                  <div>
                    <strong>Episode {ep.number}</strong>
                    <div className="muted">{ep.title}</div>
                  </div>
                  <button onClick={() => onPlayEpisode(details.anime.id, details.anime.title, ep)}>Play</button>
                </div>
              ))}
            </div>
          </>
        ) : null}
      </section>
    </div>
  );
}
