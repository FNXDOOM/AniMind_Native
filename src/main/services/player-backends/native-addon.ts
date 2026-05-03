/**
 * native-addon.ts
 *
 * Thin wrapper around the compiled addon.node binary.
 * Handles path resolution across dev / packaged-app contexts.
 */
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

let addon: any = null;
let addonInitialized = false;
let addonLoadError: string | null = null;
let resolvedAddonPath: string | null = null;
let resolvedDllDir: string | null = null;

interface AddonAvailabilityDetails {
  available: boolean;
  addonPath: string;
  dllDir: string;
  error?: string;
}

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const baseSearchRoots = [
  path.resolve(moduleDir, '../../../../'),
  process.cwd(),
  path.resolve(process.cwd(), '..'),
  path.resolve(process.cwd(), '../..'),
];

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function getElectronAppPath(): string | null {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const electron = require('electron') as typeof import('electron');
    if (!electron?.app) return null;
    if (!electron.app.isReady()) return null;
    return electron.app.getAppPath();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.warn('[MPV addon] Unable to read app path:', message);
    return null;
  }
}

function dedupePaths(pathsToFilter: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];

  for (const candidate of pathsToFilter) {
    if (!isNonEmptyString(candidate)) continue;
    const normalized = path.normalize(candidate);
    const key = process.platform === 'win32' ? normalized.toLowerCase() : normalized;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(normalized);
  }

  return out;
}

function buildCandidatePaths(relativeSegments: string[]): string[] {
  const appPath = getElectronAppPath();
  const roots = dedupePaths([
    ...baseSearchRoots,
    process.resourcesPath,
    appPath ?? '',
    path.join(process.resourcesPath, 'app.asar.unpacked'),
  ]);

  return dedupePaths(roots.map(root => path.join(root, ...relativeSegments)));
}

function pathEnvContains(dir: string): boolean {
  const currentPath = process.env.PATH ?? '';
  const entries = currentPath
    .split(path.delimiter)
    .map(entry => path.normalize(entry).toLowerCase());
  return entries.includes(path.normalize(dir).toLowerCase());
}

