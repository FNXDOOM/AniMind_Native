import { app, shell } from 'electron';
import { mkdir, readFile, writeFile, unlink } from 'fs/promises';
import path from 'path';
import { createServer, IncomingMessage, ServerResponse, Server } from 'http';
import { settingsService } from './settings.service';

/**
 * auth.service.ts — Clerk FAPI edition
 *
 * Google OAuth flow:
 *   1. POST /v1/client/sign_ins  → creates a sign-in attempt, returns { id }
 *      We persist the __client cookie from the Set-Cookie header to maintain Clerk session state.
 *   2. POST /v1/client/sign_ins/{id}/prepare_first_factor
 *        body: { strategy: "oauth_google", redirect_url: "animind://auth/callback" }
 *      → returns { authorization_url }  (a real Google/Clerk OAuth URL)
 *   3. We open authorization_url in the system browser.
 *   4. After Google auth Clerk redirects to animind://auth/callback?rotating_token=...
 *   5. handleAuthCallback() calls GET /v1/client?rotating_token=...
 *      → gives us the full client object with sessions + JWTs.
 *   6. We persist the session token and resolve the pending promise.
 *
 * Email/password flow:
 *   1. POST /v1/client/sign_ins  (identifier)
 *   2. POST /v1/client/sign_ins/{id}/attempt_first_factor  (strategy: password)
 *   → client.sessions[0] contains the JWT.
 *
 * Token refresh:
 *   Clerk session JWTs are short-lived (~60 s). We call
 *   POST /v1/client/sessions/{sessionId}/tokens  to get a fresh JWT.
 *
 * Cookie management:
 *   Clerk FAPI is stateful — it uses a __client cookie to track the sign-in context.
 *   In Electron there is no browser cookie jar, so we extract Set-Cookie headers
 *   and send them back on subsequent requests manually.
 */

const BRIDGE_SERVER_PORT = 27182;
const CLERK_JS_VERSION = '5.35.0';

interface StoredClerkSession {
  /** Short-lived Clerk session JWT */
  accessToken: string;
  /** Clerk session ID — used to refresh the JWT */
  sessionId: string;
  /** Unix timestamp (ms) when the access token expires */
  expiresAt: number;
  userId: string;
  email?: string;
}

function getSessionPath(): string {
  return path.join(app.getPath('userData'), 'clerk-session.json');
}

function getCookieCachePath(): string {
  return path.join(app.getPath('userData'), 'clerk-cookies.json');
}

function nowMs(): number {
  return Date.now();
}

// ─── Cookie jar (in-memory + persisted) ──────────────────────────────────────

/** Simple per-domain cookie store keyed by name */
const cookieJar: Map<string, string> = new Map();

/** Clerk client ID extracted from response bodies (used as x-clerk-client-id header) */
let clerkClientId: string | null = null;

/** Extract and store client ID from Clerk response body */
function ingestClientId(data: Record<string, unknown>): void {
  // The client ID lives at response.id (for sign-in responses) or at the top-level id
  const id =
    (data as { response?: { id?: string } }).response?.id ??
    (data as { id?: string }).id ??
    null;
  if (id && typeof id === 'string' && id.startsWith('client_')) {
    clerkClientId = id;
    console.log('[Auth] captured clerkClientId:', clerkClientId);
  }
}

/** Parse Set-Cookie headers and store relevant Clerk cookies */
function ingestSetCookieHeaders(headers: Headers): void {
  // Try getSetCookie() first (Node 18+), fall back to iterating all headers
  let raw: string[] = [];
  if (typeof headers.getSetCookie === 'function') {
    raw = headers.getSetCookie();
  }
  // Fallback: some Electron builds don't expose getSetCookie - read raw header
  if (raw.length === 0) {
    const single = headers.get('set-cookie');
    if (single) {
      // If multiple cookies are collapsed into one header string, split safely on cookie boundaries.
      raw = single.split(/,(?=\s*[^;,=\s]+=[^;,]*)/g).map(v => v.trim()).filter(Boolean);
    }
  }
  // Last resort: iterate all header entries
  if (raw.length === 0) {
    headers.forEach((value, name) => {
      if (name.toLowerCase() === 'set-cookie') raw.push(value);
    });
  }
  console.log('[Auth] set-cookie headers found:', raw.length, raw);
  for (const header of raw) {
    const parts = header.split(';');
    const [nameValue] = parts;
    if (!nameValue) continue;
    const eqIdx = nameValue.indexOf('=');
    if (eqIdx < 0) continue;
    const name = nameValue.slice(0, eqIdx).trim();
    const value = nameValue.slice(eqIdx + 1).trim();
    // Keep all cookies returned by Clerk/edge providers (e.g. Cloudflare bot/session cookies).
    // Clerk auth flow is stateful across multiple requests and may depend on more than __client.
    if (!name || !value) continue;
    cookieJar.set(name, value);
  }
}

