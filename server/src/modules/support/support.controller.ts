// server/src/modules/support/support.controller.ts
// Serenut OS — Support Tickets API
// Blueprint: api_contract.md — Section SUPPORT
// Routes:
//   POST /api/v1/support/tickets       — Create ticket
//   GET  /api/v1/support/tickets       — List tickets (filtered)
//   GET  /api/v1/support/tickets/:id   — Get single ticket
//   PATCH /api/v1/support/tickets/:id/status — Transition FSM

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { SupportService } from './support.service';
import { createError } from '../../config/error-codes';
import { pgPool } from '../../config/database';

const router = Router();

// Unauthenticated intake is deliberately kept outside the tenant ticket table.
router.post('/guest-requests', async (req, res) => {
  const { name, email, phone, company_name, customer_claim, category, subject, message } = req.body;
  if (!name || !email || !subject || !message) {
    return res.status(400).json({ error: 'missing_fields', message: 'Lütfen tüm zorunlu alanları doldurun.' });
  }
  const normalizedEmail = String(email).trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
    return res.status(400).json({ error: 'invalid_email', message: 'Geçerli bir e-posta adresi girin.' });
  }
  if (String(name).trim().length > 200 || String(subject).trim().length > 500 || String(message).trim().length > 10000) {
    return res.status(400).json({ error: 'invalid_length', message: 'Başvuru alanlarından biri izin verilen uzunluğu aşıyor.' });
  }
  try {
    const request = await SupportService.createGuestRequest({
      name: String(name).trim(), email: normalizedEmail,
      phone: phone ? String(phone).trim() : undefined,
      companyName: company_name ? String(company_name).trim() : undefined,
      customerClaim: customer_claim, category,
      subject: String(subject).trim(), message: String(message).trim(),
    });
    return res.status(201).json({
      request,
      message: `Başvurunuz alındı. Takip numaranız: ${request.referenceCode}`,
    });
  } catch (err) {
    if (err instanceof Error && (err.message.includes('Invalid support category') || err.message.includes('Invalid customer claim'))) {
      return res.status(400).json({ error: 'invalid_request_type', message: 'Başvuru türü veya kategori geçersiz.' });
    }
    console.error('Guest support persistence error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Başvurunuz kaydedilemedi.' });
  }
});

// All support routes require authentication
router.use(authenticateUser);

/**
 * @swagger
 * /support/tickets:
 *   post:
 *     summary: Create a new support ticket
 *     tags: [Support]
 *     security:
 *       - BearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [subject]
 *             properties:
 *               subject: { type: string, maxLength: 500 }
 *               body: { type: string }
 *               priority: { type: string, enum: [P1, P2, P3, P4] }
 *               logs: { type: string, description: "Telemetry log snapshot" }
 *     responses:
 *       201:
 *         description: Ticket created
 *       400:
 *         description: Validation error
 */
router.post('/tickets', async (req: AuthenticatedRequest, res: Response) => {
  const { subject, body, priority, category, logs } = req.body;

  if (!subject || subject.trim().length === 0) {
    return res.status(400).json({
      error: { code: 'VALIDATION', message: 'Konu alanı zorunludur.' },
    });
  }
  if (subject.length > 500) {
    return res.status(400).json({
      error: { code: 'VALIDATION', message: 'Konu en fazla 500 karakter olabilir.' },
    });
  }

  try {
    const ticket = await SupportService.createTicket({
      companyId: req.user!.company_id,
      requesterUserId: req.user!.id,
      subject: subject.trim(),
      body: body ?? undefined,
      priority: priority ?? 'P3',
      category: category ?? 'technical',
      logsSnapshot: logs ?? undefined,
    });

    return res.status(201).json({ ticket });
  } catch (err: any) {
    if (err.message.includes('Invalid priority') || err.message.includes('Invalid support category')) {
      return res.status(400).json({
        error: { code: 'VALIDATION', message: 'Geçersiz öncelik seviyesi. P1, P2, P3 veya P4 olmalıdır.' },
      });
    }
    console.error('Create ticket error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Destek talebi oluşturulamadı.' } });
  }
});

/**
 * @swagger
 * /support/tickets:
 *   get:
 *     summary: List support tickets for the authenticated company
 *     tags: [Support]
 *     security:
 *       - BearerAuth: []
 *     parameters:
 *       - in: query
 *         name: status
 *         schema: { type: string, enum: [open, in_progress, pending_customer, resolved, closed] }
 *       - in: query
 *         name: priority
 *         schema: { type: string, enum: [P1, P2, P3, P4] }
 *       - in: query
 *         name: page
 *         schema: { type: integer, default: 1 }
 *       - in: query
 *         name: limit
 *         schema: { type: integer, default: 20 }
 *     responses:
 *       200:
 *         description: Paginated list of tickets
 */
