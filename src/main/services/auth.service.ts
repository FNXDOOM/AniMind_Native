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
  private refreshPromise: Promise<Session | null> | null = null;
  private pendingGoogleSignIn:
    | {
        promise: Promise<{ user: User; accessToken: string }>;
        resolve: (value: { user: User; accessToken: string }) => void;
        reject: (reason?: unknown) => void;
        timeout: ReturnType<typeof setTimeout>;
      }
    | null = null;

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

  private createPendingGoogleSignIn(timeoutMs: number): Promise<{ user: User; accessToken: string }> {
    if (this.pendingGoogleSignIn) {
      throw new Error('Google Sign-In is already in progress. Finish that flow first.');
    }

    let resolveFn!: (value: { user: User; accessToken: string }) => void;
    let rejectFn!: (reason?: unknown) => void;

    const promise = new Promise<{ user: User; accessToken: string }>((resolve, reject) => {
      resolveFn = resolve;
      rejectFn = reject;
    });

    const timeout = setTimeout(() => {
      if (!this.pendingGoogleSignIn) return;
      const pending = this.pendingGoogleSignIn;
      this.pendingGoogleSignIn = null;
      pending.reject(new Error('Google Sign-In timed out. Please try again.'));
    }, timeoutMs);

    this.pendingGoogleSignIn = {
      promise,
      resolve: resolveFn,
      reject: rejectFn,
      timeout,
    };

    return promise;
  }

  private resolvePendingGoogleSignIn(result: { user: User; accessToken: string }): void {
    if (!this.pendingGoogleSignIn) return;
    const pending = this.pendingGoogleSignIn;
    this.pendingGoogleSignIn = null;
    clearTimeout(pending.timeout);
    pending.resolve(result);
  }

  private rejectPendingGoogleSignIn(error: unknown): void {
    if (!this.pendingGoogleSignIn) return;
    const pending = this.pendingGoogleSignIn;
    this.pendingGoogleSignIn = null;
    clearTimeout(pending.timeout);
    pending.reject(error);
  }

  async signInWithGoogle(openExternal: (url: string) => Promise<void>): Promise<{ user: User; accessToken: string }> {
    const supabase = await this.getSupabase();
    const pending = this.createPendingGoogleSignIn(180000);

    try {
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          skipBrowserRedirect: true,
          redirectTo: 'animind://auth/callback',
        },
      });

      if (error || !data.url) {
        throw new Error(error?.message ?? 'Unable to start Google Sign-In.');
      }

      await openExternal(data.url);
      return await pending;
    } catch (error) {
      this.rejectPendingGoogleSignIn(error);
      throw error;
    }
  }

  async handleAuthCallback(callbackUrl: string): Promise<boolean> {
    let parsed: URL;
    try {
      parsed = new URL(callbackUrl);
    } catch {
      return false;
    }

    if (parsed.protocol !== 'animind:') return false;

    const maybeAuthCallback =
      parsed.hostname.toLowerCase() === 'auth'
      || parsed.pathname.toLowerCase().includes('auth')
      || parsed.pathname.toLowerCase().includes('callback')
      || parsed.searchParams.has('code')
      || parsed.searchParams.has('error');

    if (!maybeAuthCallback) return false;

    const providerError = parsed.searchParams.get('error_description') || parsed.searchParams.get('error');
    if (providerError) {
      let providerMessage = providerError;
      try {
        providerMessage = decodeURIComponent(providerError);
      } catch {
        // Keep the raw provider message if it's not URI-encoded.
      }
      const error = new Error(providerMessage);
      this.rejectPendingGoogleSignIn(error);
      throw error;
    }

    const code = parsed.searchParams.get('code');
    if (!code) {
      const error = new Error('Google Sign-In callback was missing an authorization code.');
      this.rejectPendingGoogleSignIn(error);
      throw error;
    }

    const supabase = await this.getSupabase();
    const { data, error } = await supabase.auth.exchangeCodeForSession(code);
    if (error || !data.session || !data.user) {
      const exchangeError = new Error(error?.message ?? 'Failed to finish Google Sign-In session exchange.');
      this.rejectPendingGoogleSignIn(exchangeError);
      throw exchangeError;
    }

    this.session = data.session;
    await this.persistSession(data.session);
    this.resolvePendingGoogleSignIn({ user: data.user, accessToken: data.session.access_token });
    return true;
  }

  async signOut(): Promise<void> {
    if (this.supabase) {
      await this.supabase.auth.signOut().catch(() => undefined);
    }
    this.session = null;
    await unlink(getSessionPath()).catch(() => undefined);
  }

  private async refreshSessionLocked(supabase: SupabaseClient): Promise<Session | null> {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = (async () => {
      if (!this.session) return null;
      const { data, error } = await supabase.auth.refreshSession({
        refresh_token: this.session.refresh_token,
      });
      if (error || !data.session) {
        return null;
      }
      this.session = data.session;
      await this.persistSession(data.session);
      return data.session;
    })();

    try {
      return await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
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
      const refreshed = await this.refreshSessionLocked(supabase);
      if (!refreshed) return null;
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
