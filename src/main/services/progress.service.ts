import { app } from 'electron';
import { mkdir, readFile, writeFile } from 'fs/promises';
import path from 'path';
import { authService } from './auth.service';

interface ProgressEntry {
  userId: string;
  animeId: string;
  episodeIndex: number;
  timestamp: number;
  updatedAt: string;
}

type ProgressMap = Record<string, ProgressEntry>;

function keyOf(userId: string, animeId: string, episodeIndex: number): string {
  return `${userId}::${animeId}::${episodeIndex}`;
}

function getProgressPath(): string {
  return path.join(app.getPath('userData'), 'progress.json');
}

export class ProgressService {
  private cache: ProgressMap | null = null;

  private async load(): Promise<ProgressMap> {
    if (this.cache) return this.cache;
    try {
      const raw = await readFile(getProgressPath(), 'utf8');
      this.cache = JSON.parse(raw) as ProgressMap;
      return this.cache;
    } catch {
      this.cache = {};
      return this.cache;
    }
  }

  private async saveStore(store: ProgressMap): Promise<void> {
    const dir = app.getPath('userData');
    await mkdir(dir, { recursive: true });
    await writeFile(getProgressPath(), JSON.stringify(store, null, 2), 'utf8');
    this.cache = store;
  }

  async getProgress(animeId: string, episodeIndex: number): Promise<number> {
    const user = await authService.getCurrentUser();
    if (!user) return 0;
    const store = await this.load();
    return store[keyOf(user.id, animeId, episodeIndex)]?.timestamp ?? 0;
  }

  async saveProgress(
    animeId: string,
    episodeIndex: number,
    timestamp: number,
  ): Promise<{ saved: boolean; reason?: 'not-authenticated' | 'local-only' }> {
    const user = await authService.getCurrentUser();
    if (!user) {
      return { saved: false, reason: 'not-authenticated' };
    }

    const store = await this.load();
    const entry: ProgressEntry = {
      userId: user.id,
      animeId,
      episodeIndex,
      timestamp,
      updatedAt: new Date().toISOString(),
    };

    store[keyOf(user.id, animeId, episodeIndex)] = entry;
    await this.saveStore(store);

    try {
      const supabase = await authService.getSupabaseClient();
      await supabase
        .from('progress')
        .upsert(
          {
            user_id: user.id,
            anime_id: animeId,
            episode_index: episodeIndex,
            timestamp,
            updated_at: entry.updatedAt,
          },
          { onConflict: 'user_id, anime_id, episode_index' }
        );
    } catch {
      // Keep local progress even if remote sync fails.
      return { saved: true, reason: 'local-only' };
    }

    return { saved: true };
  }
}

export const progressService = new ProgressService();
