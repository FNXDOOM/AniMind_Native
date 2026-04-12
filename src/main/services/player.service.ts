import { ChildProcessWithoutNullStreams, spawn } from 'child_process';
import net from 'net';
import { randomUUID } from 'crypto';
import { settingsService } from './settings.service';

export interface MpvTrack {
  id: number;
  type: 'audio' | 'sub' | 'video' | string;
  title?: string;
  lang?: string;
  codec?: string;
  selected?: boolean;
}

export interface PlayerState {
  paused: boolean;
  timePos: number;
  duration: number;
}

export class PlayerService {
  private mpvProcess: ChildProcessWithoutNullStreams | null = null;
  private pipePath: string | null = null;

  private async getMpvPath(): Promise<string> {
    const settings = await settingsService.getSettings();
    return settings.mpvPath || 'mpv';
  }

  private createPipePath(): string {
    const id = randomUUID();
    return process.platform === 'win32'
      ? `\\\\.\\pipe\\animind-mpv-${id}`
      : `/tmp/animind-mpv-${id}.sock`;
  }

  private async waitForPipeReady(timeoutMs = 5000): Promise<void> {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      try {
        await this.sendRaw({ command: ['get_property', 'pause'] });
        return;
      } catch {
        await new Promise(resolve => setTimeout(resolve, 150));
      }
    }
    throw new Error('mpv IPC pipe did not become ready in time.');
  }

  private async sendRaw(command: Record<string, unknown>): Promise<any> {
    if (!this.pipePath) {
      throw new Error('Player is not running.');
    }

    return await new Promise((resolve, reject) => {
      const socket = net.createConnection(this.pipePath!, () => {
        socket.write(`${JSON.stringify(command)}\n`);
      });

      let buffer = '';
      socket.on('data', chunk => {
        buffer += chunk.toString('utf8');
        const lineEnd = buffer.indexOf('\n');
        if (lineEnd >= 0) {
          const line = buffer.slice(0, lineEnd);
          socket.end();
          try {
            const parsed = JSON.parse(line);
            if (parsed.error && parsed.error !== 'success') {
              reject(new Error(String(parsed.error)));
              return;
            }
            resolve(parsed);
          } catch (error) {
            reject(error);
          }
        }
      });

      socket.on('error', reject);
      socket.setTimeout(3000, () => {
        socket.destroy(new Error('Timeout communicating with mpv.'));
      });
    });
  }

  private async command(args: unknown[]): Promise<any> {
    return this.sendRaw({ command: args });
  }

  async open(url: string, title = 'Animind Desktop'): Promise<void> {
    await this.stop();

    const mpvPath = await this.getMpvPath();
    this.pipePath = this.createPipePath();

    const args = [
      '--force-window=yes',
      `--title=${title}`,
      `--input-ipc-server=${this.pipePath}`,
      '--idle=no',
      '--keep-open=no',
      '--user-agent=Animind-Desktop/1.0',
      '--load-scripts=no',
      '--no-terminal',
      '--really-quiet',
      url,
    ];

    this.mpvProcess = spawn(mpvPath, args, { stdio: 'pipe' });
    this.mpvProcess.on('exit', () => {
      this.mpvProcess = null;
      this.pipePath = null;
    });

    this.mpvProcess.on('error', error => {
      console.error('[MPV] Process error:', error.message);
    });

    await this.waitForPipeReady();
  }

  async stop(): Promise<void> {
    if (!this.mpvProcess) return;

    try {
      await this.command(['quit']);
    } catch {
      // ignore and hard kill below
    }

    try {
      this.mpvProcess.kill('SIGTERM');
    } catch {
      // noop
    }

    this.mpvProcess = null;
    this.pipePath = null;
  }

  async play(): Promise<void> {
    await this.command(['set_property', 'pause', false]);
  }

  async pause(): Promise<void> {
    await this.command(['set_property', 'pause', true]);
  }

  async seek(seconds: number): Promise<void> {
    await this.command(['set_property', 'time-pos', Math.max(0, seconds)]);
  }

  async setAudioTrack(trackId: number): Promise<void> {
    await this.command(['set_property', 'aid', trackId]);
  }

  async setSubtitleTrack(trackId: number | 'no'): Promise<void> {
    await this.command(['set_property', 'sid', trackId]);
  }

  async addSubtitleFile(filePath: string): Promise<void> {
    await this.command(['sub-add', filePath, 'select']);
  }

  async getTrackList(): Promise<MpvTrack[]> {
    const response = await this.command(['get_property', 'track-list']);
    return (response.data ?? []) as MpvTrack[];
  }

  async getState(): Promise<PlayerState> {
    const [pauseResp, posResp, durResp] = await Promise.all([
      this.command(['get_property', 'pause']).catch(() => ({ data: true })),
      this.command(['get_property', 'time-pos']).catch(() => ({ data: 0 })),
      this.command(['get_property', 'duration']).catch(() => ({ data: 0 })),
    ]);

    return {
      paused: Boolean(pauseResp.data),
      timePos: Number(posResp.data ?? 0),
      duration: Number(durResp.data ?? 0),
    };
  }
}

export const playerService = new PlayerService();
