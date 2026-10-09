import crypto from 'crypto';
import { Router, Request, Response, NextFunction } from 'express';
import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';
import {
  authenticateUser,
  AuthenticatedRequest,
  requireActiveEntitlementForMutations,
} from '../../middleware/auth.middleware';
import { isNotificationChannelEnabled } from '../notification/notification_channels';
import { dispatchNotificationOutboxBatch } from '../../workers/notification.worker';
import {
  deleteInstance as evolutionDeleteInstance,
  getConnectionStatus as evolutionGetStatus,
  getQRCode as evolutionGetQR,
  EvolutionApiError,
} from './evolution.service';

const router = Router();

async function runBypassingRls(sql: string, params: any[] = []) {
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

const supportedEvents = new Set([
  'sale_created',
  'discount_applied',
  'debt_created',
  'collection_recorded',
  'order_created',
  'order_preparing',
  'order_ready',
  'order_shipped',
  'order_delivered',
  'order_cancelled',
  'balance_reminder',
]);

// Evolution API callback is authenticated by its API key, not a Serenut JWT.
router.post('/evolution/webhook', async (req: Request, res: Response) => {
  const apiKey = process.env.EVOLUTION_API_KEY;
  const incomingKey = req.headers['apikey'] as string | undefined;
  if (!apiKey || incomingKey !== apiKey) {
    logger.warn('[Evolution] Webhook yetkisiz istek', { ip: req.ip });
    return res.status(401).json({ error: 'unauthorized' });
  }

  const body = req.body as {
    event?: string;
    instance?: string;
    data?: { state?: string; qrcode?: string };
  };
  if (body.event !== 'CONNECTION_UPDATE' || !body.instance) {
    return res.status(200).json({ received: true });
  }

  try {
    const connection = await runBypassingRls(
      "SELECT company_id FROM company_whatsapp_connections WHERE evolution_instance_id=$1 AND gateway_type='evolution'",
      [body.instance],
    );
    const companyId = connection.rows[0]?.company_id;
    if (!companyId) return res.status(200).json({ received: true });

    const state = body.data?.state;
    const dbStatus = state === 'open' ? 'active' : state === 'close' ? 'disconnected' : 'qr_pending';
    const evolutionStatus = state === 'open' ? 'open' : state === 'close' ? 'close' : 'connecting';
    await runBypassingRls(
      `UPDATE company_whatsapp_connections
       SET evolution_status=$2,status=$3,
           disconnected_at=CASE WHEN $3='disconnected' THEN NOW() ELSE disconnected_at END,
           last_verified_at=CASE WHEN $3='active' THEN NOW() ELSE last_verified_at END,
           updated_at=NOW()
       WHERE company_id=$1 AND gateway_type='evolution'`,
      [companyId, evolutionStatus, dbStatus],
    );
  } catch (error) {
    logger.error('[Evolution] Webhook DB güncelleme hatası', { error: String(error) });
  }
  return res.status(200).json({ received: true });
});

router.use(authenticateUser);
router.use(requireActiveEntitlementForMutations);

router.post('/events', async (req: AuthenticatedRequest, res: Response) => {
  const eventKey = String(req.body?.event_key || '');
  const rawRecipient = String(req.body?.recipient || '');
  const clientEventId = String(req.body?.client_event_id || '');
  const fallbackBody = String(req.body?.fallback_body || '').slice(0, 4096);
  if (!supportedEvents.has(eventKey) || !rawRecipient || !clientEventId || clientEventId.length > 100) {
    return res.status(400).json({ error: 'invalid_whatsapp_event', message: 'WhatsApp bildirim olayı geçersiz.' });
  }
  if (!isNotificationChannelEnabled('whatsapp')) {
    return res.status(503).json({ error: 'whatsapp_channel_disabled', message: 'WhatsApp bildirim kanalı etkin değil.' });
  }

  let recipient = rawRecipient.replace(/\D/g, '');
  const defaultCountryCode = (process.env.WHATSAPP_DEFAULT_COUNTRY_CODE || '90').replace(/\D/g, '');
  if (recipient.startsWith('00')) recipient = recipient.slice(2);
  if (recipient.startsWith('0')) recipient = `${defaultCountryCode}${recipient.slice(1)}`;
  if (recipient.length === 10) recipient = `${defaultCountryCode}${recipient}`;
  if (recipient.length < 8 || recipient.length > 15) {
    return res.status(400).json({ error: 'recipient_invalid', message: 'Alıcı telefon numarası geçersiz.' });
  }

  try {
    const connection = await runBypassingRls(
      `SELECT status,evolution_status FROM company_whatsapp_connections
       WHERE company_id=$1 AND gateway_type='evolution'`,
      [req.user!.company_id],
    );
    const row = connection.rows[0];
    if (!row) {
      return res.status(409).json({ error: 'whatsapp_not_configured', message: 'WhatsApp API bağlantısı kurulmamış.' });
    }
    if (row.status !== 'active' || row.evolution_status !== 'open') {
      return res.status(409).json({ error: 'whatsapp_not_connected', message: 'WhatsApp API bağlantısı açık değil.' });
    }

    const id = `notif-wa-${crypto.randomUUID()}`;
    const inserted = await runBypassingRls(
      `INSERT INTO notification_queue
         (id,company_id,channel,recipient,body,status,scheduled_at,provider_payload,client_message_id,created_by_user_id)
       VALUES($1,$2,'whatsapp',$3,$4,'pending',NOW(),NULL,$5,$6)
       ON CONFLICT(company_id,client_message_id) WHERE client_message_id IS NOT NULL DO NOTHING
       RETURNING id`,
      [id, req.user!.company_id, recipient, fallbackBody || eventKey, clientEventId, req.user!.id],
    );
    if (inserted.rows.length > 0) {
      void dispatchNotificationOutboxBatch();
    }
    return res.status(202).json({
      queued: inserted.rows.length > 0,
      duplicate: inserted.rows.length === 0,
      queue_id: inserted.rows[0]?.id || null,
    });
  } catch (error) {
    logger.error('[WhatsApp] Olay kuyruğa eklenemedi', {
      companyId: req.user!.company_id,
      error: error instanceof Error ? error.message : String(error),
    });
    return res.status(500).json({ error: 'whatsapp_queue_failed', message: 'WhatsApp bildirimi kuyruğa eklenemedi.' });
  }
});

// ── EVOLUTION API ROUTE'LARI ──────────────────────────────────────────────────
// QR tabanlı Evolution API bağlantısı.
// Her şirket Evolution API'de kendi instance'ına sahip olur.

/**
 * GET /api/v1/whatsapp/evolution/qr
 * QR kodu döndürür. İlk çağrıda instance otomatik oluşturulur.
 * Flutter'da ~5 sn polling ile kullanılır.
 */
router.get(
  '/evolution/qr',
  requireWhatsAppManager,
  async (req: AuthenticatedRequest, res: Response) => {
    const companyId = req.user!.company_id;
    try {
      // Instance yoksa oluştur, QR al
      const qr = await evolutionGetQR(companyId);

      if (qr.qrcode === 'already_connected') {
        const status = await evolutionGetStatus(companyId);
        await runBypassingRls(
          `INSERT INTO company_whatsapp_connections
             (company_id, gateway_type, evolution_instance_id, evolution_status, status,
              display_phone_number, business_display_name, last_verified_at, updated_at)
           VALUES ($1, 'evolution', $2, 'open', 'active', $3, $4, NOW(), NOW())
           ON CONFLICT (company_id) DO UPDATE
             SET gateway_type='evolution',
                 evolution_instance_id=$2,
                 evolution_status='open',
                 status='active',
                 waba_id=NULL,
                 phone_number_id=NULL,
                 encrypted_access_token=NULL,
                 display_phone_number=COALESCE(EXCLUDED.display_phone_number, company_whatsapp_connections.display_phone_number),
                 business_display_name=COALESCE(EXCLUDED.business_display_name, company_whatsapp_connections.business_display_name),
                 last_verified_at=NOW(),
                 updated_at=NOW()`,
          [companyId, `serenut_${companyId.replace(/[^a-zA-Z0-9]/g, '_')}`, status.phone ?? null, status.name ?? null],
        );

        return res.json({
          already_connected: true,
          status: 'open',
          phone: status.phone,
          name: status.name,
        });
      }

      // DB'ye qr_pending durumu yaz
      await runBypassingRls(
        `INSERT INTO company_whatsapp_connections
           (company_id, gateway_type, evolution_instance_id, evolution_status, status,
            waba_id, phone_number_id, encrypted_access_token)
         VALUES ($1, 'evolution', $2, 'connecting', 'qr_pending', NULL, NULL, NULL)
         ON CONFLICT (company_id) DO UPDATE
           SET gateway_type='evolution',
               evolution_instance_id=$2,
               evolution_status='connecting',
               status='qr_pending',
               waba_id=NULL,
               phone_number_id=NULL,
               encrypted_access_token=NULL,
               updated_at=NOW()`,
        [companyId, `serenut_${companyId.replace(/[^a-zA-Z0-9]/g, '_')}`],
      );

      return res.json({
        qrcode: qr.qrcode,
        expiresInMs: qr.expiresInMs ?? 60000,
      });
    } catch (error) {
      if (error instanceof EvolutionApiError) {
        const httpStatus =
          error.status && error.status >= 200 && error.status < 600
            ? error.status
            : 503;
        return res.status(httpStatus).json({
          error: error.status === 202 ? 'qr_pending' : 'evolution_qr_failed',
          message: error.message,
        });
      }
      logger.error('[Evolution] QR alma hatası', { error: String(error), companyId });
      return res.status(500).json({ error: 'server_error', message: 'QR kodu alınamadı.' });
    }
  },
);

/**
 * GET /api/v1/whatsapp/evolution/status
 * Anlık bağlantı durumu: { status, phone, name }
 * status: 'open' | 'connecting' | 'close'
 */
router.get(
  '/evolution/status',
  async (req: AuthenticatedRequest, res: Response) => {
    const companyId = req.user!.company_id;
    try {
      const status = await evolutionGetStatus(companyId);

      // Bağlantı kuruldu → DB'yi güncelle
      if (status.status === 'open') {
        await runBypassingRls(
          `INSERT INTO company_whatsapp_connections
             (company_id, gateway_type, evolution_instance_id, evolution_status, status,
              display_phone_number, business_display_name, last_verified_at, updated_at)
           VALUES ($1, 'evolution', $2, 'open', 'active', $3, $4, NOW(), NOW())
           ON CONFLICT (company_id) DO UPDATE
             SET gateway_type='evolution',
                 evolution_instance_id=$2,
                 evolution_status='open',
                 status='active',
                 waba_id=NULL,
                 phone_number_id=NULL,
                 encrypted_access_token=NULL,
                 display_phone_number=COALESCE(EXCLUDED.display_phone_number, company_whatsapp_connections.display_phone_number),
                 business_display_name=COALESCE(EXCLUDED.business_display_name, company_whatsapp_connections.business_display_name),
                 last_verified_at=NOW(),
                 updated_at=NOW()`,
          [companyId, `serenut_${companyId.replace(/[^a-zA-Z0-9]/g, '_')}`, status.phone ?? null, status.name ?? null],
        );
      }

      return res.json(status);
    } catch (error) {
      if (error instanceof EvolutionApiError) {
        return res.status(error.status || 503).json({
          error: 'evolution_status_failed',
          message: error.message,
        });
      }
      logger.error('[Evolution] Durum sorgulama hatası', { error: String(error), companyId });
      return res.status(500).json({ error: 'server_error', message: 'Durum alınamadı.' });
    }
  },
);

/**
 * POST /api/v1/whatsapp/evolution/disconnect
 * WhatsApp oturumunu kapatır ve instance'ı siler.
 */
router.post(
  '/evolution/disconnect',
  requireWhatsAppManager,
  async (req: AuthenticatedRequest, res: Response) => {
    const companyId = req.user!.company_id;
    try {
      await evolutionDeleteInstance(companyId);

      await runBypassingRls(
        `UPDATE company_whatsapp_connections
         SET evolution_status='close', status='disconnected',
             disconnected_at=NOW(), updated_at=NOW()
         WHERE company_id=$1 AND gateway_type='evolution'`,
        [companyId],
      );

      logger.info(`[Evolution] Bağlantı kesildi: ${companyId}`);
      return res.json({ success: true });
    } catch (error) {
      if (error instanceof EvolutionApiError) {
        return res.status(error.status || 503).json({
          error: 'evolution_disconnect_failed',
          message: error.message,
        });
      }
      logger.error('[Evolution] Bağlantı kesme hatası', { error: String(error), companyId });
      return res.status(500).json({ error: 'server_error', message: 'Bağlantı kesilemedi.' });
    }
  },
);

/**
 * POST /api/v1/whatsapp/evolution/webhook
 * Evolution API'den gelen durum olayları (CONNECTION_UPDATE, QRCODE_UPDATED vb.)
 * Kimlik doğrulama: apikey header kontrolü.
 */


export default router;
