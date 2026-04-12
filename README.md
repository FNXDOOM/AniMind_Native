# Animind Desktop Player

A modern, high-performance native desktop anime streaming player built with Electron, React, and TypeScript. Experience Netflix-like interface with YouTube-style player controls for seamless anime playback.

![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue.svg)

## ✨ Features

### Modern UI/UX
- **Netflix-inspired library** - Card grid layout with hero detail panel for anime discovery
- **YouTube-style player controls** - Compact, icon-based transport controls with SVG icons
- **Dark cinematic theme** - Optimized for late-night viewing with smooth red accent (#e50914)
- **Responsive design** - Adapts beautifully to different window sizes and resolutions

### Advanced Playback
- **Multiple audio tracks** - Seamlessly switch between dubbed and original language audio
- **Subtitle support** - Load and toggle subtitles with customizable rendering
- **Playback speed control** - Watch at your preferred pace (0.75x - 2x)
- **Native video rendering** - Direct file streaming for desktop without browser overhead
- **Buffered progress visualization** - See how much content has been downloaded/buffered

### Player Controls
- **Keyboard shortcuts** - Space/K (play/pause), Arrow keys (seek ±10s), F (fullscreen), M (mute), Esc (menu close)
- **Auto-hide controls** - Overlay fades after 2 seconds of inactivity during playback
- **Fullscreen mode** - Double-click video or click fullscreen button
- **External player fallback** - Open video in your preferred player (MPV, VLC, etc.)
- **Volume control** - Slider with mute toggle

### Content Management
- **Episode library** - Browse all episodes with play buttons
- **Progress tracking** - Resume from where you left off
- **Cloud integration** - Supabase-backed sync for your watchlist and progress
- **Multi-language support** - Audio and subtitle selection per episode

## 🚀 Quick Start

### Prerequisites
- Node.js 18+ 
- npm or yarn
- Backend server running (Animind Backend)
- Supabase account and credentials

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd animind-desktop-player

# Install dependencies
npm install

# Configure environment variables
cp .env.example .env.local
# Edit .env.local with your backend URL and Supabase credentials
```

### Development
```bash
npm run dev
```

### Production Build
```bash
npm run build       # Build production bundles
npm run dist        # Package into installers (Windows NSIS, macOS DMG)
```

## 📖 Documentation

Full documentation is available in the [docs/](./docs/) folder:

| Document | Purpose |
|----------|---------|
| [docs/INSTALLATION.md](./docs/INSTALLATION.md) | Detailed setup, configuration, and troubleshooting |
| [docs/USAGE.md](./docs/USAGE.md) | Complete player usage guide and feature walkthrough |
| [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) | Development workflow, building, debugging, testing |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | Technical design, component structure, data flow |

## 🎮 Player Hotkeys

| Key | Action |
|-----|--------|
| **Space** / **K** | Play / Pause |
| **→** | Seek forward 10 seconds |
| **←** | Seek backward 10 seconds |
| **F** | Fullscreen toggle |
| **M** | Mute toggle |
| **Esc** | Close settings menu |
| **Mouse wheel** | Volume control (when cursor over player) |
| **Double-click** | Fullscreen toggle |

## 🏗️ Technology Stack

- **Frontend**: React 18, TypeScript, Vite
- **Desktop**: Electron 37 with electron-vite
- **Styling**: Custom CSS with CSS variables for theming
- **Backend**: Animind Backend (Express.js)
- **Database**: Supabase PostgreSQL
- **Video**: HTML5 `<video>` element with optional MPV fallback
- **Package Manager**: npm
- **Build**: Electron Builder (Windows NSIS, macOS DMG)

## 📁 Project Structure

```
animind-desktop-player/
├── src/
│   ├── main/                    # Electron main process
│   │   └── index.ts             # Window creation, app lifecycle
│   └── renderer/
│       └── src/
│           ├── pages/           # Page components
│           │   ├── LibraryPage.tsx    # Anime discovery & episodes
│           │   ├── PlayerPage.tsx     # Video player with controls
│           │   ├── LoginPage.tsx      # Authentication
│           │   └── SettingsPage.tsx   # Configuration
│           ├── components/      # Reusable UI components
│           ├── hooks/           # Custom React hooks
│           ├── services/        # API communication
│           ├── App.tsx          # Application shell & routing
│           ├── types.ts         # TypeScript type definitions
│           └── styles.css       # Global theme & component styles
├── electron.vite.config.ts      # Electron + Vite configuration
├── tsconfig.json                # TypeScript configuration
├── package.json                 # Dependencies and scripts
└── .env.example                 # Configuration template
```

## 🎨 Design System

### Color Palette
- **Background**: `#070707` (--bg-0), `#111111` (--bg-1), `#181818` (--bg-2)
- **Accent**: `#e50914` (Netflix red), `#ff3340` (bright red)
- **Text**: `#f5f5f5` (primary), `#a0a0a0` (muted)
- **Border**: `rgba(255, 255, 255, 0.12)`

### Typography
- **Brand**: Bebas Neue (uppercase titles)
- **Body**: Manrope (UI text)
- **Monospace**: System font (code/debug)

## 🔐 Security & Privacy

- **Local playback**: Video streams never leave your machine (native playback)
- **Auth tokens**: Stored securely via Electron's secure storage
- **API integration**: All requests use HTTPS to Supabase
- **No telemetry**: No tracking or analytics enabled by default

## 🐛 Troubleshooting

### Common Issues

**Subtitles not showing?**
- Enable subtitles in Settings menu (Subtitles tab)
- Check subtitle file format (VTT, SRT supported)
- Verify subtitle language is correctly detected

**Video won't play?**
- Verify backend server is running
- Check backend URL in `.env.local`
- Try opening in external player (Settings → Pop-out)

**Audio track switching issues?**
- Restart the episode
- Check available audio tracks in Settings → Audio Track
- Verify backend audio transcoding service is running

**Freezing or stuttering?**
- Check system CPU/memory usage
- Reduce playback speed or lower video quality
- Disable desktop effects (Windows/macOS)

See [docs/INSTALLATION.md](./docs/INSTALLATION.md#troubleshooting) for more solutions.

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Inspired by Netflix and YouTube player designs
- Built on top of Electron ecosystem
- Backend powered by Animind Server infrastructure
- Supabase for database and auth services

## 📧 Support

For issues, feature requests, or questions:
- Open an issue on GitHub
- Check existing documentation in [docs/](./docs/) folder
- Review [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) for debugging tips

---

**Happy streaming!** 🎬✨
