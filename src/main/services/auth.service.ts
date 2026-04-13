import { app, shell } from 'electron';
import http from 'http';
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

  async signInWithGoogle(): Promise<{ user: User; accessToken: string }> {
    const supabase = await this.getSupabase();
    
    return new Promise((resolve, reject) => {
      let server: http.Server | null = null;
      let isSettled = false;

      const cleanup = () => {
        if (server) {
          server.close();
          server = null;
        }
      };

      const finish = (result: { user: User; accessToken: string }) => {
        if (isSettled) return;
        isSettled = true;
        resolve(result);
        cleanup();
      };

      const fail = (error: any) => {
        if (isSettled) return;
        isSettled = true;
        reject(error);
        cleanup();
      };

      server = http.createServer((req, res) => {
        try {
          const url = new URL(req.url || '/', 'http://localhost:43210');
          
          if (url.pathname === '/callback') {
            res.writeHead(200, { 'Content-Type': 'text/html' });
            res.end(`
              <!DOCTYPE html>
              <html lang="en">
              <head>
                <meta charset="UTF-8">
                <title>Authentication Completed</title>
                <style>
                  body { font-family: system-ui, -apple-system, sans-serif; background: #0b0f19; color: #fff; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; }
                  .container { text-align: center; padding: 40px; background: #111827; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); border: 1px solid rgba(255,255,255,0.1); }
                  h1 { margin-bottom: 12px; color: #10c996; font-size: 24px; }
                  p { color: #a1a1aa; font-size: 16px; margin: 0; }
                </style>
              </head>
              <body>
                <div class="container">
                  <h1>Animind Desktop</h1>
                  <p>Authentication processed successfully.</p>
                  <p style="font-weight: bold; margin-top: 20px; color: #fff;">You can now safely close this browser window.</p>
                </div>
                <script>
                  fetch('http://localhost:43210/exchange', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ hash: window.location.hash.substring(1) })
                  }).catch(console.error);
                </script>
              </body>
              </html>
            `);
          } else if (url.pathname === '/exchange' && req.method === 'POST') {
            let body = '';
            req.on('data', chunk => { body += chunk.toString(); });
            req.on('end', async () => {
              try {
                res.setHeader('Access-Control-Allow-Origin', '*');
                const parsed = JSON.parse(body);
                const hashParams = new URLSearchParams(parsed.hash);
                
                const accessToken = hashParams.get('access_token');
                const refreshToken = hashParams.get('refresh_token');

                if (!accessToken || !refreshToken) {
                  res.writeHead(400);
                  res.end('Missing tokens');
                  fail(new Error('Tokens missing from callback'));
                  return;
                }

                const { data, error } = await supabase.auth.setSession({ access_token: accessToken, refresh_token: refreshToken });
                
                if (error || !data.user || !data.session) {
                  res.writeHead(400);
                  res.end('Session failed');
                  fail(new Error(error?.message ?? 'Failed to finalize session'));
                  return;
                }

                this.session = data.session;
                await this.persistSession(data.session);

                res.writeHead(200);
                res.end('OK');
                
                finish({ user: data.user, accessToken: data.session.access_token });
              } catch (e) {
                console.error('[AuthServer] Exchange error:', e);
                res.writeHead(500);
                res.end('Internal error');
                fail(e);
              }
            });
          } else {
            res.writeHead(404);
            res.end();
          }
        } catch (err) {
          fail(err);
        }
      });

      server.on('error', err => fail(err));

      server.listen(43210, async () => {
        const { data, error } = await supabase.auth.signInWithOAuth({
          provider: 'google',
          options: { redirectTo: 'http://localhost:43210/callback', skipBrowserRedirect: true },
        });

        if (error || !data.url) {
          fail(new Error(error?.message ?? 'OAuth initialization failed'));
          return;
        }

        await shell.openExternal(data.url);
      });
    });
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
