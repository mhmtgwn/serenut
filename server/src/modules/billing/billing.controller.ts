import { Router, Request, Response } from 'express';
import { pgPool, redisClient } from '../../config/database';
import { authenticateUser, AuthenticatedRequest, requirePermission, requireRole } from '../../middleware/auth.middleware';
import { IyzicoService, loadIyzicoConfig } from './iyzico.service';
import { logger } from '../../config/logger';
import { webhookLimiter } from '../../middleware/rate-limit.middleware';

if (process.env.NODE_ENV !== 'test') {
  loadIyzicoConfig(pgPool).catch(err => {
    logger.warn('Failed to load iyzico config at startup:', err);
  });
}
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { CommercialLifecycleService } from './commercial_lifecycle.service';
import { PaymentReconciliationService } from './payment-reconciliation.service';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { BillingDomainService } from './billing-domain.service';
import { InvoicePdfService } from './invoice-pdf.service';
import bankTransferRouter from './billing.bank-transfer.routes';

const router = Router();
router.use(bankTransferRouter);

// ── RLS YARDIMCILARI ─────────────────────────────────────────────────────────
async function runBypassingRLS(sql: string, params: any[] = []) {
  return BillingDomainService.runBypassingRLS(sql, params);
}

// Helper to write admin audit log

async function runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
  return BillingDomainService.runWithTenantContext(companyId, sql, params);
}

/**
 * @openapi
 * /api/v1/billing/plans:
 *   get:
 *     summary: Retrieve list of subscription tiers
 */
router.get('/plans', async (req, res: Response) => {
  const cacheKey = 'plans:list';
  if (redisClient && redisClient.isOpen) {
    try {
      const cached = await redisClient.get(cacheKey);
      if (cached !== null) {
        return res.json(JSON.parse(cached));
      }
    } catch (err) {
      logger.error('Redis plans get error:', err);
    }
  }

  try {
    const result = await runBypassingRLS(
      `SELECT p.*, ROUND((p.price * 12 * 0.85)::numeric, 2) AS yearly_price
       FROM plans p WHERE is_active = true ORDER BY price ASC`,
    );
    const plans = result.rows;
    if (redisClient && redisClient.isOpen) {
      await redisClient.setEx(cacheKey, 300, JSON.stringify(plans));
    }
    return res.json(plans);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/quotes', authenticateUser, requirePermission('billing:view'), async (req: AuthenticatedRequest, res: Response) => {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const quote = await BillingDomainService.createQuote(
      client, req.user!.company_id, String(req.body?.plan_id || ''), req.body?.billing_period,
    );
    await client.query('COMMIT');
    return res.status(201).json({ quote_id: quote.quoteId, plan_id: quote.planId,
      plan_name: quote.planName, billing_period: quote.period, amount: quote.amount,
      currency: quote.currency, expires_at: quote.expiresAt.toISOString() });
  } catch (error: any) {
    await client.query('ROLLBACK').catch(() => {});
    return res.status(error?.message === 'plan_not_found' ? 404 : 400)
      .json({ error: error?.message || 'quote_failed' });
  } finally { client.release(); }
});

router.get('/effective-plans', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runBypassingRLS(
      `SELECT p.*, COALESCE(o.custom_price,p.price) AS price,
              COALESCE(o.billing_interval,p.billing_interval) AS billing_interval,
              CASE
                WHEN o.billing_interval = 'yearly' THEN NULL
                WHEN o.custom_price IS NOT NULL THEN o.custom_price
                WHEN p.billing_interval = 'yearly' THEN ROUND((p.price / (12 * 0.85))::numeric, 2)
                ELSE p.price
              END AS monthly_price,
              CASE
                WHEN o.billing_interval = 'monthly' THEN NULL
                WHEN o.custom_price IS NOT NULL THEN o.custom_price
                WHEN p.billing_interval = 'yearly' THEN p.price
                ELSE ROUND((p.price * 12 * 0.85)::numeric, 2)
              END AS yearly_price,
              o.billing_interval AS locked_billing_period,
              COALESCE(o.device_limit,p.device_limit) AS device_limit,
              COALESCE(o.store_limit,p.store_limit) AS store_limit,
              COALESCE(o.user_limit,p.user_limit) AS user_limit,
              COALESCE(p.features,'{}'::jsonb)||COALESCE(o.feature_overrides,'{}'::jsonb) AS features,
              (o.id IS NOT NULL) AS is_company_specific
       FROM plans p LEFT JOIN subscription_overrides o ON o.company_id=$1
        AND o.base_plan_id=p.id AND o.is_active=TRUE
        AND CURRENT_TIMESTAMP BETWEEN o.valid_from AND o.valid_until
       WHERE p.is_active=TRUE ORDER BY COALESCE(o.custom_price,p.price)`, [req.user!.company_id]);
    return res.json(result.rows);
  } catch (err) { return res.status(500).json({error:'server_error'}); }
});

