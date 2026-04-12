import React, { useEffect, useState } from 'react';
import type { AppSettings } from '../types';

type Props = {
  onLoad: () => Promise<AppSettings>;
  onSave: (next: AppSettings) => Promise<unknown>;
};

export function SettingsPage({ onLoad, onSave }: Props) {
  const [settings, setSettings] = useState<AppSettings>({
    backendUrl: '',
    supabaseUrl: '',
    supabaseAnonKey: '',
    mpvPath: 'mpv',
  });
  const [status, setStatus] = useState('');

  useEffect(() => {
    void onLoad().then(setSettings).catch(err => setStatus(err?.message ?? 'Failed to load settings'));
  }, [onLoad]);

  return (
    <div className="panel settings-panel">
      <h2>Settings</h2>
      <p className="muted">Configure backend, Supabase, and native mpv executable path.</p>

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
        />
      </label>

      <label>
        Supabase Anon Key
        <input
          value={settings.supabaseAnonKey}
          onChange={e => setSettings(s => ({ ...s, supabaseAnonKey: e.target.value }))}
        />
      </label>

      <label>
        mpv Path
        <input
          value={settings.mpvPath}
          onChange={e => setSettings(s => ({ ...s, mpvPath: e.target.value }))}
          placeholder="mpv"
        />
      </label>

      <div className="row gap-sm">
        <button
          className="primary-btn"
          onClick={async () => {
            setStatus('Saving...');
            try {
              await onSave(settings);
              setStatus('Saved. Restart app to ensure all settings are reloaded.');
            } catch (err: any) {
              setStatus(err?.message ?? 'Failed to save settings');
            }
          }}
        >
          Save Settings
        </button>
      </div>

      {status ? <p className="muted">{status}</p> : null}
    </div>
  );
}
