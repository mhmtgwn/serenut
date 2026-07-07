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

import { Queue, Worker, Job, QueueEvents } from 'bullmq';
import { pgPool, redisClient } from '../config/database';
import { logger } from '../config/logger';

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
  max_retries?: number;
}

// ── GATEWAY DISPATCH ─────────────────────────────────────────────────────────
async function dispatchGateway(data: NotificationJobData): Promise<boolean> {
  const { channel, recipient, title, body } = data;

  switch (channel) {
    case 'sms':
      return dispatchSms(recipient, body);
    case 'email':
      return dispatchEmail(recipient, title || 'Serenut OS', body);
    case 'whatsapp':
      return dispatchWhatsApp(recipient, body);
    case 'push':
      return dispatchPush(recipient, title, body);
    default:
      throw new Error(`Bilinmeyen kanal: ${channel}`);
  }
}

async function dispatchSms(to: string, body: string): Promise<boolean> {
  const isMock = !process.env.SMS_API_KEY || process.env.SMS_API_KEY.startsWith('YOUR_') || process.env.SMS_API_KEY === 'mock';
  if (isMock) {
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
  const isMock = !process.env.SMTP_API_KEY || process.env.SMTP_API_KEY.startsWith('YOUR_') || process.env.SMTP_API_KEY === 'mock';
  if (isMock) {
    logger.info(`[EMAIL][MOCK] Sending to ${to}: "${subject}"`);
    await new Promise((resolve) => setTimeout(resolve, 100));
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

async function dispatchWhatsApp(to: string, body: string): Promise<boolean> {
  // TODO Sprint 2: WhatsApp Business API entegrasyonu
  logger.info(`[WHATSAPP] → ${to}: "${body.substring(0, 40)}..."`);
  await new Promise((resolve) => setTimeout(resolve, 100));
  return true;
}

async function dispatchPush(deviceToken: string, title?: string, body?: string): Promise<boolean> {
  // TODO Sprint 2: FCM/APNs entegrasyonu
  logger.info(`[PUSH] → ${deviceToken}: "${title}"`);
  await new Promise((resolve) => setTimeout(resolve, 50));
  return true;
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
    `UPDATE notification_queue
     SET status = 'sent', delivered_at = NOW(), error_message = NULL
     WHERE id = $1`,
    [notificationId]
  );
  await deductCredits(companyId, channel);
}

async function markFailed(notificationId: string, errorMsg: string) {
  await runBypassingRLS(
    `UPDATE notification_queue
     SET status = 'failed', error_message = $1
     WHERE id = $2`,
    [errorMsg, notificationId]
  );
}

async function deductCredits(companyId: string, channel: string) {
  if (channel === 'push') return;
  const creditCol =
    channel === 'whatsapp' ? 'whatsapp_credits' :
    channel === 'email' ? 'email_credits' :
    'sms_credits';

  await runBypassingRLS(
    `INSERT INTO company_notification_credits (company_id)
     VALUES ($1)
     ON CONFLICT (company_id) DO UPDATE
       SET ${creditCol} = GREATEST(company_notification_credits.${creditCol} - 1, 0)`,
    [companyId]
  );

  // Invalidate Redis cache
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
        await markFailed(data.notification_id, `Max retries exceeded: ${err.message}`);
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
}

// ── YARDIMCI: Kuyruğa Bildirim Ekle ─────────────────────────────────────────
export async function enqueueNotification(data: NotificationJobData, delayMs = 0): Promise<void> {
  const queue = getNotificationQueue();

  await queue.add('send-notification', data, {
    delay: delayMs,
    jobId: `notif-${data.notification_id}`, // Aynı bildirimin çift işlenmesini önler
  });

  logger.info(
    `[NotificationWorker] Kuyruğa eklendi: channel=${data.channel} to=${data.recipient} delay=${delayMs}ms`
  );
}

// ── GRACEFUL SHUTDOWN ─────────────────────────────────────────────────────────
export async function stopNotificationWorker(): Promise<void> {
  if (workerInstance) {
    await workerInstance.close();
    logger.info('[NotificationWorker] Worker durduruldu.');
  }
}
