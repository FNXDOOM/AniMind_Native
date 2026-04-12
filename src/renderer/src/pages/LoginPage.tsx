import React, { useState } from 'react';

type Props = {
  onSubmit: (email: string, password: string) => Promise<void>;
  error: string;
};

export function LoginPage({ onSubmit, error }: Props) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);

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
          <button className="primary-btn" type="submit" disabled={loading}>{loading ? 'Signing in...' : 'Sign In'}</button>
        </form>
        {error ? <div className="error">{error}</div> : null}
      </div>
    </div>
  );
}
