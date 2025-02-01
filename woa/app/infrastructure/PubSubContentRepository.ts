'use client';

import { ContentRepository } from '@/application/ContentService';
import { ObservabilityPort } from './ObservabilityPort';
import { WebPubSubClient } from '@azure/web-pubsub-client';
import type { ConnectionState } from '@/application/ContentService';
import { GroupConnectionManager } from './GroupConnectionManager';
import { setLogLevel, AzureLogger } from "@azure/logger";

setLogLevel("verbose");
AzureLogger.log = (...args) => {
  console.log("[AZURE-LOG]", ...args);
};

const RECONNECT_DELAY = 5000;
const TOKEN_REFRESH_INTERVAL = 55 * 60 * 1000; // 55 minutes
const MAX_RETRIES = 3;

export class PubSubContentRepository implements ContentRepository {
  private client: WebPubSubClient | null = null;
  private connectionStateCallback: ((state: ConnectionState) => void) | null = null;
  private tokenRefreshTimeout: ReturnType<typeof setTimeout> | null = null;

  private hasInited = false;
  private isBaseConnectionEstablished = false;
  private retryCount = 0;

  // Content callbacks
  private contentCallback: ((filename: string, content: string) => void) | null = null;
  private eventsCallback: ((events: any[]) => void) | null = null;
  private trainerCallback: ((t: any) => void) | null = null;
  private skillsCallback: ((s: any[]) => void) | null = null;
  private spellsCallback: ((sp: any[]) => void) | null = null;
  private profilesCallback: ((p: any[]) => void) | null = null;
  private currentPlayerProfileCallback: ((p: any) => void) | null = null;

  // The manager that joins groups only after base is established
  public groupManager: GroupConnectionManager;

  constructor(
    // Client no longer provides a real connection string:
    private readonly modeLabel: string,
    private readonly observability: ObservabilityPort,
    private readonly fallbackHubName: string // not used, but included for reference
  ) {
    console.log('[DEBUG] PubSubContentRepository constructor label:', modeLabel);

    // Construct group manager, passing "this" so it can wait for the base connection
    this.groupManager = new GroupConnectionManager(
      this.observability,
      this.handleGroupStateChange.bind(this),
      this
    );

    // Kick off the base connection
    this.initializeConnection();
  }

  private handleGroupStateChange(group: string, state: ConnectionState) {
    this.observability.logInfo(`Group ${group} state changed to ${state}`);
    this.connectionStateCallback?.(state);
  }

  /**
   * The method that fetches the actual token from the new server route.
   */
  private async _fetchTokenFromServer(): Promise<string> {
    try {
      const res = await fetch('/api/webpubsub-token');
      if (!res.ok) {
        throw new Error(`Failed to fetch token. Status: ${res.status}`);
      }
      const data = await res.json();
      if (!data?.url) {
        throw new Error('No URL in token response');
      }
      return data.url;
    } catch (error) {
      throw new Error(`_fetchTokenFromServer error: ${error}`);
    }
  }

  /**
   * Allow GroupConnectionManager to wait for the base connection before group joins.
   */
  public async waitForBaseConnectionEstablished(): Promise<void> {
    let attempts = 0;
    const maxAttempts = 20; // e.g. 10 seconds at 500ms
    while (!this.isBaseConnectionEstablished && attempts < maxAttempts) {
      await new Promise((r) => setTimeout(r, 500));
      attempts++;
    }
    if (!this.isBaseConnectionEstablished) {
      throw new Error('Base WebPubSub connection did not establish in time');
    }
  }

  private scheduleTokenRefresh() {
    if (this.tokenRefreshTimeout) {
      clearTimeout(this.tokenRefreshTimeout);
    }
    this.tokenRefreshTimeout = setTimeout(() => {
      this.refreshConnection();
    }, TOKEN_REFRESH_INTERVAL);
  }

  private async refreshConnection() {
    console.log('[DEBUG] Refreshing WebPubSub connection...');
    await this.initializeConnection(true);
  }

  private async initializeConnection(isRefresh: boolean = false): Promise<void> {
    if (typeof window === 'undefined') {
      console.log('[DEBUG] Skipping WebPubSub connection on server');
      return;
    }
    if (this.hasInited && !isRefresh) {
      console.log('[DEBUG] Already initialized once, skipping...');
      return;
    }
    this.hasInited = true;

    console.log('[DEBUG] Starting WebPubSub connection...');
    await this.attemptConnection();
  }

  private async attemptConnection(): Promise<void> {
    try {
      this.client = new WebPubSubClient({
        getClientAccessUrl: async () => {
          try {
            return await this._fetchTokenFromServer();
          } catch (error) {
            console.error('[DEBUG] getClientAccessUrl() failed:', error);
            if (this.retryCount < MAX_RETRIES) {
              this.retryCount++;
              await new Promise((resolve) => setTimeout(resolve, RECONNECT_DELAY));
              return this._fetchTokenFromServer();
            }
            throw new Error('[DEBUG] Failed to retrieve WebPubSub access URL');
          }
        },
      });

      this.setupEventHandlers();
      await this.client.start();

      console.log('[DEBUG] WebPubSub connection established successfully!');
      this.retryCount = 0;
      this.isBaseConnectionEstablished = true;
      this.connectionStateCallback?.('connected');
      this.scheduleTokenRefresh();

    } catch (error) {
      console.error('[DEBUG] WebPubSub Connection FAILED:', error);
      this.isBaseConnectionEstablished = false;
      this.connectionStateCallback?.('error');

      if (this.retryCount < MAX_RETRIES) {
        this.retryCount++;
        await new Promise((resolve) => setTimeout(resolve, RECONNECT_DELAY));
        return this.attemptConnection();
      }
      throw new Error('[DEBUG] WebPubSub connection completely failed');
    }
  }

