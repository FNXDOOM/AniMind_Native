import { app } from 'electron';
import { createClient, SupabaseClient, Session, User } from '@supabase/supabase-js';
import { mkdir, readFile, writeFile, unlink } from 'fs/promises';
import path from 'path';
import { settingsService } from './settings.service';

interface StoredSession {
  access_token: string;
  refresh_token: string;
  expires_at?: number;
  user: {
    id: string;
    email?: string;
  };
}

function getSessionPath(): string {
  return path.join(app.getPath('userData'), 'session.json');
}

export class AuthService {
  private supabase: SupabaseClient | null = null;
  private session: Session | null = null;

  private async getSupabase(): Promise<SupabaseClient> {
    if (this.supabase) return this.supabase;
    const settings = await settingsService.getSettings();
    if (!settings.supabaseUrl || !settings.supabaseAnonKey) {
      throw new Error('Supabase settings are missing. Open Settings and configure Supabase URL + anon key.');
    }

    this.supabase = createClient(settings.supabaseUrl, settings.supabaseAnonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: true,
      },
    });

    return this.supabase;
  }

  async restoreSession(): Promise<void> {
    const supabase = await this.getSupabase();
    try {
      const raw = await readFile(getSessionPath(), 'utf8');
      const stored = JSON.parse(raw) as StoredSession;
      const { data, error } = await supabase.auth.setSession({
        access_token: stored.access_token,
        refresh_token: stored.refresh_token,
      });
      if (error) {
        this.session = null;
        return;
      }
      this.session = data.session;
    } catch {
      this.session = null;
    }
  }

  private async persistSession(session: Session): Promise<void> {
    const dir = app.getPath('userData');
    await mkdir(dir, { recursive: true });
    const payload: StoredSession = {
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_at: session.expires_at,
      user: {
        id: session.user.id,
        email: session.user.email,
      },
    };
    await writeFile(getSessionPath(), JSON.stringify(payload, null, 2), 'utf8');
  }

  async signIn(email: string, password: string): Promise<{ user: User; accessToken: string }> {
    const supabase = await this.getSupabase();
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.session || !data.user) {
      throw new Error(error?.message ?? 'Login failed');
    }

    this.session = data.session;
    await this.persistSession(data.session);
    return { user: data.user, accessToken: data.session.access_token };
  }

  async signOut(): Promise<void> {
    if (this.supabase) {
      await this.supabase.auth.signOut().catch(() => undefined);
    }
    this.session = null;
    await unlink(getSessionPath()).catch(() => undefined);
  }

  async getAccessToken(): Promise<string | null> {
    const supabase = await this.getSupabase();
    if (!this.session) {
      await this.restoreSession();
    }

    if (!this.session) return null;

    const expiresAt = this.session.expires_at ?? 0;
    const isExpiring = Date.now() / 1000 >= expiresAt - 60;
    if (isExpiring) {
      const { data, error } = await supabase.auth.refreshSession({
        refresh_token: this.session.refresh_token,
      });
      if (error || !data.session) return null;
      this.session = data.session;
      await this.persistSession(data.session);
    }

    return this.session?.access_token ?? null;
  }

  async getCurrentUser(): Promise<User | null> {
    const token = await this.getAccessToken();
    if (!token) return null;

    const supabase = await this.getSupabase();
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data.user) return null;
    return data.user;
  }

  async getSessionInfo(): Promise<{ userId: string; email?: string } | null> {
    const user = await this.getCurrentUser();
    if (!user) return null;
    return { userId: user.id, email: user.email ?? undefined };
  }

  async getSupabaseClient(): Promise<SupabaseClient> {
    return this.getSupabase();
  }
}

export const authService = new AuthService();
