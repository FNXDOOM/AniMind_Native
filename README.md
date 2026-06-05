# Animind Desktop Player

Native desktop anime player built with **Qt 6.5.3 / QML** and **libmpv** on Windows. Features a full player UI, AniList search, watch history, My List, and Clerk-based authentication.

---

## Requirements

Before you start, make sure you have the following installed:

| Tool | Version | Notes |
|------|---------|-------|
| **Windows** | 10 or 11 (64-bit) | Only Windows is supported |
| **Visual Studio 2019 or 2022** | Any edition | Install the **Desktop development with C++** workload |
| **CMake** | ≥ 3.21 | Add to PATH during install |
| **Python 3** | ≥ 3.8 | Required for the Qt installer (`aqt`) |
| **Node.js** | ≥ 18 | For build scripts and tests |
| **Git** | Any | To clone the repo |

> **libmpv** (`libmpv-2.dll`, `mpv-1.dll`) and the MSVC import lib are **not included** in the repo (too large for GitHub). Download them separately — see [below](#libmpv-setup).

---

## 1. Clone

```powershell
git clone https://github.com/FNXDOOM/AniMind_Native.git
cd AniMind_Native
```

---

## 2. libmpv Setup

The player requires `libmpv-2.dll` and the MSVC import lib. Get them from the [mpv-dev releases](https://github.com/shinchiro/mpv-winbuild-cmake/releases):

1. Download the latest `mpv-dev-x86_64-*.7z`
2. Extract and copy the files to `vendor/mpv/win-x64/`:

```
vendor/mpv/win-x64/
├── libmpv-2.dll          ← main shared library
├── mpv-1.dll             ← alternate name (symlink/copy of above)
├── libmpv.dll.a          ← MinGW import lib (if present)
└── manifest.json         ← already in repo
```

3. Generate the MSVC import lib (required for linking):

```powershell
# From the project root — run in a Developer Command Prompt (MSVC)
cd vendor\mpv\win-x64
dumpbin /exports libmpv-2.dll > libmpv-2-exports.txt
# Then generate the .def and .lib (see docs or use gendef + lib.exe)
```

Or use a pre-built `libmpv-2-proper.lib` if you have one — place it at `vendor/mpv/win-x64/libmpv-2-proper.lib`.

---

## 3. Install Qt 6.5.3

```powershell
# Install aqt (Qt CLI installer)
pip install aqtinstall

# Install Qt 6.5.3 MSVC 64-bit (~500 MB, one-time)
npm run install:qt
```

This installs Qt to `qt_host/.qt/6.5.3/msvc2019_64/` (gitignored).

---

## 4. Environment Variables

Copy `.env.example` to `.env` and fill in your values:

```powershell
Copy-Item .env.example .env
```

Open `.env` and set:

```env
ANIMIND_BACKEND_URL=https://your-backend-url.com
ANIMIND_SUPABASE_URL=https://your-project.supabase.co
ANIMIND_SUPABASE_ANON_KEY=your-supabase-anon-key
```

- `ANIMIND_SUPABASE_URL` — your Supabase project URL (used for watch history read/write)
- `ANIMIND_SUPABASE_ANON_KEY` — your Supabase `anon` public key
- `ANIMIND_BACKEND_URL` — your Animind API backend URL

> The app reads these at startup via `qgetenv` and exposes them to QML. Without them, watch history features will silently do nothing.

---

## 5. Build & Run

```powershell
# Install Node dependencies (Jest + fast-check for tests)
npm install

# Configure CMake (one time, or after CMakeLists.txt changes)
npm run configure

# Build the C++ host
npm run build

# Launch the app
npm run start
```

Or do configure + build + launch in one step:

```powershell
npm run dev
```

After the first build, editing QML files **does not require a rebuild** — just restart:

```powershell
npm run start
```

---

## 6. Run Tests

```powershell
npm test
```

Runs 5 test suites (60 tests) covering property-based and unit tests for `computeDisplayName`, TopBar avatar initial, AniList API, SideNav display name, and TopBar avatar states.

---

## Project Structure

```
animind-desktop-player/
├── qt_host/
│   ├── src/
│   │   ├── main.cpp              ← Qt app entry point
│   │   ├── auth_manager.h/.cpp   ← Clerk auth C++ singleton (authManager in QML)
│   │   ├── mpv_item.h/.cpp       ← MpvVideo QML type (libmpv OpenGL renderer)
│   ├── qml/
│   │   ├── main.qml              ← Root window, navigation, overlays
│   │   ├── SideNav.qml           ← 256px sidebar
│   │   ├── TopBar.qml            ← 64px top bar with search, bell, avatar
│   │   ├── SearchOverlay.qml     ← Full-screen search overlay
│   │   ├── NotificationPanel.qml ← Notification dropdown
│   │   ├── AnimePosterCard.qml   ← Reusable poster card
│   │   ├── AniListApi.qml        ← AniList GraphQL client singleton
│   │   └── pages/
│   │       ├── HomePage.qml
│   │       ├── BrowsePage.qml
│   │       ├── DetailPage.qml
│   │       ├── HistoryPage.qml   ← Watch history (Supabase)
│   │       ├── MyListPage.qml    ← Saved anime list
│   │       └── SimulcastPage.qml
│   ├── include/mpv/              ← libmpv headers
│   ├── tests/
│   │   ├── property/             ← fast-check property tests
│   │   └── unit/                 ← Jest unit tests
│   └── CMakeLists.txt
├── vendor/mpv/win-x64/           ← libmpv DLLs (not in repo, add manually)
├── .env.example                  ← Environment variable template
├── .env                          ← Your local secrets (gitignored)
└── package.json                  ← npm scripts
```

---

## npm Scripts Reference

| Script | What it does |
|--------|-------------|
| `npm run install:qt` | Install Qt 6.5.3 via aqt |
| `npm run configure` | Run CMake configure |
| `npm run build` | Build the C++ host (Release) |
| `npm run dev` | Build + launch |
| `npm run start` | Launch the built exe |
| `npm run clean:build` | Delete `qt_host/build/` |
| `npm test` | Run all Jest tests |

---

## Player Controls

| Key / Action | Effect |
|---|---|
| `Space` | Play / Pause |
| `F` or `F11` | Toggle fullscreen |
| `→` / `←` | Seek ±5 seconds |
| `↑` / `↓` | Volume ±5% |
| `M` | Toggle mute |
| `Escape` | Exit player / close overlays |

---

## Why Qt/QML?

Previous attempts used Electron then CEF to layer a web UI over a native MPV window. Both hit the same wall: Win32 window compositing — two GPU contexts competing for the same surface, causing black screens, z-order flickering, and D3D11 thread-affinity crashes.

Qt/QML solves this with a single unified scene graph (OpenGL). `MpvVideo` renders libmpv frames directly into a `QQuickFramebufferObject` texture, which Qt composites with all QML controls in one GPU draw pass — no window stacking, no transparency hacks.
