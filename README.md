# Animind Desktop Player

Native desktop anime player built with **Qt 6.5.3 / QML** and **libmpv** on Windows: a full
player UI, AniList-backed catalog, My List and history, sign-in through the AniMind backend, and
synchronised watch parties.

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

| Variable | Default | Purpose |
|---|---|---|
| `ANIMIND_BACKEND_URL` | `http://127.0.0.1:3001` | The Go backend: auth, catalog, `/api/me`, playback tickets, the watch-party socket. |
| `ANIMIND_SITE_URL` | `http://localhost:3000` | The website that mints the desktop sign-in bridge token. |
| `ANIMIND_MPV_PATH` | next to the exe | Where `libmpv-2.dll` lives. |

Sign-in opens that site's `/desktop-auth` page in the browser and listens on loopback for the
hand-off, so the desktop client holds no password and no signing key. Supabase and Clerk are gone:
history, My List and preferences are authenticated `/api/me/*` calls on the backend.

`.env.example` lists the diagnostic and headless-harness variables.

---

## 5. Build & Run

```powershell
npm install                                   # Jest + fast-check
cmake -S qt_host -B qt_host/build             # configure (no -A: see the note below)
cmake --build qt_host/build --config Release  # build
qt_host\build\Release\AnimindQtHost.exe       # run
```

> `npm run configure` passes `-A x64`, which conflicts with the platform recorded in an existing
> `qt_host/build` cache and fails. Configure without `-A`. Deleting the cache would also delete
> the installer `.exe` that lives in `build/`, so it is not the fix.

After the first build, editing QML **does not require a rebuild** — the deploy step copies
`qt_host/qml/` next to the exe, so `cmake --build` (or just re-copying the folder) is enough to
pick up a QML change. A C++ change needs the build.

---

## 6. Run Tests

```powershell
npm test        # Jest: 6 suites, 79 tests over the pure QML helpers
cmake --build qt_host/build --config Release --target syncCoreTests
qt_host\build\Release\syncCoreTests.exe -o results.txt,txt
ctest --test-dir qt_host/build -C Release
```

`syncCoreTests` covers the three pure sync layers — `clock_estimator`, `sync_decision`,
`sync_telemetry` — 40 cases with no socket, no player and no real clock: every instant is passed
in, which is the only way packet ordering, hysteresis and scheduled starts can be shown to hold
rather than assumed.

> Its PASS/FAIL lines appear **only** when redirected to a file (`-o results.txt,txt`); writing to
> stdout or `>` produces nothing and the exit code is the only signal. Read the file too — the
> exit code is a failure *count*.

Jest covers QML-side helpers by inlining them, so it cannot see a change to the `.qml` file it
claims to test. Anything that must not drift lives behind a C++ test instead.

---

## Project Structure

```
animind-desktop-player/
├── qt_host/
│   ├── src/
│   │   ├── main.cpp              ← entry point, player shell, headless harnesses
│   │   ├── auth_manager.h/.cpp   ← backend sign-in + bridge listener (authManager in QML)
│   │   ├── backend_api.h/.cpp    ← REST client: catalog, /api/me, tickets (api in QML)
│   │   ├── syncplay_client.h/.cpp← Engine.IO/Socket.IO client + room view (syncplay in QML)
│   │   ├── clock_estimator.h/.cpp← four-timestamp clock estimate, monotonic projection
│   │   ├── sync_decision.h/.cpp  ← the sync policy: one pure decide() returning named outcomes
│   │   ├── sync_telemetry.h/.cpp ← drift percentiles, correction counts, start skew
│   │   ├── mpv_item.h/.cpp       ← MpvVideo QML type (libmpv OpenGL renderer)
│   │   └── backend_config.h      ← the two backend origins, environment-driven
│   ├── qml/
│   │   ├── main.qml              ← root window, navigation, player chrome, overlays
│   │   ├── Theme.qml             ← every colour, size, font and duration
│   │   ├── SideNav.qml / TopBar.qml / AnimePosterCard.qml / AniListApi.qml
│   │   ├── components/           ← WatchParty (policy), PartyPanel, HeroBanner, EpisodeSidebar,
│   │   │                            AuthSheet, ShortcutOverlay, buttons, empty states
│   │   └── pages/                ← Home, Browse, Detail, History, MyList, Search, Settings
│   ├── include/mpv/              ← libmpv headers
│   ├── tests/
│   │   ├── property/ unit/       ← fast-check and Jest tests of the pure QML helpers
│   │   └── cpp/                  ← Qt Test for the sync layers (target syncCoreTests)
│   └── CMakeLists.txt            ← AnimindQtHost + syncCoreTests
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
| `npm run configure` | CMake configure — **fails against an existing build cache**, see §5 |
| `npm run build` | Build the C++ host (Release) |
| `npm run dev` | Build + launch |
| `npm run start` | Launch the built exe |
| `npm run clean:build` | Delete `qt_host/build/` (also deletes the installer exe — avoid) |
| `npm test` | Jest only; the C++ sync tests are a separate target (§6) |

---

## Player Controls

| Key / Action | Effect |
|---|---|
| `Space` | Play / Pause |
| `F` or `F11` | Toggle fullscreen |
| `→` / `←` | Seek ±5 seconds |
| `↑` / `↓` | Volume ±5% |
| `M` | Toggle mute |
| `[` / `]` | Previous / next chapter |
| `S` | Toggle subtitles |
| `W` | Open the watch-party panel |
| `?` | Full shortcut map |
| `Escape` | Exit player / close overlays |

---

## Watch parties

A room is code-shared and server-authoritative: the hub owns the clock, and every member is told
the *instant* to act at rather than acting when a packet lands.

| Layer | File | Owns |
|---|---|---|
| Transport | `syncplay_client.cpp` | Socket framing, roster, gate state, packet ordering by `seq` |
| Time | `clock_estimator.cpp` | Server-vs-client offset from four timestamps, monotonic projection of the group position |
| Decision | `sync_decision.cpp` | `decide(room, local) → outcome`: `await-schedule`, `nudge-slow`, `correct-to-group`, `reject-stale`, … |
| Actuation | `WatchParty.qml` | Carries the outcome out on mpv, and never corrects the viewer while they are driving |

The policy is one function with named answers, which is what makes it testable: the rules that
used to hide in event handlers (stale broadcasts, self-echo, one's own action arriving back as a
command, a pause flickering across the room) are each a case in `syncCoreTests`.

Protocol details, the tuning block the hub publishes (`syncConfig`) and the measured
0 ms-across-400 ms-of-delay start skew are in
`docs/syncplay-improvement-plan.md` §13. The wire contract lives beside the server, in
`Animind_Backend_Go/docs/06-watch-parties.md` and `internal/syncplay/room.go`.

---

## Why Qt/QML?

Previous attempts used Electron then CEF to layer a web UI over a native MPV window. Both hit the same wall: Win32 window compositing — two GPU contexts competing for the same surface, causing black screens, z-order flickering, and D3D11 thread-affinity crashes.

Qt/QML solves this with a single unified scene graph (OpenGL). `MpvVideo` renders libmpv frames directly into a `QQuickFramebufferObject` texture, which Qt composites with all QML controls in one GPU draw pass — no window stacking, no transparency hacks.
