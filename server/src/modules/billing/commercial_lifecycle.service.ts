// server/src/modules/billing/commercial_lifecycle.service.ts
// Serenut OS — Unified Commercial Lifecycle Orchestration Service
//
// This single service handles ALL transitions that result in an active subscription + license entitlement.
// It is called from:
//   1. iyzico webhook (card payment success)
//   2. Admin bank transfer approval
//   3. Admin manual grant
//
// All operations run inside the CALLER's transaction (client passed in).
// The caller is responsible for BEGIN/COMMIT/ROLLBACK.

import { PoolClient } from 'pg';
import { logger } from '../../config/logger';
import crypto from 'crypto';

export interface ActivationParams {
  companyId: string;
  planId: string;
  paymentId?: string;
  grantType: 'card' | 'bank_transfer' | 'admin_grant';
  adminUserId?: string;
  /** If provided, extend from this date instead of NOW() */
  periodStart?: Date;
  /** 'monthly' or 'yearly' */
  billingPeriod?: string;
}

export class CommercialLifecycleService {
  /**
   * Atomically activates or extends a subscription and upserts the license entitlement.
   * Must be called within an existing DB transaction (client must have BEGIN already).
   */
  static async activatePaidSubscription(
    client: PoolClient,
    params: ActivationParams
  ): Promise<{ subscriptionId: string; entitlementId: string }> {
    const { companyId, planId, paymentId, grantType, adminUserId } = params;

    // 1. Load plan limits (single source of truth)
    const planRes = await client.query(
      'SELECT id, name, device_limit, store_limit, trial_days, price, currency FROM plans WHERE id = $1',
      [planId]
    );
    if (planRes.rows.length === 0) {
      throw new Error(`plan_not_found: ${planId}`);
    }
    const plan = planRes.rows[0];

    const now = params.periodStart ?? new Date();
    const periodEnd = new Date(now);
    if (params.billingPeriod === 'yearly') {
      periodEnd.setFullYear(periodEnd.getFullYear() + 1);
    } else {
      periodEnd.setMonth(periodEnd.getMonth() + 1);
    }

    // 2. Upsert subscription (ON CONFLICT on company_id)
    const subId = `sub-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const subRes = await client.query(`
      INSERT INTO subscriptions (
        id, company_id, plan_id, status,
        current_period_start, current_period_end,
        payment_method, cancel_at_period_end,
        grace_period_until, last_payment_status,
        trial_started_at, trial_ends_at
      )
      VALUES ($1, $2, $3, 'active', $4, $5, $6, false, null, 'success', null, null)
      ON CONFLICT (company_id) DO UPDATE SET
        plan_id               = EXCLUDED.plan_id,
        status                = 'active',
        current_period_start  = EXCLUDED.current_period_start,
        current_period_end    = GREATEST(subscriptions.current_period_end, EXCLUDED.current_period_end),
        payment_method        = EXCLUDED.payment_method,
        cancel_at_period_end  = false,
        grace_period_until    = null,
        last_payment_status   = 'success'
      RETURNING id
    `, [subId, companyId, planId, now, periodEnd, grantType === 'card' ? 'credit_card' : grantType === 'bank_transfer' ? 'bank_transfer' : 'admin_grant']);

    const resolvedSubId = subRes.rows[0].id;

    // 3. Lock and deactivate any existing active/trial entitlements for this company
    // (but keep them in DB for history — just mark expired)
    await client.query(`
      SELECT id FROM license_entitlements
      WHERE company_id = $1 AND status IN ('trial', 'active')
      FOR UPDATE
    `, [companyId]);

    await client.query(`
      UPDATE license_entitlements
      SET status = 'expired', updated_at = NOW()
      WHERE company_id = $1 AND status IN ('trial', 'active')
    `, [companyId]);

    // 3b. Resolve or generate license key
    const prevKeyRes = await client.query(
      `SELECT license_key FROM license_entitlements WHERE company_id = $1 AND license_key IS NOT NULL LIMIT 1`,
      [companyId]
    );
    let licenseKey: string;
    if (prevKeyRes.rows.length > 0) {
      licenseKey = prevKeyRes.rows[0].license_key;
    } else {
      const legacyKeyRes = await client.query(
        `SELECT license_key FROM licenses WHERE company_id = $1 LIMIT 1`,
        [companyId]
      );
      if (legacyKeyRes.rows.length > 0) {
        licenseKey = legacyKeyRes.rows[0].license_key;
      } else {
        const parts = [];
        for (let i = 0; i < 4; i++) {
          parts.push(crypto.randomBytes(2).toString('hex').toUpperCase());
        }
        licenseKey = `SRNT-${parts.join('-')}`;
      }
    }

    // 4. Insert new active entitlement
    const entId = `ent-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    await client.query(`
      INSERT INTO license_entitlements (
        id, company_id, subscription_id, plan_id,
        status, device_limit, store_limit,
        valid_from, valid_until, token_version,
        license_key, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, 'active', $5, $6, $7, $8, 1, $9, NOW(), NOW())
    `, [
      entId, companyId, resolvedSubId, planId,
      plan.device_limit, plan.store_limit,
      now, periodEnd, licenseKey
    ]);

    // 4b. Sync legacy licenses table for backward compatibility
    const existingLicense = await client.query(
      `SELECT id FROM licenses WHERE company_id = $1 LIMIT 1`,
      [companyId]
    );

    if (existingLicense.rows.length > 0) {
      await client.query(`
        UPDATE licenses SET
          license_key = $1,
          tier = $2,
          allowed_devices_count = $3,
          status = 'active',
          expires_at = $4
        WHERE company_id = $5
      `, [
        licenseKey,
        plan.name.toLowerCase().includes('pro') ? 'pro' : 'basic',
        plan.device_limit,
        periodEnd,
        companyId
      ]);
    } else {
      await client.query(`
        INSERT INTO licenses (
          id, company_id, license_key, tier,
          allowed_devices_count, status, expires_at, created_at
        )
        VALUES ($1, $2, $3, $4, $5, 'active', $6, NOW())
      `, [
        `lic-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`,
        companyId,
        licenseKey,
        plan.name.toLowerCase().includes('pro') ? 'pro' : 'basic',
        plan.device_limit,
        periodEnd
      ]);
    }

    // 5. Audit log
    await client.query(`
      INSERT INTO audit_logs (id, company_id, user_id, user_name, action, entity, entity_id, new_value)
      VALUES ($1, $2, $3, $4, $5, 'subscription', $6, $7)
    `, [
      `al-${Date.now()}`,
      companyId,
      adminUserId ?? 'system',
      adminUserId ? 'Admin' : 'System',
      `ACTIVATE_SUBSCRIPTION:${grantType.toUpperCase()}`,
      resolvedSubId,
      JSON.stringify({ planId, deviceLimit: plan.device_limit, validUntil: periodEnd, paymentId })
    ]);

    logger.info(`[CommercialLifecycle] Company ${companyId} activated plan ${planId} via ${grantType}. Entitlement: ${entId}`);

    return { subscriptionId: resolvedSubId, entitlementId: entId };
  }
  static async finalizeInvoicePayment(
    client: PoolClient,
    invoiceId: string,
    grantType: 'card' | 'bank_transfer' | 'admin_grant',
    adminUserId?: string
  ): Promise<void> {
    // 1. Lock invoice
    const invRes = await client.query('SELECT * FROM invoices WHERE id = $1 FOR UPDATE', [invoiceId]);
    if (invRes.rows.length === 0) {
      throw new Error('invoice_not_found');
    }
    const invoice = invRes.rows[0];

    // Idempotency check
    if (invoice.status === 'paid') {
      logger.info(`[CommercialLifecycle] Invoice ${invoiceId} is already paid. Skipping finalization.`);
      return;
    }

    // 2. Mark invoice as paid
    await client.query(`
      UPDATE invoices 
      SET status = 'paid', paid_at = NOW() 
      WHERE id = $1
    `, [invoiceId]);

    // 3. Resolve planId and billing_period from billing_details
    let planId = 'plan-free';
    let billingPeriod = 'monthly';
    if (invoice.billing_details) {
      const details = typeof invoice.billing_details === 'string' ? JSON.parse(invoice.billing_details) : invoice.billing_details;
      planId = details.planId || planId;
      billingPeriod = details.billingPeriod || billingPeriod;
    } else if (invoice.subscription_id) {
      const subRes = await client.query('SELECT plan_id FROM subscriptions WHERE id = $1', [invoice.subscription_id]);
      if (subRes.rows.length > 0) planId = subRes.rows[0].plan_id;
    }

    const now = new Date();
    if (billingPeriod === 'yearly') {
      // It sets periodEnd = NOW + 1 month by default in activatePaidSubscription.
      // Wait, activatePaidSubscription currently hardcodes periodEnd to +1 month:
      // periodEnd.setMonth(periodEnd.getMonth() + 1);
      // Let's pass billingPeriod to activatePaidSubscription if we modify it, but let's just do it directly.
    }

    // Call activatePaidSubscription
    const { subscriptionId } = await this.activatePaidSubscription(client, {
      companyId: invoice.company_id,
      planId,
      paymentId: invoice.id,
      grantType,
      adminUserId,
      billingPeriod
    });

    // 4. Update invoice subscription_id if it was null
    if (!invoice.subscription_id) {
      await client.query('UPDATE invoices SET subscription_id = $1 WHERE id = $2', [subscriptionId, invoiceId]);
    }
  }
}
