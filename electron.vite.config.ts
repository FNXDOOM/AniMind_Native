import { defineConfig } from 'electron-vite';
import react from '@vitejs/plugin-react';
import { readFileSync, existsSync } from 'fs';
import { resolve } from 'path';

// Manually parse .env file since dotenv may not be installed
function loadEnv(envPath: string): Record<string, string> {
  if (!existsSync(envPath)) return {};
  const content = readFileSync(envPath, 'utf-8');
  const result: Record<string, string> = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx < 0) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    let value = trimmed.slice(eqIdx + 1).trim().replace(/^['"]|['"]$/g, '');
    // Unescape double-backslashes so Windows paths in .env work correctly
    value = value.replace(/\\\\/g, '\\');
    result[key] = value;
  }
  return result;
}

const env = loadEnv(resolve(__dirname, '.env'));

export default defineConfig({
  main: {
    build: {
      outDir: 'dist/main',
    },
    define: {
      'process.env.ANIMIND_BACKEND_URL': JSON.stringify(env.ANIMIND_BACKEND_URL ?? ''),
      'process.env.ANIMIND_CLERK_PUBLISHABLE_KEY': JSON.stringify(env.ANIMIND_CLERK_PUBLISHABLE_KEY ?? ''),
      'process.env.ANIMIND_MPV_PATH': JSON.stringify(env.ANIMIND_MPV_PATH ?? 'mpv'),
    },
  },
  preload: {
    build: {
      outDir: 'dist/preload',
    },
  },
  renderer: {
    root: 'src/renderer',
    // base must be './' so Vite emits relative asset paths (./assets/...)
    // instead of absolute paths (/assets/...). Absolute paths break under
    // file:// protocol when running the built app with `npm start`.
    base: './',
    build: {
      // Must be absolute: with root='src/renderer', a relative outDir is resolved
      // relative to that root (not the project root), putting output 4 levels up.
      outDir: resolve(__dirname, 'dist/renderer'),
    },
    plugins: [react()],
    define: {
      // Expose env vars to renderer. Both names are checked so neither casing breaks.
      'import.meta.env.VITE_CLERK_PUBLISHABLE_KEY': JSON.stringify(env.ANIMIND_CLERK_PUBLISHABLE_KEY ?? env.VITE_CLERK_PUBLISHABLE_KEY ?? ''),
      'import.meta.env.ANIMIND_CLERK_PUBLISHABLE_KEY': JSON.stringify(env.ANIMIND_CLERK_PUBLISHABLE_KEY ?? ''),
      'import.meta.env.VITE_BACKEND_URL': JSON.stringify(env.ANIMIND_BACKEND_URL ?? ''),
    },
  },
});
