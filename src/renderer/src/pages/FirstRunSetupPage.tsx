import React, { useMemo, useState } from 'react';
import type { AppSettings, MpvAvailability, SetupStatus } from '../types';

type Props = {
  initialStatus: SetupStatus;
  onSave: (settings: AppSettings) => Promise<SetupStatus>;
  onProbeMpv: (mpvPath: string) => Promise<MpvAvailability>;
};

export function FirstRunSetupPage({ initialStatus, onSave, onProbeMpv }: Props) {
  const [settings, setSettings] = useState<AppSettings>(initialStatus.settings);
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState<SetupStatus>(initialStatus);
  const [info, setInfo] = useState('');

  const missing = useMemo(() => status.missing, [status]);

  return (
    <div className="center-screen">
      <div className="panel setup-panel">
        <h1>First-Time Setup</h1>
        <p className="muted">
          Configure backend, Supabase, and mpv before using Animind Desktop.
        </p>

        <label>
          Backend URL
          <input
            value={settings.backendUrl}
            onChange={e => setSettings(s => ({ ...s, backendUrl: e.target.value }))}
            placeholder="http://localhost:3000"
          />
        </label>

        <label>
          Supabase URL
          <input
            value={settings.supabaseUrl}
            onChange={e => setSettings(s => ({ ...s, supabaseUrl: e.target.value }))}
            placeholder="https://xxx.supabase.co"
          />
        </label>

        <label>
          Supabase Anon Key
          <input
            value={settings.supabaseAnonKey}
            onChange={e => setSettings(s => ({ ...s, supabaseAnonKey: e.target.value }))}
            placeholder="eyJ..."
          />
        </label>

        <label>
          mpv Path
          <input
            value={settings.mpvPath}
            onChange={e => setSettings(s => ({ ...s, mpvPath: e.target.value }))}
            placeholder="mpv or C:\\Program Files\\mpv\\mpv.exe"
          />
        </label>

        <div className="row gap-sm wrap">
          <button
            onClick={async () => {
              setInfo('Probing mpv...');
              const result = await onProbeMpv(settings.mpvPath);
              setStatus(prev => ({ ...prev, mpv: result }));
              setInfo(result.available ? `mpv detected: ${result.version ?? result.path}` : `mpv unavailable: ${result.error ?? 'Unknown error'}`);
            }}
          >
            Test mpv
          </button>

          <button
            disabled={saving}
            onClick={async () => {
              setSaving(true);
              setInfo('Saving settings and validating setup...');
              try {
                const next = await onSave(settings);
                setStatus(next);
                setInfo(next.ready ? 'Setup complete. Continue to sign in.' : 'Setup still incomplete. Resolve missing values below.');
              } catch (err: any) {
                setInfo(err?.message ?? 'Failed to save settings.');
              } finally {
                setSaving(false);
              }
            }}
          >
            {saving ? 'Saving...' : 'Save & Validate'}
          </button>
        </div>

        {missing.length > 0 ? (
          <div className="error">
            Missing settings: {missing.join(', ')}
          </div>
        ) : null}

        {status.mpv.available ? (
          <div className="success">mpv available: {status.mpv.version ?? status.mpv.path}</div>
        ) : (
          <div className="error">mpv check: {status.mpv.error ?? 'Not checked yet.'}</div>
        )}

        {info ? <p className="muted">{info}</p> : null}
      </div>
    </div>
  );
}
