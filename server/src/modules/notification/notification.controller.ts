import { Router, Response, NextFunction } from 'express';
import { notificationRepository } from './notification.repository';
import { authenticateUser, AuthenticatedRequest, requireRole, requirePermission, requireActiveEntitlementForMutations } from '../../middleware/auth.middleware';
import { TemplateParserService } from './template_parser.service';
import { logger } from '../../config/logger';
import { isNotificationChannelEnabled } from './notification_channels';
import { enforceNotificationRateLimit, enforceCampaignAbuseLimit } from '../../middleware/rate-limit.middleware';
import { dispatchNotificationOutboxBatch } from '../../workers/notification.worker';

const router = Router();

const requireSmsHistoryAccess = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction,
) => {
  const permissions = req.user?.permissions || [];
  if (
    permissions.includes('notifications.history.read') ||
    permissions.includes('settings:view') || req.user?.roles?.some(r => ['owner', 'admin', 'sysadmin'].includes(r))
  ) {
    return next();
  }
  return res.status(403).json({
    error: 'forbidden',
    message: 'SMS geçmişini görüntüleme yetkiniz bulunmuyor.',
  });
};

// Apply auth globally
router.use(authenticateUser);
router.use(requireActiveEntitlementForMutations);

const runWithTenantContext = notificationRepository.runWithTenantContext.bind(notificationRepository);
const runBypassingRLS = notificationRepository.runBypassingRLS.bind(notificationRepository);
const hasSufficientCredits = notificationRepository.hasSufficientCredits.bind(notificationRepository);

/**
 * @openapi
 * /api/v1/notifications/send-direct:
 *   post:
 *     summary: Queue a direct single message
 */
