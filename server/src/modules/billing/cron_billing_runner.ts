// server/src/modules/billing/cron_billing_runner.ts
// Serenut Platform — Automated Billing Cron Job (Sprint 8)
// Processes renewals, applies grace periods, and suspends expired tenants.
// Created: 04 Jul 2026

import { pgPool } from '../../config/database';
import { PoolClient } from 'pg';
import { logger } from '../../config/logger';

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
 * Main billing engine execution routine.
 * Iterates through subscriptions and evaluates renewal / suspension rules.
 */
export async function executeBillingCron(): Promise<void> {
  logger.info('🔄 Billing Cron Engine starting...');
  
  try {
    // 1. Process active subscriptions that have passed their period end
    const expiredActive = await runBypassingRLS(`
      SELECT s.*, p.price, p.currency
      FROM subscriptions s
      JOIN plans p ON s.plan_id = p.id
      WHERE s.status = 'active' AND s.current_period_end <= NOW()
    `);

    for (const sub of expiredActive.rows) {
      if (sub.cancel_at_period_end) {
        // Cancel requested, suspend subscription and license immediately
        logger.info(`Suspending auto-cancelled subscription for company: ${sub.company_id}`);
        await suspendSubscription(sub.company_id, sub.id);
      } else {
        // Attempt simulated payment renewal
        const paymentSuccess = await simulateMockupPayment(sub.company_id, parseFloat(sub.price));
        
        if (paymentSuccess) {
          logger.info(`Successfully renewed subscription for company: ${sub.company_id}`);
          const newStart = new Date();
          const newEnd = new Date();
          newEnd.setMonth(newStart.getMonth() + 1);

          const renewalClient = await pgPool.connect();
          try {
            await renewalClient.query('BEGIN');
            await renewalClient.query("SET LOCAL app.bypass_rls = 'true'");

            await renewalClient.query(`
              UPDATE subscriptions 
              SET current_period_start = $1, current_period_end = $2, last_payment_status = 'success', grace_period_until = null
              WHERE id = $3
            `, [newStart, newEnd, sub.id]);

            // Also extend the license validity
            await renewalClient.query(`
              UPDATE licenses SET status = 'active', expires_at = $1 WHERE company_id = $2
            `, [newEnd, sub.company_id]);

            await renewalClient.query(`
              UPDATE license_entitlements 
              SET status = 'active', valid_until = $1, token_version = token_version + 1, updated_at = NOW()
              WHERE company_id = $2 AND status IN ('trial', 'active')
            `, [newEnd, sub.company_id]);

            await renewalClient.query('COMMIT');
          } catch (txnErr) {
            await renewalClient.query('ROLLBACK').catch(() => {});
            throw txnErr;
          } finally {
            renewalClient.release();
          }

        } else {
          // Payment failed: grant 7-day grace period
          logger.warn(`Payment failed on renewal for company: ${sub.company_id}. Granting 7 days grace period.`);
          const graceUntil = new Date();
          graceUntil.setDate(graceUntil.getDate() + 7);

          const graceClient = await pgPool.connect();
          try {
            await graceClient.query('BEGIN');
            await graceClient.query("SET LOCAL app.bypass_rls = 'true'");

            await graceClient.query(`
              UPDATE subscriptions 
              SET status = 'grace_period', grace_period_until = $1, last_payment_status = 'failed'
              WHERE id = $2
            `, [graceUntil, sub.id]);

            // Log warning/incident via SMS gateway logs mock
            await graceClient.query(`
              INSERT INTO sms_logs (id, company_id, phone, message, status)
              VALUES ($1, $2, 'sys', 'Abonelik yenileme ödemeniz başarısız oldu. Son 7 gün tolerans süreniz.', 'sent')
            `, [`sms-${Date.now()}-${Math.floor(Math.random()*1000)}`, sub.company_id]);

            await graceClient.query('COMMIT');
          } catch (txnErr) {
            await graceClient.query('ROLLBACK').catch(() => {});
            throw txnErr;
          } finally {
            graceClient.release();
          }
        }
      }
    }

    // 2. Process grace period subscriptions that have passed their grace_period_until date
    const expiredGrace = await runBypassingRLS(`
      SELECT * FROM subscriptions 
      WHERE status = 'grace_period' AND grace_period_until <= NOW()
    `);

    for (const sub of expiredGrace.rows) {
      logger.error(`Grace period expired for company: ${sub.company_id}. Suspending services.`);
      await suspendSubscription(sub.company_id, sub.id);
    }

    logger.info('✅ Billing Cron Engine complete.');
  } catch (err) {
    logger.error('Billing Cron Engine encountered fatal error:', err);
  }
}

// Helper: suspend subscription and disable licenses (blocks POS usage)
async function suspendSubscription(companyId: string, subscriptionId: string) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    await client.query(`
      UPDATE subscriptions SET status = 'suspended' WHERE id = $1
    `, [subscriptionId]);

    await client.query(`
      UPDATE licenses SET status = 'suspended' WHERE company_id = $1
    `, [companyId]);

    await client.query(`
      UPDATE license_entitlements 
      SET status = 'expired', token_version = token_version + 1, updated_at = NOW()
      WHERE company_id = $1 AND status IN ('trial', 'active')
    `, [companyId]);

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

// Mock payment helper
async function simulateMockupPayment(companyId: string, amount: number): Promise<boolean> {
  if (process.env.NODE_ENV === 'production') {
    // In production, mockup automatic recurring payment fails since real charging is not implemented yet
    logger.warn(`Billing renewal blocked: Mock payment is disabled in production for company ${companyId}`);
    return false;
  }
  // If company tax number ends in 9, simulate payment failure for verification tests
  const res = await runBypassingRLS('SELECT tax_number FROM companies WHERE id = $1', [companyId]);
  if (res.rows.length > 0) {
    const tax = res.rows[0].tax_number;
    if (tax.endsWith('9')) return false;
  }
  return true;
}
