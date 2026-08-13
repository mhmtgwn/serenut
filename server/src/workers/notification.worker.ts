// server/src/workers/notification.worker.ts
// Serenut Platform — BullMQ Tabanlı Bildirim İşçisi
//
// setInterval tabanlı polling'den BullMQ'ya geçiş.
// Özellikler:
//   - Sunucu yeniden başlatılsa bile işler kaybolmaz (Redis kalıcılığı)
//   - Eşzamanlı işlem (concurrency: 5)
//   - Üstel geri çekilme ile otomatik yeniden deneme (max 3)
//   - Ölü Mektup Kuyruğu (DLQ) — kalıcı hatalar ayrı kuyruğa taşınır
//   - Gateway şablonları: email, SMS, WhatsApp, push

import { Queue, Worker, Job } from 'bullmq';
import { pgPool, redisClient } from '../config/database';
import { logger } from '../config/logger';
import nodemailer from 'nodemailer';
import { assertNotificationChannelEnabled } from '../modules/notification/notification_channels';
import {
  decryptAccessToken,
  parseTemplatePayload,
  sendTemplateMessage,
  WhatsAppProviderError,
} from '../modules/whatsapp/whatsapp.service';

// ── REDIS BAĞLANTI AYARLARI ──────────────────────────────────────────────────
// BullMQ kendi ioredis bağlantısını yönetir.
function getRedisConnection() {
  const redisUrl = process.env.REDIS_URL || 'redis://127.0.0.1:6379';
  const url = new URL(redisUrl);

  return {
    host: url.hostname,
    port: parseInt(url.port || '6379', 10),
    password: url.password || url.searchParams.get('password') || process.env.REDIS_PASSWORD || undefined,
    db: 0,
    maxRetriesPerRequest: null, // BullMQ için gerekli
    enableReadyCheck: false,
  };
}

// ── KUYRUK TANIMLARI ─────────────────────────────────────────────────────────
export const NOTIFICATION_QUEUE = 'serenut-notifications';
export const NOTIFICATION_DLQ = 'serenut-notifications-dead';

let notificationQueue: Queue | null = null;
let notificationDLQ: Queue | null = null;

// ── KUYRUK ERİŞİM NOKTASI ────────────────────────────────────────────────────
export function getNotificationQueue(): Queue {
  if (!notificationQueue) {
    notificationQueue = new Queue(NOTIFICATION_QUEUE, {
      connection: getRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: {
          type: 'exponential',
          delay: 60_000, // İlk yeniden deneme: 1 dakika sonra
        },
        removeOnComplete: { count: 100, age: 24 * 3600 }, // 24 saat saklama
        removeOnFail: { count: 500 },
      },
    });
  }
  return notificationQueue;
}

function getDLQ(): Queue {
  if (!notificationDLQ) {
    notificationDLQ = new Queue(NOTIFICATION_DLQ, {
      connection: getRedisConnection(),
    });
  }
  return notificationDLQ;
}

// ── BİLDİRİM GÖNDERİ TİPLERİ ────────────────────────────────────────────────
export interface NotificationJobData {
  notification_id: string; // notification_queue.id (DB)
  company_id: string;
  channel: 'sms' | 'email' | 'whatsapp' | 'push';
  recipient: string;      // Telefon veya email
  title?: string;
  body: string;
  provider_payload?: unknown;
  max_retries?: number;
}

// ── GATEWAY DISPATCH ─────────────────────────────────────────────────────────
async function dispatchGateway(data: NotificationJobData): Promise<boolean> {
  const { channel, recipient, title, body } = data;
  assertNotificationChannelEnabled(channel);

  switch (channel) {
    case 'sms':
      return dispatchSms(recipient, body);
    case 'email':
      return dispatchEmail(recipient, title || 'Serenut OS', body);
    case 'whatsapp':
      return dispatchWhatsApp(data);
    case 'push':
      return dispatchPush(recipient, title, body);
    default:
      throw new Error(`Bilinmeyen kanal: ${channel}`);
  }
}

