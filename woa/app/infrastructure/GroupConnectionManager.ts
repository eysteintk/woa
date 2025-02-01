// app/infrastructure/GroupConnectionManager.ts
import { ObservabilityPort } from './ObservabilityPort';
import type { ConnectionState } from '@/application/ContentService';
import { PubSubContentRepository } from './PubSubContentRepository';

interface GroupState {
  name: string;
  isConnected: boolean;
  retryCount: number;
  lastAttempt?: Date;
}

export class GroupConnectionManager {
  private groups: Map<string, GroupState> = new Map();
  private readonly MAX_RETRY_ATTEMPTS = 3;
  private readonly RETRY_DELAY_MS = 2000;

  constructor(
    private observability: ObservabilityPort,
    private onStateChange: (group: string, state: ConnectionState) => void,
    private pubsubRepo: PubSubContentRepository
  ) {}

  registerGroup(groupName: string) {
    if (!this.groups.has(groupName)) {
      this.groups.set(groupName, {
        name: groupName,
        isConnected: false,
        retryCount: 0,
      });
      this.observability.logInfo(`Registered group: ${groupName}`);
    }
  }

  async handleGroupConnection(groupName: string, joinGroupFn: () => Promise<void>) {
    const group = this.groups.get(groupName);
    if (!group) {
      throw new Error(`Group ${groupName} not registered`);
    }

    try {
      console.log(`[DEBUG] Attempting to join group: ${groupName}`);

      // Ensure base WebSocket is established
      await this.pubsubRepo.waitForBaseConnectionEstablished();

      this.onStateChange(groupName, 'connecting');
      await joinGroupFn();

      group.isConnected = true;
      group.retryCount = 0;
      group.lastAttempt = new Date();

      console.log(`[DEBUG] Successfully connected to group: ${groupName}`);
      this.onStateChange(groupName, 'connected');
    } catch (error) {
      console.warn(`[DEBUG] Connection failed for group ${groupName}:`, error);
      await this.handleConnectionError(group, joinGroupFn);
    }
  }

  private async handleConnectionError(
    group: GroupState,
    joinGroupFn: () => Promise<void>
  ) {
    group.isConnected = false;
    group.lastAttempt = new Date();
    group.retryCount++;

    this.observability.logError(
      new Error(`Failed to connect to group: ${group.name}. Attempt ${group.retryCount}`)
    );

    if (group.retryCount <= this.MAX_RETRY_ATTEMPTS) {
      this.onStateChange(group.name, 'disconnected');

      // Exponential backoff
      const delay = this.RETRY_DELAY_MS * Math.pow(2, group.retryCount - 1);
      this.observability.logInfo(
        `Scheduling retry for group ${group.name} in ${delay}ms`
      );

      setTimeout(() => {
        this.handleGroupConnection(group.name, joinGroupFn).catch((error) => {
          this.observability.logError(
            new Error(`Retry failed for group ${group.name}`),
            error
          );
        });
      }, delay);
    } else {
      this.onStateChange(group.name, 'error');
      this.observability.logError(
        new Error(`Max retry attempts reached for group: ${group.name}`)
      );
    }
  }

  isGroupConnected(groupName: string): boolean {
    return this.groups.get(groupName)?.isConnected ?? false;
  }

  disconnectGroup(groupName: string) {
    const group = this.groups.get(groupName);
    if (group) {
      group.isConnected = false;
      group.retryCount = 0;
      this.onStateChange(groupName, 'disconnected');
    }
  }

  getGroupState(groupName: string): GroupState | undefined {
    return this.groups.get(groupName);
  }

  getAllGroups(): string[] {
    return Array.from(this.groups.keys());
  }
}
