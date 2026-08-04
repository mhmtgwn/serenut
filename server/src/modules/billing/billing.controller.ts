import { Router, Request, Response } from 'express';
import { pgPool, redisClient } from '../../config/database';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../middleware/auth.middleware';
import { IyzicoService, loadIyzicoConfig } from './iyzico.service';
import { logger } from '../../config/logger';
import { webhookLimiter } from '../../middleware/rate-limit.middleware';

loadIyzicoConfig(pgPool).catch(err => {
  logger.warn('Failed to load iyzico config at startup:', err);
});
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { CommercialLifecycleService } from './commercial_lifecycle.service';
import { PaymentReconciliationService } from './payment-reconciliation.service';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { BillingDomainService } from './billing-domain.service';

const router = Router();

// ── RLS YARDIMCILARI ─────────────────────────────────────────────────────────
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

// Helper to write admin audit log

async function runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
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

router.post('/quotes', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
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

// ── BANK ACCOUNTS (Platform-level — sysadmin manages, all authenticated read) ──

/**
 * @openapi
 * /api/v1/billing/bank-accounts:
 *   get:
 *     summary: List active bank accounts for bank transfer payment
 *     security:
 *       - BearerAuth: []
 */
router.get('/bank-accounts', authenticateUser, async (req, res: Response) => {
  try {
    const includeInactive = req.query.all === 'true' && (req as AuthenticatedRequest).user?.roles?.includes('sysadmin');
    const result = await runBypassingRLS(
      `SELECT id, bank_name, account_holder, iban, currency, branch_name, instructions, is_active, display_order
       FROM payment_bank_accounts ${includeInactive ? '' : 'WHERE is_active = TRUE'} ORDER BY display_order ASC`
    );
    return res.json(result.rows);
  } catch (err) {
    logger.error('Error fetching bank accounts:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

async function isIyzicoEnabled(): Promise<boolean> {
  try {
    const result = await runBypassingRLS("SELECT is_enabled FROM payment_providers WHERE id = 'iyzico' LIMIT 1");
    return result.rows[0]?.is_enabled === true;
  } catch (_) {
    return process.env.IYZICO_ENABLED === 'true';
  }
}

// ── DYNAMIC PAYMENT METHODS ───────────────────────────────────────────────────

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
    return res.json(result.rows);
  } catch (err: any) {
    // If the table doesn't exist yet, fallback to default bank transfer until migrations run
    if (err.code === '42P01') {
      return res.json([{ id: 'bank_transfer', display_name: 'Havale / EFT', config: {} }]);
    }
    logger.error('Error fetching payment methods:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/bank-accounts', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { bank_name, account_holder, iban, currency, branch_name, instructions, display_order } = req.body;
  if (!bank_name || !account_holder || !iban) {
    return res.status(400).json({ error: 'missing_fields', message: 'Banka adı, hesap sahibi ve IBAN zorunludur.' });
  }
  try {
    const id = `pba-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const result = await runBypassingRLS(
      `INSERT INTO payment_bank_accounts (id, bank_name, account_holder, iban, currency, branch_name, instructions, display_order, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [id, bank_name, account_holder, iban, currency || 'TRY', branch_name || null, instructions || null, display_order || 0, req.user!.id]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    logger.error('Error creating bank account:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.put('/bank-accounts/:id', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const { bank_name, account_holder, iban, currency, branch_name, instructions, is_active, display_order } = req.body;
  try {
    const result = await runBypassingRLS(
      `UPDATE payment_bank_accounts
       SET bank_name=$1, account_holder=$2, iban=$3, currency=$4, branch_name=$5,
           instructions=$6, is_active=$7, display_order=$8, updated_at=NOW()
       WHERE id=$9 RETURNING *`,
      [bank_name, account_holder, iban, currency || 'TRY', branch_name, instructions, is_active ?? true, display_order ?? 0, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'not_found' });
    return res.json(result.rows[0]);
  } catch (err) {
    logger.error('Error updating bank account:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── BANK TRANSFER FLOW ────────────────────────────────────────────────────────

/**
 * @openapi
 * /api/v1/billing/request-bank-transfer:
 *   post:
 *     summary: Create a bank transfer payment request with reference code
 *     security:
 *       - BearerAuth: []
 */
router.post('/request-bank-transfer', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { quote_id, bank_account_id } = req.body;
  if (!quote_id || !bank_account_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Plan ve banka hesabı seçimi zorunludur.' });
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
 * /api/v1/billing/notify-transfer:
 *   post:
 *     summary: Customer notifies that bank transfer has been sent
 *     security:
 *       - BearerAuth: []
 */
router.post('/notify-transfer', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { invoice_id, sender_name, sender_bank, transfer_date, transfer_description } = req.body;
  if (!invoice_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Fatura ID zorunludur.' });
  }
  try {
    const result = await runBypassingRLS(
      `UPDATE bank_transfer_notifications
       SET sender_name=$1, sender_bank=$2, transfer_date=$3, transfer_description=$4,
           status='pending_review', updated_at=NOW()
       WHERE invoice_id=$5 AND company_id=$6 AND status='pending'
         AND EXISTS (SELECT 1 FROM invoices i WHERE i.id=$5 AND i.status='pending' AND (i.expires_at IS NULL OR i.expires_at > NOW()))
       RETURNING reference_code`,
      [sender_name || null, sender_bank || null, transfer_date || null, transfer_description || null, invoice_id, user.company_id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'notification_not_found', message: 'Havale bildirimi bulunamadı veya zaten işleme alındı.' });
    }
    await runBypassingRLS('UPDATE invoices SET expires_at=NULL, updated_at=NOW() WHERE id=$1 AND company_id=$2', [invoice_id, user.company_id]);
    return res.json({ success: true, message: 'Havale bildiriminiz alındı. Yöneticilerimiz ödemeyi inceleyecektir.', reference_code: result.rows[0].reference_code });
  } catch (err) {
    logger.error('Error updating bank transfer notification:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/admin/pending-transfers:
 *   get:
 *     summary: List pending bank transfer approvals (sysadmin only)
 *     security:
 *       - BearerAuth: []
 */
router.get('/admin/pending-transfers', authenticateUser, requireRole('sysadmin'), async (req, res: Response) => {
  try {
    const result = await runBypassingRLS(`
      SELECT btn.id, btn.reference_code, btn.sender_name, btn.sender_bank,
             btn.transfer_date, btn.status, btn.created_at,
             inv.id as invoice_id, inv.amount, inv.invoice_number, inv.billing_details,
             c.id as company_id, c.name as company_name, c.email as company_email,
             pba.bank_name, pba.iban
      FROM bank_transfer_notifications btn
      JOIN invoices inv ON inv.id = btn.invoice_id
      JOIN companies c ON c.id = btn.company_id
      LEFT JOIN payment_bank_accounts pba ON pba.id = btn.bank_account_id
      WHERE btn.status = 'pending_review'
      ORDER BY btn.created_at DESC
      LIMIT 100
    `);
    return res.json(result.rows);
  } catch (err) {
    logger.error('Error fetching pending transfers:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/transfer-requests/:invoiceId/cancel', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const result = await client.query(
      `UPDATE invoices SET status='cancelled', updated_at=NOW()
       WHERE id=$1 AND company_id=$2 AND status='pending'
       RETURNING id`, [req.params.invoiceId, req.user!.company_id]
    );
    if (!result.rows.length) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'request_not_cancellable', message: 'Bu ödeme talebi artık iptal edilemez.' });
    }
    await client.query(
      `UPDATE bank_transfer_notifications SET status='cancelled', updated_at=NOW()
       WHERE invoice_id=$1 AND status='pending'`, [req.params.invoiceId]
    );
    await client.query('COMMIT');
    return res.json({ success: true });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Transfer request cancellation failed:', error);
    return res.status(500).json({ error: 'server_error' });
  } finally { client.release(); }
});

router.put('/admin/invoices/:id/reject-payment', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const note = String(req.body?.note || '').trim();
  if (note.length < 3) return res.status(400).json({ error: 'rejection_note_required', message: 'Red gerekçesi zorunludur.' });
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const invoice = await client.query(
      `UPDATE invoices SET status='rejected', updated_at=NOW()
       WHERE id=$1 AND status='pending' RETURNING company_id`, [req.params.id]
    );
    if (!invoice.rows.length) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'invoice_not_rejectable' });
    }
    await client.query(
      `UPDATE bank_transfer_notifications
       SET status='rejected', admin_note=$1, reviewed_by=$2, reviewed_at=NOW(), updated_at=NOW()
       WHERE invoice_id=$3 AND status='pending_review'`,
      [note, req.user!.id, req.params.id]
    );
    await client.query(
      `INSERT INTO audit_logs (id,company_id,user_id,user_name,action,entity,entity_id,new_value)
       VALUES ($1,$2,$3,'Admin','REJECTED_BANK_WIRE_PAYMENT','invoice',$4,$5)`,
      [BillingDomainService.opaqueId('al'), invoice.rows[0].company_id, req.user!.id, req.params.id, JSON.stringify({ note })]
    );
    await client.query('COMMIT');
    return res.json({ success: true, message: 'Havale bildirimi reddedildi.' });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Transfer rejection failed:', error);
    return res.status(500).json({ error: 'server_error' });
  } finally { client.release(); }
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
  const { name, price, currency, billing_interval, features } = req.body;

  if (!name || price === undefined) {
    return res.status(400).json({ error: 'missing_fields', message: 'Plan adı ve fiyatı zorunludur.' });
  }

  try {
    const query = `
      UPDATE plans 
      SET name = $1, price = $2, currency = $3, billing_interval = $4, features = $5
      WHERE id = $6
      RETURNING *
    `;
    const params = [
      name,
      price,
      currency || 'TRY',
      billing_interval || 'monthly',
      typeof features === 'string' ? features : JSON.stringify(features),
      id
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

  if (!quoteId) {
    return res.status(400).json({ error: 'quote_required' });
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

router.post('/subscribe', authenticateUser, subscribeHandler);
router.post('/checkout', authenticateUser, subscribeHandler);

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

/**
 * @openapi
 * /api/v1/admin/invoices/{id}/approve-payment:
 *   put:
 *     summary: Manually approve a bank wire payment for an invoice (Admin only)
 *     security:
 *       - BearerAuth: []
 */
router.put('/admin/invoices/:id/approve-payment', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const adminUserId = req.user!.id;

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // 1. Lock invoice row to prevent double-approval
    const invoiceRes = await client.query(
      'SELECT * FROM invoices WHERE id = $1 FOR UPDATE',
      [id]
    );
    if (invoiceRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'invoice_not_found', message: 'Fatura bulunamadı.' });
    }

    const invoice = invoiceRes.rows[0];
    if (invoice.status === 'paid') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'already_paid', message: 'Bu fatura zaten daha önce onaylandı.' });
    }
    const transferClaim = await client.query(
      `SELECT id,reference_code FROM bank_transfer_notifications WHERE invoice_id=$1 AND status='pending_review' FOR UPDATE`,
      [id]
    );
    if (!transferClaim.rows.length) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'transfer_not_pending_review', message: 'Onay bekleyen havale bildirimi bulunamadı.' });
    }

    // All payment channels finalize through the same atomic lifecycle.
    const activation = await CommercialLifecycleService.finalizeInvoicePayment(
      client, id, 'bank_transfer', adminUserId,
      { amount: Number(invoice.amount), currency: BillingDomainService.invoiceDetails(invoice).currency || 'TRY',
        referenceCode: transferClaim.rows[0].reference_code },
    );

    await client.query(`
      UPDATE bank_transfer_notifications
      SET status = 'approved', reviewed_by = $1, reviewed_at = NOW(), updated_at = NOW()
      WHERE invoice_id = $2 AND status = 'pending_review'
    `, [adminUserId, id]);

    const billingPeriod = BillingDomainService.normalizePeriod(
      BillingDomainService.invoiceDetails(invoice).billingPeriod
    );

    // 6. Write Admin Audit Log (Inside Transaction, non-blocking)
    try {
      const auditId = BillingDomainService.opaqueId('aud');
      const invoiceAfter = { ...invoice, status: 'paid', paid_at: new Date() };
      await client.query(
        `INSERT INTO audit_logs (id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          auditId,
          invoice.company_id,
          adminUserId,
          'APPROVED_BANK_WIRE_PAYMENT',
          'invoices',
          id,
          JSON.stringify(invoice),
          JSON.stringify(invoiceAfter),
          req.ip || 'admin_panel'
        ]
      );
    } catch (auditErr) {
      logger.error('Failed to write admin audit log inside transaction:', auditErr);
    }

    // 7. Send Notification (Inside Transaction, non-blocking, dynamic phone lookup)
    try {
      const companyRes = await client.query('SELECT phone FROM companies WHERE id = $1', [invoice.company_id]);
      const recipientPhone = companyRes.rows[0]?.phone;

      if (recipientPhone && recipientPhone.trim() !== '') {
        const notifId = BillingDomainService.opaqueId('notif');
        await client.query(`
          INSERT INTO notification_queue (id, company_id, channel, recipient, body, status)
          VALUES ($1, $2, 'sms', $3, 'Sayın Müşterimiz, Havale/EFT ödemeniz onaylanmış ve lisansınız aktif edilmiştir.', 'queued')
        `, [notifId, invoice.company_id, recipientPhone]);
      } else {
        logger.warn(`No phone number found for company ${invoice.company_id}. Skipping SMS notification.`);
      }
    } catch (smsErr) {
      logger.error('Failed to queue SMS notification inside transaction:', smsErr);
    }

    await client.query('COMMIT');

    // Notify open POS and portal sessions immediately. Offline clients refresh
    // their entitlement on their next connection/heartbeat.
    await RealtimeBroadcastService.publishEvent(invoice.company_id, 'LicenseUpdated', {
      subscriptionId: activation.subscriptionId,
      entitlementId: activation.entitlementId,
      invoiceId: id,
      status: 'active',
      billingPeriod,
    });

    logger.info(`Invoice ${id} bank wire approved by admin ${req.user?.email}`);
    return res.json({
      success: true,
      message: 'Ödeme başarıyla onaylandı ve abonelik aktif edildi.',
      billing_period: billingPeriod,
      subscription_id: activation.subscriptionId,
      entitlement_id: activation.entitlementId,
      license_valid_until: activation.validUntil.toISOString(),
    });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Error approving invoice payment:', err);
    return res.status(500).json({ error: 'server_error', message: 'Ödeme onaylanırken sunucu hatası oluştu.' });
  } finally {
    client.release();
  }
});

export default router;

