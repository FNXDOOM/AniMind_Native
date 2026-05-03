N-API addon scaffold for mpv-embedded

This directory contains a minimal N-API addon scaffold to start implementing
an embedded libmpv backend for Animind Desktop. It uses `node-addon-api`
and `node-gyp` to build a `.node` binary that can be required from the
Electron main process.

Quick start (Windows):

1. Install dev deps in the native folder:

```powershell
cd native
npm install
```

2. Build the addon:

```powershell
npm run build
```

3. From the app root you can require the built binary at `native/build/Release/addon.node`.

Next steps:
- Replace the stub `hello` export with real libmpv initialization, linking
  against `vendor/mpv/win-x64/libmpv-2.dll`.
- Implement rendering callbacks to present frames to Electron's BrowserWindow.
