import { app } from 'electron';
import { mkdir, readFile, writeFile } from 'fs/promises';
import path from 'path';

export interface AppSettings {
  backendUrl: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
  mpvPath: string;
}

const SETTINGS_FILE = 'settings.json';

function getDefaultSettings(): AppSettings {
  return {
    backendUrl: process.env.ANIMIND_BACKEND_URL ?? 'http://localhost:3000',
    supabaseUrl: process.env.ANIMIND_SUPABASE_URL ?? '',
    supabaseAnonKey: process.env.ANIMIND_SUPABASE_ANON_KEY ?? '',
    mpvPath: process.env.ANIMIND_MPV_PATH ?? 'mpv',
  };
}

function getSettingsPath(): string {
  return path.join(app.getPath('userData'), SETTINGS_FILE);
}

export class SettingsService {
  private cache: AppSettings | null = null;

  async getSettings(): Promise<AppSettings> {
    if (this.cache) return this.cache;
    const defaults = getDefaultSettings();
    const filePath = getSettingsPath();

    try {
      const raw = await readFile(filePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<AppSettings>;
      this.cache = { ...defaults, ...parsed };
      return this.cache;
    } catch {
      this.cache = defaults;
      await this.saveSettings(defaults);
      return defaults;
    }
  }

  async saveSettings(next: Partial<AppSettings>): Promise<AppSettings> {
    const current = await this.getSettings();
    const merged: AppSettings = { ...current, ...next };
    const dir = app.getPath('userData');
    await mkdir(dir, { recursive: true });
    await writeFile(getSettingsPath(), JSON.stringify(merged, null, 2), 'utf8');
    this.cache = merged;
    return merged;
  }
}

export const settingsService = new SettingsService();
