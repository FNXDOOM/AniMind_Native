import React, { useState } from 'react';

type Props = {
  onSubmit: (email: string, password: string) => Promise<void>;
  onGoogleSignIn: () => Promise<void>;
  error: string;
};

export function LoginPage({ onSubmit, onGoogleSignIn, error }: Props) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);

  return (
    <div className="center-screen">
      <div className="panel auth-panel">
        <h1>Animind Desktop</h1>
        <p className="muted">Sign in with your existing Animind account.</p>
        <form
          className="form-grid"
          onSubmit={async e => {
            e.preventDefault();
            setLoading(true);
            try {
              await onSubmit(email, password);
            } finally {
              setLoading(false);
            }
          }}
        >
          <label>
            Email
            <input value={email} onChange={e => setEmail(e.target.value)} type="email" required />
          </label>
          <label>
            Password
            <input value={password} onChange={e => setPassword(e.target.value)} type="password" required />
          </label>
          <button className="primary-btn" type="submit" disabled={loading || googleLoading}>
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <div style={{ margin: '20px 0', textAlign: 'center', position: 'relative' }}>
          <div style={{ borderTop: '1px solid var(--bento-border)', position: 'absolute', top: '50%', width: '100%', zIndex: 0 }}></div>
          <span style={{ position: 'relative', zIndex: 1, background: 'var(--bg-2)', padding: '0 10px', color: 'var(--muted)', fontSize: 13 }}>OR</span>
        </div>

        <button 
          className="ghost-btn" 
          onClick={async () => {
            setGoogleLoading(true);
            try {
              await onGoogleSignIn();
            } finally {
              setGoogleLoading(false);
            }
          }}
          disabled={loading || googleLoading}
          style={{ 
            width: '100%', 
            outline: '1px solid var(--bento-border)', 
            padding: '12px', 
            borderRadius: 8, 
            color: 'var(--text)',
            gap: 12
          }}
        >
          <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="currentColor">
            <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
            <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
            <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
            <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
          </svg>
          {googleLoading ? 'Check your browser...' : 'Sign in with Google'}
        </button>

        {error ? <div className="error" style={{ marginTop: 16 }}>{error}</div> : null}
      </div>
    </div>
  );
}
