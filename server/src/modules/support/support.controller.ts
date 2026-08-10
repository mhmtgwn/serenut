// server/src/modules/support/support.controller.ts
// Serenut OS — Support Tickets API
// Blueprint: api_contract.md — Section SUPPORT
// Routes:
//   POST /api/v1/support/tickets       — Create ticket
//   GET  /api/v1/support/tickets       — List tickets (filtered)
//   GET  /api/v1/support/tickets/:id   — Get single ticket
//   PATCH /api/v1/support/tickets/:id/status — Transition FSM

import { Router, Response } from 'express';
import { Webhook } from 'svix';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { SupportService } from './support.service';
import { createError } from '../../config/error-codes';
import { logger } from '../../config/logger';
import { MailService } from '../mail/mail.service';

const router = Router();

function plainTextFromHtml(value: string): string {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

// Resend inbound webhook. Signature verification must use the untouched body.
router.post('/webhooks/resend', async (req: any, res) => {
  const secret = process.env.RESEND_WEBHOOK_SECRET;
  const apiKey = process.env.RESEND_API_KEY;
  if (!secret || !apiKey) {
    logger.error('Resend inbound webhook is not configured.');
    return res.status(503).json({ error: 'webhook_not_configured' });
  }
  try {
    const rawBody = req.rawBody instanceof Buffer ? req.rawBody.toString('utf8') : '';
    if (!rawBody) return res.status(400).json({ error: 'raw_body_required' });
    const event: any = new Webhook(secret).verify(rawBody, {
      'svix-id': String(req.headers['svix-id'] || ''),
      'svix-timestamp': String(req.headers['svix-timestamp'] || ''),
      'svix-signature': String(req.headers['svix-signature'] || ''),
    });
    if (event.type !== 'email.received') {
      await MailService.updateDeliveryStatus(String(event.data?.email_id || ''), String(event.type || ''));
      return res.status(200).json({ accepted: true, ignored: true });
    }

    const data = event.data || {};
    const recipients = Array.isArray(data.to) ? data.to.map((v: unknown) => String(v).toLowerCase()) : [];
    if (!recipients.some((address: string) => address.endsWith('@serenut.com'))) {
      return res.status(200).json({ accepted: true, ignored: true });
    }
    const response = await fetch(`https://api.resend.com/emails/receiving/${encodeURIComponent(String(data.email_id))}`, {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!response.ok) throw new Error(`resend_retrieve_failed:${response.status}`);
    const email: any = await response.json();
    const rawSender = String(email.from || data.from || '').trim();
    const senderMatch = rawSender.match(/^(.*?)\s*<([^>]+)>$/);
    const senderEmail = String(senderMatch?.[2] || rawSender).trim().toLowerCase();
    const senderName = String(senderMatch?.[1] || '').replace(/^['"]|['"]$/g, '').trim().slice(0, 200);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(senderEmail)) throw new Error('invalid_sender_email');
    const subject = String(email.subject || data.subject || '(Konu yok)').trim().slice(0, 500);
    const message = String(email.text || plainTextFromHtml(String(email.html || '')) || subject).slice(0, 10000);
    await MailService.persistInbound({
      emailId: String(data.email_id), senderEmail, senderName: senderName || undefined,
      recipients, subject, textBody: message, htmlBody: email.html ? String(email.html).slice(0, 200000) : undefined,
      messageId: email.message_id || data.message_id,
      inReplyTo: email.headers?.['in-reply-to'] || email.headers?.['In-Reply-To'],
      attachments: Array.isArray(email.attachments) ? email.attachments.map((a: any) => ({
        id: a.id, filename: String(a.filename || '').slice(0, 255), content_type: a.content_type, size: a.size,
      })) : [],
      receivedAt: email.created_at || data.created_at,
    });
    return res.status(200).json({ accepted: true });
  } catch (error) {
    logger.warn('Resend inbound webhook rejected', { error: error instanceof Error ? error.message : String(error) });
    return res.status(400).json({ error: 'invalid_webhook' });
  }
});

// Unauthenticated intake is deliberately kept outside the tenant ticket table.
router.post('/guest-requests', async (req, res) => {
  const { name, email, phone, company_name, customer_claim, category, subject, message, privacy_consent, privacy_notice_version } = req.body;
  if (!name || !email || !subject || !message) {
    return res.status(400).json({ error: 'missing_fields', message: 'Lütfen tüm zorunlu alanları doldurun.' });
  }
  if (privacy_consent !== true || privacy_notice_version !== '2026-08-09') {
    return res.status(400).json({ error: 'privacy_consent_required', message: 'KVKK aydınlatma metnini okuyup onaylamanız gerekir.' });
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
      privacyNoticeVersion: privacy_notice_version,
    });
    return res.status(201).json({
      request,
      message: `Başvurunuz alındı. Takip numaranız: ${request.referenceCode}`,
    });
  } catch (err) {
    if (err instanceof Error && (err.message.includes('Invalid support category') || err.message.includes('Invalid customer claim'))) {
      return res.status(400).json({ error: 'invalid_request_type', message: 'Başvuru türü veya kategori geçersiz.' });
    }
    logger.error('Guest support persistence error:', err);
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
      requesterName: req.user!.name,
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
    logger.error('Create ticket error:', err);
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
    logger.error('List tickets error:', err);
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
    logger.error('List guest support requests error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Misafir başvuruları listelenemedi.' } });
  }
});

