# Animind Desktop Player

Native desktop video player built with **Qt 6.5 / QML** and **libmpv**.

## Architecture

```
animind-desktop-player/
├── qt_host/                  ← Active C++ / QML host
│   ├── src/
│   │   ├── main.cpp          ← Qt app entry point (QQuickStyle, QML engine)
│   │   ├── mpv_item.h        ← QQuickFramebufferObject → MpvVideo QML type
│   │   └── mpv_item.cpp      ← libmpv OpenGL render context integration
│   ├── qml/
│   │   └── main.qml          ← Native player UI (ApplicationWindow + controls)
│   ├── include/mpv/          ← libmpv headers (client.h, render.h, render_gl.h)
│   ├── CMakeLists.txt        ← Qt6 CMake build
│   └── .qt/6.5.3/            ← Qt SDK (installed by aqt, gitignored)
├── vendor/mpv/win-x64/       ← libmpv-2.dll + regenerated import lib
├── _archived/                ← Old Electron/CEF code (kept for reference)
│   ├── electron_src/         ← Previous React + Electron implementation
│   ├── cef_host/             ← Previous CEF C++ host
│   ├── cef_migration/        ← CEF migration files & logs
│   ├── electron_build/       ← Old build artefacts, node_modules
│   └── test_files/           ← Old test scripts
├── .env                      ← Environment config
└── package.json              ← Build scripts (configure / build / dev / start)
```

## Why Qt/QML?

Previous attempts used **Electron** then **Chromium Embedded Framework (CEF)** to layer
a web UI over a native `WS_CHILD` MPV window. Both hit the same fundamental problem:
Win32 window compositing — two separate GPU contexts competing for the same surface,
causing black screens, z-index flickering, D3D11 thread-affinity crashes (`0xC000000D`).

**Qt/QML solves this** by using a single unified scene graph (OpenGL). `MpvVideo` renders
libmpv frames directly into a `QQuickFramebufferObject` texture, which Qt composites with
all QML controls in one GPU draw pass. No window stacking. No transparency hacks.

## Prerequisites

- **MSVC 2019/2022** (Visual Studio Build Tools)
- **CMake ≥ 3.21**
- **Python 3** (for `aqt` Qt installer)
- **Qt 6.5.3** — install automatically with `npm run install:qt`

## Setup & Run

```powershell
# 1. Install Qt 6.5.3 via aqt (one time, ~500 MB)
npm run install:qt

# 2. Configure CMake
npm run configure

# 3. Build + launch
npm run dev

# Or separately:
npm run build    # compile only
npm run start    # launch exe
```

## QML Development

QML files are loaded from the filesystem at runtime — **no rebuild needed** after editing `qt_host/qml/main.qml`. Just restart the app:

```powershell
npm run start
```

## Player Controls

| Key / Action           | Effect                  |
|------------------------|-------------------------|
| `Space` / Click video  | Play / Pause            |
| `F` or `F11`           | Toggle fullscreen        |
| `→` / `←`             | Seek ±5 seconds         |
| `↑` / `↓`             | Volume ±5%              |
| `M`                    | Toggle mute             |
| Top URL bar (hover)    | Load any URL or file     |

## Build System

```powershell
# Full reconfigure (after CMakeLists changes)
cmake -S qt_host -B qt_host/build `
  -DCMAKE_PREFIX_PATH="qt_host/.qt/6.5.3/msvc2019_64" -A x64

# Build
cmake --build qt_host/build --config Release
```

## Key Files

| File | Purpose |
|------|---------|
| `qt_host/src/mpv_item.h` | `MpvVideo` QML type declaration |
| `qt_host/src/mpv_item.cpp` | libmpv OpenGL framebuffer renderer |
| `qt_host/src/main.cpp` | App entry: OpenGL mode, Material style, QML engine |
| `qt_host/qml/main.qml` | Complete player UI in QML |
| `vendor/mpv/win-x64/libmpv-2.dll` | libmpv shared library |
| `vendor/mpv/win-x64/libmpv-2-proper.lib` | Regenerated MSVC import lib |
