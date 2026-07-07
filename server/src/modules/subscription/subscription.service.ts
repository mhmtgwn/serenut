// server/src/modules/subscription/subscription.service.ts
// Serenut OS — Subscription State Machine
// Blueprint: state_machine_specification.md — Section 1
// FSM: trialing → active → past_due → suspended → deleted
//      trialing → expired → active (paid) or deleted (90 days)
//      active → cancelled → deleted (6 months)

import { pgPool, redisClient } from '../../config/database';
import { logger } from '../../config/logger';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';

// ── ALLOWED STATE TRANSITIONS ─────────────────────────────────────────────────
// Key: current state | Value: allowed next states
const ALLOWED_TRANSITIONS: Record<string, string[]> = {
  trialing: ['active', 'expired'],
  active: ['past_due', 'cancelled'],
  past_due: ['active', 'suspended'],
  suspended: ['active', 'deleted'],
  expired: ['active', 'deleted'],
  cancelled: ['deleted'],
  deleted: [],
};

function assertTransition(from: string, to: string): void {
  const allowed = ALLOWED_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw new Error(
      `Invalid subscription FSM transition: ${from} → ${to}. Allowed: [${allowed.join(', ')}]`
    );
  }
}

export class SubscriptionService {
  /**
   * Transitions the company's active subscription to a new state.
   * Enforces FSM rules — throws if the transition is illegal.
   */
  static async transition(
    companyId: string,
    toStatus: string,
    meta?: { reason?: string; performedBy?: string }
  ): Promise<void> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      const subRes = await client.query(
        `SELECT id, status FROM subscriptions WHERE company_id = $1 ORDER BY current_period_start DESC LIMIT 1`,
        [companyId]
      );

      if (subRes.rows.length === 0) {
        throw new Error(`No subscription found for company ${companyId}`);
      }

      const sub = subRes.rows[0];
      assertTransition(sub.status, toStatus);

      const now = new Date();
      const updates: string[] = [`status = '${toStatus}'`];
      const values: any[] = [];
      let paramIdx = 1;

      // State-specific column updates
      if (toStatus === 'suspended') {
        updates.push(`suspended_at = $${paramIdx++}`);
        values.push(now);
      }
      if (toStatus === 'cancelled') {
        updates.push(`cancelled_at = $${paramIdx++}`);
        values.push(now);
        // Schedule deletion 6 months from now (data retention)
        const deleteAt = new Date(now.getTime() + 6 * 30 * 24 * 60 * 60 * 1000);
        updates.push(`deletion_scheduled_at = $${paramIdx++}`);
        values.push(deleteAt);
      }
      if (toStatus === 'past_due') {
        // Increment retry count
        updates.push(`payment_retry_count = payment_retry_count + 1`);
        // Schedule next retry: 1→day1, 2→day3, 3→day5, 4→day7
        const retryDays = [1, 3, 5, 7];
        const retryCount = (sub.payment_retry_count ?? 0) + 1;
        const dayOffset = retryDays[Math.min(retryCount, retryDays.length) - 1];
        const nextRetry = new Date(now.getTime() + dayOffset * 24 * 60 * 60 * 1000);
        updates.push(`next_retry_at = $${paramIdx++}`);
        values.push(nextRetry);
      }
      if (toStatus === 'active') {
        // Clear retry tracking on successful payment
        updates.push(`payment_retry_count = 0`);
        updates.push(`next_retry_at = NULL`);
        updates.push(`suspended_at = NULL`);
      }

      values.push(sub.id);
      await client.query(
        `UPDATE subscriptions SET ${updates.join(', ')} WHERE id = $${paramIdx}`,
        values
      );

      await client.query('COMMIT');

      logger.info(`Subscription FSM: ${sub.status} → ${toStatus} for company ${companyId}`, {
        companyId,
        from: sub.status,
        to: toStatus,
        ...(meta ?? {}),
      });

      // Broadcast LICENSE_CHANGED to all active terminals
      // This triggers re-validation on the client side
      const eventPayload = { companyId, subscriptionStatus: toStatus };
      RealtimeBroadcastService.publishEvent(companyId, 'LICENSE_CHANGED', eventPayload).catch(
        (err) => logger.error('Failed to broadcast LICENSE_CHANGED:', err)
      );

      // Invalidate subscription cache
      if (redisClient?.isOpen) {
        await redisClient.del(`sub:${companyId}`).catch(() => {});
      }
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Returns the current subscription for a company.
   * Caches in Redis for 60 seconds.
   */
  static async getSubscription(companyId: string): Promise<any | null> {
    // Try cache first
    if (redisClient?.isOpen) {
      try {
        const cached = await redisClient.get(`sub:${companyId}`);
        if (cached) return JSON.parse(cached);
      } catch (_) {}
    }

    const res = await pgPool.query(
      `SELECT id, company_id, plan_id, status, trial_started_at, trial_ends_at,
              current_period_start, current_period_end, payment_retry_count,
              next_retry_at, suspended_at, cancelled_at, deletion_scheduled_at
       FROM subscriptions
       WHERE company_id = $1
       ORDER BY created_at DESC
       LIMIT 1`,
      [companyId]
    );

    if (res.rows.length === 0) return null;

    const sub = res.rows[0];

    // Auto-transition expired trials
    if (
      sub.status === 'trialing' &&
      sub.trial_ends_at &&
      new Date(sub.trial_ends_at) < new Date()
    ) {
      logger.info(`Auto-expiring trial for company ${companyId}`);
      await SubscriptionService.transition(companyId, 'expired', {
        reason: 'trial_period_ended',
        performedBy: 'system',
      }).catch((err) => logger.error('Failed to auto-expire trial:', err));
      sub.status = 'expired';
    }

    // Cache for 60 seconds
    if (redisClient?.isOpen) {
      await redisClient.setEx(`sub:${companyId}`, 60, JSON.stringify(sub)).catch(() => {});
    }

    return sub;
  }

  /**
   * Returns days remaining in trial. Negative if expired.
   */
  static trialDaysRemaining(subscription: any): number {
    if (!subscription?.trial_ends_at) return 30;
    const msLeft = new Date(subscription.trial_ends_at).getTime() - Date.now();
    return Math.ceil(msLeft / (24 * 60 * 60 * 1000));
  }

  /**
   * Checks if the company can perform operations (active or trialing).
   * Used by guards in license.service.ts and sync.controller.ts.
   */
  static isOperational(subscription: any): boolean {
    if (!subscription) return false;
    return ['trialing', 'active', 'past_due'].includes(subscription.status);
  }
}