  private setupEventHandlers(): void {
    if (!this.client) return;
    this.client.on('connected', () => {
      this.isBaseConnectionEstablished = true;
      this.retryCount = 0;
      console.log('[DEBUG] on("connected") fired');
      this.connectionStateCallback?.('connected');
    });

    this.client.on('disconnected', (e) => {
      this.isBaseConnectionEstablished = false;
      console.log('WebSocket closed:', e.message);
      this.connectionStateCallback?.('disconnected');

      // Try reconnect after a delay
      setTimeout(() => this.initializeConnection(), RECONNECT_DELAY);
    });

    this.client.on('group-message', this.handleGroupMessage.bind(this));
  }

  private handleGroupMessage(e: any) {
    try {
      const { dataType, data } = e.message;
      if (dataType === 'json') {
        const parsedData = typeof data === 'string' ? JSON.parse(data) : data;
        console.log('[DEBUG] Received group message type:', parsedData.type);

        switch (parsedData.type) {
          case 'content':
            this.contentCallback?.(parsedData.filename, parsedData.content);
            break;
          case 'events':
            this.eventsCallback?.(parsedData.events);
            break;
          case 'trainer':
            this.trainerCallback?.(parsedData.trainer);
            break;
          case 'skills':
            this.skillsCallback?.(parsedData.skills);
            break;
          case 'spells':
            this.spellsCallback?.(parsedData.spells);
            break;
          case 'profiles':
            this.profilesCallback?.(parsedData.profiles);
            break;
          case 'currentPlayerProfile':
            this.currentPlayerProfileCallback?.(parsedData.profile);
            break;
          default:
            console.log('[DEBUG] Unhandled message type:', parsedData.type);
        }
      }
    } catch (err) {
      console.error('Error handling group message:', err);
    }
  }

  // Called from DataContext or ContentService
  async joinGroup(group: string): Promise<void> {
    if (!this.client) {
      console.error('[DEBUG] joinGroup() failed: no WebPubSubClient');
      return;
    }

    try {
      console.log('[DEBUG] Attempting to join group:', group);
      this.groupManager.registerGroup(group);

      await this.groupManager.handleGroupConnection(group, async () => {
        await this.client!.joinGroup(group);
      });
    } catch (error) {
      console.warn('[DEBUG joinGroup] Failed to join group:', error);
    }
  }

  async leaveGroup(group: string): Promise<void> {
    if (!this.client) return;
    try {
      await this.client.leaveGroup(group);
      this.groupManager.disconnectGroup(group);
      console.log('[DEBUG] Left group:', group);
    } catch (error) {
      console.error(`[DEBUG] Failed to leave group: ${group}`, error);
      throw error;
    }
  }

  // Optional connection state callback
  onConnectionStateChange(callback: (state: ConnectionState) => void): void {
    this.connectionStateCallback = callback;
    callback(this.isBaseConnectionEstablished ? 'connected' : 'disconnected');
  }

  // Content callbacks
  onContentReceived(cb: (filename: string, content: string) => void) {
    this.contentCallback = cb;
  }
  onEventsUpdate(cb: (events: any[]) => void) {
    this.eventsCallback = cb;
  }
  onTrainerUpdate(cb: (t: any) => void) {
    this.trainerCallback = cb;
  }
  onSkillsUpdate(cb: (skills: any[]) => void) {
    this.skillsCallback = cb;
  }
  onSpellsUpdate(cb: (sp: any[]) => void) {
    this.spellsCallback = cb;
  }
  onProfilesUpdate(cb: (p: any[]) => void) {
    this.profilesCallback = cb;
  }
  onCurrentPlayerProfileUpdate(cb: (p: any) => void) {
    this.currentPlayerProfileCallback = cb;
  }

  // Send requests to specific groups
  async requestFile(filename: string): Promise<void> {
    if (!this.client) return;
    await this.client.sendToGroup('navigation', { type: 'requestFile', filename }, 'json', {
      noEcho: true,
    });
  }

  async requestMarkdown(filename: string): Promise<void> {
    if (!this.client) return;
    await this.client.sendToGroup('navigation', { type: 'requestMarkdown', filename }, 'json', {
      noEcho: true,
    });
  }

  async sendMergeRequest(line: string): Promise<void> {
    if (!this.client) return;
    await this.client.sendToGroup('navigation', { type: 'merge_request', line }, 'json', {
      noEcho: true,
    });
  }

  async sendNavigationChange(filename: string): Promise<void> {
    if (!this.client) return;
    await this.client.sendToGroup('navigation', { type: 'navigation_change', filename }, 'json', {
      noEcho: true,
    });
  }
}