async function dispatchSms(to: string, body: string): Promise<boolean> {
  const isMock = !process.env.SMS_API_KEY || process.env.SMS_API_KEY.startsWith('YOUR_') || process.env.SMS_API_KEY === 'mock';
  if (isMock) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('SMS API Credentials are not configured in production! Mock SMS is disabled.');
    }
    logger.info(`[SMS][MOCK] Sending to ${to}: "${body.substring(0, 40)}..."`);
    await new Promise((resolve) => setTimeout(resolve, 100));
    return true;
  }

  logger.info(`[SMS] Sending to ${to} via Netgsm...`);
  try {
    const response = await fetch('https://api.netgsm.com.tr/sms/send/get/', {
      method: 'POST',
      body: new URLSearchParams({
        usercode: process.env.SMS_API_KEY!,
        password: process.env.SMS_API_SECRET!,
        gsmno: to,
        message: body,
        msgheader: process.env.SMS_SENDER_ID!,
      })
    });
    const text = await response.text();
    if (!text.startsWith('00')) {
      logger.error(`[SMS] Netgsm returned failure code: ${text}`);
      throw new Error(`Netgsm error: ${text}`);
    }
    logger.info(`[SMS] Netgsm sent successfully: msgId=${text}`);
    return true;
  } catch (err: any) {
    logger.error(`[SMS] Failed to send SMS to ${to}:`, err);
    throw err;
  }
}

async function dispatchEmail(to: string, subject: string, body: string): Promise<boolean> {
  const hasSmtp = Boolean(process.env.SMTP_HOST);
  const hasPostmark = Boolean(process.env.SMTP_API_KEY && !process.env.SMTP_API_KEY.startsWith('YOUR_') && process.env.SMTP_API_KEY !== 'mock');
  const isMock = !hasSmtp && !hasPostmark;
  if (isMock) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('SMTP/Postmark API Key is not configured in production! Mock Email is disabled.');
    }
    logger.info(`[EMAIL][MOCK] Sending to ${to}: "${subject}"`);
    await new Promise((resolve) => setTimeout(resolve, 100));
    return true;
  }

  if (hasSmtp) {
    logger.info(`[EMAIL] Sending to ${to} via SMTP...`);
    const port = Number(process.env.SMTP_PORT || 587);
    const smtpUser = process.env.SMTP_USER;
    const smtpPassword = process.env.SMTP_PASSWORD;
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port,
      secure: process.env.SMTP_SECURE === 'true' || port === 465,
      ignoreTLS: process.env.SMTP_IGNORE_TLS === 'true',
      ...(smtpUser && smtpPassword ? { auth: { user: smtpUser, pass: smtpPassword } } : {}),
      pool: true,
      maxConnections: 3,
      connectionTimeout: 15_000,
      greetingTimeout: 15_000,
      socketTimeout: 30_000
    });
    await transporter.sendMail({
      from: `"${process.env.SMTP_FROM_NAME || 'Serenut'}" <${process.env.SMTP_FROM_EMAIL || 'noreply@serenut.com'}>`,
      to,
      subject,
      html: body
    });
    return true;
  }

  logger.info(`[EMAIL] Sending to ${to} via Postmark...`);
  try {
    const response = await fetch('https://api.postmarkapp.com/email', {
      method: 'POST',
      headers: {
        'X-Postmark-Server-Token': process.env.SMTP_API_KEY!,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        From: `${process.env.SMTP_FROM_NAME} <${process.env.SMTP_FROM_EMAIL}>`,
        To: to,
        Subject: subject,
        HtmlBody: body,
        MessageStream: 'outbound'
      })
    });
    if (!response.ok) {
      const errorText = await response.text();
      logger.error(`[EMAIL] Postmark returned status ${response.status}: ${errorText}`);
      throw new Error(`Postmark error: ${response.status} - ${errorText}`);
    }
    logger.info(`[EMAIL] Email sent successfully via Postmark to ${to}`);
    return true;
  } catch (err: any) {
    logger.error(`[EMAIL] Failed to send email to ${to}:`, err);
    throw err;
  }
}

