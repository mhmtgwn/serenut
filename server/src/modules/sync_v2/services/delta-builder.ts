import { pgPool } from '../../../config/database';
import { RevisionService } from './revision-service';

export interface DeltaItem {
  domain: string;
  revision: number;
  entity_type: string;
  entity_id: string;
  op_type: string;
  payload: Record<string, any>;
  client_mutation_id: string;
  created_at: string;
}

export interface DeltaFetchResult {
  head_vectors: Record<string, number>;
  has_more: boolean;
  deltas: DeltaItem[];
}

export class DeltaBuilderService {
  /**
   * Fetches delta revisions given client domain vectors.
   */
  public static async fetchDeltas(
    tenant_id: string,
    client_vectors: Record<string, number>,
    max_batch_size: number = 500
  ): Promise<DeltaFetchResult> {
    const head_vectors = await RevisionService.getHeadVectors(tenant_id);
    const deltas: DeltaItem[] = [];

    // Construct SQL clauses for domain revision filters
    const domainConditions: string[] = [];
    const queryParams: any[] = [tenant_id];
    let paramIdx = 2;

    for (const [domain, headRev] of Object.entries(head_vectors)) {
      const clientRev = client_vectors[domain] ?? 0;
      if (clientRev < headRev) {
        domainConditions.push(`(domain = $${paramIdx} AND revision > $${paramIdx + 1})`);
        queryParams.push(domain, clientRev);
        paramIdx += 2;
      }
    }

    if (domainConditions.length === 0) {
      return {
        head_vectors,
        has_more: false,
        deltas: [],
      };
    }

    const whereClause = `tenant_id = $1 AND (${domainConditions.join(' OR ')})`;
    queryParams.push(max_batch_size + 1); // +1 to check has_more

    const query = `
      SELECT revision, domain, entity_type, entity_id, op_type, payload, client_mutation_id, created_at
      FROM sync_revisions
      WHERE ${whereClause}
      ORDER BY revision ASC
      LIMIT $${queryParams.length}
    `;

    const res = await pgPool.query(query, queryParams);
    const rows = res.rows;
    const has_more = rows.length > max_batch_size;
    const targetRows = has_more ? rows.slice(0, max_batch_size) : rows;

    for (const row of targetRows) {
      deltas.push({
        domain: row.domain,
        revision: parseInt(row.revision, 10),
        entity_type: row.entity_type,
        entity_id: row.entity_id,
        op_type: row.op_type,
        payload: typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload,
        client_mutation_id: row.client_mutation_id,
        created_at: row.created_at,
      });
    }

    return {
      head_vectors,
      has_more,
      deltas,
    };
  }
}
