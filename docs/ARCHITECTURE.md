# Architecture & Design

Technical architecture guide for the Animind Desktop Player.

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Component Hierarchy](#component-hierarchy)
3. [Data Flow](#data-flow)
4. [State Management](#state-management)
5. [API Design](#api-design)
6. [Styling System](#styling-system)
7. [Performance Considerations](#performance-considerations)

## System Architecture

### High-Level Overview

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                    ANIMIND DESKTOP PLAYER                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                                                â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”    â”‚
â”‚  â”‚  Electron Main Process (src/main/index.ts)           â”‚    â”‚ Desktop Integration
â”‚  â”‚  - Window management                                 â”‚    â”‚ (File system, OS APIs)
â”‚  â”‚  - IPC bridge to renderer                            â”‚    â”‚
â”‚  â”‚  - App lifecycle (init, close, quit)                 â”‚    â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜    â”‚
â”‚                      â”‚ IPC Channels                           â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”    â”‚
â”‚  â”‚  Electron Renderer (src/renderer/src/)               â”‚    â”‚ React UI
â”‚  â”‚                                                       â”‚    â”‚
â”‚  â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”‚    â”‚
â”‚  â”‚  â”‚  React App (App.tsx)                           â”‚  â”‚    â”‚
â”‚  â”‚  â”‚  - Routing (Library / Player / Settings)       â”‚  â”‚    â”‚
â”‚  â”‚  â”‚  - Session management                         â”‚  â”‚    â”‚
â”‚  â”‚  â”‚  - Global state                               â”‚  â”‚    â”‚
â”‚  â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â”‚    â”‚
â”‚  â”‚          â†“                â†“              â†“            â”‚    â”‚
â”‚  â”‚      LibraryPage   PlayerPage   SettingsPage         â”‚    â”‚
â”‚  â”‚                                                       â”‚    â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜    â”‚
â”‚                      â”‚ HTTP/HTTPS API Calls                  â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”    â”‚
â”‚  â”‚  API Layer (services/*.ts)                           â”‚    â”‚ Backend APIs
â”‚  â”‚  - supabase.ts (Auth, DB)                            â”‚    â”‚
â”‚  â”‚  - authService.ts (Login/Logout)                     â”‚    â”‚
â”‚  â”‚  - dbService.ts (Show/Episode data)                  â”‚    â”‚
â”‚  â”‚  - anilistService.ts (AniList sync)                  â”‚    â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜    â”‚
â”‚                                                                â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
         â”‚                              â”‚
         â”‚ HTTPS                        â”‚ HTTP(S)
         â†“                              â†“
    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”           â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
    â”‚  Supabase   â”‚           â”‚ Animind Backend  â”‚
    â”‚  (Auth/DB)  â”‚           â”‚ (Stream service) â”‚
    â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜           â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
         â”‚                              â”‚
         â†“                              â†“
    â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”           â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
    â”‚ PostgreSQL  â”‚           â”‚ Video Storage    â”‚
    â”‚  Database   â”‚           â”‚ (Local/S3)       â”‚
    â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜           â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Technology Stack by Layer

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Desktop Shell** | Electron 37 | Native OS integration + window management |
| **UI Framework** | React 18 + TypeScript | Component-based UI with static typing |
| **Build Tool** | Vite 6 + electron-vite | Fast dev server + optimized production bundles |
| **Video Playback** | HTML5 `<video>` + MPV | Native video rendering with codec support |
| **Authentication** | Supabase Auth | OAuth + email/password with JWT tokens |
| **Database** | Supabase PostgreSQL | User data, watchlist, progress tracking |
| **Backend** | Express.js + Node.js | Stream serving, audio transcoding, metadata |
| **Styling** | CSS variables + Flexbox/Grid | Netflix-inspired dark theme |

## Component Hierarchy

### Page Structure

```
App (src/App.tsx)
â”œâ”€â”€ App Shell
â”‚   â”œâ”€â”€ Header (Brand + Navigation)
â”‚   â””â”€â”€ Main Content Router
â”‚       â”œâ”€â”€ LibraryPage
â”‚       â”‚   â”œâ”€â”€ Sidebar (Show List)
â”‚       â”‚   â””â”€â”€ Content (Card Grid + Hero Detail)
â”‚       â”‚       â”œâ”€â”€ Library Card Grid
â”‚       â”‚       â”‚   â””â”€â”€ Library Card Ã— N
â”‚       â”‚       â””â”€â”€ Hero Detail Panel
â”‚       â”‚           â”œâ”€â”€ Poster Image
â”‚       â”‚           â”œâ”€â”€ Title + Synopsis
â”‚       â”‚           â”œâ”€â”€ Action Buttons
â”‚       â”‚           â””â”€â”€ Episodes Block
â”‚       â”‚               â””â”€â”€ Episode Row Ã— N
â”‚       â”‚
â”‚       â”œâ”€â”€ PlayerPage
â”‚       â”‚   â”œâ”€â”€ Video Shell
â”‚       â”‚   â”‚   â”œâ”€â”€ <video> Element
â”‚       â”‚   â”‚   â”œâ”€â”€ Center Play Button
â”‚       â”‚   â”‚   â””â”€â”€ Overlay
â”‚       â”‚   â”‚       â”œâ”€â”€ Top Bar
â”‚       â”‚   â”‚       â””â”€â”€ Bottom Bar
â”‚       â”‚   â”‚           â”œâ”€â”€ Progress Bar
â”‚       â”‚   â”‚           â”œâ”€â”€ Transport Controls
â”‚       â”‚   â”‚           â””â”€â”€ Right Controls (Volume, Settings, etc.)
â”‚       â”‚   â””â”€â”€ Settings Menu (Floating)
â”‚       â”‚       â”œâ”€â”€ Main Menu
â”‚       â”‚       â”œâ”€â”€ Playback Speed Tab
â”‚       â”‚       â”œâ”€â”€ Audio Track Tab
â”‚       â”‚       â””â”€â”€ Subtitles Tab
â”‚       â”‚
â”‚       â””â”€â”€ SettingsPage
â”‚           â””â”€â”€ Configuration Form
â”‚
â””â”€â”€ Error Boundary (Global error handler)
```

### Reusable Components

Located in `src/renderer/src/components/`:

```
components/
â”œâ”€â”€ Layout.tsx           # Page wrapper with grid layout
â”œâ”€â”€ ErrorBoundary.tsx    # Error catching + fallback UI
â”œâ”€â”€ ConfirmationModal.tsx # Confirmation dialogs
â”œâ”€â”€ AnimeCard.tsx        # Reusable card component
â”œâ”€â”€ VideoModal.tsx       # Video embed component
â””â”€â”€ others...
```

## Data Flow

### LibraryPage Data Flow

```
User Opens App
    â†“
App.tsx initializes
    â†“
useLibrary() hook called
    â†“
desktopApi.getShows()  â† IPC call to electron
    â†“
Backend API /api/shows â† HTTP to backend
    â†“
DatabaseService queries Supabase
    â†“
Shows data returned â†’ setShows()
    â†“
LibraryPage renders with show cards
    â†“
User clicks card â†’ onSelectShow()
    â†“
loadShowDetails(showId) called
    â†“
desktopApi.getShowDetails() â† Fetch episodes
    â†“
Hero detail panel updates with episodes list
```

### PlayerPage Data Flow

```
User clicks episode to play
    â†“
startEpisode() in App.tsx
    â†“
setView('player') + episode state updated
    â†“
PlayerPage component mounted
    â†“
desktopApi.getStreamTicket(episodeId) â† Get playback URL + metadata
    â†“
Backend returns { url, clientType, hlsRequired, message }
    â†“
Promise.all fetches subtitles & audio tracks in parallel
    â†“
setStreamUrl(url) â†’ <video src> updated
    â†“
<video> element starts playing
    â†“
User interactions trigger:
    - onTimeUpdate() â†’ save progress
    - onSelectAudioTrack() â†’ switch audio (reload stream)
    - onSelectSubtitle() â†’ load new subtitle track
```

### Stream Ticket System

```
Player requests stream:
    "playing Episode 3, need stream URL"
    â†“
desktopApi.getStreamTicket(episode.id, audioTrack)
    â†“
Backend endpoint: POST /api/episodes/:id/stream-ticket
    â†“
Detect client type (native vs browser)
    â†“
If native:
    - Create ticket with cm='n'
    - Return direct file path (no transcode)
    â†“
If browser:
    - Create ticket with cm='b'
    - If audio track selected, queue audio variant build
    - Return presigned URL or /api/episodes/:id/stream endpoint
    â†“
Return { url, expiresIn, clientType, message }
    â†“
<video src="{url}?st={ticket}"> loads video
    â†“
Backend verifies ticket signature + expiration
    â†“
Video streams with appropriate handling (redirect vs proxy)
```

## State Management

### React Hooks Pattern

The app uses React hooks for state (no Redux/Context API for simplicity):

**App.tsx - Global State**
```typescript
// Session & Auth
const [session, setSession] = useState<SessionInfo | null>(null);
const [authError, setAuthError] = useState('');

// Navigation
const [view, setView] = useState<View>('library');

// Current playback
const [currentAnimeId, setCurrentAnimeId] = useState<string | null>(null);
const [currentEpisode, setCurrentEpisode] = useState<Episode | null>(null);
const [streamUrl, setStreamUrl] = useState('');
const [audioTracks, setAudioTracks] = useState<AudioTrack[]>([]);
```

**PlayerPage.tsx - Player State**
```typescript
// Playback control
const [paused, setPaused] = useState(true);
const [timePos, setTimePos] = useState(0);
const [duration, setDuration] = useState(0);

// UI state
const [controlsVisible, setControlsVisible] = useState(true);
const [settingsMenuOpen, setSettingsMenuOpen] = useState(false);
const [settingsTab, setSettingsTab] = useState<'main' | 'playback' | 'audio' | 'subtitles'>('main');

// Media control state
const [volume, setVolume] = useState(85);
const [speed, setSpeed] = useState(1);
const [isMuted, setIsMuted] = useState(false);
```

**LibraryPage.tsx - Library State**
```typescript
// useLibrary() hook manages:
const { shows, selectedShow, loadingShows, loadingDetails, error, loadShowDetails } = useLibrary();
```

### Custom Hooks

**useLibrary() Hook**
```typescript
// Handles:
// - Fetching all shows
// - Loading show details + episodes
// - Error handling
// - Caching

export function useLibrary() {
  const [shows, setShows] = useState<Show[]>([]);
  const [selectedShow, setSelectedShow] = useState<Show | null>(null);
  const [loading, setLoading] = useState(false);
  // ... implementation with useEffect for data fetching
}
```

## API Design

### IPC Channels (Electron â†” React)

**File: `src/renderer/src/api.ts`**

```typescript
export const desktopApi = {
  // Auth
  signIn: (email: string, password: string) => ipcInvoke('sign-in', { email, password }),
  signOut: () => ipcInvoke('sign-out'),
  getSession: () => ipcInvoke('get-session'),
  
  // Library
  getShows: () => ipcInvoke('get-shows'),
  getShowDetails: (showId: string) => ipcInvoke('get-show-details', showId),
  
  // Playback
  getStreamTicket: (episodeId: string, audioTrackIndex?: number) => 
    ipcInvoke('get-stream-ticket', { episodeId, audioTrackIndex }),
  getAudioTracks: (episodeId: string) => ipcInvoke('get-audio-tracks', episodeId),
  getSubtitles: (episodeId: string) => ipcInvoke('get-subtitles', episodeId),
  
  // Progress
  saveProgress: (animeId: string, episodeIndex: number, seconds: number) =>
    ipcInvoke('save-progress', { animeId, episodeIndex, seconds }),
  getProgress: (animeId: string, episodeIndex: number) =>
    ipcInvoke('get-progress', { animeId, episodeIndex }),
  
  // External player
  openPlayer: (streamUrl: string, title: string) =>
    ipcInvoke('open-player', { streamUrl, title }),
};
```

### Backend API Endpoints (Express)

**Called by IPC handlers:**

```
GET  /api/shows              â†’ All anime
GET  /api/shows/:id          â†’ Anime details + episodes
GET  /api/episodes/:id       â†’ Episode details
GET  /api/episodes/:id/stream â†’ Video stream (with ticket verification)
GET  /api/episodes/:id/subtitles â†’ Subtitle tracks
GET  /api/episodes/:id/audio-tracks â†’ Audio track metadata
POST /api/episodes/:id/stream-ticket â†’ Get playback token

POST /api/progress           â†’ Save watch progress
GET  /api/progress/:id       â†’ Resume position
```

## Styling System

### CSS Architecture

**File: `src/renderer/src/styles.css`**

```css
/* 1. ROOT VARIABLES (Theme) */
:root {
  --bg-0: #070707;        /* Primary background */
  --bg-1: #111111;        /* Secondary background */
  --bg-2: #181818;        /* Tertiary background */
  --text: #f5f5f5;        /* Primary text */
  --muted: #a0a0a0;       /* Secondary text */
  --accent: #e50914;      /* Netflix red */
  --accent-2: #ff3340;    /* Bright red */
  --border: rgba(255, 255, 255, 0.12);
}

/* 2. RESET & DEFAULTS */
* { box-sizing: border-box; }
body { background: var(--bg-0); color: var(--text); font-family: 'Manrope', sans-serif; }

/* 3. LAYOUT COMPONENTS */
.app-shell { display: grid; grid-template-rows: auto 1fr; }
.app-header { background: var(--bg-1); padding: 16px; }
.app-main { background: var(--bg-0); overflow-y: auto; }

/* 4. PAGE-SPECIFIC STYLES */
.library-page { display: grid; grid-template-columns: 280px 1fr; gap: 24px; }
.library-card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 16px; }

.player-page { display: grid; gap: 16px; }
.video-shell { width: 100%; aspect-ratio: 16 / 9; background: #000; border: 1px solid var(--border); }

/* 5. COMPONENT STYLES */
.ghost-btn { background: transparent; border: none; cursor: pointer; }
.ghost-btn:hover { background: rgba(255, 255, 255, 0.1); }

/* 6. RESPONSIVE MEDIA QUERIES */
@media (max-width: 1024px) { .library-page { grid-template-columns: 1fr; } }
```

### Color System

- **Backgrounds**: `--bg-0` (darkest) â†’ `--bg-1` â†’ `--bg-2` (lighter)
- **Text**: `--text` (primary), `--muted` (secondary)
- **Accent**: Netflix red (`#e50914`) for highlights and CTAs
- **Borders**: Semi-transparent white for dividers

### Component Classes

| Class | Purpose |
|-------|---------|
| `.video-shell` | 16:9 video container |
| `.plex-overlay` | Control overlay (top + bottom bars) |
| `.ghost-btn` | Transparent button with hover effect |
| `.transport-btn` | Circular media control buttons |
| `.settings-menu` | Floating settings popup |
| `.library-card` | Anime poster card |
| `.library-card-grid` | Card container grid |

## Performance Considerations

### Optimization Techniques Used

**1. Memoization**
```typescript
// Prevent unnecessary re-renders
const selectedSubtitle = useMemo(
  () => subtitles.find(s => s.id === selectedSubtitleId) ?? null,
  [selectedSubtitleId, subtitles],
);
```

**2. useCallback for Event Handlers**
```typescript
// Stable function reference across renders
const seekBy = useCallback((seconds: number) => {
  if (!videoRef.current) return;
  videoRef.current.currentTime = Math.max(0, videoRef.current.currentTime + seconds);
  signalInteraction();
}, [signalInteraction]);
```

**3. Lazy Loading**
- Settings page only loads when settings nav clicked
- Components split by route for code splitting

**4. Asset Optimization**
- SVG icons instead of image files (smaller, scalable)
- CSS variables for theming (no style duplication)
- Minimal external dependencies

### Bundling & Loading

**Vite Dev Mode:**
- On-demand module loading
- Fast refresh (HMR) for instant updates

**Production Build:**
```
Main Process:   ~300KB (minified)
Renderer JS:    ~400KB (minified, gzipped ~120KB)
Renderer CSS:   ~80KB (minified, gzipped ~15KB)
Total Bundle:   ~780KB (before compression)
```

### Video Playback Performance

- **Native rendering**: Direct file streaming (no transcoding for native client)
- **Buffering**: Browser handles with standard HTML5 video element
- **Seeking**: O(1) direct jump (no re-encoding)
- **Audio switching**: Server-side variant pre-built for fast switch

### Memory Usage

- **Target**: <500MB during playback
- **React DevTools**: ~50MB overhead in dev mode
- **Video buffer**: ~50-100MB depending on codec/resolution
- **UI components**: ~20MB for full app state

---

**For more details, see:**
- [DEVELOPMENT.md](./DEVELOPMENT.md) for dev workflow
- [USAGE.md](./USAGE.md) for feature details
- [README.md](../README.md) for overview


