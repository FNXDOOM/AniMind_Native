/**
 * test-mpv-direct.cjs - Run with:  npx electron test-mpv-direct.cjs
 */
'use strict';

const path = require('path');
const fs   = require('fs');
const os   = require('os');

const { app, BrowserWindow } = require('electron');

const dllDir = path.join(__dirname, 'vendor', 'mpv', 'win-x64');
if (fs.existsSync(dllDir)) process.env.PATH = dllDir + ';' + (process.env.PATH || '');

const addonPath = path.join(__dirname, 'native', 'build', 'Release', 'addon.node');
let addon;
try {
  addon = require(addonPath);
  console.log('addon loaded OK');
} catch(e) {
  console.error('FAILED to load addon:', e.message);
  process.exit(1);
}

// Find a local video file to test with
function findLocalVideo() {
  const searchDirs = [
    path.join(os.homedir(), 'Videos'),
    path.join(os.homedir(), 'Downloads'),
    'C:\\Users\\Public\\Videos',
    path.join(__dirname, '..'),
  ];
  const exts = ['.mp4', '.mkv', '.avi', '.mov', '.webm'];
  for (const dir of searchDirs) {
    if (!fs.existsSync(dir)) continue;
    try {
      const files = fs.readdirSync(dir);
      for (const f of files) {
        if (exts.some(e => f.toLowerCase().endsWith(e))) {
          return path.join(dir, f);
        }
      }
    } catch(e) {}
  }
  return null;
}

app.whenReady().then(async () => {
  console.log('Electron ready');

  const win = new BrowserWindow({
    width: 960, height: 540,
    title: 'MPV TEST',
    backgroundColor: '#ff0000',
    frame: true, show: false,
    webPreferences: { nodeIntegration: false, contextIsolation: true }
  });

  await win.loadURL('about:blank');
  win.show();
  win.focus();

  const hwndBuf = win.getNativeWindowHandle();
  const hwnd = hwndBuf.readBigUInt64LE(0);
  console.log('HWND:', hwnd.toString());

  await new Promise(r => setTimeout(r, 500));

  console.log('initialize...');
  try {
    const ok = addon.initialize(hwnd);
    console.log('initialize =>', ok);
    if (!ok) { app.quit(); return; }
  } catch(e) { console.error('initialize threw:', e.message); app.quit(); return; }

  await new Promise(r => setTimeout(r, 300));

  // Try a local file first
  const localFile = findLocalVideo();
  let url;
  if (localFile) {
    url = localFile;
    console.log('Using LOCAL file:', url);
  } else {
    // Fallback: create a tiny valid MP4 test file using ffmpeg if available
    // or just use the network URL
    url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
    console.log('No local file found, using network URL:', url);
  }

  console.log('open...');
  try { 
    const r = addon.open(url);
    console.log('open =>', r);
  } catch(e) { console.error('open threw:', e.message); }

  await new Promise(r => setTimeout(r, 500));

  console.log('play...');
  try { addon.play(); } catch(e) { console.error('play threw:', e.message); }

  console.log('\nPolling for 15s. Window should show video (not red/black):\n');

  let tick = 0;
  const poll = setInterval(() => {
    tick++;
    try {
      const s = addon.getState();
      console.log(`[${tick}] timePos=${s.timePos.toFixed(3)}  duration=${s.duration.toFixed(3)}  paused=${s.paused}`);
      if (s.timePos > 0.5) {
        console.log('\n SUCCESS: timePos is advancing — mpv is playing!');
        console.log('Check the window — is video visible?');
      }
    } catch(e) { console.log(`[${tick}] getState error:`, e.message); }
  }, 1000);

  setTimeout(() => {
    clearInterval(poll);
    console.log('\nDone.');
    try { addon.destroy(); } catch(e) {}
    app.quit();
  }, 15000);
});

app.on('window-all-closed', () => {});
