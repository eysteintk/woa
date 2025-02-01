// app/infrastructure/ConsoleObservability.ts
import { ObservabilityPort } from './ObservabilityPort';

export class ConsoleObservability implements ObservabilityPort {
  logInfo(message: string, data?: any): void {
    if (data) {
      console.info(`[INFO] ${message}`, data);
    } else {
      console.info(`[INFO] ${message}`);
    }
  }

  logError(error: unknown, context?: string): void {
    const errorMessage = error && typeof error === 'object' && 'message' in error
      ? error.message
      : String(error);

    if (context) {
      console.error(`[ERROR] ${context}:`, errorMessage);
    } else {
      console.error(`[ERROR]:`, errorMessage);
    }
  }

  logEvent(name: string, data?: any): void {
    if (data) {
      console.log(`[EVENT] ${name}`, data);
    } else {
      console.log(`[EVENT] ${name}`);
    }
  }
}