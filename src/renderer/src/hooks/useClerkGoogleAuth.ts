/**
 * useClerkGoogleAuth.ts
 *
 * Loads Clerk JS inside the renderer (real Chromium context with cookies/storage),
 * drives the Google OAuth flow, and once complete passes the signed OAuth URL
 * to the caller so main can open it in the system browser.
 *
 * CDN instantiation — the clerk.browser.js CDN build auto-initialises itself
 * from the data-clerk-publishable-key attribute on its own <script> tag.
 * After the script loads, window.Clerk is the already-keyed singleton instance;
 * call window.Clerk.load() to finish initialisation.
 */

import { useCallback, useEffect, useRef, useState } from 'react';

const CLERK_JS_VERSION = '5.35.1';
const CLERK_JS_CDN = `https://unpkg.com/@clerk/clerk-js@${CLERK_JS_VERSION}/dist/clerk.browser.js`;
const SCRIPT_ID = 'clerk-browser-js';

// Minimal types for what we use from @clerk/clerk-js CDN build
interface ClerkSignIn {
  create(params: {
    strategy: string;
    redirectUrl: string;
    actionCompleteRedirectUrl: string;
  }): Promise<{ externalVerificationRedirectURL?: string | URL }>;
}

interface ClerkInstance {
  load(opts?: Record<string, unknown>): Promise<void>;
  client?: { signIn: ClerkSignIn };
}

type Status = 'idle' | 'loading-sdk' | 'ready' | 'pending-oauth' | 'error';

interface UseClerkGoogleAuthOptions {
  publishableKey: string;
  onRedirectUrl: (url: string) => Promise<void> | void;
}

export interface UseClerkGoogleAuthResult {
  status: Status;
  error: string;
  startGoogleOAuth: () => Promise<void>;
}

export function useClerkGoogleAuth({
  publishableKey,
  onRedirectUrl,
}: UseClerkGoogleAuthOptions): UseClerkGoogleAuthResult {
  const [status, setStatus] = useState<Status>('idle');
  const [error, setError] = useState('');
  const clerkRef = useRef<ClerkInstance | null>(null);
  const loadedKeyRef = useRef('');
  const loadingRef = useRef(false);

  useEffect(() => {
    if (!publishableKey) return;
    if (loadedKeyRef.current === publishableKey) return;
    if (loadingRef.current) return;

    loadingRef.current = true;
    setStatus('loading-sdk');
    setError('');

    const initClerk = async () => {
      try {
        // Remove any previously injected script so we can re-inject with the
        // correct data-clerk-publishable-key if the key changed.
        const existing = document.getElementById(SCRIPT_ID);
        if (existing) existing.remove();

        await injectClerkScript(publishableKey);

        // After the script loads, window.Clerk is the singleton already keyed
        // via data-clerk-publishable-key — just call .load() on it.
        const clerk = (window as any).Clerk as ClerkInstance | undefined;
        if (!clerk || typeof clerk.load !== 'function') {
          throw new Error('Clerk JS did not expose window.Clerk after loading');
        }

        await clerk.load();
        clerkRef.current = clerk;
        loadedKeyRef.current = publishableKey;
        setStatus('ready');
        console.log('[ClerkAuth] Clerk JS initialised successfully');
      } catch (err: any) {
        console.error('[ClerkAuth] Failed to initialise Clerk JS:', err);
        setError(err?.message ?? 'Failed to load authentication SDK');
        setStatus('error');
        loadedKeyRef.current = '';
      } finally {
        loadingRef.current = false;
      }
    };

    void initClerk();
  }, [publishableKey]);

  const startGoogleOAuth = useCallback(async () => {
    setError('');

    if (status === 'loading-sdk') {
      setError('Authentication SDK is still loading — please wait a moment.');
      return;
    }

    const clerk = clerkRef.current;
    if (!clerk?.client?.signIn) {
      setError('Authentication SDK is not ready. Please try again.');
      return;
    }

    setStatus('pending-oauth');

    try {
      const redirectUrl = 'animind://auth/callback';
      const result = await clerk.client.signIn.create({
        strategy: 'oauth_google',
        redirectUrl,
        actionCompleteRedirectUrl: redirectUrl,
      });

      const oauthUrl = result.externalVerificationRedirectURL;
      if (!oauthUrl) {
        throw new Error(
          'Clerk did not return an OAuth redirect URL. ' +
          'Ensure Google OAuth is enabled in your Clerk dashboard and that ' +
          '"animind://auth/callback" is listed as an allowed redirect URI.'
        );
      }

      const urlString = oauthUrl instanceof URL ? oauthUrl.toString() : String(oauthUrl);
      console.log('[ClerkAuth] OAuth URL obtained, opening system browser');
      await onRedirectUrl(urlString);
      // Stay in pending-oauth — deep-link → auth:session-changed will resolve this
    } catch (err: any) {
      console.error('[ClerkAuth] OAuth error:', err);
      const msg =
        err?.errors?.[0]?.long_message ??
        err?.errors?.[0]?.message ??
        err?.message ??
        'Google sign-in failed';
      setError(msg);
      setStatus('ready');
    }
  }, [status, onRedirectUrl]);

  return { status, error, startGoogleOAuth };
}

/**
 * Injects the Clerk browser JS CDN script with the publishable key set as a
 * data attribute. The CDN build reads this attribute on load and self-initialises
 * window.Clerk as the keyed singleton — no `new Clerk(key)` call needed.
 */
function injectClerkScript(publishableKey: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.id = SCRIPT_ID;
    script.src = CLERK_JS_CDN;
    script.async = true;
    script.crossOrigin = 'anonymous';
    // This is the key line — tells the CDN bundle which key to use on self-init
    script.setAttribute('data-clerk-publishable-key', publishableKey);
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load Clerk JS from CDN: ${CLERK_JS_CDN}`));
    document.head.appendChild(script);
  });
}

