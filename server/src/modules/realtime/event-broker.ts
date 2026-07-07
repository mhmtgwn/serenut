import { EventEmitter } from 'events';
import { createClient } from 'redis';
import { logger } from '../../config/logger';

export interface BrokerMessage {
  topic: string;
  message: string;
}

export type BrokerCallback = (topic: string, message: string) => void;

export interface EventBroker {
  publish(topic: string, message: string): Promise<void>;
  subscribe(topic: string, callback: BrokerCallback): Promise<void>;
}

// ── LOCAL EVENT BROKER (FALLBACK) ─────────────────────────────────────────────
class LocalEventBroker implements EventBroker {
  private emitter = new EventEmitter();

  public async publish(topic: string, message: string): Promise<void> {
    this.emitter.emit(topic, message);
  }

  public async subscribe(topic: string, callback: BrokerCallback): Promise<void> {
    this.emitter.on(topic, (msg: string) => {
      callback(topic, msg);
    });
  }
}

// ── REDIS EVENT BROKER (HORIZONTAL SCALABILITY) ───────────────────────────────
class RedisEventBroker implements EventBroker {
  private pubClient: any;
  private subClient: any;
  private subCallbacks = new Map<string, BrokerCallback[]>();

  constructor(redisUrl: string) {
    this.pubClient = createClient({ url: redisUrl });
    this.subClient = createClient({ url: redisUrl });

    this.pubClient.on('error', (err: any) => logger.error('Broker Pub Client Error:', err));
    this.subClient.on('error', (err: any) => logger.error('Broker Sub Client Error:', err));

    Promise.all([this.pubClient.connect(), this.subClient.connect()])
      .then(() => {
        logger.info('🚀 Horizontally scalable Redis Event Broker initialized successfully.');
      })
      .catch((err) => {
        logger.error('🔴 Failed to initialize Redis Event Broker clients:', err);
      });
  }

  public async publish(topic: string, message: string): Promise<void> {
    if (this.pubClient && this.pubClient.isOpen) {
      await this.pubClient.publish(topic, message);
    } else {
      logger.warn(`Redis Broker pub client is closed. Cannot publish to topic: ${topic}`);
    }
  }

  public async subscribe(topic: string, callback: BrokerCallback): Promise<void> {
    if (!this.subCallbacks.has(topic)) {
      this.subCallbacks.set(topic, []);
    }
    this.subCallbacks.get(topic)!.push(callback);

    if (this.subClient && this.subClient.isOpen) {
      await this.subClient.subscribe(topic, (message: string) => {
        const callbacks = this.subCallbacks.get(topic);
        if (callbacks) {
          callbacks.forEach((cb) => cb(topic, message));
        }
      });
    } else {
      logger.warn(`Redis Broker sub client is closed. Queuing subscription callback for topic: ${topic}`);
    }
  }
}

// ── SINGLETON EXPORT ─────────────────────────────────────────────────────────
let activeBroker: EventBroker;

const redisUrl = process.env.REDIS_URL;
if (redisUrl) {
  activeBroker = new RedisEventBroker(redisUrl);
} else {
  logger.info('ℹ️ Redis URL not set. Initializing local in-memory Event Broker.');
  activeBroker = new LocalEventBroker();
}

export const eventBroker = activeBroker;
