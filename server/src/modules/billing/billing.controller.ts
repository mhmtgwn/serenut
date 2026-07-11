import { Router, Request, Response } from 'express';
import { pgPool, redisClient } from '../../config/database';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../middleware/auth.middleware';
import { InvoiceGeneratorService } from './invoice_generator.service';
import { IyzicoService, loadIyzicoConfig } from './iyzico.service';
import { logger } from '../../config/logger';
import { webhookLimiter } from '../../middleware/rate-limit.middleware';

loadIyzicoConfig(pgPool).catch(err => {
  logger.warn('Failed to load iyzico config at startup:', err);
});
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
import { CommercialLifecycleService } from './commercial_lifecycle.service';

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
    const result = await runBypassingRLS(
      'SELECT id, bank_name, account_holder, iban, currency, branch_name, instructions FROM payment_bank_accounts WHERE is_active = TRUE ORDER BY display_order ASC'
    );
    return res.json(result.rows);
  } catch (err) {
    logger.error('Error fetching bank accounts:', err);
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
  const { plan_id, bank_account_id } = req.body;
  if (!plan_id || !bank_account_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Plan ve banka hesabı seçimi zorunludur.' });
  }
  try {
    const planRes = await runBypassingRLS('SELECT * FROM plans WHERE id = $1', [plan_id]);
    if (planRes.rows.length === 0) return res.status(404).json({ error: 'plan_not_found' });
    const plan = planRes.rows[0];

    const bankRes = await runBypassingRLS('SELECT * FROM payment_bank_accounts WHERE id = $1 AND is_active = TRUE', [bank_account_id]);
    if (bankRes.rows.length === 0) return res.status(404).json({ error: 'bank_account_not_found' });
    const bank = bankRes.rows[0];

    const now = new Date();
    const periodEnd = new Date(now);
    periodEnd.setMonth(periodEnd.getMonth() + 1);

    // Create pending invoice
    const invoiceId = `inv-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const invoiceNum = `INV-${now.getFullYear()}-${Math.floor(1000 + Math.random() * 9000)}`;
    await runBypassingRLS(
      `INSERT INTO invoices (id, company_id, amount, status, due_at, invoice_number, billing_details)
       VALUES ($1,$2,$3,'pending',$4,$5,$6)`,
      [invoiceId, user.company_id, plan.price, periodEnd, invoiceNum, JSON.stringify({ planName: plan.name, planId: plan_id })]
    );

    // Generate unique reference code: SRNTT-YYYYMMDD-XXXX
    const datePart = now.toISOString().slice(0, 10).replace(/-/g, '');
    const randPart = crypto.randomBytes(2).toString('hex').toUpperCase();
    const referenceCode = `SRNTT-${datePart}-${randPart}`;

    // Create bank transfer notification
    const notifId = `btn-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    await runBypassingRLS(
      `INSERT INTO bank_transfer_notifications (id, invoice_id, company_id, bank_account_id, reference_code, status)
       VALUES ($1,$2,$3,$4,$5,'pending_review')`,
      [notifId, invoiceId, user.company_id, bank_account_id, referenceCode]
    );

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
      amount: plan.price,
      currency: plan.currency,
      message: `Lütfen havale açıklama alanına referans kodunuzu yazın: ${referenceCode}`,
    });
  } catch (err) {
    logger.error('Error creating bank transfer request:', err);
    return res.status(500).json({ error: 'server_error' });
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
       SET sender_name=$1, sender_bank=$2, transfer_date=$3, transfer_description=$4, updated_at=NOW()
       WHERE invoice_id=$5 AND company_id=$6 AND status='pending_review'
       RETURNING reference_code`,
      [sender_name || null, sender_bank || null, transfer_date || null, transfer_description || null, invoice_id, user.company_id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'notification_not_found', message: 'Havale bildirimi bulunamadı veya zaten işleme alındı.' });
    }
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
             inv.id as invoice_id, inv.amount, inv.invoice_number,
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
  if (process.env.NODE_ENV === 'production') {
    return res.status(403).send('<h2>Mock checkout portal is disabled in production.</h2>');
  }
  const { session, plan, company, token } = req.query;

  let IBAN_BANK = process.env.SYSTEM_IBAN_BANK || 'Yapı Kredi Bankası A.Ş.';
  let IBAN_BRANCH = process.env.SYSTEM_IBAN_BRANCH || 'İstanbul Kozyatağı Ticari Şubesi';
  let IBAN_OWNER = process.env.SYSTEM_IBAN_OWNER || 'Serenut Yazılım Teknolojileri Ltd. Şti.';
  let IBAN_NUMBER = process.env.SYSTEM_IBAN_NUMBER || 'TR24 0006 2000 0000 9876 5432 10';

  try {
    const settingsRes = await runBypassingRLS("SELECT key, value FROM system_settings WHERE key IN ('iban_bank', 'iban_branch', 'iban_owner', 'iban_number')");
    settingsRes.rows.forEach(r => {
      if (r.key === 'iban_bank') IBAN_BANK = r.value;
      if (r.key === 'iban_branch') IBAN_BRANCH = r.value;
      if (r.key === 'iban_owner') IBAN_OWNER = r.value;
      if (r.key === 'iban_number') IBAN_NUMBER = r.value;
    });
  } catch (err) {
    logger.warn('Failed to load system settings for checkout, using defaults:', err);
  }

  const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <title>Serenut Güvenli Ödeme Geçidi</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { background-color: #0F172A; color: white; font-family: sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px 0; box-sizing: border-box; }
        .card { background-color: #1E293B; border-radius: 12px; padding: 24px; text-align: left; max-width: 440px; width: 90%; border: 1px solid #16A34A; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
        .btn { background-color: #16A34A; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; font-size: 14px; font-weight: bold; width: 100%; margin-top: 16px; transition: all 0.3s; }
        .btn:hover { background-color: #15803d; }
        .logo { font-size: 20px; color: #16A34A; font-weight: bold; margin-bottom: 8px; text-align: center; }
        .details { font-size: 13px; color: #94A3B8; margin: 12px 0; text-align: center; }
        .tab-btn { flex: 1; padding: 10px; background: #334155; border: none; color: white; font-weight: bold; cursor: pointer; border-radius: 6px 6px 0 0; font-size: 13px; }
        .tab-btn.active { background: #1E293B; color: #16A34A; border-bottom: 2px solid #16A34A; }
        .tab-content { display: none; background: #1E293B; padding-top: 15px; }
        .tab-content.active { display: block; }
        .iban-box { background: #0F172A; border-radius: 8px; padding: 12px; font-size: 13px; line-height: 1.5; color: #E2E8F0; margin-bottom: 12px; border: 1px solid #334155; }
        .form-group { display: flex; flex-direction: column; gap: 6px; margin-bottom: 12px; }
        .form-group label { font-size: 12px; color: #94A3B8; font-weight: bold; }
        .form-group input { background: #0F172A; border: 1px solid #334155; border-radius: 6px; padding: 10px; color: white; font-size: 13px; outline: none; }
        .form-group input:focus { border-color: #16A34A; }
      </style>
      <script>
        function switchTab(tabId) {
          document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
          document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
          document.getElementById('btn-' + tabId).classList.add('active');
          document.getElementById('content-' + tabId).classList.add('active');
        }
      </script>
    </head>
    <body>
      <div class="card">
        <div class="logo">SERENUT ÖDEME GEÇİDİ</div>
        <div class="details">Lütfen tercih ettiğiniz ödeme yöntemini seçin.</div>
        
        <div style="display: flex; gap: 4px; margin-bottom: 10px; border-bottom: 1px solid #334155;">
          <button id="btn-iban" class="tab-btn active" onclick="switchTab('iban')">🏦 Banka Havalesi / EFT</button>
          <button id="btn-card" class="tab-btn" onclick="switchTab('card')">💳 Kredi Kartı (iyzico / PayTR)</button>
        </div>

        <!-- TAB: IBAN -->
        <div id="content-iban" class="tab-content active">
          <div class="iban-box">
            <strong>Banka:</strong> ${IBAN_BANK}<br>
            <strong>Şube:</strong> ${IBAN_BRANCH}<br>
            <strong>Alıcı:</strong> ${IBAN_OWNER}<br>
            <strong>IBAN:</strong> <span style="font-family: monospace; color:#10B981; font-weight:bold;">${IBAN_NUMBER}</span><br>
            <strong>Açıklama:</strong> <span style="color:#F59E0B; font-weight:bold;">${company}</span> (Şirket ID'nizi açıklama alanına aynen yazınız.)
          </div>
          
          <form action="/api/v1/billing/mock-checkout-callback" method="POST">
            <input type="hidden" name="sessionToken" value="${session}">
            <input type="hidden" name="planId" value="${plan}">
            <input type="hidden" name="companyId" value="${company}">
            <input type="hidden" name="jwtToken" value="${token}">
            <input type="hidden" name="payment_method" value="bank_wire">
            <input type="hidden" name="status" value="pending">
            
            <div class="form-group">
              <label>Ödemeyi Yapan Ad Soyad / Ünvan</label>
              <input type="text" name="senderName" placeholder="Örn: Ahmet Yılmaz" required>
            </div>
            
            <div class="form-group">
              <label>Gönderilen Banka</label>
              <input type="text" name="senderBank" placeholder="Örn: Garanti Bankası" required>
            </div>
            
            <button type="submit" class="btn">HAVALE ÖDEMESİNİ BİLDİR VE TAMAMLA</button>
          </form>
        </div>

        <!-- TAB: CREDIT CARD -->
        <div id="content-card" class="tab-content">
          <div class="iban-box" style="border-left: 3px solid #F59E0B; background: rgba(245,158,11,0.05);">
            ℹ️ Kredi kartı ile otomatik ödeme entegrasyonu (iyzico / PayTR) yakında aktif edilecektir. 
            Geliştirme aşamasında kredi kartı akışını test etmek için aşağıdaki simülasyon butonunu kullanabilirsiniz.
          </div>
          
          <form action="/api/v1/billing/mock-checkout-callback" method="POST">
            <input type="hidden" name="sessionToken" value="${session}">
            <input type="hidden" name="planId" value="${plan}">
            <input type="hidden" name="companyId" value="${company}">
            <input type="hidden" name="jwtToken" value="${token}">
            <input type="hidden" name="payment_method" value="credit_card">
            <input type="hidden" name="status" value="success">
            
            <button type="submit" class="btn" style="background-color: #8B5CF6;">SİMÜLE KART ÖDEMESİNİ TAMAMLA</button>
          </form>
        </div>

        <form action="/api/v1/billing/mock-checkout-callback" method="POST">
          <input type="hidden" name="sessionToken" value="${session}">
          <input type="hidden" name="planId" value="${plan}">
          <input type="hidden" name="companyId" value="${company}">
          <input type="hidden" name="jwtToken" value="${token}">
          <input type="hidden" name="status" value="failed">
          <button type="submit" class="btn" style="background-color: #EF4444; margin-top: 8px;">ÖDEMEYİ İPTAL ET / PENCEREYİ KAPAT</button>
        </form>
      </div>
    </body>
    </html>
  `;
  return res.send(html);
});

