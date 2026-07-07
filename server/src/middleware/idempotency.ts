import { Request, Response, NextFunction } from 'express';
import { createClient } from 'redis';
import crypto from 'crypto';
import { logger } from '../config/logger';

interface CachedResponse {
  status: 'processing' | 'success';
  statusCode?: number;
  headers?: any;
  body?: string;
  payloadHash?: string;
  expiresAt: number;
}

class IdempotencyCache {
  private localCache = new Map<string, CachedResponse>();
  private redisClient: any;
  private useRedis = false;

  constructor() {
    const redisUrl = process.env.REDIS_URL;
    if (redisUrl) {
      try {
        this.redisClient = createClient({ url: redisUrl });
        this.redisClient.on('error', (err: any) => logger.error('Idempotency Redis Client Error:', err));
        this.redisClient.connect()
          .then(() => {
            this.useRedis = true;
            logger.info('🚀 Idempotency Redis Cache initialized successfully.');
          })
          .catch((err: any) => {
            logger.warn('⚠️ Idempotency Redis connect failed, using memory cache fallback:', err.message);
          });
      } catch (err: any) {
        logger.warn('⚠️ Idempotency Redis init failed, using memory cache fallback:', err.message);
      }
    }
  }

  public async get(key: string): Promise<CachedResponse | null> {
    if (this.useRedis && this.redisClient.isOpen) {
      try {
        const raw = await this.redisClient.get(`idemp:${key}`);
        if (raw) {
          const parsed = JSON.parse(raw);
          if (parsed.expiresAt < Date.now()) {
            await this.redisClient.del(`idemp:${key}`);
            return null;
          }
          return parsed;
        }
      } catch (err) {
        logger.error('Failed to get from Redis:', err);
      }
    }

    // Fallback to local memory cache
    const cached = this.localCache.get(key);
    if (cached) {
      if (cached.expiresAt < Date.now()) {
        this.localCache.delete(key);
        return null;
      }
      return cached;
    }

    return null;
  }

  public async set(key: string, value: CachedResponse, ttlSeconds: number = 86400): Promise<void> {
    value.expiresAt = Date.now() + ttlSeconds * 1000;

    if (this.useRedis && this.redisClient.isOpen) {
      try {
        await this.redisClient.set(
          `idemp:${key}`,
          JSON.stringify(value),
          { EX: ttlSeconds }
        );
        return;
      } catch (err) {
        logger.error('Failed to set in Redis:', err);
      }
    }

    this.localCache.set(key, value);
    // Cleanup local cache entry after expiration
    setTimeout(() => {
      const current = this.localCache.get(key);
      if (current && current.expiresAt <= Date.now()) {
        this.localCache.delete(key);
      }
    }, ttlSeconds * 1000);
  }
}

const cache = new IdempotencyCache();

export async function idempotencyMiddleware(req: Request, res: Response, next: NextFunction) {
  // Only apply idempotency check to mutating requests (POST, PUT, PATCH)
  if (!['POST', 'PUT', 'PATCH'].includes(req.method)) {
    return next();
  }

  const key = req.header('Idempotency-Key');
  if (!key) {
    return next();
  }

  // Generate payload hash to protect against key collision (same key, different bodies)
  const incomingPayload = req.body ? JSON.stringify(req.body) : '';
  const incomingHash = crypto.createHash('sha256').update(incomingPayload).digest('hex');

  try {
    const cached = await cache.get(key);

    if (cached) {
      // Collision verification: Same key, different body
      if (cached.payloadHash && cached.payloadHash !== incomingHash) {
        return res.status(422).json({
          status: 'error',
          code: 'IDEMPOTENCY_KEY_COLLISION',
          message: 'Idempotency Key Collision: An identical key was submitted but with a different request payload.'
        });
      }

      if (cached.status === 'processing') {
        return res.status(409).json({
          status: 'error',
          code: 'CONCURRENT_REQUEST',
          message: 'An identical request is currently being processed. Please try again shortly.'
        });
      }

      if (cached.status === 'success') {
        // Replay cached response headers
        if (cached.headers) {
          Object.keys(cached.headers).forEach((h) => {
            res.setHeader(h, cached.headers[h]);
          });
        }
        res.setHeader('X-Cache-Lookup', 'HIT - Idempotency Replay');
        return res.status(cached.statusCode || 200).send(cached.body ? JSON.parse(cached.body) : {});
      }
    }

    // Flag key as processing with payload hash to lock out duplicate concurrent requests (2-min timeout)
    await cache.set(key, { status: 'processing', payloadHash: incomingHash, expiresAt: 0 }, 120);

    // Intercept sending response to save it upon success
    const originalSend = res.send;
    res.send = function (body: any): Response {
      res.send = originalSend; // Restore function to avoid loops

      const statusCode = res.statusCode;
      if (statusCode >= 200 && statusCode < 300) {
        // Mutating success: Cache payload for 24 hours
        cache.set(key, {
          status: 'success',
          statusCode,
          headers: res.getHeaders(),
          body: typeof body === 'string' ? body : JSON.stringify(body),
          payloadHash: incomingHash,
          expiresAt: 0
        }, 86400).catch((err) => logger.error('Failed to cache idempotency response:', err));
      } else {
        // Unlock on server errors or client errors, allowing immediate retries
        cache.set(key, { status: 'processing', payloadHash: incomingHash, expiresAt: 0 }, 0).catch(() => {});
      }

      return originalSend.call(this, body);
    };

    next();
  } catch (err: any) {
    logger.error('Idempotency Middleware Error:', err);
    next();
  }
}
