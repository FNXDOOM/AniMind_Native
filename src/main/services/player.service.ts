import { PlayerBackend } from './player-backends/types';
import { mpvEmbeddedBackend } from './player-backends/mpv-embedded.backend';
import { mpvExternalBackend } from './player-backends/mpv-external.backend';

const backendPreference = (process.env.ANIMIND_PLAYER_BACKEND ?? 'embedded').trim().toLowerCase();

const backend: PlayerBackend = backendPreference === 'external'
  ? mpvExternalBackend
  : mpvEmbeddedBackend;

console.log(`[Player] Using "${backendPreference === 'external' ? 'external' : 'embedded'}" backend`);

export const playerService: PlayerBackend = backend;
