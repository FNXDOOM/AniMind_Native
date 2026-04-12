import axios, { AxiosInstance } from 'axios';
import { authService } from './auth.service';
import { settingsService } from './settings.service';

export interface CloudShow {
  id: string;
  title: string;
  synopsis?: string;
  cover_image_url?: string;
  episode_count?: number;
  rating?: number;
  genres?: string[];
}

export interface CloudEpisode {
  id: string;
  number: number;
  title: string;
  duration: string;
  thumbnail: string;
}

export interface ShowDetails {
  anime: {
    id: string;
    title: string;
    synopsis: string;
    imageUrl: string;
  };
  episodes: CloudEpisode[];
}

export interface StreamTicket {
  url: string;
  expiresIn?: number;
  hlsRequired: boolean;
  clientType?: 'native' | 'browser';
  message?: string;
}

export interface SubtitleTrack {
  id: string;
  label: string;
  language: string;
  content: string;
}

export interface AudioTrack {
  id: string;
  label: string;
  language: string;
  streamIndex: number;
  codec?: string;
  browserSupported?: boolean;
  cached?: boolean;
}

export class LibraryService {
  private client: AxiosInstance | null = null;

  private async getClient(): Promise<AxiosInstance> {
    if (this.client) return this.client;
    const settings = await settingsService.getSettings();
    this.client = axios.create({
      baseURL: settings.backendUrl,
      headers: {
        'User-Agent': 'Animind-Desktop/1.0',
      },
    });
    return this.client;
  }

  private async authHeaders(): Promise<Record<string, string>> {
    const token = await authService.getAccessToken();
    if (!token) throw new Error('Not authenticated. Please sign in.');
    return { Authorization: `Bearer ${token}` };
  }

  async getShows(): Promise<CloudShow[]> {
    const client = await this.getClient();
    const response = await client.get('/api/shows?limit=200&offset=0');
    return (response.data?.data ?? []) as CloudShow[];
  }

  async getShowDetails(showId: string): Promise<ShowDetails> {
    const client = await this.getClient();
    const response = await client.get(`/api/shows/${encodeURIComponent(showId)}`);
    const payload = response.data as any;

    const anime = {
      id: payload.id,
      title: payload.title,
      synopsis: payload.synopsis ?? '',
      imageUrl: payload.cover_image_url ?? '',
    };

    const episodes = (payload.episodes ?? [])
      .map((ep: any, index: number) => ({
        id: ep.id,
        number: Math.round(ep.episode_number ?? index + 1),
        title: ep.title?.trim() || `Episode ${Math.round(ep.episode_number ?? index + 1)}`,
        duration: ep.duration ? String(ep.duration) : '24:00',
        thumbnail: anime.imageUrl,
      }))
      .sort((a: CloudEpisode, b: CloudEpisode) => a.number - b.number);

    return { anime, episodes };
  }

  async getEpisodeStreamTicket(episodeId: string, audioTrackIndex?: number): Promise<StreamTicket> {
    const client = await this.getClient();
    const headers = await this.authHeaders();
    const params: Record<string, string | number> = { clientType: 'desktop' };
    if (typeof audioTrackIndex === 'number') params.at = audioTrackIndex;

    const response = await client.get(`/api/episodes/${encodeURIComponent(episodeId)}/stream-ticket`, {
      headers,
      params,
    });

    const payload = response.data as StreamTicket;
    if (!payload.url) throw new Error('Stream ticket response missing URL.');

    return {
      ...payload,
      url: payload.url.startsWith('http') ? payload.url : `${client.defaults.baseURL}${payload.url}`,
    };
  }

  async getEpisodeSubtitles(episodeId: string): Promise<SubtitleTrack[]> {
    const client = await this.getClient();
    const headers = await this.authHeaders();
    const response = await client.get(`/api/episodes/${encodeURIComponent(episodeId)}/subtitles`, { headers });
    return (response.data?.tracks ?? []) as SubtitleTrack[];
  }

  async getEpisodeAudioTracks(episodeId: string): Promise<AudioTrack[]> {
    const client = await this.getClient();
    const headers = await this.authHeaders();
    const response = await client.get(`/api/episodes/${encodeURIComponent(episodeId)}/audio-tracks`, { headers });
    return (response.data?.tracks ?? []) as AudioTrack[];
  }
}

export const libraryService = new LibraryService();
