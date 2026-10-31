// server/src/modules/analytics/telemetry.controller.ts
// Serenut Platform — Health Telemetry, Observability & Audit Logs Router (Sprint 11)
// Created: 04 Jul 2026

import { Router, Response } from 'express';
import os from 'os';
import { telemetryRepository } from './telemetry.repository';
import { authenticateUser, AuthenticatedRequest, requirePermission, requireActiveEntitlementForMutations } from '../../middleware/auth.middleware';
import { logger } from '../../config/logger';

const router = Router();

router.use(authenticateUser);
router.use(requireActiveEntitlementForMutations);

router.post('/upload', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const metrics = Array.isArray(req.body?.metrics) ? req.body.metrics.slice(0, 100) : [];
  if (metrics.length === 0) return res.status(400).json({ error: 'empty_metrics' });

  const accepted = await telemetryRepository.uploadMetrics({
      companyId: user.company_id,
      userId: user.id,
      userName: user.name,
      metrics,
      ip: req.ip || null,
      userAgent: String(req.headers['user-agent'] || 'unknown'),
    });
    return res.json({ success: true, accepted });
});

router.get('/client-events', requirePermission('telemetry.view'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 1000);
  const isSysadmin = user.roles.includes('sysadmin');
  try {
    const result = isSysadmin
      ? await runBypassingRLS(`
          SELECT id, company_id, user_id, metric_name, metric_value, occurred_at, metadata, received_at
          FROM client_telemetry_events ORDER BY occurred_at DESC LIMIT $1
        `, [limit])
      : await runWithTenantContext(user.company_id, `
          SELECT id, company_id, user_id, metric_name, metric_value, occurred_at, metadata, received_at
          FROM client_telemetry_events WHERE company_id = $1 ORDER BY occurred_at DESC LIMIT $2
        `, [user.company_id, limit]);
    return res.json(result.rows);
  } catch (err) {
    logger.error('Client telemetry query failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

const runBypassingRLS = telemetryRepository.runBypassingRLS.bind(telemetryRepository);
const runWithTenantContext = telemetryRepository.runWithTenantContext.bind(telemetryRepository);

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
router.get('/health-status', requirePermission('telemetry.view'), async (req: AuthenticatedRequest, res: Response) => {
  try {
    // 1. CPU & RAM Metrics
    const freeMem = os.freemem();
    const totalMem = os.totalmem();
    const memUsagePct = ((totalMem - freeMem) / totalMem) * 100;
    
    // 2. Database active connections pool
    const activeConns = telemetryRepository.getActiveDbPoolCount();

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
router.get('/audit-logs', requirePermission('telemetry.view'), async (req: AuthenticatedRequest, res: Response) => {
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
