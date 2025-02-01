// app/hooks/useConnectedProfiles.ts
'use client';

import { useData } from '@/context/DataContext';

export function useConnectedProfiles(file: string | null) {
  const { profiles } = useData();
  if (!file) return [];
  // If it's a communal file (team/hawthorn_rangers.md, quest, dungeons)
  if (file.includes('team') || file.includes('quest') || file.includes('dungeons')) {
    return profiles.slice(0, 2);
  }
  return [];
}
