import { Router, Request, Response } from 'express';
import { pgPool, redisClient } from '../../config/database';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../middleware/auth.middleware';
import { InvoiceGeneratorService } from './invoice_generator.service';
import { IyzicoService } from './iyzico.service';
import { logger } from '../../config/logger';
import {
  schedulePaymentRetry,
  processSubscriptionCancellation,
  processReactivation,
} from '../../workers/billing.scheduler';
import { enqueueNotification } from '../../workers/notification.worker';
import {
  welcomePaidEmail,
} from '../notifications/email.templates';
import crypto from 'crypto';
import fs from 'fs';

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
    const result = await runBypassingRLS('SELECT * FROM plans ORDER BY price ASC');
    const plans = result.rows;
    if (redisClient && redisClient.isOpen) {
      await redisClient.setEx(cacheKey, 300, JSON.stringify(plans));
    }
    return res.json(plans);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
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
 *     summary: Start a mockup Stripe/iyzico checkout session
 *     security:
 *       - BearerAuth: []
 */
router.post('/subscribe', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { plan_id, payment_method } = req.body;

  if (!plan_id) {
    return res.status(400).json({ error: 'missing_plan_id' });
  }

  try {
    // 1. Verify plan exists
    const planRes = await runBypassingRLS('SELECT * FROM plans WHERE id = $1', [plan_id]);
    if (planRes.rows.length === 0) {
      return res.status(404).json({ error: 'plan_not_found' });
    }

    const plan = planRes.rows[0];

    // Mockup 3D Secure Webview payment session URL creation
    const sessionToken = `mock-session-${Date.now()}-${Math.floor(Math.random()*1000)}`;
    
    // In production this would hit iyzico/Stripe API, returns checkout url.
    // We return a session token and a redirect URL.
    return res.json({
      success: true,
      sessionToken,
      checkoutUrl: `/api/v1/billing/mock-checkout-portal?session=${sessionToken}&plan=${plan_id}&company=${user.company_id}&token=${req.headers.authorization?.split(' ')[1]}`
    });
  } catch (err) {
    logger.error('Subscribe setup failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// Mockup 3D Secure Checkout HTML Portal (interactive UI shown inside POS or Customer Portal webview)
router.get('/mock-checkout-portal', async (req, res: Response) => {
  const { session, plan, company, token } = req.query;

  const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <title>Serenut Güvenli Ödeme Geçidi</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { background-color: #0F172A; color: white; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .card { background-color: #1E293B; border-radius: 12px; padding: 24px; text-align: center; max-width: 380px; width: 90%; border: 1px solid #16A34A; }
        .btn { background-color: #16A34A; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: bold; width: 100%; margin-top: 16px; }
        .logo { font-size: 20px; color: #16A34A; font-weight: bold; margin-bottom: 8px; }
        .details { font-size: 13px; color: #94A3B8; margin: 12px 0; }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="logo">SERENUT SECURE CHECKOUT</div>
        <div class="details">iyzico / Stripe 3D Secure Entegrasyon Simülasyonu</div>
        <div style="font-size: 16px; font-weight: bold; margin: 20px 0;">Ödeme Tutarı: Simüle Edildi</div>
        
        <form action="/api/v1/billing/mock-checkout-callback" method="POST">
          <input type="hidden" name="sessionToken" value="${session}">
          <input type="hidden" name="planId" value="${plan}">
          <input type="hidden" name="companyId" value="${company}">
          <input type="hidden" name="jwtToken" value="${token}">
          <input type="hidden" name="status" value="success">
          
          <button type="submit" class="btn">3D SECURE ÖDEMEYİ TAMAMLA</button>
        </form>
        
        <form action="/api/v1/billing/mock-checkout-callback" method="POST">
          <input type="hidden" name="sessionToken" value="${session}">
          <input type="hidden" name="planId" value="${plan}">
          <input type="hidden" name="companyId" value="${company}">
          <input type="hidden" name="jwtToken" value="${token}">
          <input type="hidden" name="status" value="failed">
          <button type="submit" class="btn" style="background-color: #EF4444; margin-top: 8px;">ÖDEMEYİ İPTAL ET / REDDET</button>
        </form>
      </div>
    </body>
    </html>
  `;
  return res.send(html);
});

// Checkout Mockup Callback
router.post('/mock-checkout-callback', async (req, res: Response) => {
  const { sessionToken, planId, companyId, jwtToken, status } = req.body;

  if (status !== 'success') {
    return res.send(`
      <script>
        alert("Ödeme iptal edildi veya başarısız oldu.");
        window.close();
      </script>
      <div style="font-family: sans-serif; text-align: center; margin-top: 100px;">
        <h2 style="color: #EF4444;">Ödeme Başarısız ❌</h2>
        <p>Pencereyi kapatıp tekrar deneyebilirsiniz.</p>
      </div>
    `);
  }

  try {
    // 1. Get plan details
    const planRes = await runBypassingRLS('SELECT * FROM plans WHERE id = $1', [planId]);
    const plan = planRes.rows[0];

    // 2. Fetch company billing info for PDF (tax details)
    const companyRes = await runBypassingRLS('SELECT * FROM companies WHERE id = $1', [companyId]);
    const company = companyRes.rows[0];

    // 3. Upsert subscription
    const subId = `sub-${Date.now()}`;
    const now = new Date();
    const periodEnd = new Date();
    periodEnd.setMonth(now.getMonth() + 1); // 1-month cycle

    await runBypassingRLS(`
      INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end, payment_method, cancel_at_period_end, grace_period_until, last_payment_status)
      VALUES ($1, $2, $3, 'active', $4, $5, 'credit_card', false, null, 'success')
      ON CONFLICT (company_id) DO UPDATE SET
        plan_id = EXCLUDED.plan_id,
        status = 'active',
        current_period_start = EXCLUDED.current_period_start,
        current_period_end = EXCLUDED.current_period_end,
        grace_period_until = null,
        last_payment_status = 'success'
    `, [subId, companyId, planId, now, periodEnd]);

    // 4. Create formal Invoice record
    const invoiceId = `inv-rec-${Date.now()}`;
    const invoiceNum = `INV-${now.getFullYear()}-${Math.floor(1000 + Math.random()*9000)}`;
    const billDetails = {
      companyName: company.name,
      taxOffice: company.tax_office || 'Belirtilmedi',
      taxNumber: company.tax_number,
      address: company.address || 'Serenut POS Tenant Address'
    };

    // 5. Generate PDF File
    const pdfPath = await InvoiceGeneratorService.generateInvoicePdf(companyId, {
      invoiceNumber: invoiceNum,
      date: now,
      dueDate: periodEnd,
      companyName: company.name,
      companyAddress: billDetails.address,
      taxOffice: billDetails.taxOffice,
      taxNumber: company.tax_number,
      currency: plan.currency,
      items: [
        {
          description: `Serenut POS Bulut SaaS ${plan.name} Aboneliği`,
          quantity: 1,
          unitPrice: parseFloat(plan.price),
          taxRate: 20 // Standard %20 VAT
        }
      ]
    });

    await runBypassingRLS(`
      INSERT INTO invoices (id, company_id, subscription_id, amount, status, due_at, paid_at, invoice_number, billing_details, payment_gateway_reference, pdf_path)
      VALUES ($1, $2, $3, $4, 'paid', $5, $6, $7, $8, $9, $10)
    `, [
      invoiceId,
      companyId,
      subId,
      plan.price,
      periodEnd,
      now,
      invoiceNum,
      JSON.stringify(billDetails),
      sessionToken,
      pdfPath
    ]);

    // 6. Automatically sync license allowed_devices_count based on plan limits
    const allowedDevices = planId === 'plan-free' ? 1 : (planId === 'plan-basic' ? 2 : (planId === 'plan-pro' ? 5 : 99));
    const tier = planId === 'plan-free' ? 'trial' : (planId === 'plan-enterprise' ? 'enterprise' : 'pro');
    
    // Update license expiration to match sub period end
    await runBypassingRLS(`
      UPDATE licenses 
      SET allowed_devices_count = $1, tier = $2, status = 'active', expires_at = $3
      WHERE company_id = $4
    `, [allowedDevices, tier, periodEnd, companyId]);

    // Send success screen auto-close script
    return res.send(`
      <script>
        alert("Ödeme başarıyla doğrulandı ve aboneliğiniz aktif edildi!");
        if (window.opener) {
          window.opener.postMessage({ status: 'success', planId: '${planId}' }, '*');
        }
        window.close();
      </script>
      <div style="font-family: sans-serif; text-align: center; margin-top: 100px;">
        <h2 style="color: #16A34A;">Ödeme Başarılı! ✅</h2>
        <p>Aboneliğiniz başarıyla aktif edildi. Bu pencereyi kapatabilirsiniz.</p>
      </div>
    `);
  } catch (err) {
    logger.error('Checkout callback DB writing failed:', err);
    return res.status(500).send('Database writing error during checkout completion.');
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

    const path = invoiceRes.rows[0].pdf_path;
    if (!path || !fs.existsSync(path)) {
      return res.status(404).json({ error: 'pdf_not_found', message: 'Fatura PDF dosyası henüz üretilmemiş veya silinmiş.' });
    }

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${invoiceRes.rows[0].invoice_number}.pdf"`);
    return fs.createReadStream(path).pipe(res);
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
router.post('/cancel', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    await runWithTenantContext(
      user.company_id,
      'UPDATE subscriptions SET cancel_at_period_end = true WHERE company_id = $1',
      [user.company_id]
    );
    return res.json({ success: true, message: 'Abonelik yenilemesi iptal edildi. Dönem sonuna kadar kullanım devam edecektir.' });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
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
router.post('/webhook/iyzico', async (req: Request, res: Response) => {
  const signature = req.headers['x-iyz-signature'] as string;
  const payload = req.body;

  logger.info('[Iyzico Webhook] Received webhook event:', JSON.stringify(payload));

  // Signature validation if signature and IYZICO_SECRET are present
  const IYZICO_SECRET = process.env.IYZICO_SECRET_KEY;
  if (IYZICO_SECRET && signature) {
    const computedSignature = crypto
      .createHmac('sha256', IYZICO_SECRET)
      .update(JSON.stringify(payload))
      .digest('hex');
    if (computedSignature !== signature) {
      logger.warn('[Iyzico Webhook] Signature verification failed!');
      return res.status(400).json({ error: 'invalid_signature' });
    }
  }

  const { eventType, token, status, conversationId } = payload;

  try {
    if (status === 'SUCCESS' && token) {
      const subRes = await runBypassingRLS(
        `SELECT id, company_id FROM subscriptions WHERE id = $1 OR company_id = (SELECT company_id FROM invoices WHERE payment_gateway_reference = $2 LIMIT 1)`,
        [conversationId, token]
      );

      if (subRes.rows.length > 0) {
        const sub = subRes.rows[0];
        
        const newStart = new Date();
        const newEnd = new Date();
        newEnd.setMonth(newStart.getMonth() + 1);

        await runBypassingRLS(`
          UPDATE subscriptions 
          SET status = 'active', current_period_start = $1, current_period_end = $2, last_payment_status = 'success', grace_period_until = null
          WHERE id = $3
        `, [newStart, newEnd, sub.id]);

        await runBypassingRLS(`
          UPDATE licenses SET status = 'active', expires_at = $1 WHERE company_id = $2
        `, [newEnd, sub.company_id]);

        logger.info(`[Iyzico Webhook] Successfully updated subscription to active for company: ${sub.company_id}`);
      }
    } else if (status === 'FAILURE') {
      const subRes = await runBypassingRLS(
        `SELECT id, company_id FROM subscriptions WHERE id = $1 OR company_id = (SELECT company_id FROM invoices WHERE payment_gateway_reference = $2 LIMIT 1)`,
        [conversationId, token]
      );
      if (subRes.rows.length > 0) {
        const sub = subRes.rows[0];
        const graceUntil = new Date();
        graceUntil.setDate(graceUntil.getDate() + 7);

        await runBypassingRLS(`
          UPDATE subscriptions 
          SET status = 'grace_period', grace_period_until = $1, last_payment_status = 'failed'
          WHERE id = $2
        `, [graceUntil, sub.id]);

        logger.warn(`[Iyzico Webhook] Subscription set to grace_period for company: ${sub.company_id}`);
      }
    }
    
    return res.json({ status: 'OK' });
  } catch (err) {
    logger.error('[Iyzico Webhook] Error processing event:', err);
    return res.status(500).json({ error: 'server_error' });
  }
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

  try {
    // 1. Get invoice details
    const invoiceRes = await runBypassingRLS('SELECT * FROM invoices WHERE id = $1', [id]);
    if (invoiceRes.rows.length === 0) {
      return res.status(404).json({ error: 'invoice_not_found', message: 'Fatura bulunamadı.' });
    }

    const invoice = invoiceRes.rows[0];
    if (invoice.status === 'paid') {
      return res.status(400).json({ error: 'already_paid', message: 'Fatura zaten ödenmiş.' });
    }

    // 2. Fetch subscription and plan details
    const subRes = await runBypassingRLS('SELECT * FROM subscriptions WHERE id = $1', [invoice.subscription_id]);
    if (subRes.rows.length === 0) {
      return res.status(404).json({ error: 'subscription_not_found', message: 'Abonelik bulunamadı.' });
    }

    const sub = subRes.rows[0];
    const planRes = await runBypassingRLS('SELECT * FROM plans WHERE id = $1', [sub.plan_id]);
    const plan = planRes.rows[0];

    const now = new Date();
    const periodEnd = new Date();
    periodEnd.setMonth(now.getMonth() + 1);

    // 3. Update invoice status
    await runBypassingRLS(
      "UPDATE invoices SET status = 'paid', paid_at = $1 WHERE id = $2",
      [now, id]
    );

    // 4. Update subscription status
    await runBypassingRLS(`
      UPDATE subscriptions 
      SET status = 'active', current_period_start = $1, current_period_end = $2, grace_period_until = null, last_payment_status = 'success'
      WHERE id = $3
    `, [now, periodEnd, sub.id]);

    // 5. Update license allowed_devices_count and expiration
    const allowedDevices = plan.id === 'plan-free' ? 1 : (plan.id === 'plan-basic' ? 2 : (plan.id === 'plan-pro' ? 5 : 99));
    const tier = plan.id === 'plan-free' ? 'trial' : (plan.id === 'plan-enterprise' ? 'enterprise' : 'pro');

    await runBypassingRLS(`
      UPDATE licenses 
      SET allowed_devices_count = $1, tier = $2, status = 'active', expires_at = $3
      WHERE company_id = $4
    `, [allowedDevices, tier, periodEnd, invoice.company_id]);

    logger.info(`Invoice ${id} bank wire payment approved by admin ${req.user?.email}`);
    return res.json({ success: true, message: 'Ödeme başarıyla onaylandı ve abonelik aktif edildi.' });
  } catch (err) {
    logger.error('Error approving invoice payment:', err);
    return res.status(500).json({ error: 'server_error', message: 'Ödeme onaylanırken sunucu hatası oluştu.' });
  }
});

export default router;

