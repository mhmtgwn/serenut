import { WebSocket } from 'ws';
import { ConnectionRegistry } from './connection-registry';
import { logger } from '../../config/logger';
import { writeAuditLog } from '../analytics/telemetry.controller';

export class TopicManager {
  // Topic path -> Set of Sockets
  private static subscriptions = new Map<string, Set<WebSocket>>();
  // Socket -> Set of Topics (for quick cleanup on disconnect)
  private static socketSubscriptions = new Map<WebSocket, Set<string>>();

  /**
   * Subscribe a client socket to a topic
   */
  public static async subscribe(ws: WebSocket, topic: string, correlationId?: string): Promise<boolean> {
    const meta = ConnectionRegistry.getMetadata(ws);
    if (!meta) {
      logger.warn(`WS Subscribe rejected: Socket metadata not found`);
      return false;
    }

    // Tenant Isolation check: topic must start with tenant/{companyId}/
    const expectedPrefix = `tenant/${meta.companyId}/`;
    if (!topic.startsWith(expectedPrefix)) {
      logger.warn(
        `WS Tenant Isolation Violation: user_id=${meta.userId} (tenant=${meta.companyId}) attempted to subscribe to topic: ${topic}`
      );
      
      // Log to Audit Log (non-blocking)
      writeAuditLog(
        meta.companyId,
        meta.userId,
        meta.userName,
        'WEBSOCKET_UNAUTHORIZED_SUBSCRIPTION',
        'WebSocketTopic',
        topic,
        null,
        { topic, correlationId },
        meta.ipAddress,
        meta.userAgent
      ).catch((auditErr: any) => {
        logger.error(`Failed to write WS audit log: ${auditErr.message}`);
      });
      
      return false;
    }

    // Register subscription
    if (!this.subscriptions.has(topic)) {
      this.subscriptions.set(topic, new Set());
    }
    this.subscriptions.get(topic)!.add(ws);

    if (!this.socketSubscriptions.has(ws)) {
      this.socketSubscriptions.set(ws, new Set());
    }
    this.socketSubscriptions.get(ws)!.add(topic);

    logger.info(`WS Client subscribed: user_id=${meta.userId}, topic=${topic}`);
    return true;
  }

  /**
   * Unsubscribe a client socket from a topic
   */
  public static unsubscribe(ws: WebSocket, topic: string) {
    const meta = ConnectionRegistry.getMetadata(ws);
    const userId = meta ? meta.userId : 'unknown';

    const subscribers = this.subscriptions.get(topic);
    if (subscribers) {
      subscribers.delete(ws);
      if (subscribers.size === 0) {
        this.subscriptions.delete(topic);
      }
    }

    const clientTopics = this.socketSubscriptions.get(ws);
    if (clientTopics) {
      clientTopics.delete(topic);
      if (clientTopics.size === 0) {
        this.socketSubscriptions.delete(ws);
      }
    }

    logger.info(`WS Client unsubscribed: user_id=${userId}, topic=${topic}`);
  }

  /**
   * Unsubscribe a client socket from all topics (on disconnect)
   */
  public static unsubscribeAll(ws: WebSocket) {
    const clientTopics = this.socketSubscriptions.get(ws);
    if (clientTopics) {
      for (const topic of clientTopics) {
        const subscribers = this.subscriptions.get(topic);
        if (subscribers) {
          subscribers.delete(ws);
          if (subscribers.size === 0) {
            this.subscriptions.delete(topic);
          }
        }
      }
      this.socketSubscriptions.delete(ws);
    }
  }

  /**
   * Get all sockets subscribed to a topic
   */
  public static getSubscribers(topic: string): Set<WebSocket> {
    return this.subscriptions.get(topic) || new Set();
  }

  /**
   * Expose count of active subscriptions for monitoring
   */
  public static getSubscriptionsCount(): number {
    let count = 0;
    for (const subs of this.subscriptions.values()) {
      count += subs.size;
    }
    return count;
  }

  /**
   * Get all topics a client socket is subscribed to
   */
  public static getClientTopics(ws: WebSocket): Set<string> {
    return this.socketSubscriptions.get(ws) || new Set();
  }
}