router.post('/send-direct', enforceNotificationRateLimit, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { channel, recipient, title, body, template_name, template_payload, scheduled_at } = req.body;

  if (!channel || !recipient) {
    return res.status(400).json({ error: 'missing_fields', message: 'Kanal ve alıcı bilgileri zorunludur.' });
  }
  if (!isNotificationChannelEnabled(channel)) {
    return res.status(409).json({
      error: 'notification_channel_not_enabled',
      message: 'Bu bildirim kanalı bu sunucuda etkin değil.',
    });
  }

  try {
    if (channel === 'whatsapp') {
      const connection = await runWithTenantContext(
        user.company_id,
        `SELECT status,evolution_status FROM company_whatsapp_connections
         WHERE company_id=$1 AND gateway_type='evolution'`,
        [user.company_id],
      );
      const row = connection.rows[0];
      if (!row || row.status !== 'active' || row.evolution_status !== 'open') {
        return res.status(409).json({
          error: 'whatsapp_not_connected',
          message: 'WhatsApp Evolution API bağlantısı açık değil.',
        });
      }
    }

    // 1. Verify credits
    const hasCredit = await hasSufficientCredits(user.company_id, channel);
    if (!hasCredit) {
      return res.status(402).json({ error: 'out_of_credits', message: 'Gönderim için kalan krediniz yetersizdir.' });
    }

    let finalBody = body || '';

    // 2. Parse dynamic template if template_name is specified
    if (template_name) {
      const templateRes = await runWithTenantContext(
        user.company_id,
        'SELECT body FROM notification_templates WHERE name = $1 AND channel = $2',
        [template_name, channel]
      );
      if (templateRes.rows.length > 0) {
        finalBody = TemplateParserService.parse(templateRes.rows[0].body, template_payload || {});
      } else {
        return res.status(404).json({ error: 'template_not_found', message: 'Belirtilen şablon bulunamadı.' });
      }
    }

    if (!finalBody) {
      return res.status(400).json({ error: 'empty_message', message: 'Mesaj içeriği boş olamaz.' });
    }

    // 3. Insert into queue
    const id = `notif-${Date.now()}-${Math.floor(Math.random()*1000)}`;
    const parsedScheduledAt = scheduled_at ? new Date(scheduled_at) : new Date();

    await runWithTenantContext(
      user.company_id,
      `INSERT INTO notification_queue
         (id, company_id, channel, recipient, title, body, provider_payload, scheduled_at, created_by_user_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9)`,
      [id, user.company_id, channel, recipient, title || null, finalBody,
        null, parsedScheduledAt, user.id]
    );

    dispatchNotificationOutboxBatch().catch(() => {});
    return res.status(201).json({ success: true, queue_id: id });
  } catch (err) {
    logger.error('Failed direct notify queue push:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/notifications/sync-local:
 *   post:
 *     summary: Log a local SMS attempt from the client to the cloud database
 */
router.post('/sync-local', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { recipient, body, status, error_message, channel, created_at, client_message_id } = req.body;

  if (!recipient || !body || !status) {
    return res.status(400).json({ error: 'missing_fields', message: 'Alıcı, mesaj içeriği ve durum zorunludur.' });
  }

  try {
    const id = `notif-loc-${Date.now()}-${Math.floor(Math.random()*1000)}`;
    const parsedCreatedAt = created_at ? new Date(created_at) : new Date();

    const result = await runWithTenantContext(
      user.company_id,
      `INSERT INTO notification_queue (id, company_id, channel, recipient, title, body, status, error_message, created_at, delivered_at, client_message_id, created_by_user_id)
       VALUES ($1, $2, $3, $4, NULL, $5, $6, $7, $8, $9, $10, $11)
       ON CONFLICT (company_id, client_message_id)
       WHERE client_message_id IS NOT NULL
       DO NOTHING
       RETURNING id`,
      [
        id,
        user.company_id,
        channel || 'sms',
        recipient,
        body,
        status,
        error_message || null,
        parsedCreatedAt,
        status === 'sent' ? new Date() : null,
        client_message_id || null,
        user.id,
      ]
    );

    const wasDeduplicated = !result.rows || result.rows.length === 0;
    return res.status(201).json({
      success: true,
      queue_id: wasDeduplicated ? null : id,
      deduplicated: wasDeduplicated,
    });
  } catch (err) {
    logger.error('Failed to sync local notification:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/sms-gateway', async (req: AuthenticatedRequest, res: Response) => {
  const result = await runWithTenantContext(
    req.user!.company_id,
    `SELECT g.device_activation_id, g.selected_at, g.last_poll_at,
            d.device_name, d.device_hash, d.platform, d.status,
            CASE WHEN g.last_poll_at > NOW() - INTERVAL '5 minutes' THEN true ELSE false END AS is_online
     FROM company_sms_gateways g
     JOIN device_activations d ON d.id = g.device_activation_id
     WHERE g.company_id = $1`,
    [req.user!.company_id]
  );
  return res.json(result.rows[0] || null);
});

router.put('/sms-gateway', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  if (!user.roles?.includes('owner') && !user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden' });
  }
  const deviceId = String(req.body.device_id || '');
  const device = await runWithTenantContext(
    user.company_id,
    `SELECT id FROM device_activations
     WHERE id = $1 AND company_id = $2 AND status = 'active' AND LOWER(COALESCE(platform, '')) = 'android'`,
    [deviceId, user.company_id]
  );
  if (device.rows.length === 0) {
    return res.status(400).json({ error: 'invalid_android_device', message: 'Aktif bir Android cihaz seçin.' });
  }
  await runWithTenantContext(
    user.company_id,
    `INSERT INTO company_sms_gateways (company_id, device_activation_id, selected_by)
     VALUES ($1, $2, $3)
     ON CONFLICT (company_id) DO UPDATE SET
       device_activation_id = EXCLUDED.device_activation_id,
       selected_by = EXCLUDED.selected_by,
       selected_at = NOW(), last_poll_at = NULL`,
    [user.company_id, deviceId, user.id]
  );
  return res.json({ success: true, device_id: deviceId });
});

router.post('/sms-gateway/poll', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const deviceId = String(req.body.device_id || '');
  const limit = Math.min(Math.max(Number(req.body.limit || 20), 1), 50);
  try {
    const result = await notificationRepository.pollSmsGateway(user.company_id, deviceId, limit);
    if (!result.success) {
      return res.status(403).json({ error: result.error });
    }
    return res.json({ messages: result.messages || [] });
  } catch (err) {
    logger.error('SMS gateway poll failed', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/sms-gateway/messages/:id/result', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const deviceId = String(req.body.device_id || '');
  const status = String(req.body.status || '');
  if (!['sending', 'sent', 'failed'].includes(status)) {
    return res.status(400).json({ error: 'invalid_status' });
  }
  try {
    const result = await runWithTenantContext(
      user.company_id,
      `UPDATE notification_queue q SET status = $1::varchar, error_message = $2::text,
         delivered_at = CASE WHEN $1::varchar = 'sent' THEN NOW() ELSE delivered_at END,
         gateway_updated_at = NOW()
       WHERE q.id = $3::varchar AND q.company_id = $4::varchar AND q.channel = 'sms'
         AND EXISTS (
           SELECT 1 FROM company_sms_gateways g
           JOIN device_activations d ON d.id = g.device_activation_id
           WHERE g.company_id = $4::varchar
             AND d.device_hash = $5::varchar
             AND q.gateway_device_id = g.device_activation_id
         )
       RETURNING q.id, q.status`,
      [status, req.body.error_message || null, req.params.id, user.company_id, deviceId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'message_not_found' });
    return res.json(result.rows[0]);
  } catch (err) {
    logger.error('SMS gateway result update failed', {
      error: err instanceof Error ? err.message : String(err),
      message_id: req.params.id,
      company_id: user.company_id,
    });
    return res.status(500).json({ error: 'server_error' });
  }
});


/**
 * @openapi
 * /api/v1/notifications/queue:
 *   get:
 *     summary: Get message queue delivery history
 */
router.get('/queue', requireSmsHistoryAccess, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const history = await runWithTenantContext(
      user.company_id,
      `SELECT id, channel, recipient, title, body, status, retry_count, error_message,
              provider_message_id,provider_status,provider_error_code,delivered_at,created_at
       FROM notification_queue WHERE company_id = $1 ORDER BY created_at DESC LIMIT 100`,
      [user.company_id]
    );
    return res.json(history.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/notifications/credits:
 *   get:
 *     summary: Retrieve remaining messaging credits
 */
router.get('/credits', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const creditsRes = await runWithTenantContext(
      user.company_id,
      'SELECT sms_credits, whatsapp_credits, email_credits FROM company_notification_credits WHERE company_id = $1', [user.company_id]
    );

    if (creditsRes.rows.length === 0) {
      // Seed credits
      await runBypassingRLS(
        'INSERT INTO company_notification_credits (company_id) VALUES ($1)',
        [user.company_id]
      );
      return res.json({ sms_credits: 100, whatsapp_credits: 50, email_credits: 1000 });
    }

    return res.json(creditsRes.rows[0]);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/notifications/templates:
 *   post:
 *     summary: Create or update notification template
 */
router.post('/templates', requirePermission('notifications.templates.manage'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { name, channel, title, body } = req.body;

  if (!name || !channel || !body) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  try {
    const id = `tpl-${Date.now()}`;
    await runWithTenantContext(
      user.company_id,
      `INSERT INTO notification_templates (id, company_id, name, channel, title, body)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (company_id, name) DO UPDATE SET
         channel = EXCLUDED.channel,
         title = EXCLUDED.title,
         body = EXCLUDED.body,
         updated_at = NOW()`,
      [id, user.company_id, name, channel, title || null, body]
    );

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/notifications/templates:
 *   get:
 *     summary: List templates
 */
router.get('/templates', requirePermission('notifications.templates.manage'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id, 'SELECT * FROM notification_templates ORDER BY name ASC');
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/notifications/campaign:
 *   post:
 *     summary: Trigger targeted marketing campaigns (segmentation)
 */
router.post('/campaign', enforceCampaignAbuseLimit, requirePermission('notifications.campaign.send'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { segment, channel, template_name } = req.body;

  if (!segment || !channel || !template_name) {
    return res.status(400).json({ error: 'missing_fields', message: 'Segment, kanal ve şablon seçimi zorunludur.' });
  }

  try {
    // 1. Fetch template body
    const templateRes = await runWithTenantContext(
      user.company_id,
      'SELECT body, title FROM notification_templates WHERE name = $1 AND channel = $2',
      [template_name, channel]
    );

    if (templateRes.rows.length === 0) {
      return res.status(404).json({ error: 'template_not_found', message: 'Şablon bulunamadı.' });
    }

    const { body: templateBody, title: templateTitle } = templateRes.rows[0];

    // 2. Fetch segment recipients based on RLS constraints
    let recipientsRes: any;
    if (segment === 'all_customers') {
      recipientsRes = await runWithTenantContext(
        user.company_id,
        'SELECT name, phone, email FROM customers WHERE is_deleted = FALSE'
      );
    } else if (segment === 'debtors') {
      recipientsRes = await runWithTenantContext(
        user.company_id,
        'SELECT name, phone, email FROM customers WHERE balance > 0 AND is_deleted = FALSE'
      );
    } else if (segment === 'inactive_30d') {
      // Fetch customers who haven't made a transaction/sale in the last 30 days
      recipientsRes = await runWithTenantContext(
        user.company_id,
        `SELECT c.name, c.phone, c.email FROM customers c
         LEFT JOIN sales s ON s.customer_id = c.id AND s.created_at >= NOW() - INTERVAL '30 days'
         WHERE s.id IS NULL AND c.is_deleted = FALSE`
      );
    } else {
      return res.status(400).json({ error: 'invalid_segment', message: 'Geçersiz alıcı grubu seçimi.' });
    }

    const recipients = recipientsRes.rows;
    if (recipients.length === 0) {
      return res.json({ success: true, queued_count: 0, message: 'Seçilen grupta uygun alıcı bulunamadı.' });
    }

    const queuedCount = await notificationRepository.enqueueCampaignRecipients({
      companyId: user.company_id,
      userId: user.id,
      channel,
      recipients,
      templateTitle,
      templateBody,
    });

    return res.json({ success: true, queued_count: queuedCount, message: `${queuedCount} adet kampanya mesajı başarıyla kuyruğa eklendi.` });
  } catch (err) {
    logger.error('Campaign trigger failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/admin/notifications/stats:
 *   get:
 *     summary: Admin global notification delivery metrics
 *     security:
 *       - BearerAuth: []
 */
router.get('/admin/stats', requireRole('sysadmin'), async (req, res: Response) => {
  try {
    const stats = await runBypassingRLS(`
      SELECT 
        status, 
        COUNT(*) as count 
      FROM notification_queue
      GROUP BY status
    `);

    const result: Record<string, number> = { queued: 0, sent: 0, failed: 0, retrying: 0, sending: 0 };
    for (const row of stats.rows) {
      result[row.status] = parseInt(row.count, 10);
    }

    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
