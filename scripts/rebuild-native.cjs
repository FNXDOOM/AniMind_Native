'use strict';
const { execSync, spawnSync } = require('child_process');
const path  = require('path');
const fs    = require('fs');

const projectRoot = path.resolve(__dirname, '..');
const nativeDir   = path.join(projectRoot, 'native');

// ── 1. Read Electron version ──────────────────────────────────────────────────
const electronPkg = path.join(projectRoot, 'node_modules', 'electron', 'package.json');
if (!fs.existsSync(electronPkg)) {
  console.error('ERROR: node_modules/electron not found. Run "npm install" in project root first.');
  process.exit(1);
}
const electronVersion = require(electronPkg).version;
console.log(`[rebuild] Electron version : ${electronVersion}`);
console.log(`[rebuild] Native dir       : ${nativeDir}`);

// ── 2. Ensure native/node_modules exists ─────────────────────────────────────
const nativeNM = path.join(nativeDir, 'node_modules');
if (!fs.existsSync(nativeNM)) {
  console.log('[rebuild] Running npm install inside native/ ...');
  const r = spawnSync('npm', ['install'], {
    cwd: nativeDir, stdio: 'inherit', shell: true,
  });
  if (r.status !== 0) { console.error('[rebuild] npm install failed.'); process.exit(1); }
}

// ── 3. Find node-gyp ─────────────────────────────────────────────────────────
function findNodeGyp() {
  const candidates = [
    path.join(path.dirname(process.execPath), 'node_modules', 'npm', 'node_modules', 'node-gyp', 'bin', 'node-gyp.js'),
    path.join(nativeDir, 'node_modules', 'node-gyp', 'bin', 'node-gyp.js'),
    path.join(projectRoot, 'node_modules', 'node-gyp', 'bin', 'node-gyp.js'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) { console.log('[rebuild] node-gyp :', c); return c; }
  }
  return null;
}

const nodeGypScript = findNodeGyp();
const nodeGypCmd = nodeGypScript ? `node "${nodeGypScript}"` : 'npx node-gyp';

// ── 4. Build ──────────────────────────────────────────────────────────────────
const args = [
  'rebuild',
  `--target=${electronVersion}`,
  '--dist-url=https://electronjs.org/headers',
  '--arch=x64',
  '--runtime=electron',
  '--release',
].join(' ');

const cmd = `${nodeGypCmd} ${args}`;
console.log(`[rebuild] Running: ${cmd}\n`);

try {
  execSync(cmd, { cwd: nativeDir, stdio: 'inherit', shell: true });
} catch {
  console.error('\n[rebuild] Build failed. See MSVC errors above.');
  process.exit(1);
}

// ── 5. Verify ─────────────────────────────────────────────────────────────────
const out = path.join(nativeDir, 'build', 'Release', 'addon.node');
if (!fs.existsSync(out)) {
  console.error('[rebuild] addon.node not found after build.');
  process.exit(1);
}
console.log('\n[rebuild] SUCCESS:', out);