router.get('/guest-requests/:id', async (req: AuthenticatedRequest, res: Response) => {
  if (!req.user!.roles?.includes('sysadmin')) return res.status(403).json(createError('AUTH005'));
  try {
    return res.json({ request: await SupportService.getGuestRequest(req.params.id) });
  } catch (error: any) {
    if (error.message === 'guest_request_not_found') {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Başvuru bulunamadı.' } });
    }
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Başvuru yüklenemedi.' } });
  }
});

router.patch('/guest-requests/:id/status', async (req: AuthenticatedRequest, res: Response) => {
  if (!req.user!.roles?.includes('sysadmin')) return res.status(403).json(createError('AUTH005'));
  const status = String(req.body?.status || '');
  if (!['under_review', 'routed_to_sales', 'closed'].includes(status)) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçersiz başvuru durumu.' } });
  }
  try {
    return res.json({ request: await SupportService.updateGuestRequestStatus(req.params.id, status) });
  } catch (error: any) {
    if (error.message === 'guest_request_not_found') {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Başvuru bulunamadı.' } });
    }
    logger.error('Guest support status update failed', error);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Başvuru güncellenemedi.' } });
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
    return res.json(await SupportService.getTicket(
      id,
      isAdmin ? undefined : req.user!.company_id,
    ));
  } catch (err: any) {
    if (err.message.includes('not found')) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Destek talebi bulunamadı.' } });
    }
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Talep getirilemedi.' } });
  }
});

router.post('/tickets/:id/messages', async (req: AuthenticatedRequest, res: Response) => {
  const message = String(req.body?.message || '').trim();
  if (!message || message.length > 10000) {
    return res.status(400).json({
      error: { code: 'VALIDATION', message: 'Yanıt 1 ile 10.000 karakter arasında olmalıdır.' },
    });
  }
  const isSysadmin = req.user!.roles?.includes('sysadmin');
  try {
    const created = await SupportService.addMessage({
      ticketId: req.params.id,
      companyId: isSysadmin ? undefined : req.user!.company_id,
      senderId: req.user!.id,
      senderName: isSysadmin ? 'Serenut Destek' : req.user!.name,
      message,
      isSysadmin,
    });
    return res.status(201).json({ message: created });
  } catch (err: any) {
    if (err.message.includes('not found')) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Destek talebi bulunamadı.' } });
    }
    if (err.message.includes('closed')) {
      return res.status(409).json({ error: { code: 'TICKET_CLOSED', message: 'Kapalı talebe yanıt eklenemez.' } });
    }
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Yanıt kaydedilemedi.' } });
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
    logger.error('Ticket transition error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Durum güncellenemedi.' } });
  }
});

export default router;
