import { pgPool } from '../config/database';
import { logger } from '../config/logger';

/**
 * Hash a string to a 32-bit signed integer for pg_advisory_lock consumption
 */
function hashKeyToInt(key: string): number {
  let hash = 0;
  for (let i = 0; i < key.length; i++) {
    const char = key.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0; // Convert to 32-bit signed integer
  }
  return hash;
}

export class LockManager {
  /**
   * Try to acquire a session-level distributed lock on a given key.
   * Returns true if lock is acquired, false otherwise (non-blocking).
   */
  public static async tryAcquireLock(key: string): Promise<boolean> {
    const lockId = hashKeyToInt(key);
    const client = await pgPool.connect();
    try {
      const res = await client.query('SELECT pg_try_advisory_lock($1) as acquired', [lockId]);
      const acquired = res.rows[0].acquired === true;
      if (acquired) {
        logger.info(`🔒 Lock acquired successfully for key: ${key} (id: ${lockId})`);
      } else {
        logger.warn(`⚠️ Failed to acquire lock (busy) for key: ${key} (id: ${lockId})`);
      }
      return acquired;
    } catch (err: any) {
      logger.error(`🔴 Error acquiring advisory lock for key ${key}: ${err.message}`);
      return false;
    } finally {
      client.release();
    }
  }

  /**
   * Release a previously acquired session-level lock.
   * Returns true if released successfully, false otherwise.
   */
  public static async releaseLock(key: string): Promise<boolean> {
    const lockId = hashKeyToInt(key);
    const client = await pgPool.connect();
    try {
      const res = await client.query('SELECT pg_advisory_unlock($1) as released', [lockId]);
      const released = res.rows[0].released === true;
      if (released) {
        logger.info(`🔓 Lock released successfully for key: ${key} (id: ${lockId})`);
      } else {
        logger.warn(`⚠️ Lock was not active/released for key: ${key} (id: ${lockId})`);
      }
      return released;
    } catch (err: any) {
      logger.error(`🔴 Error releasing advisory lock for key ${key}: ${err.message}`);
      return false;
    } finally {
      client.release();
    }
  }
}
