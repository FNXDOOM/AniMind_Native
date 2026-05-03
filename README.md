# Animind Desktop Player

A modern desktop anime streaming player built with Electron, React, and TypeScript.

![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue.svg)

## Features

### Modern UI/UX
- Netflix-inspired library browsing
- YouTube-style player controls
- Cinematic dark theme
- Responsive desktop layout

### Playback
- Multiple audio tracks
- Subtitles (VTT/SRT)
- Playback speed control
- Progress tracking and resume
- External player fallback

### Controls
- Keyboard shortcuts for play/pause, seek, fullscreen, mute
- Auto-hide controls overlay
- Fullscreen mode
- Volume slider + mute toggle

## Quick Start

### Prerequisites
- Node.js 18+
- npm
- Animind backend running

### Installation

```bash
git clone <repo-url>
cd animind-desktop-player
npm install
```

### Development

```bash
npm run dev
```

### Build

```bash
npm run build
npm run dist
```

## Documentation

- [docs/INSTALLATION.md](./docs/INSTALLATION.md)
- [docs/USAGE.md](./docs/USAGE.md)
- [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)
- [docs/CLERK_ELECTRON_SETUP.md](./docs/CLERK_ELECTRON_SETUP.md)

## Playback Architecture (Current)

- Stable playback path: embedded native MPV (`libmpv`) in the app window
- HTML5 and external MPV playback paths are disabled in this build
- Renderer talks only through preload bridge (`contextIsolation: true`, `nodeIntegration: false`)

## Plex-Style Direction (Electron 41)

Target architecture:

- Single Electron app window
- React/Electron UI for controls and overlays
- Native `libmpv` playback engine under the hood
- Event/command bridge through main + preload IPC

Important clarifications:

- Deprecated Pepper/PPAPI `mpv.js` is not used
- End-state is not a separate external MPV window
- End-state is true in-window native playback on Electron 41

Spike plan:

- [docs/libmpv-electron41-modern-spike-plan.md](./docs/libmpv-electron41-modern-spike-plan.md)

## Technology Stack

- Frontend: React 19, TypeScript, Vite
- Desktop: Electron 41 with electron-vite
- Backend: Animind Backend (Express.js)
- Database: Supabase PostgreSQL
- Build: Electron Builder (Windows NSIS, macOS DMG)

## Project Structure

```text
animind-desktop-player/
├── src/
│   ├── main/                    # Electron main process
│   ├── preload/                 # Safe renderer bridge
│   └── renderer/                # React app
├── docs/
├── electron.vite.config.ts
├── package.json
└── README.md
```

## Security

- HTTPS API calls
- Secure auth/session handling in main process
- No renderer Node access

## Contributing

1. Fork the repository
2. Create a branch
3. Commit changes
4. Push and open a pull request

## License

MIT
