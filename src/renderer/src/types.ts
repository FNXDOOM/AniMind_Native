export interface SessionInfo {
  userId: string;
  email?: string;
}

export interface Show {
  id: string;
  title: string;
  synopsis?: string;
  cover_image_url?: string;
  episode_count?: number;
}

export interface Episode {
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
  episodes: Episode[];
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

export interface PlayerTrack {
  id: number;
  type: string;
  title?: string;
  lang?: string;
  codec?: string;
  selected?: boolean;
}
