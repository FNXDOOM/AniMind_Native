import { app } from 'electron';
import { mkdir, writeFile } from 'fs/promises';
import path from 'path';

interface SubtitleTrack {
  id: string;
  label: string;
  language: string;
  content: string;
}

function toSafeName(value: string): string {
  return value.replace(/[^a-z0-9_-]/gi, '_');
}

export class SubtitleService {
  async writeTrackToTempFile(episodeId: string, track: SubtitleTrack): Promise<string> {
    const dir = path.join(app.getPath('userData'), 'subtitles', toSafeName(episodeId));
    await mkdir(dir, { recursive: true });

    const fileName = `${toSafeName(track.id)}.vtt`;
    const fullPath = path.join(dir, fileName);
    const content = track.content.startsWith('WEBVTT') ? track.content : `WEBVTT\n\n${track.content}`;
    await writeFile(fullPath, content, 'utf8');
    return fullPath;
  }
}

export const subtitleService = new SubtitleService();
