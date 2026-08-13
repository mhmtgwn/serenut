import crypto from 'crypto';
import { Router, Request, Response, NextFunction } from 'express';
import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';
import {
  authenticateUser,
  AuthenticatedRequest,
  requireActiveEntitlementForMutations,
} from '../../middleware/auth.middleware';
import {
  createMessageTemplate,
  decryptAccessToken,
  encryptAccessToken,
  exchangeEmbeddedSignupCode,
  getEmbeddedSignupConfig,
  listMessageTemplates,
  parseTemplatePayload,
  STANDARD_WHATSAPP_TEMPLATES,
  subscribeWaba,
  unsubscribeWaba,
  verifyPhoneBelongsToWaba,
  verifyWebhookSignature,
  WhatsAppProviderError,
} from './whatsapp.service';
import { isNotificationChannelEnabled } from '../notification/notification_channels';

const router = Router();

function stateHash(state: string): string {
  return crypto.createHash('sha256').update(state, 'utf8').digest('hex');
}

async function runWithTenantContext(companyId: string, sql: string, params: unknown[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
    const result = await client.query(sql, params);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function runBypassingRls(sql: string, params: unknown[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const result = await client.query(sql, params);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

function requireWhatsAppManager(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const roles = req.user?.roles || [];
  const permissions = req.user?.permissions || [];
  if (roles.includes('owner') || roles.includes('sysadmin') || permissions.includes('notifications.channels.manage')) {
    return next();
  }
  return res.status(403).json({
    error: 'forbidden',
    message: 'WhatsApp bağlantısını yalnızca firma sahibi veya yetkili yönetici değiştirebilir.',
  });
}

function providerErrorResponse(res: Response, error: unknown) {
  if (error instanceof WhatsAppProviderError) {
    return res.status(error.httpStatus).json({ error: error.code, message: error.message });
  }
  const dbError = error as { code?: string };
  if (dbError?.code === '23505') {
    return res.status(409).json({
      error: 'whatsapp_number_already_connected',
      message: 'Bu WhatsApp numarası başka bir Serenut firmasına bağlı.',
    });
  }
  logger.error('WhatsApp operation failed', { error: error instanceof Error ? error.message : String(error) });
  return res.status(500).json({ error: 'server_error', message: 'WhatsApp işlemi tamamlanamadı.' });
}

async function syncStandardTemplates(companyId: string, wabaId: string, accessToken: string, createMissing: boolean) {
  let remote = await listMessageTemplates(accessToken, wabaId);
  if (createMissing) {
    const remoteNames = new Set(remote.map((item) => `${item.name}:${item.language}`));
    for (const definition of STANDARD_WHATSAPP_TEMPLATES) {
      if (remoteNames.has(`${definition.name}:tr`)) continue;
      try {
        await createMessageTemplate(accessToken, wabaId, definition);
      } catch (error) {
        logger.warn('Standard WhatsApp template could not be created', {
          companyId,
          template: definition.name,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    remote = await listMessageTemplates(accessToken, wabaId);
  }

  for (const definition of STANDARD_WHATSAPP_TEMPLATES) {
    const template = remote.find((item) => item.name === definition.name && item.language === 'tr');
    await runWithTenantContext(
      companyId,
      `INSERT INTO company_whatsapp_templates
         (id,company_id,event_key,meta_template_name,language_code,category,status,rejection_reason,last_synced_at)
       VALUES($1,$2,$3,$4,'tr',$5,$6,$7,NOW())
       ON CONFLICT(company_id,event_key) DO UPDATE SET
         meta_template_name=EXCLUDED.meta_template_name,language_code=EXCLUDED.language_code,
         category=EXCLUDED.category,status=EXCLUDED.status,rejection_reason=EXCLUDED.rejection_reason,
         last_synced_at=NOW(),updated_at=NOW()`,
      [
        `wa-tpl-${companyId}-${definition.eventKey}`,
        companyId,
        definition.eventKey,
        definition.name,
        template?.category || 'UTILITY',
        String(template?.status || 'pending').toLowerCase(),
        template?.rejected_reason || null,
      ],
    );
  }
}

// Meta webhook verification is intentionally public and must be declared before auth.
router.get('/webhook', (req: Request, res: Response) => {
  const mode = String(req.query['hub.mode'] || '');
  const token = String(req.query['hub.verify_token'] || '');
  const challenge = String(req.query['hub.challenge'] || '');
  const expected = process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN || '';
  if (mode === 'subscribe' && expected && token.length === expected.length &&
      crypto.timingSafeEqual(Buffer.from(token), Buffer.from(expected))) {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

router.post('/webhook', async (req: Request & { rawBody?: Buffer }, res: Response) => {
  const signature = req.header('x-hub-signature-256') || undefined;
  if (!verifyWebhookSignature(req.rawBody, signature)) {
    logger.warn('Rejected WhatsApp webhook with invalid signature', { ip: req.ip });
    return res.sendStatus(401);
  }

  // Acknowledge valid Meta deliveries after the durable database update. Meta retries
  // non-2xx responses, while provider_message_id makes repeated deliveries idempotent.
  try {
    const entries = Array.isArray(req.body?.entry) ? req.body.entry : [];
    for (const entry of entries) {
      const changes = Array.isArray(entry?.changes) ? entry.changes : [];
      for (const change of changes) {
        const statuses = Array.isArray(change?.value?.statuses) ? change.value.statuses : [];
        for (const status of statuses) {
          const providerMessageId = String(status?.id || '');
          const providerStatus = String(status?.status || '');
          if (!providerMessageId || !['sent', 'delivered', 'read', 'failed'].includes(providerStatus)) continue;
          const errorCode = status?.errors?.[0]?.code ? String(status.errors[0].code) : null;
          const errorMessage = status?.errors?.[0]?.title || status?.errors?.[0]?.message || null;
          await runBypassingRls(
            `UPDATE notification_queue
             SET provider_status=$1,
                 provider_error_code=$2,
                 error_message=CASE WHEN $1='failed' THEN $3 ELSE error_message END,
                 status=CASE WHEN $1='failed' THEN 'failed' WHEN $1 IN ('sent','delivered','read') THEN 'sent' ELSE status END,
                 delivered_at=CASE WHEN $1 IN ('delivered','read') THEN COALESCE(delivered_at,NOW()) ELSE delivered_at END,
                 updated_at=NOW()
             WHERE provider_message_id=$4 AND channel='whatsapp'`,
            [providerStatus, errorCode, errorMessage, providerMessageId],
          );
        }
        if (change?.field === 'message_template_status_update') {
          const value = change.value || {};
          const templateName = String(value.message_template_name || value.name || '');
          const templateStatus = String(value.event || value.status || '').toLowerCase();
          if (templateName && ['approved', 'rejected', 'pending', 'paused', 'disabled'].includes(templateStatus)) {
            await runBypassingRls(
              `UPDATE company_whatsapp_templates t
               SET status=$1,rejection_reason=$2,last_synced_at=NOW(),updated_at=NOW()
               FROM company_whatsapp_connections c
               WHERE c.company_id=t.company_id AND c.waba_id=$3 AND t.meta_template_name=$4`,
              [templateStatus, value.reason || null, String(entry?.id || ''), templateName],
            );
          }
        }
      }
    }
    return res.sendStatus(200);
  } catch (error) {
    logger.error('WhatsApp webhook persistence failed', { error: error instanceof Error ? error.message : String(error) });
    return res.sendStatus(500);
  }
});

router.use(authenticateUser);
router.use(requireActiveEntitlementForMutations);

router.get('/connection', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runWithTenantContext(
      req.user!.company_id,
      `SELECT company_id,waba_id,phone_number_id,display_phone_number,business_display_name,
              status,connected_at,last_verified_at,last_error_code,last_error_message,updated_at
       FROM company_whatsapp_connections WHERE company_id=$1`,
      [req.user!.company_id],
    );
    const configured = Boolean(
      process.env.META_APP_ID && process.env.META_APP_SECRET &&
      process.env.WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID &&
      process.env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY &&
      process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN,
    );
    return res.json({ configured, connection: result.rows[0] || null });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.post('/onboarding/start', requireWhatsAppManager, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const config = getEmbeddedSignupConfig();
    const state = crypto.randomBytes(32).toString('base64url');
    await runWithTenantContext(
      req.user!.company_id,
      `INSERT INTO whatsapp_onboarding_sessions(state_hash,company_id,created_by_user_id,expires_at)
       VALUES($1,$2,$3,NOW()+INTERVAL '10 minutes')`,
      [stateHash(state), req.user!.company_id, req.user!.id],
    );
    return res.status(201).json({ ...config, state });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.get('/templates', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runWithTenantContext(
      req.user!.company_id,
      `SELECT event_key,meta_template_name,language_code,category,status,rejection_reason,last_synced_at
       FROM company_whatsapp_templates WHERE company_id=$1 ORDER BY event_key`,
      [req.user!.company_id],
    );
    return res.json(result.rows);
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.post('/templates/sync', requireWhatsAppManager, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const connection = await runWithTenantContext(
      req.user!.company_id,
      `SELECT waba_id,encrypted_access_token,status FROM company_whatsapp_connections WHERE company_id=$1`,
      [req.user!.company_id],
    );
    const row = connection.rows[0];
    if (!row || row.status !== 'active') {
      return res.status(409).json({ error: 'whatsapp_connection_not_active', message: 'Aktif WhatsApp bağlantısı bulunamadı.' });
    }
    await syncStandardTemplates(req.user!.company_id, row.waba_id, decryptAccessToken(row.encrypted_access_token), true);
    return res.json({ success: true });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.post('/events', async (req: AuthenticatedRequest, res: Response) => {
  const eventKey = String(req.body?.event_key || '');
  const recipient = String(req.body?.recipient || '');
  const clientEventId = String(req.body?.client_event_id || '');
  const parameters = Array.isArray(req.body?.parameters) ? req.body.parameters.map((item: unknown) => String(item)) : [];
  const fallbackBody = String(req.body?.fallback_body || '').slice(0, 4096);
  const knownEvent = STANDARD_WHATSAPP_TEMPLATES.some((definition) => definition.eventKey === eventKey);
  if (!knownEvent || !recipient || !clientEventId || clientEventId.length > 100) {
    return res.status(400).json({ error: 'invalid_whatsapp_event', message: 'WhatsApp bildirim olayı geçersiz.' });
  }
  if (!isNotificationChannelEnabled('whatsapp')) {
    return res.status(202).json({ queued: false, reason: 'channel_disabled' });
  }
  try {
    const template = await runWithTenantContext(
      req.user!.company_id,
      `SELECT t.meta_template_name,t.language_code,t.status,c.status AS connection_status
       FROM company_whatsapp_templates t
       JOIN company_whatsapp_connections c ON c.company_id=t.company_id
       WHERE t.company_id=$1 AND t.event_key=$2`,
      [req.user!.company_id, eventKey],
    );
    const row = template.rows[0];
    if (!row || row.connection_status !== 'active' || row.status !== 'approved') {
      return res.status(202).json({ queued: false, reason: !row ? 'not_configured' : row.status });
    }
    const payload = parseTemplatePayload({
      template_name: row.meta_template_name,
      language_code: row.language_code,
      parameters,
    });
    const id = `notif-wa-${crypto.randomUUID()}`;
    const inserted = await runWithTenantContext(
      req.user!.company_id,
      `INSERT INTO notification_queue
         (id,company_id,channel,recipient,body,status,scheduled_at,provider_payload,client_message_id,created_by_user_id)
       VALUES($1,$2,'whatsapp',$3,$4,'pending',NOW(),$5::jsonb,$6,$7)
       ON CONFLICT(company_id,client_message_id) WHERE client_message_id IS NOT NULL DO NOTHING
       RETURNING id`,
      [id, req.user!.company_id, recipient, fallbackBody || eventKey, JSON.stringify(payload), clientEventId, req.user!.id],
    );
    return res.status(202).json({ queued: inserted.rows.length > 0, duplicate: inserted.rows.length === 0, queue_id: inserted.rows[0]?.id || null });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.post('/onboarding/complete', requireWhatsAppManager, async (req: AuthenticatedRequest, res: Response) => {
  const state = String(req.body?.state || '');
  const code = String(req.body?.code || '');
  const wabaId = String(req.body?.waba_id || '');
  const phoneNumberId = String(req.body?.phone_number_id || '');
  const metaBusinessId = req.body?.meta_business_id ? String(req.body.meta_business_id) : null;
  if (!state || !code || !/^\d+$/.test(wabaId) || !/^\d+$/.test(phoneNumberId)) {
    return res.status(400).json({ error: 'invalid_onboarding_result', message: 'Meta bağlantı sonucu eksik veya geçersiz.' });
  }

  try {
    const consumed = await runWithTenantContext(
      req.user!.company_id,
      `UPDATE whatsapp_onboarding_sessions SET consumed_at=NOW()
       WHERE state_hash=$1 AND company_id=$2 AND created_by_user_id=$3
         AND consumed_at IS NULL AND expires_at>NOW()
       RETURNING state_hash`,
      [stateHash(state), req.user!.company_id, req.user!.id],
    );
    if (consumed.rows.length === 0) {
      return res.status(409).json({ error: 'onboarding_session_invalid', message: 'Bağlantı oturumu kullanılmış veya süresi dolmuş.' });
    }

    const accessToken = await exchangeEmbeddedSignupCode(code);
    const phone = await verifyPhoneBelongsToWaba(accessToken, wabaId, phoneNumberId);
    await subscribeWaba(accessToken, wabaId);
    const encryptedToken = encryptAccessToken(accessToken);

    await runWithTenantContext(
      req.user!.company_id,
      `INSERT INTO company_whatsapp_connections
         (company_id,meta_business_id,waba_id,phone_number_id,display_phone_number,business_display_name,
          encrypted_access_token,status,connected_by_user_id,connected_at,last_verified_at,updated_at)
       VALUES($1,$2,$3,$4,$5,$6,$7,'active',$8,NOW(),NOW(),NOW())
       ON CONFLICT(company_id) DO UPDATE SET
         meta_business_id=EXCLUDED.meta_business_id,waba_id=EXCLUDED.waba_id,
         phone_number_id=EXCLUDED.phone_number_id,display_phone_number=EXCLUDED.display_phone_number,
         business_display_name=EXCLUDED.business_display_name,encrypted_access_token=EXCLUDED.encrypted_access_token,
         status='active',connected_by_user_id=EXCLUDED.connected_by_user_id,connected_at=NOW(),
         last_verified_at=NOW(),disconnected_at=NULL,last_error_code=NULL,last_error_message=NULL,updated_at=NOW()`,
      [
        req.user!.company_id, metaBusinessId, wabaId, phoneNumberId,
        phone.displayPhoneNumber, phone.verifiedName, encryptedToken, req.user!.id,
      ],
    );
    try {
      await syncStandardTemplates(req.user!.company_id, wabaId, accessToken, true);
    } catch (templateError) {
      logger.warn('WhatsApp connected but template provisioning is pending', {
        companyId: req.user!.company_id,
        error: templateError instanceof Error ? templateError.message : String(templateError),
      });
    }
    return res.json({
      success: true,
      connection: {
        waba_id: wabaId,
        phone_number_id: phoneNumberId,
        display_phone_number: phone.displayPhoneNumber,
        business_display_name: phone.verifiedName,
        status: 'active',
      },
    });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.delete('/connection', requireWhatsAppManager, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const current = await runWithTenantContext(
      req.user!.company_id,
      `SELECT waba_id,encrypted_access_token,status FROM company_whatsapp_connections WHERE company_id=$1`,
      [req.user!.company_id],
    );
    const connection = current.rows[0];
    if (connection?.status === 'active') {
      try {
        await unsubscribeWaba(decryptAccessToken(connection.encrypted_access_token), connection.waba_id);
      } catch (error) {
        logger.warn('WhatsApp WABA unsubscribe failed during disconnect', {
          companyId: req.user!.company_id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    const tombstone = encryptAccessToken(`disconnected:${crypto.randomBytes(24).toString('hex')}`);
    await runWithTenantContext(
      req.user!.company_id,
      `UPDATE company_whatsapp_connections
       SET status='disconnected',encrypted_access_token=$1,disconnected_at=NOW(),updated_at=NOW()
       WHERE company_id=$2`,
      [tombstone, req.user!.company_id],
    );
    return res.json({ success: true });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

router.post('/test', requireWhatsAppManager, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const payload = parseTemplatePayload(req.body?.provider_payload);
    const recipient = String(req.body?.recipient || '');
    if (!recipient) return res.status(400).json({ error: 'recipient_required', message: 'Test alıcısı zorunludur.' });
    if (!isNotificationChannelEnabled('whatsapp')) {
      return res.status(409).json({ error: 'notification_channel_not_enabled', message: 'WhatsApp kanalı sunucuda etkin değil.' });
    }
    const approved = await runWithTenantContext(
      req.user!.company_id,
      `SELECT 1 FROM company_whatsapp_templates t
       JOIN company_whatsapp_connections c ON c.company_id=t.company_id
       WHERE t.company_id=$1 AND t.meta_template_name=$2 AND t.language_code=$3
         AND t.status='approved' AND c.status='active'`,
      [req.user!.company_id, payload.template_name, payload.language_code],
    );
    if (approved.rows.length === 0) {
      return res.status(409).json({ error: 'whatsapp_template_not_approved', message: 'Seçilen WhatsApp şablonu henüz onaylı değil.' });
    }
    const id = `notif-wa-test-${crypto.randomUUID()}`;
    await runWithTenantContext(
      req.user!.company_id,
      `INSERT INTO notification_queue
         (id,company_id,channel,recipient,body,status,scheduled_at,provider_payload,created_by_user_id)
       VALUES($1,$2,'whatsapp',$3,$4,'pending',NOW(),$5::jsonb,$6)`,
      [id, req.user!.company_id, recipient, `WhatsApp test: ${payload.template_name}`, JSON.stringify(payload), req.user!.id],
    );
    return res.status(201).json({ success: true, queue_id: id });
  } catch (error) {
    return providerErrorResponse(res, error);
  }
});

export default router;