async function isIyzicoEnabled(): Promise<boolean> {
  try {
    const result = await runBypassingRLS("SELECT is_enabled FROM payment_providers WHERE id = 'iyzico' LIMIT 1");
    return result.rows[0]?.is_enabled === true;
  } catch (_) {
    return process.env.IYZICO_ENABLED === 'true';
  }
}

/**
 * @openapi
 * /api/v1/billing/payment-methods:
 *   get:
 *     summary: Get all active payment methods
 */
router.get('/payment-methods', async (req: Request, res: Response) => {
  try {
    const result = await runBypassingRLS(`
      SELECT id, display_name, config 
      FROM payment_providers 
      WHERE is_enabled = true
    `);
    
    // We intentionally exclude secrets and backend metadata (last_test_at, etc.)
    return res.json(result.rows.map(row => ({ ...row, is_enabled: true })));
  } catch (err: any) {
    // Missing schema is an operational error; never invent a payment method.
    if (err.code === '42P01') {
      return res.status(503).json({ error: 'payment_configuration_unavailable' });
    }
    logger.error('Error fetching payment methods:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/billing/request-bank-transfer:
 *   post:
 *     summary: Create a bank transfer payment request with reference code
 *     security:
 *       - BearerAuth: []
 */
router.post('/request-bank-transfer', authenticateUser, requirePermission('billing:view'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { quote_id, bank_account_id, legal_acceptance, pre_information_version, distance_sales_version } = req.body;
  if (!quote_id || !bank_account_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Plan ve banka hesabı seçimi zorunludur.' });
  }
  if (legal_acceptance !== true || pre_information_version !== '2026-08-09' || distance_sales_version !== '2026-08-09') {
    return res.status(400).json({ error: 'legal_acceptance_required', message: 'Ön bilgilendirme ve mesafeli satış koşullarını onaylamanız gerekir.' });
  }
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const quote = await BillingDomainService.lockQuote(client, user.company_id, quote_id);

    const bankRes = await client.query('SELECT * FROM payment_bank_accounts WHERE id = $1 AND is_active = TRUE', [bank_account_id]);
    if (bankRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'bank_account_not_found' });
    }
    const bank = bankRes.rows[0];

    const now = new Date();
    const periodEnd = BillingDomainService.addPeriod(now, quote.period);
    const finalPriceStr = quote.amount.toFixed(2);

    // Create pending invoice
    const invoiceId = BillingDomainService.opaqueId('inv');
    const invoiceNum = await BillingDomainService.nextInvoiceNumber(client);
    await client.query(
      `INSERT INTO invoices (id, company_id, amount, status, due_at, expires_at, invoice_number, billing_details)
       VALUES ($1,$2,$3,'pending',$4,NOW() + INTERVAL '48 hours',$5,$6)`,
      [invoiceId, user.company_id, quote.amount, periodEnd, invoiceNum, JSON.stringify({ quoteId: quote.quoteId, planName: quote.planName, planId: quote.planId, billingPeriod: quote.period, currency: quote.currency })]
    );
    await client.query(
      `INSERT INTO billing_legal_acceptances
       (id,user_id,company_id,quote_id,invoice_id,channel,pre_information_version,distance_sales_version,ip_address,user_agent)
       VALUES($1,$2,$3,$4,$5,'bank_transfer',$6,$7,$8,$9)`,
      [BillingDomainService.opaqueId('bla'), user.id, user.company_id, quote.quoteId, invoiceId,
       pre_information_version, distance_sales_version, req.ip || null, req.headers['user-agent'] || null],
    );

    // Generate unique reference code: SRNTT-YYYYMMDD-XXXX
    const datePart = now.toISOString().slice(0, 10).replace(/-/g, '');
    const randPart = crypto.randomBytes(2).toString('hex').toUpperCase();
    const referenceCode = `SRNTT-${datePart}-${randPart}`;

    // Create bank transfer notification
    const notifId = BillingDomainService.opaqueId('btn');
    await client.query(
      `INSERT INTO bank_transfer_notifications (id, invoice_id, company_id, bank_account_id, reference_code, status)
       VALUES ($1,$2,$3,$4,$5,'pending')`,
      [notifId, invoiceId, user.company_id, bank_account_id, referenceCode]
    );
    await BillingDomainService.consumeQuote(client, quote.quoteId, invoiceId);

    await client.query('COMMIT');

    return res.status(201).json({
      reference_code: referenceCode,
      invoice_id: invoiceId,
      bank: {
        bank_name: bank.bank_name,
        account_holder: bank.account_holder,
        iban: bank.iban,
        branch_name: bank.branch_name,
        instructions: bank.instructions,
      },
      amount: finalPriceStr,
      currency: quote.currency,
      billing_period: quote.period,
      period_end: periodEnd.toISOString(),
      message: `Lütfen havale açıklama alanına referans kodunuzu yazın: ${referenceCode}`,
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Error creating bank transfer request:', err);
    if ((err as Error).message === 'plan_not_found') return res.status(404).json({ error: 'plan_not_found' });
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

/**
 * @openapi
 * /api/v1/billing/plans/{id}:
 *   put:
 *     summary: Update an existing pricing plan (Admin only)
 *     security:
 *       - BearerAuth: []
 */
router.put('/plans/:id', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const { name, price, currency, billing_interval, features, device_limit, store_limit,
    user_limit, trial_days, is_active } = req.body;

  if (!name || price === undefined) {
    return res.status(400).json({ error: 'missing_fields', message: 'Plan adı ve fiyatı zorunludur.' });
  }

  try {
    const query = `
      UPDATE plans 
      SET name = $1, price = $2, currency = $3, billing_interval = $4, features = $5,
          device_limit=$6, store_limit=$7, user_limit=$8, trial_days=$9, is_active=$10
      WHERE id = $11
      RETURNING *
    `;
    const params = [
      name,
      price,
      currency || 'TRY',
      billing_interval || 'monthly',
      typeof features === 'string' ? features : JSON.stringify(features),
      Number(device_limit || 1), Number(store_limit || 1), Number(user_limit || 1),
      Number(trial_days || 0), is_active !== false, id
    ];
    
    const result = await runBypassingRLS(query, params);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'plan_not_found', message: 'Güncellenecek plan bulunamadı.' });
    }

    if (redisClient && redisClient.isOpen) {
      try {
        await redisClient.del('plans:list');
        logger.info('Invalidated plans:list Redis cache.');
      } catch (err) {
        logger.error('Redis plans del error:', err);
      }
    }

    logger.info(`Plan ${id} updated by admin ${req.user?.email}`);
    return res.json({ success: true, plan: result.rows[0] });
  } catch (err) {
    logger.error('Error updating plan:', err);
    return res.status(500).json({ error: 'server_error', message: 'Plan güncellenirken sunucu hatası oluştu.' });
  }
});

router.post('/plans', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { name, price, currency, billing_interval, features, device_limit, store_limit,
    user_limit, trial_days } = req.body;
  const limits = [device_limit, store_limit, user_limit].map(Number);
  if (!String(name || '').trim() || !Number.isFinite(Number(price)) || Number(price) < 0 ||
      limits.some(value => !Number.isInteger(value) || value < 1 || value > 1000)) {
    return res.status(400).json({ error: 'invalid_plan', message: 'Plan adı, fiyat ve 1-1000 arasındaki limitler zorunludur.' });
  }
  const id = `plan-${crypto.randomUUID()}`;
  try {
    const result = await runBypassingRLS(
      `INSERT INTO plans(id,name,price,currency,billing_interval,features,device_limit,store_limit,user_limit,trial_days,is_active)
       VALUES($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,TRUE) RETURNING *`,
      [id, String(name).trim(), Number(price), currency || 'TRY', billing_interval === 'yearly' ? 'yearly' : 'monthly',
       JSON.stringify(features || {}), limits[0], limits[1], limits[2], Math.max(0, Number(trial_days || 0))],
    );
    if (redisClient?.isOpen) await redisClient.del('plans:list').catch(() => undefined);
    return res.status(201).json({ success: true, plan: result.rows[0] });
  } catch (error) {
    logger.error('Error creating plan:', error);
    return res.status(500).json({ error: 'server_error', message: 'Plan oluşturulamadı.' });
  }
});


/**
 * @openapi
 * /api/v1/billing/subscribe:
 *   post:
 *     summary: Start an Iyzico checkout session
 *     security:
 *       - BearerAuth: []
 */

/**
 * @swagger
 * /api/v1/billing/subscription:
 *   get:
 *     summary: Get current subscription details for the tenant
 *     tags: [Billing]
 *     security:
 *       - bearerAuth: []
 */
router.get('/subscription', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const companyId = req.user!.company_id;
    
    const subRes = await runBypassingRLS(`
      SELECT s.*, p.name as plan_name, p.price as plan_price, p.currency as plan_currency
      FROM subscriptions s
      JOIN plans p ON s.plan_id = p.id
      WHERE s.company_id = $1
      ORDER BY s.current_period_start DESC
      LIMIT 1
    `, [companyId]);

    if (subRes.rows.length === 0) {
      return res.status(200).json({ status: 'no_subscription' });
    }

    const sub = subRes.rows[0];
    res.json(sub);
  } catch (error) {
    logger.error('Error fetching subscription:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * @swagger
 * /api/v1/billing/reactivate:
 *   post:
 *     summary: Reactivate a cancelled but still active subscription
 *     tags: [Billing]
 *     security:
 *       - bearerAuth: []
 */
router.post('/reactivate', authenticateUser, requireRole('owner'), async (req: AuthenticatedRequest, res: Response) => {
  const client = await pgPool.connect();
  try {
    const companyId = req.user!.company_id;
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    await CommercialLifecycleService.setAutoRenewal(client, {
      companyId, actorId: req.user!.id, enabled: true,
    });
    await client.query('COMMIT');
    res.json({ message: 'Subscription reactivated successfully' });
  } catch (error: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    logger.error('Error reactivating subscription:', error);
    res.status(error.message === 'active_subscription_not_found' ? 404 : 500).json({ error: error.message });
  } finally { client.release(); }
});

const subscribeHandler = async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const quoteId = req.body.quote_id || req.body.quoteId;
  const { legal_acceptance, pre_information_version, distance_sales_version } = req.body;

  if (!quoteId) {
    return res.status(400).json({ error: 'quote_required' });
  }
  if (legal_acceptance !== true || pre_information_version !== '2026-08-09' || distance_sales_version !== '2026-08-09') {
    return res.status(400).json({ error: 'legal_acceptance_required', message: 'Ön bilgilendirme ve mesafeli satış koşullarını onaylamanız gerekir.' });
  }

  if (!(await isIyzicoEnabled())) {
    return res.status(501).json({
      error: 'not_implemented',
      message: 'Kredi kartı tahsilat altyapısı şu anda aktif değildir. Lütfen banka havalesi ile ödeme yapınız.'
    });
  }

  try {
    const billingClient = await pgPool.connect();
    let quote;
    let invoiceId: string;
    try {
      await billingClient.query('BEGIN');
      await billingClient.query("SET LOCAL app.bypass_rls = 'true'");
      quote = await BillingDomainService.lockQuote(billingClient, user.company_id, quoteId);
      invoiceId = BillingDomainService.opaqueId('inv');
      const invoiceNum = await BillingDomainService.nextInvoiceNumber(billingClient);
      await billingClient.query(
        `INSERT INTO invoices (id, company_id, amount, status, due_at, expires_at, invoice_number, billing_details)
         VALUES ($1,$2,$3,'pending',NOW(),NOW() + INTERVAL '2 hours',$4,$5)`,
        [invoiceId, user.company_id, quote.amount, invoiceNum, JSON.stringify({ quoteId: quote.quoteId, planName: quote.planName, planId: quote.planId, billingPeriod: quote.period, currency: quote.currency })]
      );
      await billingClient.query(
        `INSERT INTO billing_legal_acceptances
         (id,user_id,company_id,quote_id,invoice_id,channel,pre_information_version,distance_sales_version,ip_address,user_agent)
         VALUES($1,$2,$3,$4,$5,'card',$6,$7,$8,$9)`,
        [BillingDomainService.opaqueId('bla'), user.id, user.company_id, quote.quoteId, invoiceId,
         pre_information_version, distance_sales_version, req.ip || null, req.headers['user-agent'] || null],
      );
      await BillingDomainService.consumeQuote(billingClient, quote.quoteId, invoiceId);
      await billingClient.query('COMMIT');
    } catch (billingError) {
      await billingClient.query('ROLLBACK').catch(() => {});
      throw billingError;
    } finally {
      billingClient.release();
    }
    const finalPriceStr = quote.amount.toFixed(2);

    // Fetch company info for billing
    const companyRes = await runBypassingRLS('SELECT * FROM companies WHERE id = $1', [user.company_id]);
    const company = companyRes.rows[0] || {};

    const protocol = req.protocol || 'https';
    const baseUrl = `${protocol}://${req.get('host')}`;

    const buyerNameParts = user.name.split(' ');
    const buyerName = buyerNameParts[0];
    const buyerSurname = buyerNameParts.slice(1).join(' ') || 'Müşteri';

    const reqData = {
      conversationId: invoiceId,
      price: finalPriceStr,
      paidPrice: finalPriceStr,
      currency: quote.currency as 'TRY' | 'USD' | 'EUR',
      basketId: user.company_id,
      callbackUrl: `${baseUrl}/api/v1/billing/iyzico/callback`,
      buyer: {
        id: user.id,
        name: buyerName,
        surname: buyerSurname,
        email: user.email,
        identityNumber: company.tax_number || '11111111111',
        registrationAddress: company.address || 'Belirtilmedi',
        city: company.city || 'Istanbul',
        country: 'Turkey',
        ip: req.ip || '85.34.78.112'
      },
      billingAddress: {
        contactName: user.name,
        city: company.city || 'Istanbul',
        country: 'Turkey',
        address: company.address || 'Belirtilmedi'
      },
      basketItems: [{
        id: quote.planId,
        name: `${quote.planName} (${quote.period === 'yearly' ? 'Yıllık' : 'Aylık'})`,
        category1: 'Software',
        itemType: 'VIRTUAL',
        price: finalPriceStr
      }]
    };

    const iyzicoRes = await IyzicoService.createCheckoutSession(reqData as any);
    if (iyzicoRes.status === 'success') {
      // Bind the provider token to this exact invoice. The callback must never
      // resolve an arbitrary "latest pending" invoice.
      await runBypassingRLS(
        `UPDATE invoices
         SET billing_details = COALESCE(billing_details, '{}'::jsonb) || $1::jsonb,
             updated_at = NOW()
         WHERE id = $2`,
        [JSON.stringify({ iyzicoToken: iyzicoRes.token }), invoiceId]
      );
      return res.json({ 
        success: true, 
        checkoutFormContent: iyzicoRes.checkoutFormContent, 
        token: iyzicoRes.token,
        invoiceId: invoiceId
      });
    } else {
      logger.error('Iyzico session failed:', iyzicoRes.errorMessage);
      await runBypassingRLS("UPDATE invoices SET status = 'failed', updated_at = NOW() WHERE id = $1", [invoiceId]);
      return res.status(400).json({ error: 'checkout_failed', message: iyzicoRes.errorMessage });
    }
  } catch (err) {
    logger.error('Subscribe setup failed:', err);
    if ((err as Error).message === 'plan_not_found') return res.status(404).json({ error: 'plan_not_found' });
    return res.status(500).json({ error: 'server_error' });
  }
};

router.post('/subscribe', authenticateUser, requirePermission('billing:view'), subscribeHandler);
router.post('/checkout', authenticateUser, requirePermission('billing:view'), subscribeHandler);

/**
 * @openapi
 * /api/v1/billing/iyzico/callback:
 *   post:
 *     summary: Iyzico Checkout Webhook Callback
 */
router.post('/iyzico/callback', async (req: Request, res: Response) => {
  if (!(await isIyzicoEnabled())) {
    return res.status(410).send('Kart ödeme kanalı kapalıdır.');
  }
  const { token } = req.body;
  if (!token) {
    return res.status(400).send('Token missing');
  }

  try {
    // The callback token identifies a pending invoice; provider verification
    // below supplies the payment evidence before any commercial state changes.
    const tokenInfoRes = await runBypassingRLS(
      `SELECT * FROM invoices
       WHERE status IN ('pending','verification_pending')
         AND billing_details->>'iyzicoToken' = $1
       LIMIT 1`,
      [token]
    );
    if (tokenInfoRes.rows.length === 0) {
      logger.warn(`Iyzico callback rejected: no pending invoice for token ${String(token).slice(0, 8)}…`);
      return res.redirect('/app/?payment=invalid#billing-center');
    }
    
    const invoice = tokenInfoRes.rows[0];
    await runBypassingRLS(
      `UPDATE invoices SET status='verification_pending',next_verification_at=NOW(),updated_at=NOW()
       WHERE id=$1 AND status='pending'`, [invoice.id],
    );
    const reconciliation = await PaymentReconciliationService.reconcileInvoice(invoice.id);
    if (reconciliation.status !== 'paid') {
      return res.redirect('/app/?payment=pending#billing-center');
    }
    const activation = reconciliation.activation;
    await RealtimeBroadcastService.publishEvent(invoice.company_id, 'LicenseUpdated', {
      subscriptionId: activation.subscriptionId,
      entitlementId: activation.entitlementId,
      invoiceId: invoice.id,
      status: 'active',
    });
    return res.redirect('/app/?payment=success#billing-center');

  } catch (error) {
    logger.error('Iyzico callback error:', error);
    res.redirect('/app/?payment=error#billing-center');
  }
});

/**
 * @openapi
 * /api/v1/billing/invoices:
 *   get:
 *     summary: Retrieve tenant billing invoices
 *     security:
 *       - BearerAuth: []
 */
router.get('/invoices', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(
      user.company_id,
      'SELECT id, amount, status, due_at, paid_at, invoice_number FROM invoices ORDER BY due_at DESC'
    );
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/billing/invoices/{id}/pdf:
 *   get:
 *     summary: Download specific invoice PDF
 *     security:
 *       - BearerAuth: []
 */
router.get('/invoices/:id/pdf', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const generated = await InvoicePdfService.ensureInvoicePdf(
      req.params.id,
      user.company_id,
      Boolean(user.roles?.includes('sysadmin')),
    );
    if (!generated) {
      return res.status(404).json({ error: 'invoice_not_found' });
    }
    const resolvedPath = path.resolve(generated.pdfPath);
    const invoicesDir = InvoicePdfService.getInvoicesDir();
    if (!resolvedPath.startsWith(invoicesDir) && !resolvedPath.startsWith('/var/invoices')) {
      return res.status(403).json({ error: 'forbidden', message: 'Geçersiz fatura dizini.' });
    }
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${generated.invoiceNumber}.pdf"`);
    return fs.createReadStream(resolvedPath).pipe(res);
  } catch (err) {
    logger.error('Invoice PDF generation error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/reactivate', authenticateUser, requirePermission('billing:view'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    await CommercialLifecycleService.setAutoRenewal(client, {
      companyId: user.company_id, actorId: user.id, enabled: true,
    });
    await client.query('COMMIT');
    return res.json({ success: true, message: 'Otomatik abonelik yenilemesi tekrar aktifleştirildi.' });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    return res.status(err.message === 'active_subscription_not_found' ? 404 : 500).json({ error: err.message });
  } finally { client.release(); }
});

router.get('/invoices/:id/pdf-legacy-unused', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const invoiceRes = await runWithTenantContext(
      user.company_id,
      'SELECT pdf_path, invoice_number FROM invoices WHERE id = $1',
      [req.params.id]
    );

    if (invoiceRes.rows.length === 0) {
      return res.status(404).json({ error: 'invoice_not_found' });
    }

    const pdfPath = invoiceRes.rows[0].pdf_path;
    if (!pdfPath || !fs.existsSync(pdfPath)) {
      return res.status(404).json({ error: 'pdf_not_found', message: 'Fatura PDF dosyası henüz üretilmemiş veya silinmiş.' });
    }

    const resolvedPath = path.resolve(pdfPath);
    const invoicesDir = path.resolve(process.env.INVOICES_DIR || path.join(__dirname, '../../../../invoices'));
    if (!resolvedPath.startsWith(invoicesDir) && !resolvedPath.startsWith('/var/invoices')) {
      return res.status(403).json({ error: 'forbidden', message: 'Geçersiz fatura dizini.' });
    }

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${invoiceRes.rows[0].invoice_number}.pdf"`);
    return fs.createReadStream(resolvedPath).pipe(res);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/billing/cancel:
 *   post:
 *     summary: Cancel auto-renewal at period end
 *     security:
 *       - BearerAuth: []
 */
router.post('/cancel', authenticateUser, requireRole('owner'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    await CommercialLifecycleService.setAutoRenewal(client, {
      companyId: user.company_id, actorId: user.id, enabled: false,
    });
    await client.query('COMMIT');
    return res.json({ success: true, message: 'Abonelik yenilemesi iptal edildi. Dönem sonuna kadar kullanım devam edecektir.' });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    return res.status(err.message === 'active_subscription_not_found' ? 404 : 500).json({ error: err.message });
  } finally { client.release(); }
});

/**
 * @openapi
 * /api/v1/admin/billing/stats:
 *   get:
 *     summary: Admin billing dashboard metrics (MRR, ARR, active subscribers count)
 *     security:
 *       - BearerAuth: []
 */
router.get('/admin/stats', authenticateUser, requireRole('sysadmin'), async (req, res: Response) => {
  try {
    // 1. Calculate Monthly Recurring Revenue (MRR)
    const mrrRes = await runBypassingRLS(`
      SELECT COALESCE(SUM(p.price), 0) as mrr
      FROM subscriptions s
      JOIN plans p ON s.plan_id = p.id
      WHERE s.status = 'active'
    `);

    // 2. Count active subscribers
    const activeSubscribers = await runBypassingRLS(`
      SELECT COUNT(*) FROM subscriptions WHERE status = 'active'
    `);

    // 3. Count grace period warnings
    const graceRes = await runBypassingRLS(`
      SELECT COUNT(*) FROM subscriptions WHERE status = 'grace_period'
    `);

    const mrr = parseFloat(mrrRes.rows[0].mrr);

    return res.json({
      mrr,
      arr: mrr * 12,
      activeSubscribers: parseInt(activeSubscribers.rows[0].count, 10),
      gracePeriodCount: parseInt(graceRes.rows[0].count, 10)
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/billing/webhook/iyzico:
 *   post:
 *     summary: Handle incoming Iyzico payment events (SUCCESS/FAILURE) via webhook
 */
router.post('/webhook/iyzico', webhookLimiter, async (req: Request, res: Response) => {
  return res.status(410).json({
    error: 'legacy_webhook_removed',
    message: 'Ödeme sonuçları yalnızca sağlayıcıdan doğrulanan checkout callback akışıyla işlenir.',
  });
});

export default router;

