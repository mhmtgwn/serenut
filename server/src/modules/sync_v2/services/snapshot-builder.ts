import { pgPool } from '../../../config/database';
import { logger } from '../../../config/logger';

export interface SnapshotPayload {
  tenant_id: string;
  domain: string;
  snapshot_revision: number;
  entities: Record<string, any>[];
  created_at: string;
}

export class SnapshotBuilderService {
  /**
   * Generates a full state snapshot for a given tenant and domain.
   */
  public static async createSnapshot(tenant_id: string, domain: string): Promise<SnapshotPayload> {
    // 1. Get head revision for the domain
    const compRes = await pgPool.query('SELECT domain_revisions FROM companies WHERE id = $1', [tenant_id]);
    if (compRes.rowCount === 0) {
      throw new Error(`Tenant company not found: ${tenant_id}`);
    }

    const domainRevs = compRes.rows[0].domain_revisions || {};
    const snapshot_revision = domainRevs[domain] || 0;

    // 2. Query all active entities for the domain from sync_revisions (latest state per entity_id)
    const entityQuery = `
      SELECT DISTINCT ON (entity_type, entity_id) entity_type, entity_id, op_type, payload, revision
      FROM sync_revisions
      WHERE tenant_id = $1 AND domain = $2
      ORDER BY entity_type, entity_id, revision DESC
    `;
    const res = await pgPool.query(entityQuery, [tenant_id, domain]);

    // Filter out deleted entities
    const activeEntities = res.rows
      .filter((row) => row.op_type !== 'DELETE')
      .map((row) => ({
        entity_type: row.entity_type,
        entity_id: row.entity_id,
        payload: typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload,
        revision: parseInt(row.revision, 10),
      }));

    const snapshotPayloadJson = JSON.stringify(activeEntities);

    // 3. Save snapshot to sync_snapshots table
    await pgPool.query(
      `INSERT INTO sync_snapshots (tenant_id, domain, snapshot_revision, payload)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (tenant_id, domain, snapshot_revision) DO UPDATE SET payload = EXCLUDED.payload`,
      [tenant_id, domain, snapshot_revision, snapshotPayloadJson]
    );

    logger.info(`SyncV2 SnapshotBuilder: Created snapshot for tenant ${tenant_id}, domain ${domain} at rev ${snapshot_revision}`);

    return {
      tenant_id,
      domain,
      snapshot_revision,
      entities: activeEntities,
      created_at: new Date().toISOString(),
    };
  }

  /**
   * Fetches latest snapshot for a tenant and domain.
   */
  public static async getLatestSnapshot(tenant_id: string, domain: string): Promise<SnapshotPayload | null> {
    const res = await pgPool.query(
      `SELECT snapshot_revision, payload, created_at
       FROM sync_snapshots
       WHERE tenant_id = $1 AND domain = $2
       ORDER BY snapshot_revision DESC
       LIMIT 1`,
      [tenant_id, domain]
    );

    if (res.rowCount === 0) {
      return null;
    }

    const row = res.rows[0];
    return {
      tenant_id,
      domain,
      snapshot_revision: parseInt(row.snapshot_revision, 10),
      entities: typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload,
      created_at: row.created_at,
    };
  }
}
