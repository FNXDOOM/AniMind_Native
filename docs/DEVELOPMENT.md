# Development Guide

Complete developer guide for building, debugging, and extending the Animind Desktop Player.

## Table of Contents
1. [Development Setup](#development-setup)
2. [Project Structure](#project-structure)
3. [Running Development Mode](#running-development-mode)
4. [Building & Packaging](#building--packaging)
5. [Debugging](#debugging)
6. [Adding Features](#adding-features)
7. [Testing](#testing)
8. [Performance Optimization](#performance-optimization)
9. [Contributing](#contributing)

## Development Setup

### Prerequisites
- Node.js 18+ (recommend using NVM)
- npm 9+
- Git
- Code editor (VS Code recommended)
- Backend running on http://localhost:3000

### Initial Setup

```bash
# Clone repository
git clone <repo-url>
cd animind-desktop-player

# Install dependencies
npm install

# Create environment file
cp .env.example .env.local

# Edit .env.local with local URLs
# ANIMIND_BACKEND_URL=http://localhost:3000
# etc.
```

### IDE Setup (VS Code)

**Recommended Extensions:**
- ESLint
- Prettier Code Formatter
- TypeScript Vue Plugin
- Electron Tools
- React Developer Tools

**Settings (`.vscode/settings.json`):**
```json
{
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "editor.formatOnSave": true,
  "files.exclude": {
    "**/node_modules": true,
    "**/dist": true
  }
}
```

## Project Structure

```
animind-desktop-player/
â”‚
â”œâ”€â”€ src/
â”‚   â”œâ”€â”€ main/                              # Electron main process
â”‚   â”‚   â””â”€â”€ index.ts                       # App initialization, window mgmt, IPC
â”‚   â”‚
â”‚   â””â”€â”€ renderer/
â”‚       â””â”€â”€ src/
â”‚           â”œâ”€â”€ pages/                     # Full-page components
â”‚           â”‚   â”œâ”€â”€ LibraryPage.tsx        # Anime grid + details
â”‚           â”‚   â”œâ”€â”€ PlayerPage.tsx         # Video + controls
â”‚           â”‚   â”œâ”€â”€ LoginPage.tsx          # Auth form
â”‚           â”‚   â”œâ”€â”€ SettingsPage.tsx       # App settings
â”‚           â”‚   â””â”€â”€ FirstRunSetupPage.tsx  # Onboarding wizard
â”‚           â”‚
â”‚           â”œâ”€â”€ components/                # Reusable UI components
â”‚           â”‚   â”œâ”€â”€ Layout.tsx             # App shell wrapper
â”‚           â”‚   â”œâ”€â”€ ErrorBoundary.tsx      # Error handling
â”‚           â”‚   â””â”€â”€ others...
â”‚           â”‚
â”‚           â”œâ”€â”€ hooks/                     # Custom React hooks
â”‚           â”‚   â””â”€â”€ useLibrary.ts          # Library data fetching
â”‚           â”‚
â”‚           â”œâ”€â”€ services/                  # API communication
â”‚           â”‚   â”œâ”€â”€ authService.ts         # Auth endpoints
â”‚           â”‚   â”œâ”€â”€ anilistService.ts      # AniList integration
â”‚           â”‚   â”œâ”€â”€ dbService.ts           # Database queries
â”‚           â”‚   â””â”€â”€ supabase.ts            # Supabase client setup
â”‚           â”‚
â”‚           â”œâ”€â”€ App.tsx                    # Router + main layout
â”‚           â”œâ”€â”€ types.ts                   # TypeScript interfaces
â”‚           â”œâ”€â”€ styles.css                 # Global theme + components
â”‚           â””â”€â”€ api.ts                     # Electron IPC bridge
â”‚
â”œâ”€â”€ electron.vite.config.ts                # Vite + Electron config
â”œâ”€â”€ tsconfig.json                          # TypeScript configuration
â”œâ”€â”€ package.json                           # Dependencies, scripts
â”œâ”€â”€ README.md                              # Project overview
â”œâ”€â”€ USAGE.md                               # End-user guide
â”œâ”€â”€ INSTALLATION.md                        # Setup instructions
â”œâ”€â”€ ARCHITECTURE.md                        # Technical design
â””â”€â”€ .env.example                           # Environment template
```

### Key Files Explained

| File | Purpose |
|------|---------|
| `src/main/index.ts` | Electron main process - creates window, handles lifecycle, IPC |
| `src/renderer/src/App.tsx` | Root React component - routing, state management |
| `src/renderer/src/pages/PlayerPage.tsx` | Video player UI with all controls |
| `src/renderer/src/pages/LibraryPage.tsx` | Anime discovery grid and details |
| `src/renderer/src/api.ts` | Electron â†” React bridge (IPC) |
| `src/renderer/src/types.ts` | Shared TypeScript types |
| `electron.vite.config.ts` | Build configuration |

## Running Development Mode

### Start Development Server

```bash
npm run dev
```

**What happens:**
1. Electron app launches with dev tools enabled
2. Vite dev server starts on background
3. Hot Module Reload (HMR) enabled
4. React components auto-refresh on save
5. Source maps generated for debugging

**First app window opens automatically.** Close it to stop development mode.

### Available During Development

- **Live reload** - Save React file â†’ app updates instantly
- **Dev tools** - `Ctrl+Shift+I` opens Chrome DevTools
- **Console** - `F12` opens browser console
- **React DevTools** - Inspect React components
- **Network tab** - Monitor API calls

### Troubleshooting Dev Mode

**App crashes on startup:**
```bash
# Clear dev cache and rebuild
rm -rf dist/ node_modules/.vite
npm run dev
```

**Hot reload stops working:**
```bash
# Stop and restart dev server
npm run dev
```

**Port conflict (Vite already in use):**
```bash
# Kill process on port 5173
lsof -ti:5173 | xargs kill -9  # macOS/Linux

# Edit electron.vite.config.ts to use different port
```

## Building & Packaging

### Development Build

```bash
npm run build
```

**Output:**
- Main process bundle: `dist/main/index.js`
- Renderer bundle: `dist/renderer/index.html` + JS/CSS

### Production Installers

```bash
npm run dist
```

**Creates installers in `release/` folder:**
- **Windows**: `Animind Desktop Setup 0.1.0.exe` (NSIS installer)
- **macOS**: `Animind Desktop 0.1.0.dmg` (Disk image)
- **Linux**: `.AppImage` or `.deb` (depending on config)

### Build Optimization

**For faster builds:**
```bash
# Skip minification (dev-like build)
npm run build

# Rebuild clean
rm -rf dist/
npm run build
```

**Build analysis:**
```bash
# Check bundle sizes
npm run build -- --report
```

## Debugging

### Enable Debug Mode

**In code:**
```typescript
// Add debug statements
console.log('PlayerPage mounted', { episode, streamUrl });

// Or use conditional logging
if (process.env.DEBUG === 'true') {
  console.debug('Button clicked:', action);
}
```

**Via environment:**
```bash
DEBUG=true npm run dev
```

### DevTools Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+I` | Toggle DevTools (same as browser) |
| `F12` | Toggle console |
| `Ctrl+Shift+C` | Inspect element |
| `Ctrl+Shift+J` | Show console |

### Debugging React Components

1. **Open DevTools** (`Ctrl+Shift+I`)
2. **Go to Elements/Sources tab**
3. **Find component** in React DevTools (Components tab)
4. **Click component** to highlight in DOM
5. **Check props** and state in right panel
6. **Add breakpoints** in Sources tab

### Debugging IPC (Electron â†” React Communication)

```typescript
// Add logging to IPC handlers (main process)
ipcMain.handle('get-stream-ticket', async (event, episodeId) => {
  console.log('[IPC] get-stream-ticket', episodeId);
  const result = await getStreamTicket(episodeId);
  console.log('[IPC] response:', result);
  return result;
});

// Add logging to IPC calls (renderer)
const result = await desktopApi.getStreamTicket(episode.id);
console.log('Stream ticket received:', result);
```

### Network Debugging

1. **DevTools** â†’ **Network tab**
2. **Watch API calls** to backend
3. **Check response status** (200 = OK, 4xx = client error, 5xx = server error)
4. **Inspect response** body for errors
5. **Check timing** for performance issues

### Common Debug Scenarios

**"Video won't play":**
```typescript
// Check stream ticket
console.log('Stream info:', streamInfo);
console.log('Stream URL:', streamUrl);

// Check Network tab for /api/episodes/.../stream calls
```

**"Settings menu not closing":**
```typescript
// Check state
console.log('Settings open?', settingsMenuOpen);
console.log('Clicked element:', event.target);

// Verify click handler is attached
```

**"Progress not saving":**
```typescript
// Check save calls
console.log('Saving progress', { animeId, episodeIndex, seconds });

// Monitor API calls in Network tab
// POST /api/progress
```

## Adding Features

### Adding a New Player Control Button

**1. Add SVG icon function in `PlayerPage.tsx`:**
```typescript
function MyNewIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className={className}>
      <path fill="currentColor" d="M..." />
    </svg>
  );
}
```

**2. Add to renders with handler:**
```typescript
<button 
  className="ghost-btn yt-btn" 
  onClick={() => handleMyAction()}
  title="My action"
  aria-label="My action"
>
  <MyNewIcon className="control-icon" />
</button>
```

**3. Add handler in component:**
```typescript
const handleMyAction = useCallback(() => {
  console.log('My action triggered');
  // Your logic here
}, [dependencies]);
```

### Adding a New Settings Tab

**1. Update settings state type in `PlayerPage.tsx`:**
```typescript
const [settingsTab, setSettingsTab] = useState<
  'main' | 'playback' | 'audio' | 'subtitles' | 'mynew'
>('main');
```

**2. Add menu option in main settings:**
```typescript
{settingsTab === 'main' ? (
  <div className="settings-option-list">
    {/* existing options... */}
    <button 
      className="settings-option row split" 
      onClick={() => setSettingsTab('mynew')}
    >
      <span>My New Setting</span>
      <span>Current value</span>
    </button>
  </div>
) : null}
```

**3. Add tab content:**
```typescript
{settingsTab === 'mynew' ? (
  <div className="settings-option-list">
    {/* Your options here */}
  </div>
) : null}
```

### Adding a New API Endpoint Call

**1. In `App.tsx`, add state and handler:**
```typescript
const [myData, setMyData] = useState(null);

const fetchMyData = useCallback(async () => {
  try {
    const result = await desktopApi.callMyEndpoint(params);
    setMyData(result);
  } catch (err) {
    console.error('Error:', err);
  }
}, []);
```

**2. Pass to component:**
```typescript
<PlayerPage
  {...otherProps}
  myData={myData}
  onFetchMyData={fetchMyData}
/>
```

## Testing

### Type Checking

```bash
# Check TypeScript types (no compilation)
npm run typecheck

# Fix issues before committing
```

### Manual Testing Checklist

**Playback:**
- [ ] Video loads and plays
- [ ] Audio tracks switchable
- [ ] Subtitles toggle on/off
- [ ] Playback speed changeable
- [ ] Progress saves and resumes
- [ ] Keyboard shortcuts work

**Controls:**
- [ ] Play/pause button works
- [ ] Seek bar draggable
- [ ] Volume slider works
- [ ] Mute button toggles
- [ ] Settings menu opens/closes
- [ ] Fullscreen toggles

**UI:**
- [ ] Responsive to window resize
- [ ] Controls fade on inactivity
- [ ] No visual glitches
- [ ] Smooth animations
- [ ] Text readable in all states

## Performance Optimization

### Analyzing Performance

```bash
# Profile build
npm run build -- --profile

# Check bundle size
npm run build -- --report
```

### Common Optimizations

**Memoization for expensive renders:**
```typescript
const expensiveValue = useMemo(() => {
  return calculateExpensive(dep1, dep2);
}, [dep1, dep2]);

const handleClick = useCallback(() => {
  // expensive operation
}, [dependencies]);
```

**Lazy load components:**
```typescript
const SettingsPage = React.lazy(() => import('./pages/SettingsPage'));

// Use with Suspense:
<Suspense fallback={<div>Loading...</div>}>
  <SettingsPage />
</Suspense>
```

**Debounce API calls:**
```typescript
const debouncedSearch = useMemo(
  () => debounce((query: string) => {
    fetchResults(query);
  }, 300),
  []
);
```

## Contributing

### Code Style

- **TypeScript** - Strict mode enabled
- **React** - Functional components + hooks
- **Naming** - camelCase for variables/functions, PascalCase for components
- **Comments** - Add comments for complex logic
- **Formatting** - Use Prettier (auto on save)

### Before Committing

```bash
# 1. Type check
npm run typecheck

# 2. Build to ensure no errors
npm run build

# 3. Test key features manually

# 4. Commit with clear message
git commit -m "feat: add playback speed control"
```

### Commit Message Format

```
feat: add new feature
fix: fix bug
docs: update documentation
style: code style changes (formatting)
refactor: code refactoring
perf: performance improvements
test: add/update tests
chore: maintenance tasks
```

### Pull Request Process

1. Fork repository
2. Create feature branch: `git checkout -b feat/my-feature`
3. Make changes and test thoroughly
4. Type check: `npm run typecheck`
5. Build: `npm run build`
6. Commit with clear messages
7. Push: `git push origin feat/my-feature`
8. Open PR with description of changes
9. Address review feedback
10. Merge when approved

## Useful References

- **Electron Docs**: https://www.electronjs.org/docs
- **React Docs**: https://react.dev
- **TypeScript Handbook**: https://www.typescriptlang.org/docs/
- **Vite Guide**: https://vitejs.dev/guide/
- **MDN Web Docs**: https://developer.mozilla.org/

---

**Questions?** Feel free to open an issue or ask in discussions.

**Happy coding!** ðŸ’»âœ¨

