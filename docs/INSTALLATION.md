# Installation & Setup Guide

Complete guide for installing, configuring, and troubleshooting the Animind Desktop Player.

## Table of Contents
1. [System Requirements](#system-requirements)
2. [Installation Steps](#installation-steps)
3. [Configuration](#configuration)
4. [Backend Setup](#backend-setup)
5. [Development Environment](#development-environment)
6. [Troubleshooting](#troubleshooting)

## System Requirements

### Minimum
- **OS**: Windows 10 (build 19041), macOS 10.15, or Linux (Ubuntu 18.04+)
- **CPU**: Intel i5 / AMD Ryzen 5 equivalent or better
- **RAM**: 4 GB
- **Storage**: 2 GB free space
- **Internet**: Stable connection for streaming

### Recommended
- **OS**: Windows 11, macOS Ventura+, or Ubuntu 22.04+
- **CPU**: Intel i7 / AMD Ryzen 7 or better
- **RAM**: 8 GB or more
- **Storage**: SSD with 5+ GB free space
- **Connection**: 50+ Mbps for smooth 1080p streaming

### Software Requirements
- **Node.js**: v18.0.0 or higher
- **npm**: v9.0.0 or higher
- **Git**: For version control (optional)

## Installation Steps

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/animind-desktop-player.git
cd animind-desktop-player
```

### 2. Install Dependencies

```bash
npm install
```

This will install all required npm packages specified in `package.json`:
- React 19.1.1
- Electron 37.2.0
- TypeScript 5.8.3
- Vite 6.3.5
- And other development tools

Wait for installation to complete (may take 2-5 minutes).

### 3. Copy Environment Configuration

```bash
cp .env.example .env.local
```

This creates a local environment file for your credentials.

### 4. Configure Environment Variables

Edit `.env.local` with your settings:

```env
# Backend API server
ANIMIND_BACKEND_URL=http://localhost:3000

# Supabase credentials (get from https://supabase.com)
ANIMIND_SUPABASE_URL=https://your-project.supabase.co
ANIMIND_SUPABASE_ANON_KEY=your-anon-key-here

# Optional: Path to MPV executable (for external playback)
ANIMIND_MPV_PATH=mpv
```

#### Getting Supabase Credentials

1. Go to [supabase.com](https://supabase.com) and create a free account
2. Create a new project
3. Navigate to **Settings** â†’ **API**
4. Copy the project URL and Anon Key
5. Paste into `.env.local`

#### Backend URL

- **Development**: `http://localhost:3000` (if running backend locally)
- **Production**: Your deployed backend URL (e.g., `https://api.example.com`)

## Configuration

### Video Codec Support

The player supports common video formats:
- **Containers**: MP4, MKV, WebM
- **Video Codecs**: H.264, H.265, VP8, VP9, AV1
- **Audio Codecs**: AAC, MP3, Opus, Vorbis

For unsupported codecs, use Settings â†’ External Player.

### Subtitle Formats

Supported subtitle file types:
- **VTT** (WebVTT) - Recommended
- **SRT** (SubRip)

Subtitles auto-load from sidecar files:
```
Episode 01.mkv
Episode 01.vtt       â† Automatically loaded
Episode 01.srt       â† Also supported
```

### Audio Tracks

Browser-safe audio codecs are supported natively:
- AAC (default)
- MP3
- Opus
- Vorbis

Non-browser-safe codecs (FLAC, DTS) automatically transcode to AAC on first play.

## Backend Setup

### Prerequisites
- Node.js v18+ with npm
- Docker (optional, for containerized deployment)
- Supabase database

### Quick Start (Local Development)

```bash
# Navigate to backend directory
cd ../Backend/animind-backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env

# Start development server
npm run dev
```

The backend should now be running at `http://localhost:3000`.

### Docker Setup

```bash
cd ../Backend/animind-backend

# Build Docker image
docker build -t animind-backend .

# Run container
docker run -p 3000:3000 \
  -e DATABASE_URL="postgresql://..." \
  -e SUPABASE_URL="https://..." \
  animind-backend
```

See [Backend Documentation](../Backend/animind-backend/RUN.md) for detailed setup.

## Development Environment

### Running in Development Mode

```bash
npm run dev
```

This starts:
- **Electron app** with hot reload
- **Vite dev server** on background
- **React dev tools** enabled
- **Source maps** for debugging

The app window opens automatically.

### Building for Production

```bash
# Build bundles (no package)
npm run build

# Build + create installers (Windows .exe, macOS .dmg)
npm run dist
```

Installers will be created in the `release/` directory.

### Type Checking

```bash
npm run typecheck
```

Validates TypeScript types without building. Run this before commits.

## Troubleshooting

### Installation Issues

#### npm install fails with permission error
```bash
# On Linux/macOS:
sudo npm install --unsafe-perm

# Or use NVM (recommended):
nvm install 18
nvm use 18
npm install
```

#### Node modules won't install
```bash
# Clear npm cache
npm cache clean --force

# Delete node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
```

### Runtime Issues

#### "Backend URL not found" error
- **Check**: Is `.env.local` created?
- **Verify**: `ANIMIND_BACKEND_URL` is set correctly
- **Test**: `curl http://localhost:3000/health`
- **Solution**: Restart app after updating `.env.local`

#### Video won't play / "Playback failed"
- **Try**: Open in external player (Settings â†’ Pop-out)
- **Check**: Video codec support (H.264 works on all platforms)
- **Verify**: Backend is serving video correctly: `curl http://localhost:3000/api/episodes/{id}/stream`

#### "Supabase connection failed"
- **Check**: Internet connection
- **Verify**: `ANIMIND_SUPABASE_URL` is correct format (should start with `https://`)
- **Test**: Visit URL in browser - should return JSON
- **Check**: Anon key in `.env.local` matches Supabase project

#### Subtitles not appearing
- **Enable** in player Settings â†’ Subtitles
- **Check**: File is VTT or SRT format
- **Verify**: Subtitle file exists next to video
- **Test**: Try system subtitle file to rule out formatting issues

#### Audio tracks not available
- **Check**: Backend audio service is running
- **Verify**: Video has embedded audio tracks: `ffprobe -show_streams video.mkv`
- **Note**: Some audio codecs require transcoding (first play takes longer)

#### Frequent freezing or buffering
- **Network**: Check internet speed and stability
- **CPU**: Monitor system resource usage (Task Manager)
- **Disk**: Verify storage space (>1GB free)
- **Solution**: Reduce playback speed or use external player

#### "Electron failed to start"
```bash
# Try clearing app cache
rm -rf ~/.config/animind-desktop    # Linux
rm -rf ~/Library/Application\ Support/Animind\ Desktop    # macOS
rmdir %APPDATA%\Animind\ Desktop    # Windows

# Reinstall and rebuild
npm install
npm run dev
```

### Development Issues

#### Hot reload not working
```bash
# Hard restart
npm run dev

# If still failing, clear Vite cache:
rm -rf node_modules/.vite
npm run dev
```

#### TypeScript errors before app loads
```bash
npm run typecheck
# Fix errors shown, then restart:
npm run dev
```

#### Port 3000 already in use
```bash
# Kill process using port 3000
lsof -ti:3000 | xargs kill -9    # macOS/Linux

# Windows:
netstat -ano | findstr :3000
taskkill /PID <PID> /F
```

### Performance Troubleshooting

#### App slow on startup
- **Check**: Hard drive type (SSD vs HDD)
- **Try**: Run `npm cache verify`
- **Check**: Antivirus exclusions for `node_modules/`

#### Memory usage high (>500MB)
- **Cause**: Usually normal for Electron + large video
- **Try**: Close other apps
- **Check**: Video codec (hardware acceleration on supported GPUs)

#### Video playback stuttering
- **Network**: Check bandwidth with speed test
- **CPU**: Verify process not maxed: `top` / Task Manager
- **Alternative**: Use external player for CPU-intensive codecs

## Next Steps

After successful installation:

1. **First Run Setup**
   - App will prompt for Supabase setup if needed
   - Complete initial configuration wizard

2. **Load Content**
   - Backend must be configured with video storage
   - Episodes auto-discover from configured paths

3. **Start Streaming**
   - Select anime from library
   - Click "Watch Now" to see episodes
   - Click episode to start playback

4. **Explore Settings**
   - Configure external players (MPV, VLC)
   - Adjust playback preferences
   - Set subtitle rendering options

## Getting Help

- **Documentation**: See [README.md](../README.md) and [DEVELOPMENT.md](./DEVELOPMENT.md)
- **Issues**: Check GitHub issues for known problems
- **Debugging**: Enable dev tools: `Ctrl+Shift+I` in app
- **Logs**: Check browser console for error messages

---

**Happy watching!** ðŸŽŒ


