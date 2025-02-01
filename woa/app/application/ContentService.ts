// app/application/ContentService.ts
import { mapFilenameToGroup } from '@/domain/entities';

export interface ContentRepository {
  joinGroup(group: string): Promise<void>;
  leaveGroup(group: string): Promise<void>;

  onContentReceived(callback: (filename: string, content: string) => void): void;
  onEventsUpdate(callback: (events: any[]) => void): void;
  onTrainerUpdate(callback: (t: any) => void): void;
  onSkillsUpdate(callback: (skills: any[]) => void): void;
  onSpellsUpdate(callback: (sp: any[]) => void): void;
  onProfilesUpdate(callback: (p: any[]) => void): void;
  onCurrentPlayerProfileUpdate(callback: (p: any) => void): void;
  onConnectionStateChange?(callback: (state: ConnectionState) => void): void;

  requestFile(filename: string): Promise<void>;
  requestMarkdown(filename: string): Promise<void>;
  sendMergeRequest(line: string): Promise<void>;
  sendNavigationChange(filename: string): Promise<void>;
}

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';

export class ContentService {
  private currentGroup: string | null = null;
  private currentFilename: string | null = null;
  private connectionState: ConnectionState = 'disconnected';
  private connectionStateCallback: ((state: ConnectionState) => void) | null = null;

  constructor(private readonly repository: ContentRepository) {
    if (repository.onConnectionStateChange) {
      repository.onConnectionStateChange((state) => {
        this.connectionState = state;
        this.connectionStateCallback?.(state);
      });
    }
  }

  async selectFile(filename: string) {
    this.currentFilename = filename;
    const newGroup = mapFilenameToGroup(filename);

    try {
      // If we have a current group that's different, leave it first
      if (this.currentGroup && this.currentGroup !== newGroup) {
        await this.repository.leaveGroup(this.currentGroup);
      }

      // Join new group if not already joined
      if (!this.currentGroup || this.currentGroup !== newGroup) {
        await this.repository.joinGroup(newGroup);
        this.currentGroup = newGroup;
      }

      // Request the file content
      await this.repository.requestFile(filename);
    } catch (err) {
      const msg = err && typeof err === 'object' && 'message' in (err as any)
        ? (err as any).message
        : String(err);
      const error = new Error(`Error in selectFile: ${msg}`);
      console.error(error.message);
      throw error;
    }
  }

  // Content callbacks
  onContentReceived(cb: (filename: string, content: string) => void) {
    this.repository.onContentReceived(cb);
  }
  onEventsUpdate(cb: (events: any[]) => void) {
    this.repository.onEventsUpdate(cb);
  }
  onTrainerUpdate(cb: (t: any) => void) {
    this.repository.onTrainerUpdate(cb);
  }
  onSkillsUpdate(cb: (s: any[]) => void) {
    this.repository.onSkillsUpdate(cb);
  }
  onSpellsUpdate(cb: (sp: any[]) => void) {
    this.repository.onSpellsUpdate(cb);
  }
  onProfilesUpdate(cb: (p: any[]) => void) {
    this.repository.onProfilesUpdate(cb);
  }
  onCurrentPlayerProfileUpdate(cb: (p: any) => void) {
    this.repository.onCurrentPlayerProfileUpdate(cb);
  }

  onConnectionStateChange(cb: (state: ConnectionState) => void) {
    this.connectionStateCallback = cb;
    cb(this.connectionState);
  }

  // Additional actions
  requestMarkdown(filename: string) {
    return this.repository.requestMarkdown(filename);
  }
  sendMergeRequest(line: string) {
    return this.repository.sendMergeRequest(line);
  }
  sendNavigationChange(filename: string) {
    return this.repository.sendNavigationChange(filename);
  }

  async joinGroup(group: string) {
    try {
      await this.repository.joinGroup(group);
      this.currentGroup = group;
    } catch (err) {
      console.error('[ContentService.joinGroup] failed:', err);
    }
  }

  async leaveGroup(group: string) {
    try {
      await this.repository.leaveGroup(group);
      if (this.currentGroup === group) {
        this.currentGroup = null;
      }
    } catch (err) {
      const msg = err && typeof err === 'object' && 'message' in (err as any)
        ? (err as any).message
        : String(err);
      const error = new Error(`Failed to leave group ${group}: ${msg}`);
      console.error(error.message);
      throw error;
    }
  }

  getCurrentState(): ConnectionState {
    return this.connectionState;
  }
}
