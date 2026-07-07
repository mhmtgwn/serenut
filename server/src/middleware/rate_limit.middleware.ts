// server/src/middleware/rate_limit.middleware.ts
// Serenut Platform — Tenant Rate Limiting & Abuse Detection Middleware (Sprint 11)
// Enforces credit limits and safeguards gateway channels from spam.
// Created: 04 Jul 2026

import { Response, NextFunction } from 'express';
import { AuthenticatedRequest } from './auth.middleware';
import { pgPool } from '../config/database';
import { logger } from '../config/logger';

// In-Memory cache tracker for campaign limits per company
const campaignTracker = new Map<string, { count: number; windowStart: number }>();

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

/**
 * Limit: A company is restricted to 100 notification messages (queued/sent/failed) per rolling hour
 * to prevent gateway credit drain or script loop errors.
 */
export async function enforceNotificationRateLimit(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const user = req.user;
  if (!user) return res.status(401).json({ error: 'unauthorized' });

  try {
    // Count messages queued in the last 1 hour for this tenant
    const countRes = await runBypassingRLS(`
      SELECT COUNT(*) FROM notification_queue
      WHERE company_id = $1 AND created_at >= NOW() - INTERVAL '1 hour'
    `, [user.company_id]);

    const oneHourCount = parseInt(countRes.rows[0].count, 10);
    const hourlyLimit = 100;

    if (oneHourCount >= hourlyLimit) {
      logger.warn(`Rate limit triggered for company ${user.company_id}. Messages in last hour: ${oneHourCount}/${hourlyLimit}`);
      return res.status(429).json({
        error: 'rate_limit_exceeded',
        message: 'Saatlik maksimum mesaj gönderim limitine (100) ulaştınız. Lütfen daha sonra tekrar deneyin.'
      });
    }

    next();
  } catch (err) {
    logger.error('Rate limit evaluation error:', err);
    next();
  }
}

/**
 * Abuse Protection: Restricts campaign creation actions to 5 times per 1 minute window.
 */
export function enforceCampaignAbuseLimit(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const user = req.user;
  if (!user) return res.status(401).json({ error: 'unauthorized' });

  const companyId = user.company_id;
  const now = Date.now();
  const windowMs = 60 * 1000; // 1 minute
  const maxCampaigns = 5;

  const tracker = campaignTracker.get(companyId) || { count: 0, windowStart: now };

  if (now - tracker.windowStart > windowMs) {
    // Reset window
    tracker.count = 1;
    tracker.windowStart = now;
  } else {
    tracker.count++;
  }

  campaignTracker.set(companyId, tracker);

  if (tracker.count > maxCampaigns) {
    logger.error(`Abuse/spam detected for company ${companyId} - triggered ${tracker.count} campaigns in 1 minute.`);
    return res.status(429).json({
      error: 'abuse_detected',
      message: 'Çok fazla kampanya isteği tespit edildi. 1 dakikada en fazla 5 kampanya başlatılabilir.'
    });
  }

  next();
}
