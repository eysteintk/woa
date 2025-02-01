'use client';

import React, {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
} from 'react';
import { ContentService, ConnectionState } from '@/application/ContentService';
import { PubSubContentRepository } from '@/infrastructure/PubSubContentRepository';
import { ConsoleObservability } from '@/infrastructure/ConsoleObservability';

const KNOWN_GROUPS = ['navigation', 'events', 'story', 'details'];

interface Profile {
  name: string;
  image: string;
  path: string;
}

interface Trainer {
  name: string;
}

interface Skill {
  name: string;
  state: string;
}

interface Spell {
  name: string;
  state: string;
  cooldown: number;
}

interface AppEvent {
  id: number;
  timestamp: string;
  location: string;
  content: string;
  echartsOption?: any;
}

interface DataContextValue {
  connectionState: ConnectionState;
  groupConnectionStates: Record<string, ConnectionState>;
  selectedFile: string | null;
  contentsByFilename: Record<string, string>;
  handleSelectFile: (filename: string) => void;
  handleJoinGroup: (group: string) => void;
  requestMarkdown: (filename: string) => void;
  sendMergeRequest: (line: string) => void;
  profiles: Profile[];
  currentPlayerProfile: Profile | null;
  trainer: Trainer | null;
  skills: Skill[];
  spells: Spell[];
  events: AppEvent[];
  joinGroup: (group: string) => Promise<void>;
  leaveGroup: (group: string) => Promise<void>;
  isReady: boolean;
}

export const DataContext = createContext<DataContextValue | null>(null);

function useServices() {
  const [services, setServices] = useState<{
    observability: ConsoleObservability;
    repository?: PubSubContentRepository;
    service?: ContentService;
    isReady: boolean;
  }>({
    observability: new ConsoleObservability(),
    isReady: false,
  });

  useEffect(() => {
    if (typeof window === 'undefined') {
      console.log('[DEBUG] Skipping useServices() setup on server-side.');
      return;
    }

    async function initializeServices() {
      try {
        console.log('[DEBUG] Starting initializeServices()...');
        // We no longer check any NEXT_PUBLIC_ env here

        console.log('[DEBUG] Creating PubSubContentRepository...');
        // Pass placeholders for constructor
        const repository = new PubSubContentRepository(
          'client-route-mode',
          services.observability,
          'woa' // optional fallback
        );

        console.log('[DEBUG] Repository instance created:', repository);

        console.log('[DEBUG] Creating ContentService...');
        const service = new ContentService(repository);
        console.log('[DEBUG] Service instance created:', service);

        setServices({
          observability: services.observability,
          repository,
          service,
          isReady: true,
        });

        console.log('[DEBUG] Web PubSub services initialized successfully.');
      } catch (error) {
        console.error('[DEBUG] Failed to initialize Web PubSub services:', error);
      }
    }

    initializeServices();
  }, []);

  return services;
}

export function DataProvider({ children }: { children: React.ReactNode }) {
  const { observability, repository, service, isReady } = useServices();
  const [connectionState, setConnectionState] = useState<ConnectionState>('disconnected');
  const [groupConnectionStates, setGroupConnectionStates] = useState<Record<string, ConnectionState>>(
    KNOWN_GROUPS.reduce((acc, group) => ({ ...acc, [group]: 'disconnected' }), {})
  );

  const [selectedFile, setSelectedFile] = useState<string | null>(null);
  const [contentsByFilename, setContentsByFilename] = useState<Record<string, string>>({});
  const [events, setEvents] = useState<AppEvent[]>([]);
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [currentPlayerProfile, setCurrentPlayerProfile] = useState<Profile | null>(null);
  const [trainer, setTrainer] = useState<Trainer | null>({ name: 'No trainer assigned' });
  const [skills, setSkills] = useState<Skill[]>([]);
  const [spells, setSpells] = useState<Spell[]>([]);

  const updateGroupState = useCallback((group: string, state: ConnectionState) => {
    setGroupConnectionStates((prev) => ({ ...prev, [group]: state }));
  }, []);

  const joinGroup = useCallback(
    async (group: string) => {
      if (!service) {
        console.warn(`[joinGroup] Service is not ready, delaying group join: ${group}`);
        return;
      }
      observability.logInfo('[DataProvider] Joining group', { group });

      try {
        updateGroupState(group, 'connecting');
        await service.joinGroup(group);
        updateGroupState(group, 'connected');
      } catch (error) {
        console.error(`[joinGroup] Raw error thrown:`, error);
        updateGroupState(group, 'error');
      }
    },
    [service, updateGroupState, observability]
  );

  const leaveGroup = useCallback(
    async (group: string) => {
      if (!service) return;
      observability.logInfo('[DataProvider] Leaving group', { group });
      try {
        await service.leaveGroup(group);
        updateGroupState(group, 'disconnected');
      } catch (error) {
        console.error('[leaveGroup] Failed to leave group:', error);
      }
    },
    [service, updateGroupState, observability]
  );

  const handleJoinGroup = useCallback(
    (group: string) => {
      if (!service) {
        console.error('[handleJoinGroup] Service is undefined.');
        return;
      }
      observability.logInfo('[DataProvider] handleJoinGroup called', { group });
      joinGroup(group).catch((error) => {
        console.error('[handleJoinGroup] Failed to join group:', error);
      });
    },
    [joinGroup, observability]
  );

  const contextValue: DataContextValue = {
    connectionState,
    groupConnectionStates,
    selectedFile,
    contentsByFilename,
    handleSelectFile: setSelectedFile,
    handleJoinGroup,
    requestMarkdown: () => {},
    sendMergeRequest: () => {},
    profiles,
    currentPlayerProfile,
    trainer,
    skills,
    spells,
    events,
    joinGroup,
    leaveGroup,
    isReady,
  };

  return <DataContext.Provider value={contextValue}>{children}</DataContext.Provider>;
}

export function useData() {
  const ctx = useContext(DataContext);
  if (!ctx) throw new Error('useData must be used within a DataProvider');
  return ctx;
}