// ─────────────────────────────────────────────────────────────────────────────
// Add the vendor DLL directory to Windows' DLL search path BEFORE loading the
// addon. Without this, LoadLibraryA("libmpv-2.dll") inside addon.cc fails
// because the DLL is in vendor/mpv/win-x64/ which is not on PATH.
// ─────────────────────────────────────────────────────────────────────────────
function ensureDllSearchPath(): string {
  if (process.platform !== 'win32') return '';

  const candidates = buildCandidatePaths(['vendor', 'mpv', 'win-x64']);
  for (const dir of candidates) {
    if (!fs.existsSync(dir)) continue;

    if (!pathEnvContains(dir)) {
      process.env.PATH = [dir, process.env.PATH ?? ''].filter(Boolean).join(path.delimiter);
      console.log('[MPV addon] Added DLL search path:', dir);
    }

    resolvedDllDir = dir;
    return dir;
  }

  throw new Error(
    `libmpv vendor directory was not found. Searched: ${candidates.join(', ')}. ` +
    'Make sure `vendor/mpv/win-x64` is packaged with the app.',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Load addon.node from the first path that actually exists
// ─────────────────────────────────────────────────────────────────────────────
function loadAddon(): void {
  if (addon) return;

  addonLoadError = null;
  resolvedAddonPath = null;

  try {
    ensureDllSearchPath();
  } catch (err) {
    addonLoadError = err instanceof Error ? err.message : String(err);
    console.warn('[MPV addon] DLL search path setup failed:', addonLoadError);
    return;
  }

  const candidates = buildCandidatePaths(['native', 'build', 'Release', 'addon.node']);

  for (const candidate of candidates) {
    try {
      if (fs.existsSync(candidate)) {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        addon = require(candidate);
        resolvedAddonPath = candidate;
        console.log('[MPV addon] Loaded from:', candidate);
        return;
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (
        message.toLowerCase().includes('application control policy has blocked this file')
        || message.toLowerCase().includes('enterprise signing level requirements')
      ) {
        addonLoadError =
          `Failed to load addon from "${candidate}": ${message}. ` +
          'Windows Code Integrity / WDAC policy is blocking native module loading. ' +
          'Ask your administrator to allow this addon.node and vendor/mpv/win-x64/libmpv-2.dll.';
      } else {
        addonLoadError = `Failed to load addon from "${candidate}": ${message}`;
      }
      console.warn('[MPV addon] Failed to load from', candidate, ':', err);
    }
  }

  if (!addonLoadError) {
    addonLoadError = `Could not find addon.node. Searched: ${candidates.join(', ')}. ` +
      'Run `npm run native:rebuild` if the addon has not been built yet.';
  }
  console.warn('[MPV addon]', addonLoadError);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/** Returns true if libmpv-2.dll can be loaded. Does NOT require initialize(). */
export function isAvailable(): boolean {
  loadAddon();
  return addon !== null && typeof addon.isAvailable === 'function' && Boolean(addon.isAvailable());
}

export function getAvailabilityDetails(): AddonAvailabilityDetails {
  loadAddon();

  const available = addon !== null
    && typeof addon.isAvailable === 'function'
    && Boolean(addon.isAvailable());

  return {
    available,
    addonPath: resolvedAddonPath ?? '',
    dllDir: resolvedDllDir ?? '',
    error: available ? undefined : (addonLoadError ?? 'Native addon is unavailable.'),
  };
}

/**
 * Create & initialize the mpv instance with the target HWND.
 * The HWND MUST be passed before mpv_initialize so mpv sets up its
 * video output (VO) against the correct window from the very start.
 * Idempotent — safe to call again if already initialized.
 */
export async function initialize(hwnd: bigint): Promise<boolean> {
  loadAddon();
  if (!addon || typeof addon.initialize !== 'function') return false;
  return new Promise((resolve, reject) => {
    try {
      addon.initialize(hwnd, (err: Error | null, ok: boolean) => {
        if (err) {
          reject(err);
        } else {
          const success = Boolean(ok);
          if (success) addonInitialized = true;
          resolve(success);
        }
      });
    } catch (err) {
      reject(err);
    }
  });
}

export function getHeartbeat(): bigint {
  loadAddon();
  if (!addon || typeof addon.getHeartbeat !== 'function') return 0n;
  try {
    return BigInt(addon.getHeartbeat());
  } catch {
    return 0n;
  }
}

export function setWindowBounds(x: number, y: number, w: number, h: number): boolean {
  loadAddon();
  if (!addon || typeof addon.setWindowBounds !== 'function') return false;
  return addon.setWindowBounds(x, y, w, h);
}

/**
 * Embed mpv video output inside the given window handle (HWND on Windows).
 * Must be called AFTER initialize() and BEFORE open().
 *
 * @param hwnd  Native window handle as JS bigint to preserve full 64-bit HWND
 */
export async function setWindowId(hwnd: bigint): Promise<boolean> {
  loadAddon();
  if (!addon || typeof addon.setWindowId !== 'function') {
    throw new Error('native addon setWindowId() not found — rebuild the addon');
  }
  return Boolean(addon.setWindowId(hwnd));
}

/**
 * Load a URL or local file path into mpv and begin playback.
 * Auto-initializes mpv if not already done.
 */
export async function open(url: string, authToken?: string): Promise<boolean> {
  loadAddon();
  if (!addon || typeof addon.open !== 'function') {
    throw new Error('native addon not available');
  }
  if (!addonInitialized) {
    throw new Error('mpv not initialized — call initialize(hwnd) before open()');
  }
  return Boolean(addon.open(String(url), authToken ? String(authToken) : undefined));
}

export async function play(): Promise<boolean> {
  loadAddon();
  if (!addon?.play) throw new Error('native addon not available');
  return Boolean(addon.play());
}

export async function pause(): Promise<boolean> {
  loadAddon();
  if (!addon?.pause) throw new Error('native addon not available');
  return Boolean(addon.pause());
}

export async function seek(seconds: number): Promise<boolean> {
  loadAddon();
  if (!addon?.seek) throw new Error('native addon not available');
  return Boolean(addon.seek(Number(seconds)));
}

export async function setVolume(volume: number): Promise<boolean> {
  loadAddon();
  if (!addon?.setVolume) throw new Error('native addon not available');
  return Boolean(addon.setVolume(Math.max(0, Math.min(100, volume))));
}

export async function setMuted(muted: boolean): Promise<boolean> {
  loadAddon();
  if (!addon?.setMuted) throw new Error('native addon not available');
  return Boolean(addon.setMuted(Boolean(muted)));
}

export async function setAudioTrack(trackId: number): Promise<boolean> {
  loadAddon();
  if (!addon?.setAudioTrack) throw new Error('native addon not available');
  return Boolean(addon.setAudioTrack(Number(trackId)));
}

export async function setSubtitleTrack(trackId: number | 'no'): Promise<boolean> {
  loadAddon();
  if (!addon?.setSubtitleTrack) throw new Error('native addon not available');
  return Boolean(addon.setSubtitleTrack(trackId));
}

export async function addSubtitleFile(filePath: string): Promise<boolean> {
  loadAddon();
  if (!addon?.addSubtitleFile) throw new Error('native addon not available');
  return Boolean(addon.addSubtitleFile(String(filePath)));
}

export async function getTrackList(): Promise<
  Array<{ id: number; type: string; title: string; lang: string; codec: string; selected: boolean }>
> {
  loadAddon();
  if (!addon?.getTrackList) return [];
  try { return addon.getTrackList(); } catch { return []; }
}

export async function getState(): Promise<{ paused: boolean; timePos: number; duration: number }> {
  loadAddon();
  if (!addon?.getState) return { paused: true, timePos: 0, duration: 0 };
  try { return addon.getState(); } catch { return { paused: true, timePos: 0, duration: 0 }; }
}

export async function getAudioState(): Promise<{ volume: number; muted: boolean }> {
  loadAddon();
  if (!addon?.getAudioState) return { volume: 100, muted: false };
  try { return addon.getAudioState(); } catch { return { volume: 100, muted: false }; }
}

export async function destroy(): Promise<void> {
  loadAddon();
  if (!addon?.destroy) return;
  try { addon.destroy(); } catch { /* ignore */ }
  finally { addonInitialized = false; }
}
