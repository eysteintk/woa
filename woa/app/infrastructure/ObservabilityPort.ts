// app/infrastructure/ObservabilityPort.ts
export interface ObservabilityPort {
  logInfo(message: string, data?: any): void;
  logError(error: unknown, context?: string): void;  // Changed from Error to unknown
  logEvent(name: string, data?: any): void;
}