async function dispatchWhatsApp(data: NotificationJobData): Promise<boolean> {
  const existing = await runBypassingRLS(
    `SELECT provider_message_id FROM notification_queue WHERE id=$1 AND company_id=$2 AND channel='whatsapp'`,
    [data.notification_id, data.company_id],
  );
  if (existing.rows[0]?.provider_message_id) return true;

  const connection = await runBypassingRLS(
    `SELECT phone_number_id,encrypted_access_token,status
     FROM company_whatsapp_connections WHERE company_id=$1`,
    [data.company_id],
  );
  const row = connection.rows[0];
  if (!row || row.status !== 'active') {
    throw new Error('whatsapp_connection_not_active');
  }

  const payload = parseTemplatePayload(data.provider_payload);
  let providerMessageId: string;
  try {
    providerMessageId = await sendTemplateMessage({
      accessToken: decryptAccessToken(row.encrypted_access_token),
      phoneNumberId: row.phone_number_id,
      recipient: data.recipient,
      payload,
    });
  } catch (error) {
    const providerError = error instanceof WhatsAppProviderError ? error : null;
    const requiresAuthorization = providerError?.code === '190' || providerError?.httpStatus === 401;
    await runBypassingRLS(
      `UPDATE company_whatsapp_connections
       SET status=CASE WHEN $1 THEN 'reauthorization_required' ELSE status END,
           last_error_code=$2,last_error_message=$3,updated_at=NOW()
       WHERE company_id=$4`,
      [requiresAuthorization, providerError?.code || 'send_failed', error instanceof Error ? error.message : String(error), data.company_id],
    );
    throw error;
  }
  await runBypassingRLS(
    `WITH message_update AS (
       UPDATE notification_queue
       SET provider_message_id=$1,provider_status='accepted',provider_error_code=NULL,updated_at=NOW()
       WHERE id=$2 AND company_id=$3 AND channel='whatsapp' RETURNING id
     )
     UPDATE company_whatsapp_connections
     SET last_verified_at=NOW(),last_error_code=NULL,last_error_message=NULL,updated_at=NOW()
     WHERE company_id=$3 AND EXISTS(SELECT 1 FROM message_update)`,
    [providerMessageId, data.notification_id, data.company_id],
  );
  return true;
}

async function dispatchPush(deviceToken: string, title?: string, body?: string): Promise<boolean> {
  throw new Error('notification_channel_not_enabled:push');
}

// ── VERİTABANI DURUM GÜNCELLEME ──────────────────────────────────────────────
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

async function markSent(notificationId: string, companyId: string, channel: string) {
  await runBypassingRLS(
    `WITH marked AS (
       UPDATE notification_queue SET status='sent',delivered_at=NOW(),error_message=NULL,updated_at=NOW()
       WHERE id=$1 AND status<>'sent' RETURNING id
     )
     UPDATE notification_credit_reservations SET status='consumed',consumed_at=NOW()
     WHERE notification_id=$1 AND status='reserved' AND EXISTS(SELECT 1 FROM marked)`,
    [notificationId]
  );
  await invalidateCreditCache(companyId, channel);
}

function creditColumn(channel: string) {
  return channel === 'whatsapp' ? 'whatsapp_credits' : channel === 'email' ? 'email_credits' : 'sms_credits';
}

async function invalidateCreditCache(companyId: string, channel: string) {
  if (channel === 'push') return;
  const cacheKey = `notif_credits:${companyId}:${channel}`;
  if (redisClient && redisClient.isOpen) {
    try {
      await redisClient.del(cacheKey);
      logger.info(`[NotificationWorker] Invalidated cache for: ${cacheKey}`);
    } catch (err) {
      logger.error(`[NotificationWorker] Redis delete error for key ${cacheKey}:`, err);
    }
  }
}

// ── WORKER ───────────────────────────────────────────────────────────────────
let workerInstance: Worker | null = null;
let outboxDispatcher: NodeJS.Timeout | null = null;
let outboxDispatchRunning = false;

/**
 * notification_queue is the durable PostgreSQL outbox. Producers commit the
 * business event and this row together; this dispatcher is the only bridge to
 * BullMQ. A deterministic jobId makes retries and multi-instance dispatch safe.
 */