/** Build Cookie header string from jar */
function buildCookieHeader(): string {
  return [...cookieJar.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
}

async function persistCookies(): Promise<void> {
  try {
    const obj = Object.fromEntries(cookieJar.entries());
    await writeFile(getCookieCachePath(), JSON.stringify(obj), 'utf8');
  } catch { /* non-critical */ }
}

async function restoreCookies(): Promise<void> {
  try {
    const raw = await readFile(getCookieCachePath(), 'utf8');
    const obj = JSON.parse(raw) as Record<string, string>;
    for (const [k, v] of Object.entries(obj)) {
      cookieJar.set(k, v);
    }
  } catch { /* no cookies yet */ }
}

// ─── Shared FAPI fetch helper ──────────────────────────────────────────────

function clerkHeaders(extra?: Record<string, string>): Record<string, string> {
  const cookie = buildCookieHeader();
  return {
    'Content-Type': 'application/json',
    'x-clerk-js-version': CLERK_JS_VERSION,
    ...(cookie ? { Cookie: cookie } : {}),
    ...(clerkClientId ? { 'x-clerk-client-id': clerkClientId } : {}),
    ...extra,
  };
}

async function clerkGet(fapiUrl: string, urlPath: string, params?: Record<string, string>): Promise<Response> {
  const url = new URL(`${fapiUrl}${urlPath}`);
  if (params) {
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  }
  const res = await fetch(url.toString(), {
    method: 'GET',
    headers: clerkHeaders(),
  });
  ingestSetCookieHeaders(res.headers);
  const cloned = res.clone();
  cloned.json().then(ingestClientId).catch(() => undefined);
  await persistCookies();
  return res;
}

async function clerkPost(fapiUrl: string, urlPath: string, body: unknown): Promise<Response> {
  const res = await fetch(`${fapiUrl}${urlPath}`, {
    method: 'POST',
    headers: clerkHeaders(),
    body: JSON.stringify(body),
  });
  ingestSetCookieHeaders(res.headers);
  const cloned = res.clone();
  cloned.json().then(ingestClientId).catch(() => undefined);
  await persistCookies();
  return res;
}

async function clerkPostForm(
  fapiUrl: string,
  urlPath: string,
  body: Record<string, string>,
): Promise<Response> {
  const encoded = new URLSearchParams(body);
  const res = await fetch(`${fapiUrl}${urlPath}`, {
    method: 'POST',
    headers: clerkHeaders({ 'Content-Type': 'application/x-www-form-urlencoded' }),
    body: encoded.toString(),
  });
  ingestSetCookieHeaders(res.headers);
  const cloned = res.clone();
  cloned.json().then(ingestClientId).catch(() => undefined);
  await persistCookies();
  return res;
}

// ─── Response shape helpers ────────────────────────────────────────────────

interface ClerkSession {
  id?: string;
  status?: string;
  last_active_token?: { jwt?: string; expires_at?: number };
  user?: {
    id?: string;
    email_addresses?: Array<{ email_address?: string }>;
  };
}

interface ClerkClientResponse {
  meta?: {
    client?: {
      sessions?: ClerkSession[];
      sign_in?: {
        id?: string;
        created_session_id?: string;
        first_factor_verification?: {
          authorization_url?: string;
          external_verification_redirect_url?: string;
          status?: string;
        } | null;
      };
    };
  };
  id?: string;
  status?: string;
  created_session_id?: string;
  first_factor_verification?: {
    authorization_url?: string;
    external_verification_redirect_url?: string;
    status?: string;
  };
  sessions?: ClerkSession[];
  response?: {
    id?: string;
    status?: string;
    authorization_url?: string;
    external_verification_redirect_url?: string;
    created_session_id?: string;
    first_factor_verification?: {
      authorization_url?: string;
      external_verification_redirect_url?: string;
      status?: string;
    };
  };
  client?: {
    sessions?: ClerkSession[];
    sign_in?: {
      id?: string;
      status?: string;
      created_session_id?: string;
      first_factor_verification?: {
        authorization_url?: string;
        external_verification_redirect_url?: string;
      };
    };
  };
  errors?: Array<{ message?: string; long_message?: string; code?: string }>;
}

function formatClerkError(data: ClerkClientResponse, clerkFapiUrl: string): string {
  const err = data.errors?.[0];
  if (!err) return 'Clerk request failed';

  if (err.code === 'authorization_invalid') {
    return [
      err.long_message ?? err.message ?? 'Unauthorized request',
      `Clerk instance: ${clerkFapiUrl}`,
      'Check that your Clerk publishable key belongs to this exact instance and that Google OAuth is enabled on the same Clerk app.',
    ].join(' | ');
  }

  return err.long_message ?? err.message ?? 'Clerk request failed';
}

function hasClerkErrorCode(data: ClerkClientResponse, code: string): boolean {
  return data.errors?.some(err => err.code === code) ?? false;
}

function deriveAccountPortalSignInUrl(clerkFapiUrl: string, redirectUrl: string): string {
  const current = new URL(clerkFapiUrl);
  const host = current.hostname.startsWith('clerk.')
    ? current.hostname.replace(/^clerk\./, 'accounts.')
    : current.hostname.replace(/^([^.]*)\./, 'accounts.');
  const url = new URL(`https://${host}/sign-in`);
  url.searchParams.set('redirect_url', redirectUrl);
  return url.toString();
}

function extractSession(data: ClerkClientResponse, sessionId?: string): ClerkSession | undefined {
  const sessions = data.client?.sessions ?? data.sessions ?? data.meta?.client?.sessions ?? [];
  if (sessionId) {
    return sessions.find(s => s.id === sessionId) ?? sessions[0];
  }
  return sessions[0];
}

function extractSignInId(data: ClerkClientResponse): string | undefined {
  return data.id ?? data.response?.id ?? data.client?.sign_in?.id ?? data.meta?.client?.sign_in?.id;
}

function extractCreatedSessionId(data: ClerkClientResponse): string | undefined {
  return data.created_session_id ?? data.response?.created_session_id ?? data.client?.sign_in?.created_session_id ?? data.meta?.client?.sign_in?.created_session_id;
}

function extractAuthorizationUrl(data: ClerkClientResponse): string | undefined {
  return (
    data.first_factor_verification?.external_verification_redirect_url ??
    data.first_factor_verification?.authorization_url ??
    data.response?.first_factor_verification?.external_verification_redirect_url ??
    data.response?.first_factor_verification?.authorization_url ??
    data.response?.external_verification_redirect_url ??
    data.response?.authorization_url ??
    data.client?.sign_in?.first_factor_verification?.external_verification_redirect_url ??
    data.client?.sign_in?.first_factor_verification?.authorization_url ??
    data.meta?.client?.sign_in?.first_factor_verification?.external_verification_redirect_url ??
    data.meta?.client?.sign_in?.first_factor_verification?.authorization_url
  );
}

export class AuthService {
  private session: StoredClerkSession | null = null;
  private refreshPromise: Promise<StoredClerkSession | null> | null = null;

  /** Pending Google/OAuth sign-in promise and its resolvers */
  private pendingOAuth: {
    promise: Promise<{ userId: string; email?: string; accessToken: string }>;
    resolve: (v: { userId: string; email?: string; accessToken: string }) => void;
    reject: (r?: unknown) => void;
    timeout: ReturnType<typeof setTimeout>;
  } | null = null;

  // ─── Session persistence ───────────────────────────────────────────────────

  private async persist(session: StoredClerkSession): Promise<void> {
    const dir = app.getPath('userData');
    await mkdir(dir, { recursive: true });
    await writeFile(getSessionPath(), JSON.stringify(session, null, 2), 'utf8');
    this.session = session;
  }

  async restoreSession(): Promise<void> {
    // Restore cookies first so any refresh calls work
    await restoreCookies();
    try {
      const raw = await readFile(getSessionPath(), 'utf8');
      const stored = JSON.parse(raw) as StoredClerkSession;
      if (!stored.accessToken || !stored.userId) {
        this.session = null;
        return;
      }
      this.session = stored;
      // Refresh eagerly if expiring within 2 minutes
      if (stored.expiresAt - nowMs() < 120_000) {
        await this.refreshSession().catch(() => undefined);
      }
    } catch {
      this.session = null;
    }
  }

  // ─── Token refresh ─────────────────────────────────────────────────────────

  private async refreshSession(): Promise<StoredClerkSession | null> {
    if (this.refreshPromise) return this.refreshPromise;

    this.refreshPromise = (async (): Promise<StoredClerkSession | null> => {
      if (!this.session?.sessionId) return null;

      const settings = await settingsService.getSettings();
      const clerkFapiUrl = deriveClerkFapiUrl(settings.clerkPublishableKey);
      if (!clerkFapiUrl) return null;

      try {
        const res = await clerkPost(
          clerkFapiUrl,
          `/v1/client/sessions/${this.session.sessionId}/tokens`,
          {},
        );

        if (!res.ok) {
          this.session = null;
          await unlink(getSessionPath()).catch(() => undefined);
          return null;
        }

        const data = await res.json() as { jwt?: string; expires_at?: number; object?: string };
        const jwt = data.jwt;
        if (!jwt) return null;

        const next: StoredClerkSession = {
          accessToken: jwt,
          sessionId: this.session.sessionId,
          expiresAt: data.expires_at ? data.expires_at * 1000 : nowMs() + 55_000,
          userId: this.session.userId,
          email: this.session.email,
        };

        await this.persist(next);
        return next;
      } catch {
        return null;
      }
    })();

    try {
      return await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
  }

  // ─── Public: get a fresh access token ─────────────────────────────────────

  async getAccessToken(): Promise<string | null> {
    // If an OAuth flow is in progress, wait for it to complete
    if (this.pendingOAuth) {
      try {
        const result = await this.pendingOAuth.promise;
        return result.accessToken;
      } catch {
        return null;
      }
    }

    if (!this.session) await this.restoreSession();
    if (!this.session) return null;

    const isExpiring = this.session.expiresAt - nowMs() < 60_000;
    if (isExpiring) {
      const refreshed = await this.refreshSession();
      if (!refreshed) return null;
    }

    return this.session?.accessToken ?? null;
  }

  async getCurrentUser(): Promise<{ id: string; email?: string } | null> {
    const token = await this.getAccessToken();
    if (!token || !this.session) return null;
    return { id: this.session.userId, email: this.session.email };
  }

  async getSessionInfo(): Promise<{ userId: string; email?: string } | null> {
    const user = await this.getCurrentUser();
    if (!user) return null;
    return { userId: user.id, email: user.email };
  }

  // ─── Email / password sign-in ──────────────────────────────────────────────

  async signIn(
    email: string,
    password: string,
  ): Promise<{ userId: string; email?: string; accessToken: string }> {
    const settings = await settingsService.getSettings();
    const clerkFapiUrl = deriveClerkFapiUrl(settings.clerkPublishableKey);
    if (!clerkFapiUrl) {
      throw new Error('Clerk publishable key is not configured. Open Settings and add it.');
    }

    // Step 1: Initialize the client (creates __client cookie if not present)
    await this.ensureClientInitialized(clerkFapiUrl);

    // Step 2: Create sign-in attempt with identifier
    const attemptRes = await clerkPost(clerkFapiUrl, '/v1/client/sign_ins', { identifier: email });
    const attemptData = await attemptRes.json() as ClerkClientResponse;
    ingestClientId(attemptData as unknown as Record<string, unknown>);

    if (!attemptRes.ok) {
      throw new Error(formatClerkError(attemptData, clerkFapiUrl));
    }

    const signInId = extractSignInId(attemptData);
    if (!signInId) throw new Error('Could not initiate sign-in — no sign-in ID returned');

    // Step 3: Attempt first factor with password
    const completeRes = await clerkPost(
      clerkFapiUrl,
      `/v1/client/sign_ins/${signInId}/attempt_first_factor`,
      { strategy: 'password', password },
    );
    const completeData = await completeRes.json() as ClerkClientResponse;
    ingestClientId(completeData as unknown as Record<string, unknown>);

    if (!completeRes.ok) {
      const msg =
        formatClerkError(completeData, clerkFapiUrl) ??
        'Incorrect password';
      throw new Error(msg);
    }

    const createdSessionId = extractCreatedSessionId(completeData);
    const activeSession = extractSession(completeData, createdSessionId);

    const jwt = activeSession?.last_active_token?.jwt;
    const expiresAtSec = activeSession?.last_active_token?.expires_at;
    const userId = activeSession?.user?.id;
    const userEmail =
      activeSession?.user?.email_addresses?.[0]?.email_address ?? email;

    if (!jwt || !userId) throw new Error('Sign-in succeeded but no session token was returned');

    const stored: StoredClerkSession = {
      accessToken: jwt,
      sessionId: activeSession?.id ?? createdSessionId ?? '',
      expiresAt: expiresAtSec ? expiresAtSec * 1000 : nowMs() + 55_000,
      userId,
      email: userEmail,
    };

    await this.persist(stored);
    return { userId, email: userEmail, accessToken: jwt };
  }

  // ─── Ensure Clerk client is initialized (creates __client cookie) ──────────
  //
  // Clerk FAPI requires a __client cookie to be present for stateful flows.
  // Without it every request returns "Signed out". We initialize by calling
  // GET /v1/client which creates the cookie on first use.

  private async ensureClientInitialized(clerkFapiUrl: string, forceRefresh = false): Promise<void> {
    if (!forceRefresh && (cookieJar.has('__client') || clerkClientId)) return;
    // Clear any stale state before fresh init
    cookieJar.clear();
    clerkClientId = null;
    try {
      const res = await clerkGet(clerkFapiUrl, '/v1/client');
      console.log('[Auth] ensureClientInitialized status:', res.status, 'clientId:', clerkClientId, 'cookies:', [...cookieJar.keys()]);
    } catch (e) {
      console.warn('[Auth] ensureClientInitialized failed:', e);
    }
  }

  // ─── Google OAuth sign-in ──────────────────────────────────────────────────

  async signInWithGoogle(
    openExternal: (url: string) => Promise<void>,
  ): Promise<{ userId: string; email?: string; accessToken: string }> {
    if (this.pendingOAuth) {
      throw new Error('A Google sign-in is already in progress.');
    }

    const settings = await settingsService.getSettings();
    const clerkFapiUrl = deriveClerkFapiUrl(settings.clerkPublishableKey);
    if (!clerkFapiUrl) {
      throw new Error('Clerk publishable key is not configured. Open Settings and add it.');
    }
    console.log('[Auth] Google sign-in using Clerk FAPI:', clerkFapiUrl);

    let resolveFn!: (v: { userId: string; email?: string; accessToken: string }) => void;
    let rejectFn!: (r?: unknown) => void;

    const promise = new Promise<{ userId: string; email?: string; accessToken: string }>(
      (resolve, reject) => {
        resolveFn = resolve;
        rejectFn = reject;
      },
    );

    const timeout = setTimeout(() => {
      if (!this.pendingOAuth) return;
      this.pendingOAuth = null;
      rejectFn(new Error('Google Sign-In timed out after 3 minutes. Please try again.'));
    }, 180_000);

    this.pendingOAuth = { promise, resolve: resolveFn, reject: rejectFn, timeout };

    const openHostedSignInFallback = async (): Promise<{ userId: string; email?: string; accessToken: string }> => {
      const hostedUrl = deriveAccountPortalSignInUrl(clerkFapiUrl, 'animind://auth/callback');
      console.log('[Auth] Falling back to Clerk Account Portal sign-in:', hostedUrl);
      await openExternal(hostedUrl);
      return await promise;
    };

    // --- Step 1: Initialize the client to get __client cookie ---
    // Force a fresh client init for Google OAuth to avoid stale cookie issues
    await this.ensureClientInitialized(clerkFapiUrl, true);

    const providerRedirectUri = 'https://clerk.fnxdoom.in/v1/oauth_callback';
    const appCompleteRedirectUri = 'animind://auth/callback';

    // --- Step 2: Create OAuth sign-in attempt with strategy ---
    console.log('[Auth] Creating sign-in attempt, cookies:', [...cookieJar.keys()]);
    const createRes = await clerkPost(clerkFapiUrl, '/v1/client/sign_ins', {
      strategy: 'oauth_google',
      redirect_url: providerRedirectUri,
      action_complete_redirect_url: appCompleteRedirectUri,
    });
    const createData = await createRes.json() as ClerkClientResponse;
    ingestClientId(createData as unknown as Record<string, unknown>);
    console.log('[Auth] sign_ins response status:', createRes.status, 'errors:', createData.errors);

    if (!createRes.ok) {
      if (hasClerkErrorCode(createData, 'authorization_invalid')) {
        return await openHostedSignInFallback();
      }
      const errMsg = formatClerkError(createData, clerkFapiUrl) ?? 'Failed to create Google sign-in attempt';
      throw new Error(errMsg);
    }

    const signInId = extractSignInId(createData);
    if (!signInId) {
      throw new Error('No sign-in ID returned from Clerk. Check your Clerk publishable key.');
    }

    // Newer Clerk responses can include OAuth redirect directly on sign-in create.
    // Check both top-level and nested shapes before continuing the first-factor flow.
    let authorizationUrl = extractAuthorizationUrl(createData);

    if (!authorizationUrl) {
      const prepareRes = await clerkPostForm(
        clerkFapiUrl,
        `/v1/client/sign_ins/${signInId}/prepare_first_factor`,
        {
          strategy: 'oauth_google',
          redirect_url: providerRedirectUri,
          action_complete_redirect_url: appCompleteRedirectUri,
        },
      );
      const prepareData = await prepareRes.json() as ClerkClientResponse;
      ingestClientId(prepareData as unknown as Record<string, unknown>);

      if (!prepareRes.ok) {
        if (hasClerkErrorCode(prepareData, 'authorization_invalid')) {
          return await openHostedSignInFallback();
        }
        const errMsg = formatClerkError(prepareData, clerkFapiUrl) ?? 'Failed to prepare Google OAuth';
        throw new Error(`${errMsg} | prepare response: ${JSON.stringify(prepareData)}`);
      }

      authorizationUrl = extractAuthorizationUrl(prepareData);
    }

    if (!authorizationUrl) {
      console.error('[Auth] create_sign_in response:', JSON.stringify(createData, null, 2));
      throw new Error(
        `Clerk did not return an authorization URL. Response: ${JSON.stringify(createData)}`,
      );
    }

    try {
      await openExternal(authorizationUrl);
      return await promise;
    } catch (err) {
      this.pendingOAuth = null;
      clearTimeout(timeout);
      throw err;
    }
  }

  async signInBrowserBridge(
    openExternal: (url: string) => Promise<void>,
  ): Promise<{ userId: string; email?: string; accessToken: string }> {
    if (this.pendingOAuth) {
      throw new Error('A Google sign-in is already in progress.');
    }

    const settings = await settingsService.getSettings();
    const clerkFapiUrl = deriveClerkFapiUrl(settings.clerkPublishableKey);
    if (!clerkFapiUrl) {
      throw new Error('Clerk publishable key is not configured.');
    }

    let resolveFn!: (v: { userId: string; email?: string; accessToken: string }) => void;
    let rejectFn!: (r?: unknown) => void;

    const promise = new Promise<{ userId: string; email?: string; accessToken: string }>(
      (resolve, reject) => {
        resolveFn = resolve;
        rejectFn = reject;
      },
    );

    const timeout = setTimeout(() => {
      if (!this.pendingOAuth) return;
      this.pendingOAuth = null;
      rejectFn(new Error('Sign-In timed out after 3 minutes. Please try again.'));
    }, 180_000);

    this.pendingOAuth = { promise, resolve: resolveFn, reject: rejectFn, timeout };

    const server = await this.startBridgeServer();

    try {
      // Primary strategy: Redirect the browser to the website's auth bridge page.
      // That page will capture the Clerk token and then redirect the browser TO:
      // http://localhost:27182/auth?token=<jwt>
      const websiteBridgeUrl = 'https://fnxdoom.in/desktop-auth';
      const hostedUrl = deriveAccountPortalSignInUrl(clerkFapiUrl, websiteBridgeUrl);
      
      console.log('[Auth] Opening browser bridge via:', hostedUrl);
      await openExternal(hostedUrl);
      return await promise;
    } finally {
      server.close();
    }
  }

  private async startBridgeServer(): Promise<Server> {
    return new Promise((resolve) => {
      const server = createServer((req, res) => {
        const url = new URL(req.url ?? '', `http://localhost:${BRIDGE_SERVER_PORT}`);
        
        // Handle both /auth (direct token) and /callback (rotating token)
        const isAuth = url.pathname.includes('auth') || url.pathname.includes('callback');
        
        if (isAuth) {
          const directToken = url.searchParams.get('token');
          if (directToken) {
            // Case 1: Direct session JWT delivery (from website bridge)
            this.handleDirectToken(directToken)
              .then(() => {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end('<html><body><h1>Success</h1><p>Authenticated! You can close this window now.</p></body></html>');
              })
              .catch((err) => {
                res.writeHead(500, { 'Content-Type': 'text/html' });
                res.end(`<html><body><h1>Error</h1><p>${err.message}</p></body></html>`);
              });
          } else {
            // Case 2: Standard rotating token callback
            const callbackUrl = `animind://auth/callback${url.search}`;
            this.handleAuthCallback(callbackUrl)
              .then(() => {
                res.writeHead(200, { 'Content-Type': 'text/html' });
                res.end('<html><body><h1>Success</h1><p>Authenticated! You can close this window now.</p></body></html>');
              })
              .catch((err) => {
                res.writeHead(500, { 'Content-Type': 'text/html' });
                res.end(`<html><body><h1>Error</h1><p>${err.message}</p></body></html>`);
              });
          }
        } else {
          res.writeHead(404);
          res.end();
        }
      });
      server.listen(BRIDGE_SERVER_PORT, () => resolve(server));
    });
  }

  /** Handle direct JWT delivery (skips rotating_token exchange) */
  private async handleDirectToken(token: string): Promise<void> {
    const settings = await settingsService.getSettings();
    const clerkFapiUrl = deriveClerkFapiUrl(settings.clerkPublishableKey);
    if (!clerkFapiUrl) throw new Error('Clerk not configured.');

    // Step 1: Decode the JWT locally to get userId and sessionId
    // JWT format: header.payload.signature
    let payload: any = {};
    try {
      const parts = token.split('.');
      if (parts.length !== 3) throw new Error('Invalid token format');
      const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const json = Buffer.from(base64, 'base64').toString('utf8');
      payload = JSON.parse(json);
    } catch (err) {
      console.error('[Auth] Failed to decode JWT:', err);
      throw new Error('Invalid session token delivered.');
    }

    const userId = payload.sub || payload.user_id || payload.userId;
    let sessionId = payload.sid || payload.session_id || payload.sessionId;
    const expiresAt = (payload.exp || payload.expires_at) ? (payload.exp || payload.expires_at) * 1000 : nowMs() + 55_000;

    if (!userId) {
      console.error('[Auth] Decoded payload missing userId (sub):', payload);
      throw new Error('Token delivered but userId (sub) is missing.');
    }

    // Step 2: Persist the session
    // We try to fetch the client object to get the sessionId (if missing from JWT) and email.
    let email: string | undefined;
    try {
      await this.ensureClientInitialized(clerkFapiUrl);
      const clientRes = await clerkGet(clerkFapiUrl, '/v1/client');
      const clientData = await clientRes.json() as ClerkClientResponse;
      if (clientRes.ok) {
        // If sessionId was missing from JWT, find the first active session for this user
        const activeSession = extractSession(clientData, sessionId);
        if (activeSession) {
          sessionId = activeSession.id;
          email = activeSession.user?.email_addresses?.[0]?.email_address;
        }
      }
    } catch (err) {
      console.warn('[Auth] Failed to fetch client info to resolve sessionId/email:', err);
    }

    if (!sessionId) {
      // Fallback: if we still don't have a sessionId, we can't refresh but we can 
      // at least try to use the current token until it expires.
      // However, most Clerk flows expect a session ID.
      console.warn('[Auth] No sessionId found in JWT or client response. Refresh may fail.');
      sessionId = `temp_${Date.now()}`; 
    }

    const stored: StoredClerkSession = {
      accessToken: token,
      sessionId,
      expiresAt,
      userId,
      email,
    };

    await this.persist(stored);

    if (this.pendingOAuth) {
      const p = this.pendingOAuth;
      this.pendingOAuth = null;
      clearTimeout(p.timeout);
      p.resolve({ userId, email, accessToken: token });
    }
  }

  // ─── OAuth callback handler (called from deep link in index.ts) ───────────
  //
  // Clerk redirects to: animind://auth/callback?rotating_token=<token>
  // We then call GET /v1/client?rotating_token=<token> to get the session.

  async handleAuthCallback(callbackUrl: string): Promise<boolean> {
    let parsed: URL;
    try {
      parsed = new URL(callbackUrl);
    } catch {
      return false;
    }

    if (parsed.protocol !== 'animind:') return false;

    const isAuthPath =
      parsed.hostname.toLowerCase() === 'auth' ||
      parsed.pathname.toLowerCase().includes('callback') ||
      parsed.pathname.toLowerCase().includes('auth');

    if (!isAuthPath) return false;

    // Handle explicit errors from Clerk/Google
    const providerError =
      parsed.searchParams.get('error_description') ??
      parsed.searchParams.get('error');
    if (providerError) {
      let msg = providerError;
      try { msg = decodeURIComponent(providerError); } catch { /* keep raw */ }
      const err = new Error(msg);
      this.rejectPendingOAuth(err);
      throw err;
    }

    // Clerk passes a rotating_token after successful OAuth
    const rotatingToken =
      parsed.searchParams.get('rotating_token') ??
      parsed.searchParams.get('rotating_token_nonce');

    if (!rotatingToken) {
      console.warn('[Auth] Callback received but no rotating_token found:', callbackUrl);
      return false;
    }

    const settings = await settingsService.getSettings();
    const clerkFapiUrl = deriveClerkFapiUrl(settings.clerkPublishableKey);
    if (!clerkFapiUrl) {
      const err = new Error('Clerk is not configured. Cannot complete OAuth.');
      this.rejectPendingOAuth(err);
      throw err;
    }

    try {
      // GET /v1/client?rotating_token=...  — fetches the authenticated client object
      const clientRes = await clerkGet(clerkFapiUrl, '/v1/client', { rotating_token: rotatingToken });
      const clientData = await clientRes.json() as ClerkClientResponse;
      ingestClientId(clientData as unknown as Record<string, unknown>);

      if (!clientRes.ok) {
        throw new Error(formatClerkError(clientData, clerkFapiUrl));
      }

      const activeSession = extractSession(clientData);
      const jwt = activeSession?.last_active_token?.jwt;
      const userId = activeSession?.user?.id;
      const email = activeSession?.user?.email_addresses?.[0]?.email_address;

      if (!jwt || !userId) {
        throw new Error('OAuth completed but no session token was returned from Clerk.');
      }

      const expiresAtSec = activeSession?.last_active_token?.expires_at;
      const stored: StoredClerkSession = {
        accessToken: jwt,
        sessionId: activeSession?.id ?? '',
        expiresAt: expiresAtSec ? expiresAtSec * 1000 : nowMs() + 55_000,
        userId,
        email,
      };

      await this.persist(stored);

      if (this.pendingOAuth) {
        const p = this.pendingOAuth;
        this.pendingOAuth = null;
        clearTimeout(p.timeout);
        p.resolve({ userId, email, accessToken: jwt });
      }

      return true;
    } catch (err) {
      this.rejectPendingOAuth(err);
      throw err;
    }
  }

  private rejectPendingOAuth(err: unknown): void {
    if (!this.pendingOAuth) return;
    const p = this.pendingOAuth;
    this.pendingOAuth = null;
    clearTimeout(p.timeout);
    p.reject(err);
  }

  // ─── Sign out ──────────────────────────────────────────────────────────────

  async signOut(): Promise<void> {
    this.session = null;
    cookieJar.clear();
    await unlink(getSessionPath()).catch(() => undefined);
    await unlink(getCookieCachePath()).catch(() => undefined);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Derives the Clerk Frontend API base URL from a publishable key.
 *
 * pk_test_<base64url>  or  pk_live_<base64url>
 * The base64url encodes the FAPI hostname followed by "$".
 */
export function deriveClerkFapiUrl(publishableKey: string): string | null {
  if (!publishableKey) return null;

  try {
    const prefix = publishableKey.startsWith('pk_test_')
      ? 'pk_test_'
      : publishableKey.startsWith('pk_live_')
      ? 'pk_live_'
      : null;

    if (!prefix) return null;

    const encoded = publishableKey.slice(prefix.length);
    const padded = encoded + '='.repeat((4 - (encoded.length % 4)) % 4);
    const decoded = Buffer.from(padded, 'base64').toString('utf8');
    const domain = decoded.replace(/\$$/, '').trim();
    if (!domain) return null;

    return `https://${domain}`;
  } catch {
    return null;
  }
}

export const authService = new AuthService();