router.get('/tickets', async (req: AuthenticatedRequest, res: Response) => {
  const { status, priority, page, limit } = req.query;

  // Sysadmin sees ALL tickets; regular users see only their company's tickets
  const isSysadmin = req.user!.roles?.includes('sysadmin');
  const companyIdFilter = isSysadmin ? undefined : req.user!.company_id;

  try {
    const result = await SupportService.listTickets({
      companyId: companyIdFilter,
      status: status as string | undefined,
      priority: priority as string | undefined,
      page: page ? parseInt(page as string, 10) : 1,
      limit: limit ? Math.min(parseInt(limit as string, 10), 100) : 20,
    });

    return res.json(result);
  } catch (err: any) {
    console.error('List tickets error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Destek talepleri listelenemedi.' } });
  }
});

router.get('/guest-requests', async (req: AuthenticatedRequest, res: Response) => {
  const isSysadmin = req.user!.roles?.includes('sysadmin');
  if (!isSysadmin) return res.status(403).json(createError('AUTH005'));
  try {
    const requests = await SupportService.listGuestRequests(Number(req.query.limit) || 100);
    return res.json({ requests });
  } catch (err) {
    console.error('List guest support requests error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Misafir başvuruları listelenemedi.' } });
  }
});

/**
 * @swagger
 * /support/tickets/{id}:
 *   get:
 *     summary: Get a single ticket by ID
 *     tags: [Support]
 *     security:
 *       - BearerAuth: []
 */
router.get('/tickets/:id', async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const isAdmin = req.user!.roles?.includes('sysadmin');

  try {
    const client = await pgPool.connect();
    try {
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const query = isAdmin
        ? 'SELECT * FROM support_tickets WHERE id = $1'
        : 'SELECT * FROM support_tickets WHERE id = $1 AND company_id = $2';
      const params = isAdmin ? [id] : [id, req.user!.company_id];
      const result = await client.query(query, params);

      if (result.rows.length === 0) {
        return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Destek talebi bulunamadı.' } });
      }

      return res.json({ ticket: result.rows[0] });
    } finally {
      client.release();
    }
  } catch (err: any) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Talep getirilemedi.' } });
  }
});

/**
 * @swagger
 * /support/tickets/{id}/status:
 *   patch:
 *     summary: Transition ticket status (FSM)
 *     tags: [Support]
 *     security:
 *       - BearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [status]
 *             properties:
 *               status:
 *                 type: string
 *                 enum: [in_progress, pending_customer, resolved, closed]
 */
router.patch('/tickets/:id/status', async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const { status } = req.body;

  if (!req.user!.roles?.includes('sysadmin')) {
    return res.status(403).json(createError('AUTH005'));
  }

  if (!status) {
    return res.status(400).json({
      error: { code: 'VALIDATION', message: 'Yeni durum belirtilmelidir.' },
    });
  }

  const validStatuses = ['open', 'in_progress', 'pending_customer', 'resolved', 'closed'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({
      error: { code: 'VALIDATION', message: `Geçersiz durum. Geçerli değerler: ${validStatuses.join(', ')}` },
    });
  }

  try {
    const result = await SupportService.transitionTicket(id, status, req.user!.email);
    return res.json(result);
  } catch (err: any) {
    if (err.message.includes('Invalid ticket FSM transition')) {
      return res.status(409).json({
        error: { code: 'INVALID_TRANSITION', message: err.message },
      });
    }
    if (err.message.includes('not found')) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Destek talebi bulunamadı.' } });
    }
    console.error('Ticket transition error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Durum güncellenemedi.' } });
  }
});

/**
 * @swagger
 * /support/tickets/{id}/pin:
 *   post:
 *     summary: Generate one-time remote support PIN (sysadmin only)
 *     tags: [Support]
 *     security:
 *       - BearerAuth: []
 */
router.post('/tickets/:id/pin', async (req: AuthenticatedRequest, res: Response) => {
  const isAdmin = req.user!.roles?.includes('sysadmin');
  if (!isAdmin) {
    return res.status(403).json(createError('AUTH005'));
  }

  const { id } = req.params;

  try {
    const pin = await SupportService.generateSupportPin(id);
    return res.json({ pin, ticketId: id });
  } catch (err: any) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'PIN oluşturulamadı.' } });
  }
});

export default router;