export async function dispatchNotificationOutboxBatch(limit = 100): Promise<number> {
  if (outboxDispatchRunning) return 0;
  outboxDispatchRunning = true;
  try {
    const result = await runBypassingRLS(
      `SELECT id, company_id, channel, recipient, title, body, provider_payload, scheduled_at, max_retries
       FROM notification_queue
       WHERE status IN ('pending', 'queued', 'retrying')
         AND (next_retry_at IS NULL OR next_retry_at <= NOW())
       ORDER BY created_at ASC
       LIMIT $1`,
      [Math.min(Math.max(limit, 1), 500)],
    );
    let dispatched = 0;
    for (const row of result.rows) {
      try {
        if (!await reserveNotificationCredit(row.id, row.company_id, row.channel)) continue;
        const scheduledAt = row.scheduled_at ? new Date(row.scheduled_at).getTime() : Date.now();
        await enqueueBullNotification({
          notification_id: row.id,
          company_id: row.company_id,
          channel: row.channel,
          recipient: row.recipient,
          title: row.title || undefined,
          body: row.body,
          provider_payload: row.provider_payload,
          max_retries: row.max_retries || 3,
        }, Math.max(0, scheduledAt - Date.now()));
        await runBypassingRLS(
          `UPDATE notification_queue SET status = 'enqueued', updated_at = NOW()
           WHERE id = $1 AND status IN ('pending', 'queued', 'retrying')`,
          [row.id],
        );
        dispatched++;
      } catch (error: any) {
        logger.error('[NotificationOutbox] Dispatch failed', {
          notificationId: row.id,
          error: error?.message || 'outbox_dispatch_failed',
        });
      }
    }
    return dispatched;
  } finally {
    outboxDispatchRunning = false;
  }
}

async function markFailed(notificationId: string, companyId: string, channel: string, errorMsg: string) {
  const creditCol = creditColumn(channel);
  await runBypassingRLS(
    channel === 'push'
      ? `UPDATE notification_queue SET status='failed',error_message=$1,updated_at=NOW() WHERE id=$2`
      : `WITH released AS (
           UPDATE notification_credit_reservations SET status='released',released_at=NOW()
           WHERE notification_id=$2 AND status='reserved' RETURNING company_id
         ), restored AS (
           UPDATE company_notification_credits SET ${creditCol}=${creditCol}+1
           WHERE company_id=$3 AND EXISTS(SELECT 1 FROM released)
         )
         UPDATE notification_queue SET status='failed',error_message=$1,updated_at=NOW() WHERE id=$2`,
    channel === 'push' ? [errorMsg, notificationId] : [errorMsg, notificationId, companyId],
  );
  await invalidateCreditCache(companyId, channel);
}

