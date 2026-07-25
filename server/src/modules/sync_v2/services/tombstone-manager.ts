import { pgPool } from '../../../config/database';
import { logger } from '../../../config/logger';

export class TombstoneManagerService {
  /**
   * Purges tombstones older than retentionDays (default 30 days).
   */
  public static async purgeExpiredTombstones(retentionDays: number = 30): Promise<number> {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - retentionDays);

    const query = `
      UPDATE sync_tombstones
      SET purged_at = CURRENT_TIMESTAMP
      WHERE deleted_at < $1 AND purged_at IS NULL
    `;

    const res = await pgPool.query(query, [cutoffDate.toISOString()]);
    const purgedCount = res.rowCount || 0;
    logger.info(`SyncV2 TombstoneManager: Purged ${purgedCount} expired tombstones older than ${retentionDays} days.`);

    return purgedCount;
  }
}
