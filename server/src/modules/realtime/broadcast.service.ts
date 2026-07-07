import crypto from 'crypto';
import { eventBroker } from './event-broker';
import { logger } from '../../config/logger';

export interface RealtimeEventModel {
  id: string;
  type: string;
  tenantId: string;
  timestamp: string;
  payload: any;
  version: number;
  correlationId: string;
}

export class RealtimeBroadcastService {
  private static eventCount = 0;
  private static failedEventCount = 0;

  /**
   * Publish an event to the system and distribute it to interested WebSocket clients
   */
  public static async publishEvent(
    companyId: string,
    type: string,
    payload: any,
    correlationId?: string
  ): Promise<void> {
    try {
      const event: RealtimeEventModel = {
        id: `evt-${crypto.randomUUID()}`,
        type,
        tenantId: companyId,
        timestamp: new Date().toISOString(),
        payload,
        version: 1,
        correlationId: correlationId || `corr-${crypto.randomBytes(8).toString('hex')}`,
      };

      // Determine category (e.g. OrderCreated -> orders)
      const category = this.getTopicCategory(type);
      const topic = `tenant/${companyId}/${category}`;

      logger.info(`Realtime Event Generated: id=${event.id}, type=${type}, topic=${topic}`);

      // Serialize asynchronously
      const messageJson = JSON.stringify(event);

      // Publish to the event broker
      await eventBroker.publish(topic, messageJson);

      this.eventCount++;
    } catch (err: any) {
      this.failedEventCount++;
      logger.error(`Failed to publish realtime event: ${err.message}`, { companyId, type, payload });
    }
  }

  /**
   * Helper to map a event type to its topic suffix category
   */
  private static getTopicCategory(type: string): string {
    const lowerType = type.toLowerCase();
    if (lowerType.includes('order') || lowerType.includes('sale')) return 'orders';
    if (lowerType.includes('payment')) return 'payments';
    if (lowerType.includes('inventory') || lowerType.includes('price')) return 'inventory';
    if (lowerType.includes('customer')) return 'customers';
    if (lowerType.includes('notification')) return 'notifications';
    if (lowerType.includes('license')) return 'license';
    if (lowerType.includes('backup')) return 'backup';
    if (lowerType.includes('user') || lowerType.includes('auth') || lowerType.includes('log')) return 'auth';
    if (lowerType.includes('setting')) return 'settings';
    if (lowerType.includes('report')) return 'reports';
    return 'general';
  }

  // Telemetry getters
  public static getSentEventsCount(): number {
    return this.eventCount;
  }

  public static getFailedEventsCount(): number {
    return this.failedEventCount;
  }
}
