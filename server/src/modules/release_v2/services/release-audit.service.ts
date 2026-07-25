// server/src/modules/release_v2/services/release-audit.service.ts
import { Pool } from 'pg';
import crypto from 'crypto';

export interface AuditLogEntry {
  releaseId: string;
  actorId: string;
  action: 'PUBLISH' | 'PROMOTE' | 'YANK' | 'ROLLBACK' | 'SIGN';
  fromState?: string | null;
  toState?: string | null;
  payload?: any;
}

function canonicalizeJson(obj: any): string {
  if (obj === null || obj === undefined) return '{}';
  if (typeof obj !== 'object') return JSON.stringify(obj);
  if (Array.isArray(obj)) {
    return '[' + obj.map(canonicalizeJson).join(',') + ']';
  }
  const keys = Object.keys(obj).sort();
  const parts = keys.map(k => `${JSON.stringify(k)}:${canonicalizeJson(obj[k])}`);
  return '{' + parts.join(',') + '}';
}

export class ReleaseAuditService {
  constructor(private pool: Pool) {}

  /**
   * Logs a tamper-evident audit record by chaining hashes with the previous log entry.
   */
  async log(entry: AuditLogEntry): Promise<string> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // Fetch the last record's hash to chain
      const lastRes = await client.query(`
        SELECT record_hash 
        FROM release_audit 
        ORDER BY id DESC 
        LIMIT 1
      `);

      const previousHash = lastRes.rows.length > 0 
        ? lastRes.rows[0].record_hash 
        : '0000000000000000000000000000000000000000000000000000000000000000';

      const payloadStr = canonicalizeJson(entry.payload);

      // Compute hash: SHA256(previousHash + releaseId + actorId + action + fromState + toState + payloadStr)
      const dataToHash = [
        previousHash,
        entry.releaseId,
        entry.actorId,
        entry.action,
        entry.fromState || '',
        entry.toState || '',
        payloadStr
      ].join('|');

      const recordHash = crypto.createHash('sha256').update(dataToHash).digest('hex');

      await client.query(`
        INSERT INTO release_audit (
          release_id, actor_id, action, from_state, to_state, payload, previous_record_hash, record_hash
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `, [
        entry.releaseId,
        entry.actorId,
        entry.action,
        entry.fromState || null,
        entry.toState || null,
        entry.payload || null,
        previousHash,
        recordHash
      ]);

      await client.query('COMMIT');
      return recordHash;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Verifies the entire audit trail chain, ensuring no records have been tampered with or deleted.
   * Returns true if the chain is fully valid, false if tampering is detected.
   */
  async verifyAuditChain(): Promise<{ valid: boolean; compromisedId?: string }> {
    const res = await this.pool.query('SELECT * FROM release_audit ORDER BY id ASC');
    let expectedPreviousHash = '0000000000000000000000000000000000000000000000000000000000000000';

    for (const row of res.rows) {
      if (row.previous_record_hash !== expectedPreviousHash) {
        return { valid: false, compromisedId: String(row.id) };
      }

      const payloadStr = canonicalizeJson(row.payload);
      const dataToHash = [
        row.previous_record_hash,
        row.release_id,
        row.actor_id,
        row.action,
        row.from_state || '',
        row.to_state || '',
        payloadStr
      ].join('|');

      const computedHash = crypto.createHash('sha256').update(dataToHash).digest('hex');

      if (row.record_hash !== computedHash) {
        return { valid: false, compromisedId: String(row.id) };
      }

      expectedPreviousHash = row.record_hash;
    }

    return { valid: true };
  }
}
