import { useCallback, useEffect, useState } from 'react';
import { desktopApi } from '../api';
import type { Show, ShowDetails } from '../types';

export function useLibrary() {
  const [shows, setShows] = useState<Show[]>([]);
  const [loadingShows, setLoadingShows] = useState(false);
  const [selectedShow, setSelectedShow] = useState<ShowDetails | null>(null);
  const [loadingDetails, setLoadingDetails] = useState(false);
  const [error, setError] = useState<string>('');

  const loadShows = useCallback(async () => {
    setLoadingShows(true);
    setError('');
    try {
      const data = await desktopApi.getShows();
      setShows(data);
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load shows');
    } finally {
      setLoadingShows(false);
    }
  }, []);

  const loadShowDetails = useCallback(async (showId: string) => {
    setLoadingDetails(true);
    setError('');
    try {
      const details = await desktopApi.getShowDetails(showId);
      setSelectedShow(details);
    } catch (err: any) {
      setError(err?.message ?? 'Failed to load show details');
    } finally {
      setLoadingDetails(false);
    }
  }, []);

  useEffect(() => {
    void loadShows();
  }, [loadShows]);

  return {
    shows,
    loadingShows,
    selectedShow,
    loadingDetails,
    error,
    loadShows,
    loadShowDetails,
  };
}
