import { PoolClient } from 'pg';
import { pgPool } from '../../../config/database';
import { logger } from '../../../config/logger';
import { MutationPayload } from '../domain/conflict-resolver';
import { MutationValidatorDomain } from '../domain/mutation-validator';
import { SignalBroadcaster } from '../ws/signal-broadcaster';

export interface ProcessedMutationResult {
  client_mutation_id: string;
  revision: number;
  domain: string;
  op_type: string;
  status: 'APPLIED' | 'IDEMPOTENT_SKIPPED' | 'REJECTED';
  error?: string;
}

export class RevisionService {
  /**
   * Processes a batch of client mutations inside a single isolated PostgreSQL transaction.
   */
  public static async processMutationsBatch(
    tenant_id: string,
    device_id: string,
    mutations: MutationPayload[]
  ): Promise<{ results: ProcessedMutationResult[]; head_vectors: Record<string, number> }> {
    const client: PoolClient = await pgPool.connect();
    const results: ProcessedMutationResult[] = [];

    try {
      await client.query('BEGIN');

      // 1. Fetch Company Lock & Current Revisions
      const companyRes = await client.query(
        'SELECT current_revision, domain_revisions FROM companies WHERE id = $1 FOR UPDATE',
        [tenant_id]
      );

      if (companyRes.rowCount === 0) {
        throw new Error(`Tenant company not found: ${tenant_id}`);
      }

      let globalRev = parseInt(companyRes.rows[0].current_revision, 10) || 0;
      let domainVectors: Record<string, number> = companyRes.rows[0].domain_revisions || {
        sales: 0,
        stock: 0,
        customer: 0,
        invoice: 0,
        settings: 0,
      };

      for (const mutation of mutations) {
        const validation = MutationValidatorDomain.validate(mutation);
        if (!validation.valid) {
          results.push({
            client_mutation_id: mutation.client_mutation_id,
            revision: 0,
            domain: mutation.domain || 'unknown',
            op_type: mutation.op_type || 'UNKNOWN',
            status: 'REJECTED',
            error: validation.error,
          });
          continue;
        }

        // 2. Idempotency Check
        const existingRevRes = await client.query(
          'SELECT revision, domain FROM sync_revisions WHERE tenant_id = $1 AND client_mutation_id = $2',
          [tenant_id, mutation.client_mutation_id]
        );

        if (existingRevRes.rowCount! > 0) {
          results.push({
            client_mutation_id: mutation.client_mutation_id,
            revision: parseInt(existingRevRes.rows[0].revision, 10),
            domain: existingRevRes.rows[0].domain,
            op_type: mutation.op_type,
            status: 'IDEMPOTENT_SKIPPED',
          });
          continue;
        }

        // 3. Increment Revision Sequence
        globalRev += 1;
        domainVectors[mutation.domain] = (domainVectors[mutation.domain] || 0) + 1;
        const assignedRev = globalRev;

        // 4. Write Revision Entry to DB Log
        await client.query(
          `INSERT INTO sync_revisions 
            (tenant_id, revision, domain, entity_type, entity_id, op_type, payload, client_mutation_id, device_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
          [
            tenant_id,
            assignedRev,
            mutation.domain,
            mutation.entity_type,
            mutation.entity_id,
            mutation.op_type,
            JSON.stringify(mutation.payload),
            mutation.client_mutation_id,
            device_id,
          ]
        );

        // 5. If DELETE or RESTORE, update tombstones table
        if (mutation.op_type === 'DELETE') {
          await client.query(
            `INSERT INTO sync_tombstones (tenant_id, domain, entity_type, entity_id, deleted_by_device)
             VALUES ($1, $2, $3, $4, $5)`,
            [tenant_id, mutation.domain, mutation.entity_type, mutation.entity_id, device_id]
          );
        } else if (mutation.op_type === 'RESTORE') {
          await client.query(
            `DELETE FROM sync_tombstones 
             WHERE tenant_id = $1 AND entity_type = $2 AND entity_id = $3`,
            [tenant_id, mutation.entity_type, mutation.entity_id]
          );
        }

        results.push({
          client_mutation_id: mutation.client_mutation_id,
          revision: assignedRev,
          domain: mutation.domain,
          op_type: mutation.op_type,
          status: 'APPLIED',
        });
      }

      // 6. Update Company Domain Vectors & Current Revision
      await client.query(
        'UPDATE companies SET current_revision = $1, domain_revisions = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3',
        [globalRev, JSON.stringify(domainVectors), tenant_id]
      );

      await client.query('COMMIT');
      logger.info(`SyncV2: Processed ${mutations.length} mutations for tenant ${tenant_id}. New Head Rev: ${globalRev}`);

      // Publish Signal Invalidation (Zero Data Payload)
      for (const [domain, rev] of Object.entries(domainVectors)) {
        SignalBroadcaster.publishInvalidation(tenant_id, domain, rev as number).catch(() => {});
      }

      return {
        results,
        head_vectors: domainVectors,
      };
    } catch (err: any) {
      await client.query('ROLLBACK');
      logger.error(`SyncV2 RevisionService Error: ${err.message}`);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Fetches latest head vectors for a tenant.
   */
  public static async getHeadVectors(tenant_id: string): Promise<Record<string, number>> {
    const res = await pgPool.query(
      'SELECT domain_revisions FROM companies WHERE id = $1',
      [tenant_id]
    );
    if (res.rowCount === 0) {
      return { sales: 0, stock: 0, customer: 0, invoice: 0, settings: 0 };
    }
    return res.rows[0].domain_revisions || {};
  }
}
