import { redisClient } from '../config/database';
import { logger } from '../config/logger';

export class LockManager {
  /**
   * Try to acquire a distributed lock on a given key using Redis (NX/PX pattern).
   * Returns true if lock is acquired, false otherwise (non-blocking).
   * Default TTL is 30 seconds to prevent permanent deadlocks.
   * Accept an unique token to identify the owner of the lock.
   */
  public static async tryAcquireLock(key: string, token: string, ttlMs = 30000): Promise<boolean> {
    const lockKey = `lock:${key}`;

    if (!redisClient || !redisClient.isOpen) {
      logger.warn(`⚠️ Redis is down. Bypassing lock check to prevent system blocking for key: ${key}`);
      return true; // Safe operational fallback
    }

    try {
      const res = await redisClient.set(lockKey, token, {
        NX: true,
        PX: ttlMs,
      });
      const acquired = res === 'OK';
      if (acquired) {
        logger.info(`🔒 Redis Lock acquired successfully for key: ${key} (token: ${token})`);
      } else {
        logger.warn(`⚠️ Failed to acquire Redis lock (busy) for key: ${key}`);
      }
      return acquired;
    } catch (err: any) {
      logger.error(`🔴 Error acquiring Redis lock for key ${key}: ${err.message}`);
      return false;
    }
  }

  /**
   * Release a previously acquired distributed lock if and only if the token matches.
   * Returns true if released successfully, false otherwise.
   */
  public static async releaseLock(key: string, token: string): Promise<boolean> {
    const lockKey = `lock:${key}`;

    if (!redisClient || !redisClient.isOpen) {
      return true;
    }

    try {
      // Atomic compare-and-delete Lua script to ensure safe release
      const luaScript = `
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      `;

      // Execute Lua script using eval
      const result = await redisClient.eval(luaScript, {
        keys: [lockKey],
        arguments: [token]
      });

      const released = Number(result) === 1;
      if (released) {
        logger.info(`🔓 Redis Lock released successfully for key: ${key}`);
      } else {
        logger.warn(`⚠️ Lock release skipped: token mismatch or lock expired for key: ${key}`);
      }
      return released;
    } catch (err: any) {
      logger.error(`🔴 Error releasing Redis lock for key ${key}: ${err.message}`);
      return false;
    }
  }
}
