import React, { useState } from 'react';
import { desktopApi } from '../api';

type Props = {
  onSignedIn: (userId: string, accessToken: string) => void;
};

export function LoginPage({ onSignedIn }: Props) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    setError('');
    setLoading(true);
    try {
      await desktopApi.signInBrowserBridge();
      const session = await desktopApi.getSession();
      if (!session?.userId) throw new Error('Sign-in did not complete. Please try again.');
      onSignedIn(session.userId, '');
    } catch (err: any) {
      setError(err?.message ?? 'Login failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'var(--bg)',
    }}>
      <div style={{
        width: '100%',
        maxWidth: 420,
        padding: '40px 36px',
        background: 'var(--bento-bg)',
        border: '1px solid var(--bento-border)',
        borderRadius: 18,
        boxShadow: '0 24px 64px rgba(0,0,0,0.5)',
      }}>
        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <p style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.12em', textTransform: 'uppercase', color: 'var(--accent)', marginBottom: 10 }}>
            Animind Desktop
          </p>
          <h1 style={{ fontSize: 26, fontWeight: 700, margin: '0 0 8px', color: 'var(--text)' }}>
            Welcome back
          </h1>
          <p style={{ fontSize: 14, color: 'var(--muted)', margin: 0 }}>
            Sign in to your account to continue
          </p>
        </div>

        {/* Sign In button */}
        <button
          id="login-submit"
          className="primary-btn"
          style={{ width: '100%', padding: '13px', fontSize: 15 }}
          disabled={loading}
          onClick={() => void handleSubmit()}
        >
          {loading ? 'Opening sign-in...' : 'Sign In with Email & Password'}
        </button>

        {/* Error */}
        {error && (
          <div style={{
            marginTop: 16,
            padding: '12px 14px',
            background: 'rgba(248,113,113,0.08)',
            border: '1px solid rgba(248,113,113,0.25)',
            borderRadius: 10,
            fontSize: 13,
            color: '#f87171',
            lineHeight: 1.55,
          }}>
            {error}
          </div>
        )}

        <p style={{ textAlign: 'center', fontSize: 12, color: 'var(--muted)', marginTop: 24 }}>
          Don&apos;t have an account?{' '}
          <a
            href="https://fnxdoom.in/sign-up"
            target="_blank"
            rel="noreferrer"
            style={{ color: 'var(--accent)', textDecoration: 'none' }}
          >
            Sign up on fnxdoom.in
          </a>
        </p>
      </div>
    </div>
  );
}