// Checkout Mockup Callback
router.post('/mock-checkout-callback', async (req, res: Response) => {
  if (process.env.NODE_ENV === 'production') {
    return res.status(403).json({ error: 'forbidden', message: 'Mock callback is disabled in production.' });
  }
  const { sessionToken, planId, companyId, jwtToken, status, payment_method, senderName, senderBank } = req.body;

  if (status === 'failed') {
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

  const isBankWire = payment_method === 'bank_wire';

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

    const subStatus = isBankWire ? 'suspended' : 'active';
    const subPayStatus = isBankWire ? 'pending' : 'success';
    const payMethod = payment_method || 'credit_card';

    await runBypassingRLS(`
      INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end, payment_method, cancel_at_period_end, grace_period_until, last_payment_status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, false, null, $8)
      ON CONFLICT (company_id) DO UPDATE SET
        plan_id = EXCLUDED.plan_id,
        status = EXCLUDED.status,
        payment_method = EXCLUDED.payment_method,
        grace_period_until = null,
        last_payment_status = EXCLUDED.last_payment_status
    `, [subId, companyId, planId, subStatus, now, periodEnd, payMethod, subPayStatus]);

    // 4. Create formal Invoice record
    const invoiceId = `inv-rec-${Date.now()}`;
    const invoiceNum = `INV-${now.getFullYear()}-${Math.floor(1000 + Math.random()*9000)}`;
    const billDetails = {
      companyName: company.name,
      taxOffice: company.tax_office || 'Belirtilmedi',
      taxNumber: company.tax_number,
      address: company.address || 'Serenut POS Tenant Address',
      senderName: senderName || null,
      senderBank: senderBank || null,
      paymentMethod: payMethod
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

    const invStatus = isBankWire ? 'pending' : 'paid';
    const paidAtVal = isBankWire ? null : now;

    await runBypassingRLS(`
      INSERT INTO invoices (id, company_id, subscription_id, amount, status, due_at, paid_at, invoice_number, billing_details, payment_gateway_reference, pdf_path)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    `, [
      invoiceId,
      companyId,
      subId,
      plan.price,
      invStatus,
      periodEnd,
      paidAtVal,
      invoiceNum,
      JSON.stringify(billDetails),
      sessionToken,
      pdfPath
    ]);

    if (!isBankWire) {
      // 6. Activate subscription + license entitlement via CommercialLifecycleService
      const lsClient = await pgPool.connect();
      try {
        await lsClient.query('BEGIN');
        await lsClient.query("SET LOCAL app.bypass_rls = 'true'");
        await CommercialLifecycleService.activatePaidSubscription(lsClient, {
          companyId,
          planId,
          grantType: 'card',
          periodStart: now,
        });
        await lsClient.query('COMMIT');
      } catch (lsErr) {
        await lsClient.query('ROLLBACK');
        throw lsErr;
      } finally {
        lsClient.release();
      }

      return res.send(`
        <script>
          alert("Ödemeniz başarıyla alındı ve onaylandı.");
          if (window.opener) {
            window.opener.postMessage({ status: "success" }, "*");
          }
          window.close();
        </script>
        <div style="font-family: sans-serif; text-align: center; margin-top: 100px;">
          <h2 style="color: #16A34A;">Ödeme Başarılı ✔️</h2>
          <p>Aboneliğiniz aktif edildi. Bu pencereyi kapatabilirsiniz.</p>
        </div>
      `);
    } else {
      // For bank wire: do not touch license (remains suspended/inactive until admin manually approves it).
      return res.send(`
        <script>
          alert("Banka havalesi ödeme bildiriminiz alındı! Yöneticilerimiz ödemeyi onayladığında aboneliğiniz aktif edilecektir.");
          if (window.opener) {
            window.opener.postMessage({ status: "pending" }, "*");
          }
          window.close();
        </script>
        <div style="font-family: sans-serif; text-align: center; margin-top: 100px; color: white;">
          <h2 style="color: #10B981;">Ödeme Bildirimi Alındı ✔️</h2>
          <p>Havale bildiriminiz yöneticilere iletildi. Kontroller yapıldıktan sonra aboneliğiniz onaylanacaktır.</p>
          <p>Bu pencereyi kapatabilirsiniz.</p>
        </div>
      `);
    }
  } catch (err) {
    logger.error('Checkout callback processing failed:', err);
    return res.status(500).send("<h2>Ödeme onaylama esnasında hata oluştu.</h2>");
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
router.post('/webhook/iyzico', webhookLimiter, async (req: Request, res: Response) => {
  const signature = req.headers['x-iyz-signature'] as string;
  const payload = req.body;

  logger.info('[Iyzico Webhook] Received webhook event:', JSON.stringify(payload));

  const IYZICO_SECRET = process.env.IYZICO_SECRET_KEY;
  if (!IYZICO_SECRET) {
    logger.error('[Iyzico Webhook] Server configuration error: IYZICO_SECRET_KEY is missing.');
    return res.status(500).json({ error: 'misconfigured_payment_gateway' });
  }

  if (!signature) {
    logger.warn('[Iyzico Webhook] Webhook request rejected: missing x-iyz-signature header.');
    return res.status(400).json({ error: 'missing_signature' });
  }

  if (!req.rawBody && process.env.NODE_ENV !== 'test') {
    logger.error('[Iyzico Webhook] Raw body buffer is missing. Express parser verify config is incorrect.');
    return res.status(500).json({ error: 'internal_error' });
  }

  const rawPayload = req.rawBody || Buffer.from(JSON.stringify(payload));
  const computedSignature = crypto
    .createHmac('sha256', IYZICO_SECRET)
    .update(rawPayload)
    .digest('hex');

  try {
    const signatureBuffer = Buffer.from(signature, 'hex');
    const computedBuffer = Buffer.from(computedSignature, 'hex');

    if (
      signatureBuffer.length !== computedBuffer.length ||
      !crypto.timingSafeEqual(signatureBuffer, computedBuffer)
    ) {
      logger.warn('[Iyzico Webhook] Webhook signature verification failed!');
      return res.status(400).json({ error: 'invalid_signature' });
    }
  } catch (err) {
    logger.error('[Iyzico Webhook] Hex signature parsing or comparison failed:', err);
    return res.status(400).json({ error: 'invalid_signature_format' });
  }

  // Replay protection: Check webhook timestamp payload if present (iyziEventTime or standard timestamp)
  // Ensure the difference is not more than 5 minutes (300 seconds)
  const eventTime = payload.iyziEventTime || payload.timestamp;
  if (eventTime) {
    const eventMs = isNaN(Number(eventTime)) ? Date.parse(eventTime) : Number(eventTime);
    if (!isNaN(eventMs)) {
      const diffSec = Math.abs(Date.now() - eventMs) / 1000;
      if (diffSec > 300) {
        logger.warn(`[Iyzico Webhook] Replay attack alert: event older than 300s (diff: ${diffSec}s).`);
        return res.status(400).json({ error: 'stale_webhook_event' });
      }
    }
  }

  const { eventType, token, status, conversationId } = payload;

  // Idempotency check: If invoice is already marked as paid, return OK early without processing database updates
  if (token) {
    try {
      const invoiceCheck = await runBypassingRLS(
        "SELECT status FROM invoices WHERE payment_gateway_reference = $1",
        [token]
      );
      if (invoiceCheck.rows.length > 0 && invoiceCheck.rows[0].status === 'paid') {
        logger.info(`[Iyzico Webhook] Webhook ignored idempotently: Invoice already paid for token: ${token}`);
        return res.json({ status: 'OK' });
      }
    } catch (dbErr) {
      logger.error('[Iyzico Webhook] Idempotency check db error:', dbErr);
    }
  }

  try {
    if (status === 'SUCCESS' && token) {
      const subRes = await runBypassingRLS(
        `SELECT id, company_id, plan_id FROM subscriptions WHERE id = $1 OR company_id = (SELECT company_id FROM invoices WHERE payment_gateway_reference = $2 LIMIT 1)`,
        [conversationId, token]
      );

      if (subRes.rows.length > 0) {
        const sub = subRes.rows[0];
        
        // Execute unified entitlement activation via database client transaction
        const client = await pgPool.connect();
        try {
          await client.query('BEGIN');
          await client.query("SET LOCAL app.bypass_rls = 'true'");
          
          await CommercialLifecycleService.activatePaidSubscription(client, {
            companyId: sub.company_id,
            planId: sub.plan_id || 'plan-pro',
            paymentId: token,
            grantType: 'card'
          });

          // Mark matching invoice as paid
          await client.query(
            "UPDATE invoices SET status = 'paid', paid_at = NOW() WHERE payment_gateway_reference = $1",
            [token]
          );

          await client.query('COMMIT');
        } catch (txnErr) {
          await client.query('ROLLBACK');
          throw txnErr;
        } finally {
          client.release();
        }

        logger.info(`[Iyzico Webhook] Successfully updated subscription & entitlements to active for company: ${sub.company_id}`);
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

    // 2. Fetch plan from subscription
    const subRes = await client.query(
      'SELECT plan_id FROM subscriptions WHERE id = $1',
      [invoice.subscription_id]
    );
    const planId = subRes.rows[0]?.plan_id ?? 'plan-basic';

    // 3. Mark invoice as paid
    await client.query(
      "UPDATE invoices SET status = 'paid', paid_at = NOW() WHERE id = $1",
      [id]
    );

    // 4. Update bank_transfer_notifications if present
    await client.query(`
      UPDATE bank_transfer_notifications
      SET status = 'approved', reviewed_by = $1, reviewed_at = NOW(), updated_at = NOW()
      WHERE invoice_id = $2 AND status = 'pending_review'
    `, [adminUserId, id]);

    // 5. Atomic subscription + entitlement upsert
    await CommercialLifecycleService.activatePaidSubscription(client, {
      companyId: invoice.company_id,
      planId,
      grantType: 'bank_transfer',
      adminUserId,
    });

    await client.query('COMMIT');

    logger.info(`Invoice ${id} bank wire approved by admin ${req.user?.email}`);
    return res.json({ success: true, message: 'Ödeme başarıyla onaylandı ve abonelik aktif edildi.' });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Error approving invoice payment:', err);
    return res.status(500).json({ error: 'server_error', message: 'Ödeme onaylanırken sunucu hatası oluştu.' });
  } finally {
    client.release();
  }
});

export default router;

