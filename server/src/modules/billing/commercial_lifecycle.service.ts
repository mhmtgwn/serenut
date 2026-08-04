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
import { BillingDomainService, BillingPeriod } from './billing-domain.service';

export interface ActivationParams {
  companyId: string;
  planId: string;
  paymentId?: string;
  grantType: 'card' | 'bank_transfer' | 'admin_grant';
  adminUserId?: string;
  /** If provided, extend from this date instead of NOW() */
  periodStart?: Date;
  /** 'monthly' or 'yearly' */
  billingPeriod?: BillingPeriod;
  /** Audited manual exceptions only; paid activations must use billingPeriod. */
  grantDays?: number;
  deviceLimitOverride?: number;
  storeLimitOverride?: number;
  grantReason?: string;
}

export class CommercialLifecycleService {
  static async provisionPendingTrial(
    client: PoolClient,
    params: { companyId: string; planId?: string },
  ): Promise<{ subscriptionId: string; entitlementId: string; licenseId: string; licenseKey: string }> {
    const planId = params.planId ?? 'plan-basic';
    const plan = await client.query(
      `SELECT id,device_limit,store_limit FROM plans WHERE id=$1`,
      [planId],
    );
    if (!plan.rowCount) throw new Error('trial_plan_not_found');
    const prior = await client.query(
      `SELECT s.id subscription_id,le.id entitlement_id,l.id license_id,le.license_key
       FROM subscriptions s JOIN license_entitlements le ON le.subscription_id=s.id
       JOIN licenses l ON l.company_id=s.company_id AND l.license_key=le.license_key
       WHERE s.company_id=$1 FOR UPDATE OF s,le,l`,
      [params.companyId],
    );
    if (prior.rowCount) return {
      subscriptionId: prior.rows[0].subscription_id,
      entitlementId: prior.rows[0].entitlement_id,
      licenseId: prior.rows[0].license_id,
      licenseKey: prior.rows[0].license_key,
    };
    const subscriptionId = BillingDomainService.opaqueId('sub');
    const entitlementId = BillingDomainService.opaqueId('ent');
    const licenseId = BillingDomainService.opaqueId('lic');
    const licenseKey = `SRNT-${crypto.randomBytes(2).toString('hex').toUpperCase()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
    await client.query(
      `INSERT INTO subscriptions(id,company_id,plan_id,status,current_period_start,current_period_end,
         trial_started_at,trial_ends_at,payment_retry_count)
       VALUES($1,$2,$3,'trialing',NOW(),NOW() + INTERVAL '1 second',NULL,NULL,0)`,
      [subscriptionId, params.companyId, planId],
    );
    await client.query(
      `INSERT INTO license_entitlements(id,company_id,subscription_id,plan_id,status,
         device_limit,store_limit,valid_from,valid_until,token_version,license_key)
       VALUES($1,$2,$3,$4,'trial',$5,$6,NULL,NULL,1,$7)`,
      [entitlementId, params.companyId, subscriptionId, planId,
        plan.rows[0].device_limit, plan.rows[0].store_limit, licenseKey],
    );
    await client.query(
      `INSERT INTO licenses(id,company_id,license_key,tier,allowed_devices_count,status,expires_at)
       VALUES($1,$2,$3,'trial',$4,'inactive',NOW())`,
      [licenseId, params.companyId, licenseKey, plan.rows[0].device_limit],
    );
    return { subscriptionId, entitlementId, licenseId, licenseKey };
  }

  /**
   * Atomically activates or extends a subscription and upserts the license entitlement.
   * Must be called within an existing DB transaction (client must have BEGIN already).
   */
  private static async activatePaidSubscription(
    client: PoolClient,
    params: ActivationParams
  ): Promise<{ subscriptionId: string; entitlementId: string; validFrom: Date; validUntil: Date }> {
    const { companyId, planId, paymentId, grantType, adminUserId } = params;

    // 1. Load plan limits (single source of truth)
    const planRes = await client.query(
      `SELECT p.id, p.name, COALESCE(o.device_limit,p.device_limit) AS device_limit,
              COALESCE(o.store_limit,p.store_limit) AS store_limit,
              COALESCE(o.user_limit,p.user_limit) AS user_limit,
              COALESCE(o.custom_price,p.price) AS price, p.currency, p.trial_days,
              COALESCE(o.billing_interval,p.billing_interval) AS effective_billing_interval,
              COALESCE(p.features,'{}'::jsonb)||COALESCE(o.feature_overrides,'{}'::jsonb) AS features
       FROM plans p LEFT JOIN subscription_overrides o ON o.company_id=$2
        AND o.base_plan_id=p.id AND o.is_active=TRUE
        AND CURRENT_TIMESTAMP BETWEEN o.valid_from AND o.valid_until
       WHERE p.id=$1`,
      [planId, companyId]
    );
    if (planRes.rows.length === 0) {
      throw new Error(`plan_not_found: ${planId}`);
    }
    const plan = planRes.rows[0];

    const now = params.periodStart ?? new Date();

    // Renewals extend the furthest active expiry. Lock both the modern and
    // legacy records because web and installed clients still read both models.
    const existingSubRes = await client.query(
      `SELECT current_period_end FROM subscriptions WHERE company_id = $1 FOR UPDATE`,
      [companyId]
    );
    const existingEntitlementRes = await client.query(
      `SELECT valid_until FROM license_entitlements
       WHERE company_id = $1 AND status IN ('trial', 'active') FOR UPDATE`,
      [companyId]
    );
    const existingLegacyRes = await client.query(
      `SELECT expires_at FROM licenses
       WHERE company_id = $1 AND status = 'active' FOR UPDATE`,
      [companyId]
    );
    const renewalBase = [
      now,
      ...existingSubRes.rows.map(row => new Date(row.current_period_end)),
      ...existingEntitlementRes.rows.map(row => new Date(row.valid_until)),
      ...existingLegacyRes.rows.map(row => new Date(row.expires_at)),
    ].filter(value => !Number.isNaN(value.getTime()))
      .reduce((latest, value) => value > latest ? value : latest, now);

    const billingPeriod = BillingDomainService.normalizePeriod(
      params.billingPeriod ?? plan.effective_billing_interval
    );
    if (grantType === 'admin_grant' && !params.grantReason?.trim()) {
      throw new Error('admin_grant_reason_required');
    }
    const periodEnd = params.grantDays != null
      ? new Date(renewalBase.getTime() + params.grantDays * 24 * 60 * 60 * 1000)
      : BillingDomainService.addPeriod(renewalBase, billingPeriod);
    if (params.grantDays != null &&
        (grantType !== 'admin_grant' || !Number.isInteger(params.grantDays) || params.grantDays < 1 || params.grantDays > 3660)) {
      throw new Error('invalid_admin_grant_days');
    }
    const resolvedDeviceLimit = params.deviceLimitOverride ?? Number(plan.device_limit);
    const resolvedStoreLimit = params.storeLimitOverride ?? Number(plan.store_limit);
    if (!Number.isInteger(resolvedDeviceLimit) || resolvedDeviceLimit < 1 || resolvedDeviceLimit > 1000 ||
        !Number.isInteger(resolvedStoreLimit) || resolvedStoreLimit < 1 || resolvedStoreLimit > 1000) {
      throw new Error('invalid_entitlement_limits');
    }

    // 2. Upsert subscription (ON CONFLICT on company_id)
    const subId = `sub-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const subRes = await client.query(`
      INSERT INTO subscriptions (
        id, company_id, plan_id, status,
        current_period_start, current_period_end,
        payment_method, cancel_at_period_end,
        grace_period_until, last_payment_status,
        trial_started_at, trial_ends_at, billing_interval
      )
      VALUES ($1, $2, $3, 'active', $4, $5, $6, false, null, 'success', null, null, $7)
      ON CONFLICT (company_id) DO UPDATE SET
        plan_id               = EXCLUDED.plan_id,
        status                = 'active',
        current_period_start  = EXCLUDED.current_period_start,
        current_period_end    = GREATEST(subscriptions.current_period_end, EXCLUDED.current_period_end),
        payment_method        = EXCLUDED.payment_method,
        cancel_at_period_end  = false,
        grace_period_until    = null,
        last_payment_status   = 'success'
        ,billing_interval      = EXCLUDED.billing_interval
        ,updated_at            = NOW()
      RETURNING id
    `, [subId, companyId, planId, now, periodEnd, grantType === 'card' ? 'credit_card' : grantType === 'bank_transfer' ? 'bank_transfer' : 'admin_grant', billingPeriod]);

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
      resolvedDeviceLimit, resolvedStoreLimit,
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
        resolvedDeviceLimit,
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
        resolvedDeviceLimit,
        periodEnd
      ]);
    }

    // 5. Audit log
    await client.query(`
      INSERT INTO audit_logs (id, company_id, user_id, user_name, action, entity, entity_id, new_value)
      VALUES ($1, $2, $3, $4, $5, 'subscription', $6, $7)
    `, [
      BillingDomainService.opaqueId('al'),
      companyId,
      adminUserId ?? 'system',
      adminUserId ? 'Admin' : 'System',
      `ACTIVATE_SUBSCRIPTION:${grantType.toUpperCase()}`,
      resolvedSubId,
      JSON.stringify({ planId, deviceLimit: resolvedDeviceLimit, storeLimit: resolvedStoreLimit,
        validUntil: periodEnd, paymentId, reason: params.grantReason || null })
    ]);

    logger.info(`[CommercialLifecycle] Company ${companyId} activated plan ${planId} via ${grantType}. Entitlement: ${entId}`);

    return { subscriptionId: resolvedSubId, entitlementId: entId, validFrom: now, validUntil: periodEnd };
  }
  static async finalizeInvoicePayment(
    client: PoolClient,
    invoiceId: string,
    grantType: 'card' | 'bank_transfer' | 'admin_grant',
    adminUserId?: string,
    evidence?: { providerTransactionId?: string; amount?: number; currency?: string; referenceCode?: string }
  ): Promise<{ subscriptionId: string; entitlementId: string; validFrom: Date; validUntil: Date }> {
    // 1. Lock invoice
    const invRes = await client.query('SELECT * FROM invoices WHERE id = $1 FOR UPDATE', [invoiceId]);
    if (invRes.rows.length === 0) {
      throw new Error('invoice_not_found');
    }
    const invoice = invRes.rows[0];

    // Idempotency check
    if (invoice.status === 'paid') {
      const existing = await client.query(`
        SELECT g.subscription_id, g.entitlement_id, le.valid_from, le.valid_until
        FROM commercial_entitlement_grants g
        JOIN license_entitlements le ON le.id=g.entitlement_id
        WHERE g.invoice_id=$1
      `, [invoiceId]);
      if (!existing.rows.length) throw new Error('paid_invoice_without_entitlement');
      const row = existing.rows[0];
      logger.info(`[CommercialLifecycle] Invoice ${invoiceId} already finalized.`);
      return { subscriptionId: row.subscription_id, entitlementId: row.entitlement_id, validFrom: new Date(row.valid_from), validUntil: new Date(row.valid_until) };
    }

    if (invoice.status !== 'pending') throw new Error('invoice_not_payable');
    const details = BillingDomainService.invoiceDetails(invoice);
    const currency = String(evidence?.currency || details.currency || 'TRY');
    const amount = Number(evidence?.amount ?? invoice.amount);
    if (!Number.isFinite(amount) || Math.abs(amount - Number(invoice.amount)) > 0.009) {
      throw new Error('payment_amount_mismatch');
    }
    if (grantType === 'card' && !evidence?.providerTransactionId) {
      throw new Error('provider_payment_evidence_required');
    }
    if (grantType === 'bank_transfer') {
      const transfer = await client.query(
        `SELECT reference_code FROM bank_transfer_notifications
         WHERE invoice_id=$1 AND status='pending_review' FOR UPDATE`,
        [invoiceId],
      );
      if (!transfer.rowCount || (evidence?.referenceCode && transfer.rows[0].reference_code !== evidence.referenceCode)) {
        throw new Error('bank_transfer_evidence_required');
      }
    }

    const paymentId = BillingDomainService.opaqueId('pay');
    await client.query(
      `INSERT INTO payment_transactions
       (id,invoice_id,company_id,channel,provider_transaction_id,amount,currency,status,evidence,verified_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'succeeded',$8::jsonb,$9)`,
      [paymentId, invoiceId, invoice.company_id, grantType,
        evidence?.providerTransactionId || null, amount, currency,
        JSON.stringify(evidence || {}), adminUserId || null],
    );

    // 3. Resolve planId and billing_period from billing_details
    let planId = '';
    let billingPeriod: BillingPeriod = 'monthly';
    if (invoice.billing_details) {
      planId = details.planId || planId;
      billingPeriod = BillingDomainService.normalizePeriod(details.billingPeriod);
    } else if (invoice.subscription_id) {
      const subRes = await client.query('SELECT plan_id FROM subscriptions WHERE id = $1', [invoice.subscription_id]);
      if (subRes.rows.length > 0) planId = subRes.rows[0].plan_id;
    }

    if (!planId) throw new Error('invoice_plan_missing');

    const activation = await this.activatePaidSubscription(client, {
      companyId: invoice.company_id,
      planId,
      paymentId: invoice.id,
      grantType,
      adminUserId,
      billingPeriod
    });

    await client.query(
      `INSERT INTO commercial_entitlement_grants
       (invoice_id,payment_id,subscription_id,entitlement_id) VALUES ($1,$2,$3,$4)`,
      [invoiceId, paymentId, activation.subscriptionId, activation.entitlementId],
    );

    await client.query(
      `UPDATE invoices SET status='paid',paid_at=NOW(),subscription_id=$1,
         payment_gateway_reference=COALESCE($2,payment_gateway_reference),updated_at=NOW()
       WHERE id=$3`,
      [activation.subscriptionId, evidence?.providerTransactionId || null, invoiceId],
    );

    // 4. Update invoice subscription_id if it was null
    return activation;
  }

  static async grantManualEntitlement(
    client: PoolClient,
    params: Omit<ActivationParams, 'grantType'> & {
      adminUserId: string;
      grantReason: string;
      grantDays: number;
    },
  ): Promise<{ subscriptionId: string; entitlementId: string; validFrom: Date; validUntil: Date }> {
    return this.activatePaidSubscription(client, { ...params, grantType: 'admin_grant' });
  }

  static async setEntitlementStatus(
    client: PoolClient,
    params: {
      companyId: string;
      status: 'active' | 'suspended' | 'revoked';
      actorId: string;
      reason: string;
    },
  ): Promise<void> {
    if (!params.reason.trim()) throw new Error('status_reason_required');
    const entitlementStatus = params.status === 'suspended' ? 'suspended' : params.status;
    const legacyStatus = params.status === 'active' ? 'active' : params.status;
    const locked = await client.query(
      `SELECT id FROM license_entitlements
       WHERE company_id=$1 AND status IN ('trial','active','suspended') FOR UPDATE`,
      [params.companyId],
    );
    if (!locked.rowCount) throw new Error('entitlement_not_found');
    if (params.status === 'active') {
      const valid = await client.query(
        `SELECT 1 FROM license_entitlements WHERE company_id=$1 AND valid_until>NOW() LIMIT 1`,
        [params.companyId],
      );
      if (!valid.rowCount) throw new Error('expired_entitlement_requires_grant');
    }
    await client.query(
      `UPDATE license_entitlements SET status=$1, token_version=token_version+1, updated_at=NOW()
       WHERE company_id=$2 AND status IN ('trial','active','suspended')`,
      [entitlementStatus, params.companyId],
    );
    await client.query(
      `UPDATE licenses SET status=$1, updated_at=NOW() WHERE company_id=$2 AND status!='revoked'`,
      [legacyStatus, params.companyId],
    );
    if (params.status === 'suspended') {
      await client.query(
        `UPDATE device_activations SET status='suspended', revoked_at=NOW(), revoked_by=$1, updated_at=NOW()
         WHERE company_id=$2 AND status='active'`,
        [params.actorId, params.companyId],
      );
    } else if (params.status === 'revoked') {
      await client.query(
        `UPDATE device_activations SET status='revoked', revoked_at=NOW(), revoked_by=$1, updated_at=NOW()
         WHERE company_id=$2 AND status IN ('active','suspended')`,
        [params.actorId, params.companyId],
      );
    } else {
      await client.query(
        `UPDATE device_activations SET status='active', revoked_at=NULL, revoked_by=NULL, updated_at=NOW()
         WHERE company_id=$1 AND status='suspended'`,
        [params.companyId],
      );
    }
    await client.query(
      `INSERT INTO audit_logs (id,company_id,user_id,user_name,action,entity,entity_id,new_value)
       VALUES ($1,$2,$3,'Admin',$4,'license_entitlement',$2,$5::jsonb)`,
      [BillingDomainService.opaqueId('al'), params.companyId, params.actorId,
        `ENTITLEMENT_${params.status.toUpperCase()}`, JSON.stringify({ reason: params.reason })],
    );
  }

  static async setAutoRenewal(
    client: PoolClient,
    params: { companyId: string; actorId: string; enabled: boolean },
  ): Promise<{ subscriptionId: string; periodEnd: Date }> {
    const result = await client.query(
      `SELECT s.id,s.current_period_end FROM subscriptions s
       WHERE s.company_id=$1 AND s.status='active' AND s.current_period_end>NOW()
         AND EXISTS(SELECT 1 FROM license_entitlements le
           WHERE le.subscription_id=s.id AND le.status='active' AND le.valid_until>NOW())
       ORDER BY s.current_period_end DESC LIMIT 1 FOR UPDATE OF s`,
      [params.companyId],
    );
    if (!result.rowCount) throw new Error('active_subscription_not_found');
    await client.query(
      `UPDATE subscriptions SET cancel_at_period_end=$1,updated_at=NOW() WHERE id=$2`,
      [!params.enabled, result.rows[0].id],
    );
    await client.query(
      `INSERT INTO audit_logs(id,company_id,user_id,user_name,action,entity,entity_id,new_value)
       VALUES($1,$2,$3,'Owner',$4,'subscription',$5,$6::jsonb)`,
      [BillingDomainService.opaqueId('al'), params.companyId, params.actorId,
        params.enabled ? 'AUTO_RENEWAL_REACTIVATED' : 'AUTO_RENEWAL_CANCELLED',
        result.rows[0].id, JSON.stringify({ cancel_at_period_end: !params.enabled })],
    );
    return { subscriptionId: result.rows[0].id, periodEnd: new Date(result.rows[0].current_period_end) };
  }

  static async expireTrials(client: PoolClient, companyId?: string): Promise<number> {
    const expired = await client.query(
      `SELECT id,company_id FROM subscriptions
       WHERE status='trialing' AND trial_ends_at IS NOT NULL AND trial_ends_at<=NOW()
         AND ($1::varchar IS NULL OR company_id=$1) FOR UPDATE`,
      [companyId || null],
    );
    for (const subscription of expired.rows) {
      await client.query(`UPDATE subscriptions SET status='trial_expired',updated_at=NOW() WHERE id=$1`,
        [subscription.id]);
      await client.query(
        `UPDATE license_entitlements SET status='expired',token_version=token_version+1,updated_at=NOW()
         WHERE subscription_id=$1 AND status='trial'`, [subscription.id]);
      await client.query(
        `UPDATE licenses SET status='inactive',updated_at=NOW()
         WHERE company_id=$1 AND tier='trial' AND status!='revoked'`, [subscription.company_id]);
      await client.query(
        `UPDATE device_activations SET status='revoked',revoked_at=NOW(),updated_at=NOW()
         WHERE company_id=$1 AND status='active'
           AND entitlement_id IN(SELECT id FROM license_entitlements WHERE subscription_id=$2)`,
        [subscription.company_id, subscription.id]);
    }
    return expired.rowCount || 0;
  }
}