export async function reserveNotificationCredit(notificationId: string, companyId: string, channel: string): Promise<boolean> {
  if (channel === 'push') return true;
  const creditCol = creditColumn(channel);
  const client = await pgPool.connect();
  let allowed = false;
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    await client.query(
      `INSERT INTO company_notification_credits(company_id) VALUES($1) ON CONFLICT(company_id) DO NOTHING`,
      [companyId],
    );
    const locked = await client.query(
      `SELECT id FROM notification_queue WHERE id=$1 AND company_id=$2
       AND status IN ('pending','queued','retrying','enqueued') FOR UPDATE`,
      [notificationId, companyId],
    );
    if (locked.rowCount) {
      const existing = await client.query(
        `SELECT status FROM notification_credit_reservations
         WHERE notification_id=$1 AND status IN ('reserved','consumed')`,
        [notificationId],
      );
      if (existing.rowCount) {
        allowed = true;
      } else {
        const debited = await client.query(
          `UPDATE company_notification_credits SET ${creditCol}=${creditCol}-1
           WHERE company_id=$1 AND ${creditCol}>0 RETURNING company_id`,
          [companyId],
        );
        if (debited.rowCount) {
          await client.query(
            `INSERT INTO notification_credit_reservations(notification_id,company_id,channel) VALUES($1,$2,$3)`,
            [notificationId, companyId, channel],
          );
          allowed = true;
        }
      }
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
  if (!allowed) await markFailed(notificationId, companyId, channel, 'out_of_credits');
  await invalidateCreditCache(companyId, channel);
  return allowed;
}

export function startNotificationWorker(): void {
  const redisUrl = process.env.REDIS_URL;

  if (!redisUrl) {
    logger.warn('[NotificationWorker] REDIS_URL bulunamadı — BullMQ worker başlatılamıyor. Bildirimler çalışmayacak.');
    return;
  }

  workerInstance = new Worker<NotificationJobData>(
    NOTIFICATION_QUEUE,
    async (job: Job<NotificationJobData>) => {
      const data = job.data;
      logger.info(`[NotificationWorker] İşleniyor: job=${job.id} channel=${data.channel} to=${data.recipient}`);

      const success = await dispatchGateway(data);

      if (!success) {
        throw new Error('Gateway gönderim başarısız');
      }

      // DB'de başarı durumunu güncelle
      await markSent(data.notification_id, data.company_id, data.channel);
      
      // Broadcast NotificationCreated event
      try {
        const { RealtimeBroadcastService } = require('../modules/realtime/broadcast.service');
        await RealtimeBroadcastService.publishEvent(data.company_id, 'NotificationCreated', {
          notificationId: data.notification_id,
          channel: data.channel,
          recipient: data.recipient,
          title: data.title,
          body: data.body,
        });
      } catch (wsErr: any) {
        logger.error(`[NotificationWorker] Realtime broadcast error: ${wsErr.message}`);
      }

      logger.info(`[NotificationWorker] Başarılı: job=${job.id} channel=${data.channel}`);
    },
    {
      connection: getRedisConnection(),
      concurrency: 5,
    }
  );

  // ── WORKER OLAYI DİNLEYİCİLERİ ──────────────────────────────────────────
  workerInstance.on('completed', (job) => {
    logger.info(`[NotificationWorker] Tamamlandı: job=${job.id}`);
  });

  workerInstance.on('failed', async (job, err) => {
    if (!job) return;
    const data = job.data as NotificationJobData;
    const attemptsLeft = (data.max_retries ?? 3) - (job.attemptsMade ?? 0);

    logger.warn(
      `[NotificationWorker] Hata: job=${job.id} channel=${data.channel} ` +
      `attempt=${job.attemptsMade} error=${err.message}`
    );

    if (attemptsLeft <= 0) {
      // Maksimum yeniden deneme aşıldı → Ölü Mektup Kuyruğuna taşı
      try {
        await getDLQ().add('dead-notification', {
          ...data,
          final_error: err.message,
          failed_at: new Date().toISOString(),
          attempts: job.attemptsMade,
        });
        await markFailed(data.notification_id, data.company_id, data.channel, `Max retries exceeded: ${err.message}`);
        logger.error(`[NotificationWorker] DLQ'ya taşındı: job=${job.id}`);
      } catch (dlqErr) {
        logger.error('[NotificationWorker] DLQ yazma hatası:', dlqErr);
      }
    }
  });

  workerInstance.on('error', (err) => {
    logger.error('[NotificationWorker] Worker hatası:', err);
  });

  logger.info('[NotificationWorker] ✅ BullMQ worker başlatıldı (concurrency=5)');

  void dispatchNotificationOutboxBatch();
  outboxDispatcher = setInterval(() => {
    void dispatchNotificationOutboxBatch();
  }, 5_000);
  outboxDispatcher.unref();
}

// ── YARDIMCI: Kuyruğa Bildirim Ekle ─────────────────────────────────────────
async function enqueueBullNotification(data: NotificationJobData, delayMs = 0): Promise<void> {
  const queue = getNotificationQueue();

  await queue.add('send-notification', data, {
    delay: delayMs,
    jobId: `notif-${data.notification_id}`, // Aynı bildirimin çift işlenmesini önler
  });

  logger.info(
    `[NotificationWorker] Kuyruğa eklendi: channel=${data.channel} to=${data.recipient} delay=${delayMs}ms`
  );
}

/**
 * The only producer entry point. It persists a durable outbox row; only the
 * dispatcher may talk to BullMQ, after atomically reserving channel credit.
 */
export async function enqueueNotification(data: NotificationJobData, delayMs = 0): Promise<void> {
  const scheduledAt = new Date(Date.now() + Math.max(0, delayMs));
  await runBypassingRLS(
    `INSERT INTO notification_queue
       (id,company_id,channel,recipient,title,body,provider_payload,status,scheduled_at,max_retries,updated_at)
     VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,'pending',$8,$9,NOW())
     ON CONFLICT(id) DO NOTHING`,
    [data.notification_id,data.company_id,data.channel,data.recipient,data.title || null,
      data.body,data.provider_payload ? JSON.stringify(data.provider_payload) : null,
      scheduledAt,data.max_retries || 3],
  );
}

// ── GRACEFUL SHUTDOWN ─────────────────────────────────────────────────────────
export async function stopNotificationWorker(): Promise<void> {
  if (outboxDispatcher) {
    clearInterval(outboxDispatcher);
    outboxDispatcher = null;
  }
  if (workerInstance) {
    await workerInstance.close();
    logger.info('[NotificationWorker] Worker durduruldu.');
  }
}
