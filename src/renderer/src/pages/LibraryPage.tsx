import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { Episode, Show, ShowDetails } from '../types';
import type { PendingSync } from '../App';

interface CastMember {
  name: string;
  role: string;
  image: string;
}

type Props = {
  shows: Show[];
  details: ShowDetails | null;
  loadingShows: boolean;
  loadingDetails: boolean;
  error: string;
  pendingSync: PendingSync;
  onSelectShow: (showId: string) => void;
  onClearShow: () => void;
  onPlayEpisode: (animeId: string, animeTitle: string, episode: Episode) => void;
  onWatchTogether: (animeId: string, animeTitle: string, episode: Episode, sync: PendingSync) => void;
};

export function LibraryPage({
  shows,
  details,
  loadingShows,
  loadingDetails,
  error,
  pendingSync,
  onSelectShow,
  onClearShow,
  onPlayEpisode,
  onWatchTogether,
}: Props) {
  const [query, setQuery] = useState('');
  const episodesRef = useRef<HTMLDivElement | null>(null);
  const [cast, setCast] = useState<CastMember[]>([]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return shows;
    return shows.filter(s => s.title.toLowerCase().includes(q));
  }, [shows, query]);

  useEffect(() => {
    if (!details) { setCast([]); return; }
    const title = details.anime.title;
    const query = `
      query ($search: String) {
        Media(search: $search, type: ANIME) {
          characters(perPage: 8, sort: [ROLE]) {
            edges {
              node {
                name { full }
                image { medium }
              }
              voiceActors(language: JAPANESE) {
                name { full }
                image { medium }
              }
            }
          }
        }
      }
    `;
    fetch('https://graphql.anilist.co', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ query, variables: { search: title } }),
    })
      .then(r => r.json())
      .then((data: any) => {
        const edges = data?.data?.Media?.characters?.edges ?? [];
        const members: CastMember[] = edges.flatMap((edge: any) => {
          const charName = edge?.node?.name?.full ?? '';
          const charImg = edge?.node?.image?.medium ?? '';
          const actor = edge?.voiceActors?.[0];
          return actor ? [{
            name: actor.name?.full ?? charName,
            role: charName,
            image: actor.image?.medium ?? charImg,
          }] : [];
        });
        setCast(members);
      })
      .catch(() => setCast([]));
  }, [details?.anime.id]);

  if (details || loadingDetails) {
    return (
      <div className="plex-detail-view" style={{ paddingBottom: 64 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 40 }}>
          <button
            onClick={onClearShow}
            style={{
              display: 'flex', alignItems: 'center', gap: 8,
              background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)',
              borderRadius: 8, padding: '8px 16px', color: 'var(--text)', cursor: 'pointer',
              fontSize: 14, fontWeight: 500, transition: 'background 0.2s', boxShadow: 'none'
            }}
            onMouseEnter={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.1)')}
            onMouseLeave={e => (e.currentTarget.style.background = 'rgba(255,255,255,0.05)')}
          >
            ← Back to Library
          </button>
          <span style={{ color: 'var(--muted)', fontSize: 13 }}>
            Home › {details?.anime.title || 'Loading...'}
          </span>
        </div>

        {loadingDetails && <p className="muted">Loading details...</p>}
        {details && (
          <>
            <div className="plex-hero">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                <div
                  className="plex-poster"
                  style={details.anime.imageUrl ? { backgroundImage: `url(${details.anime.imageUrl})` } : undefined}
                />
                <div className="muted" style={{ fontSize: 13, background: 'var(--bg-2)', padding: '16px', borderRadius: 4, textAlign: 'center', border: '1px solid var(--bento-border)' }}>
                   On Deck — S1 · E1
                </div>
              </div>

              <div className="plex-hero-content">
                 <h1 style={{ fontSize: 48, fontWeight: 700, margin: 0, letterSpacing: '-0.5px' }}>{details.anime.title}</h1>
                 <div className="muted" style={{ fontWeight: 500, fontSize: 15, marginTop: 4 }}>2024</div>
                 <div className="muted" style={{ fontWeight: 500, fontSize: 15 }}>Animation, Adventure, and more</div>
                 <div className="row gap-sm align-center muted" style={{ fontSize: 13, marginTop: 8 }}>
                    <span style={{ padding: '2px 6px' }}>TV-MA</span>
                    <span style={{ border: '1px solid var(--bento-border)', padding: '2px 4px', borderRadius: 4 }}>1080p</span>
                    <span>⭐⭐⭐⭐⭐</span>
                 </div>
                 
                 <div className="plex-play-row" style={{ marginTop: 24, marginBottom: 24 }}>
                    <button className="primary-btn" onClick={() => { if(details.episodes.length) onPlayEpisode(details.anime.id, details.anime.title, details.episodes[0]) }} style={{ padding: '12px 32px', fontSize: 16 }}>
                       ▶ Play
                    </button>
                    {/* Watch Together: create a new SyncPlay room for this anime */}
                    <button
                      onClick={() => {
                        if (!details.episodes.length) return;
                        onWatchTogether(details.anime.id, details.anime.title, details.episodes[0], { type: 'create' });
                      }}
                      style={{
                        padding: '12px 20px', fontSize: 15, display: 'flex', alignItems: 'center', gap: 8,
                        background: 'rgba(16,201,150,0.1)', border: '1px solid rgba(16,201,150,0.35)',
                        color: 'var(--accent)', borderRadius: 10, cursor: 'pointer',
                      }}
                      title="Create a SyncPlay room and watch together with friends"
                    >
                      <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>
                      Watch Together
                    </button>
                    {pendingSync?.type === 'join' && (
                      <button
                        onClick={() => {
                          if (!details.episodes.length) return;
                          onWatchTogether(details.anime.id, details.anime.title, details.episodes[0], pendingSync);
                        }}
                        style={{
                          padding: '12px 20px', fontSize: 15, display: 'flex', alignItems: 'center', gap: 8,
                          background: 'rgba(59,130,246,0.12)', border: '1px solid rgba(59,130,246,0.35)',
                          color: '#60a5fa', borderRadius: 10, cursor: 'pointer',
                        }}
                        title={`Join room ${pendingSync.code} and watch`}
                      >
                        <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M17 12h-5v5h5v-5zM16 1v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2h-1V1h-2zm3 18H5V8h14v11z"/></svg>
                        Join Room {pendingSync.code}
                      </button>
                    )}
                    <button className="ghost-btn" title="Add to List" style={{ outline: '2px solid rgba(255,255,255,0.1)' }}>♥</button>
                    <button className="ghost-btn" title="Mark as Watched" style={{ outline: '2px solid rgba(255,255,255,0.1)' }}>✓</button>
                    <button className="ghost-btn" title="Download" style={{ outline: '2px solid rgba(255,255,255,0.1)' }}>⬇</button>
                    <button className="ghost-btn" title="Share" style={{ outline: '2px solid rgba(255,255,255,0.1)' }}>↗</button>
                 </div>
                 <p className="synopsis-copy" style={{ maxWidth: 800, fontSize: 16, lineHeight: 1.6 }}>{details.anime.synopsis}</p>
              </div>
            </div>

            <div style={{ marginTop: 64 }}>
              <h3 style={{ marginBottom: 24, fontSize: 22, fontWeight: 600 }}>Episodes</h3>
              <div className="episode-plex-list" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: '20px', maxHeight: 'none', overflow: 'visible' }}>
                {details.episodes.map(ep => (
                  <div className="plex-card-wrap" key={ep.id} onClick={() => onPlayEpisode(details.anime.id, details.anime.title, ep)}>
                    <div className="plex-card" style={{ aspectRatio: '16/9', backgroundImage: `url(${details.anime.imageUrl})`, borderRadius: 8 }}>
                       <div className="plex-card-badge">E{ep.number}</div>
                    </div>
                    <div className="plex-card-title">{ep.title || `Episode ${ep.number}`}</div>
                    <div className="plex-card-subtitle">{ep.duration || '24m'}</div>
                  </div>
                ))}
              </div>
            </div>
            
            {cast.length > 0 && (
              <div style={{ marginTop: 64 }}>
                <h3 style={{ marginBottom: 24, fontSize: 22, fontWeight: 600 }}>Cast & Crew</h3>
                <div style={{ display: 'flex', gap: 24, overflowX: 'auto', paddingBottom: 16 }}>
                  {cast.map((member, i) => (
                    <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', minWidth: 120, maxWidth: 140 }}>
                      <div style={{
                        width: 120, height: 120, borderRadius: '50%',
                        overflow: 'hidden',
                        border: '2px solid var(--bento-border)',
                        flexShrink: 0,
                        background: 'var(--bg-2)',
                        marginBottom: 12,
                      }}>
                        {member.image ? (
                          <img
                            src={member.image}
                            alt={member.name}
                            style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
                            referrerPolicy="no-referrer"
                          />
                        ) : null}
                      </div>
                      <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)', textAlign: 'center', lineHeight: 1.3 }}>{member.name}</span>
                      <span style={{ fontSize: 12, color: 'var(--muted)', textAlign: 'center', marginTop: 4, lineHeight: 1.3 }}>{member.role} (voice)</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </div>
    );
  }

  return (
    <div className="library-modern">
      <div className="row split gap-md" style={{ marginBottom: 24 }}>
        <h2 style={{ fontSize: 24, fontWeight: 700 }}>Discover Anime</h2>
        <input
          className="search-input"
          style={{ maxWidth: 300 }}
          placeholder="Search anime..."
          value={query}
          onChange={e => setQuery(e.target.value)}
        />
      </div>
      {loadingShows ? <p className="muted">Loading shows...</p> : null}
      {error ? <p className="error">{error}</p> : null}

      <div className="plex-grid">
        {filtered.map(show => {
          const cover = show.cover_image_url || '';
          return (
            <div 
              key={show.id}
              className="plex-card-wrap"
              onClick={() => onSelectShow(show.id)}
            >
              <div 
                className="plex-card"
                style={{ 
                  backgroundImage: `url(${cover})`
                }}
              >
                <div className="plex-card-badge">
                  {show.episode_count || '12'}
                </div>
              </div>
              <div className="plex-card-title">{show.title}</div>
              <div className="plex-card-subtitle">{show.episode_count ? `${show.episode_count} Episodes` : '1 Season'}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
