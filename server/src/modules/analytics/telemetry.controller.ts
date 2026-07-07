// server/src/modules/analytics/telemetry.controller.ts
// Serenut Platform — Health Telemetry, Observability & Audit Logs Router (Sprint 11)
// Created: 04 Jul 2026

import { Router, Response } from 'express';
import os from 'os';
import { pgPool } from '../../config/database';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../middleware/auth.middleware';
import { logger } from '../../config/logger';

const router = Router();

router.use(authenticateUser);

async function runBypassingRLS(sql: string, params: any[] = []) {
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

async function runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SET LOCAL app.current_company_id = '${companyId.replace(/'/g, "''")}'`);
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

/**
 * Write a secure, un-erasable Audit Log entry
 */
export async function writeAuditLog(
  companyId: string,
  userId: string,
  userName: string,
  action: string,
  entityType: string,
  entityId: string,
  oldValues: any,
  newValues: any,
  ipAddress: string,
  userAgent: string
) {
  const id = `aud-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
  try {
    await runBypassingRLS(`
      INSERT INTO audit_logs (id, company_id, user_id, user_name, action, entity_type, entity_id, old_values, new_values, ip_address, user_agent)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    `, [
      id,
      companyId,
      userId,
      userName,
      action,
      entityType,
      entityId,
      oldValues ? JSON.stringify(oldValues) : null,
      newValues ? JSON.stringify(newValues) : null,
      ipAddress || '127.0.0.1',
      userAgent || 'unknown_agent'
    ]);
  } catch (err) {
    logger.error('Failed to write audit log:', err);
  }
}

/**
 * @openapi
 * /api/v1/telemetry/health-status:
 *   get:
 *     summary: Retrieve real-time CPU, DB connection pools, Queue volumes and Gateway healths
 */
router.get('/health-status', async (req: AuthenticatedRequest, res: Response) => {
  try {
    // 1. CPU & RAM Metrics
    const freeMem = os.freemem();
    const totalMem = os.totalmem();
    const memUsagePct = ((totalMem - freeMem) / totalMem) * 100;
    
    // 2. Database active connections pool
    const activeConns = pgPool.waitingCount + pgPool.totalCount;

    // 3. Queue metrics (bypass RLS to check overall/own queue statistics)
    const queueStats = await runBypassingRLS(`
      SELECT status, COUNT(*) as qty 
      FROM notification_queue 
      GROUP BY status
    `);

    const queueReport: Record<string, number> = { queued: 0, sending: 0, sent: 0, failed: 0, retrying: 0 };
    for (const row of queueStats.rows) {
      queueReport[row.status] = parseInt(row.qty, 10);
    }

    // 4. Gateway health evaluations (Check error rates in last 10 attempts per channel)
    // If error rate is >= 30%, report DOWN. Otherwise UP.
    const gateways = ['sms', 'email', 'push', 'whatsapp'];
    const gatewayHealthReport: Record<string, string> = {};

    for (const gw of gateways) {
      const attempts = await runBypassingRLS(`
        SELECT status FROM notification_queue
        WHERE channel = $1
        ORDER BY created_at DESC
        LIMIT 10
      `, [gw]);

      if (attempts.rows.length === 0) {
        gatewayHealthReport[gw] = 'UP';
        continue;
      }

      const fails = attempts.rows.filter(r => r.status === 'failed').length;
      const failRate = (fails / attempts.rows.length) * 100;

      gatewayHealthReport[gw] = failRate >= 30 ? 'DOWN' : 'UP';
    }

    return res.json({
      system: {
        cpuLoad: os.loadavg()[0],
        memoryUsage: memUsagePct.toFixed(2) + '%',
        dbActivePool: activeConns,
      },
      queue: queueReport,
      gateways: gatewayHealthReport,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    logger.error('Telemetry report failure:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/telemetry/audit-logs:
 *   get:
 *     summary: Retrieve RLS-scoped audit trails for this tenant
 */
router.get('/audit-logs', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const logs = await runWithTenantContext(
      user.company_id,
      'SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 50'
    );
    return res.json(logs.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/telemetry/audit-logs:
 *   post:
 *     summary: Log a critical operational change securely
 */
router.post('/audit-logs', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { action, entity_type, entity_id, old_values, new_values } = req.body;

  if (!action || !entity_type || !entity_id) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  try {
    await writeAuditLog(
      user.company_id,
      user.id,
      user.name,
      action,
      entity_type,
      entity_id,
      old_values,
      new_values,
      req.ip || '127.0.0.1',
      req.headers['user-agent'] || 'unknown'
    );

    return res.status(201).json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
