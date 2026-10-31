// server/src/modules/analytics/telemetry.repository.ts
import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';

export class TelemetryRepository {
  getActiveDbPoolCount(): number {
    return pgPool.waitingCount + pgPool.totalCount;
  }

  async runBypassingRLS(sql: string, params: any[] = []) {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const res = await client.query(sql, params);
      await client.query('COMMIT');
      return res;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
      const res = await client.query(sql, params);
      await client.query('COMMIT');
      return res;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async uploadMetrics(params: {
    companyId: string;
    userId: string;
    userName?: string;
    metrics: any[];
    ip: string | null;
    userAgent: string;
  }): Promise<number> {
    const { companyId, userId, userName, metrics, ip, userAgent } = params;
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
      for (const metric of metrics) {
        const name = String(metric.metric_name || '').slice(0, 120);
        if (!/^[a-z0-9_.-]+$/i.test(name)) continue;
        const value = Number(metric.metric_value);
        const occurredAt = new Date(metric.timestamp);
        if (!Number.isFinite(value) || Number.isNaN(occurredAt.getTime())) continue;

        let metadata: Record<string, unknown> = {};
        try {
          const parsed = typeof metric.metadata === 'string'
            ? JSON.parse(metric.metadata || '{}')
            : metric.metadata;
          if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) metadata = parsed;
        } catch (err) {
          logger.debug('Malformed telemetry metadata payload skipped', { err });
        }

        for (const key of ['token', 'access_token', 'refresh_token', 'password', 'authorization']) {
          delete metadata[key];
        }

        await client.query(`
          INSERT INTO client_telemetry_events
            (company_id, user_id, metric_name, metric_value, occurred_at, metadata, ip_address, user_agent)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        `, [
          companyId, userId, name, value, occurredAt.toISOString(),
          JSON.stringify(metadata), ip,
          userAgent.slice(0, 500)
        ]);

        if (name === 'audit_event' && typeof metadata.record_hash === 'string') {
          await client.query(`
            INSERT INTO audit_logs
              (id, company_id, user_id, user_name, action, entity_type,
               entity_id, old_values, new_values, ip_address, user_agent,
               device_id, previous_hash, record_hash, created_at)
            VALUES
              ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            ON CONFLICT DO NOTHING
          `, [
            String(metadata.id || `audit-${Date.now()}`),
            companyId,
            userId,
            String(userName || metadata.user_name || 'Kullanıcı').slice(0, 150),
            String(metadata.event_type || 'unknown').slice(0, 150),
            String(metadata.entity_type || 'unknown').slice(0, 120),
            metadata.entity_id ? String(metadata.entity_id).slice(0, 255) : null,
            metadata.old_value ? JSON.stringify(metadata.old_value) : null,
            metadata.new_value ? JSON.stringify(metadata.new_value) : null,
            ip,
            userAgent.slice(0, 500),
            metadata.device_id ? String(metadata.device_id).slice(0, 255) : null,
            metadata.previous_hash ? String(metadata.previous_hash).slice(0, 64) : null,
            String(metadata.record_hash).slice(0, 64),
            occurredAt.toISOString(),
          ]);
        }
      }
      await client.query('COMMIT');
      return metrics.length;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
}

export const telemetryRepository = new TelemetryRepository();
