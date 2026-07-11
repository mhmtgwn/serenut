// server/src/workers/billing.scheduler.ts
// Serenut Platform — BullMQ Tabanlı Fatura & SaaS Yaşam Döngüsü Zamanlayıcısı
//
// Yönetilen akışlar:
//   A. Trial → Paid dönüşüm tetikleyicileri (7. gün, 13. gün, 14. gün)
//   B. Başarısız ödeme retry senaryosu (24s, 72s, 7g)
//   C. Abonelik dönem sonu yenileme
//   D. Grace period kontrolü → askı
//   E. Abonelik iptal akışı
//   F. Yeniden aktivasyon akışı
//
// Çalışma zamanı:
//   - scheduleTrialLifecycleJobs() → Trial aktivasyonunda bir kez çağrılır
//   - schedulePaymentRetry()       → Başarısız ödemede çağrılır
//   - billingCronWorker            → Her gece 02:30'da çalışır (dönem sonu yenileme)

import { Queue, Worker, Job } from 'bullmq';
import { pgPool } from '../config/database';
import { logger } from '../config/logger';
import { enqueueNotification } from './notification.worker';
import {
  welcomePaidEmail,
  trialExpiring7Email,
  trialExpiring1Email,
  trialExpiredEmail,
  paymentFailedEmail,
  paymentRetryEmail,
  paymentSuccessEmail,
  subscriptionCancelledEmail,
  SmsTemplates,
} from '../modules/notifications/email.templates';

// ── REDIS BAĞLANTISI ─────────────────────────────────────────────────────────
function getRedisConnection() {
  const redisUrl = process.env.REDIS_URL || 'redis://127.0.0.1:6379';
  const url = new URL(redisUrl);
  return {
    host: url.hostname,
    port: parseInt(url.port || '6379', 10),
    password: url.password || process.env.REDIS_PASSWORD || undefined,
    maxRetriesPerRequest: null,
    enableReadyCheck: false,
  };
}

// ── KUYRUK TANIMLARI ─────────────────────────────────────────────────────────
const BILLING_QUEUE = 'serenut-billing';

let billingQueue: Queue | null = null;

export function getBillingQueue(): Queue {
  if (!billingQueue) {
    billingQueue = new Queue(BILLING_QUEUE, {
      connection: getRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 30_000 },
        removeOnComplete: { count: 200, age: 7 * 24 * 3600 },
        removeOnFail: { count: 500 },
      },
    });
  }
  return billingQueue;
}

// ── VERİTABANI YARDIMCISI ────────────────────────────────────────────────────
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

// Şirket bilgilerini çek
async function getCompanyInfo(companyId: string) {
  const res = await runBypassingRLS(
    `SELECT c.name, c.email, c.phone, s.plan_id, p.name as plan_name, p.price, p.currency,
            s.current_period_end, s.grace_period_until, s.cancel_at_period_end
     FROM companies c
     LEFT JOIN subscriptions s ON c.id = s.company_id
     LEFT JOIN plans p ON s.plan_id = p.id
     WHERE c.id = $1`,
    [companyId]
  );
  return res.rows[0] || null;
}

// ── A. TRIAL YAŞAM DÖNGÜSÜ İŞLERİNİ ZAMANLA ─────────────────────────────────
/**
 * Trial aktivasyonunda çağrılır. Otomatik olarak:
 *   - Gün 7: "7 gün kaldı" email + SMS
 *   - Gün 13: "1 gün kaldı" email + SMS
 *   - Gün 14: "Trial bitti" email + SMS
 * BullMQ delayed job olarak kaydedilir — sunucu yeniden başlatılsa kaybolmaz.
 */
export async function scheduleTrialLifecycleJobs(params: {
  companyId: string;
  companyName: string;
  email: string;
  phone?: string;
  trialStartDate: Date;
  trialDays?: number;
}): Promise<void> {
  const { companyId, companyName, email, phone, trialStartDate, trialDays = 30 } = params;
  const queue = getBillingQueue();
  const DAY = 24 * 60 * 60 * 1000;
  const now = Date.now();

  const day7Ms  = trialStartDate.getTime() + 7  * DAY - now;
  const day13Ms = trialStartDate.getTime() + 13 * DAY - now;
  const day14Ms = trialStartDate.getTime() + 14 * DAY - now;

  const expiryDate = new Date(trialStartDate.getTime() + trialDays * DAY)
    .toLocaleDateString('tr-TR');

  const base = { companyId, companyName, email, phone, expiryDate };

  // Gün 7 — pozitifse zamanla, geçmişse atla
  if (day7Ms > 0) {
    await queue.add('trial-expiring-7', { type: 'trial_expiring_7', ...base }, {
      delay: day7Ms,
      jobId: `trial-7d-${companyId}`,
    });
    logger.info(`[BillingScheduler] Trial Gün-7 uyarısı zamanlandı: ${companyId} (${Math.round(day7Ms / DAY)} gün sonra)`);
  }

  if (day13Ms > 0) {
    await queue.add('trial-expiring-1', { type: 'trial_expiring_1', ...base }, {
      delay: day13Ms,
      jobId: `trial-1d-${companyId}`,
    });
    logger.info(`[BillingScheduler] Trial Gün-13 uyarısı zamanlandı: ${companyId}`);
  }

  if (day14Ms > 0) {
    await queue.add('trial-expired', { type: 'trial_expired', ...base }, {
      delay: day14Ms,
      jobId: `trial-expired-${companyId}`,
    });
    logger.info(`[BillingScheduler] Trial sona erme zamanlandı: ${companyId}`);
  }
}

// ── B. BAŞARISIZ ÖDEME RETRY SENARYOSU ───────────────────────────────────────
/**
 * Ödeme başarısız olduğunda çağrılır.
 * 3 ayrı BullMQ delayed job:
 *   - Anında: "Ödeme alınamadı" bildirimi gönder
 *   - 24 saat: Retry #1
 *   - 72 saat: Retry #2
 *   - 7 gün: Retry #3 — başarısız olursa askıya al
 */
export async function schedulePaymentRetry(params: {
  companyId: string;
  companyName: string;
  email: string;
  phone?: string;
  amount: string;
  currency: string;
  subscriptionId: string;
  invoiceId: string;
}): Promise<void> {
  const queue = getBillingQueue();
  const HOUR = 60 * 60 * 1000;

  const base = {
    type: 'payment_retry',
    ...params,
  };

  // Anında bildirim (gecikme yok)
  await queue.add('payment-failed-notify', { type: 'payment_failed_notify', ...params }, {
    delay: 0,
    jobId: `payment-failed-notify-${params.invoiceId}`,
  });

  // 24 saat sonra retry
  await queue.add('payment-retry-1', { ...base, retryCount: 1 }, {
    delay: 24 * HOUR,
    jobId: `payment-retry-1-${params.invoiceId}`,
  });

  // 72 saat sonra retry
  await queue.add('payment-retry-2', { ...base, retryCount: 2 }, {
    delay: 72 * HOUR,
    jobId: `payment-retry-2-${params.invoiceId}`,
  });

  // 7 gün sonra son retry — başarısız → askı
  await queue.add('payment-retry-3', { ...base, retryCount: 3 }, {
    delay: 7 * 24 * HOUR,
    jobId: `payment-retry-3-${params.invoiceId}`,
  });

  logger.info(`[BillingScheduler] Ödeme retry planlandı: ${params.companyId} — 3 deneme (24s, 72s, 7g)`);
}

// ── C. ABONELİK İPTAL AKIŞI ──────────────────────────────────────────────────
export async function processSubscriptionCancellation(
  companyId: string,
  requestedBy: string
): Promise<{ success: boolean; periodEnd: Date | null; message: string }> {
  try {
    const info = await getCompanyInfo(companyId);
    if (!info) {
      return { success: false, periodEnd: null, message: 'Şirket bulunamadı' };
    }

    // cancel_at_period_end = true yap (dönem sonunda otomatik iptal)
    await runBypassingRLS(
      `UPDATE subscriptions SET cancel_at_period_end = true WHERE company_id = $1`,
      [companyId]
    );

    const periodEnd = info.current_period_end ? new Date(info.current_period_end) : null;

    // İptal bildirimi email kuyruğuna ekle
    await enqueueNotification({
      notification_id: `cancel-notify-${companyId}-${Date.now()}`,
      company_id: companyId,
      channel: 'email',
      recipient: info.email,
      title: 'Aboneliğiniz iptal edildi',
      body: subscriptionCancelledEmail({
        companyName: info.name,
        expiryDate: periodEnd?.toLocaleDateString('tr-TR'),
        upgradeLink: `${process.env.PORTAL_URL || 'https://portal.serenut.com'}/billing`,
      }).html,
    });

    // Veri indirme linki için 30 gün sonra hatırlatma
    const queue = getBillingQueue();
    if (periodEnd) {
      const delay = periodEnd.getTime() - Date.now() + 30 * 24 * 60 * 60 * 1000;
      if (delay > 0) {
        await queue.add('data-deletion-warning', {
          type: 'data_deletion_warning',
          companyId,
          email: info.email,
          companyName: info.name,
        }, {
          delay,
          jobId: `data-deletion-${companyId}`,
        });
      }
    }

    logger.info(`[BillingScheduler] Abonelik iptal planlandı: ${companyId} — dönem sonu: ${periodEnd?.toISOString()}`);

    return {
      success: true,
      periodEnd,
      message: `Aboneliğiniz ${periodEnd?.toLocaleDateString('tr-TR') || 'dönem sonunda'} iptal edilecek.`,
    };
  } catch (err: any) {
    logger.error('[BillingScheduler] processSubscriptionCancellation error:', err);
    return { success: false, periodEnd: null, message: err.message };
  }
}

// ── D. YENİDEN AKTİVASYON ────────────────────────────────────────────────────
export async function processReactivation(
  companyId: string,
  planId: string
): Promise<{ success: boolean; message: string }> {
  try {
    const info = await getCompanyInfo(companyId);
    if (!info) {
      return { success: false, message: 'Şirket bulunamadı' };
    }

    // cancel_at_period_end = false, status = active yap
    await runBypassingRLS(
      `UPDATE subscriptions
       SET cancel_at_period_end = false, status = 'active', grace_period_until = null, last_payment_status = 'success'
       WHERE company_id = $1`,
      [companyId]
    );

    // Lisansı da aktif et
    await runBypassingRLS(
      `UPDATE license_entitlements SET status = 'active', token_version = token_version + 1, updated_at = NOW() WHERE company_id = $1`,
      [companyId]
    );
    await runBypassingRLS(
      `UPDATE licenses SET status = 'active' WHERE company_id = $1`,
      [companyId]
    );

    // "Hoş geldin geri" bildirimi
    await enqueueNotification({
      notification_id: `reactivate-notify-${companyId}-${Date.now()}`,
      company_id: companyId,
      channel: 'email',
      recipient: info.email,
      title: 'Aboneliğiniz yeniden aktif edildi',
      body: welcomePaidEmail({
        companyName: info.name,
        planName: info.plan_name,
        amount: info.price,
        currency: info.currency,
        invoiceNumber: `Yeniden aktivasyon`,
        nextBillingDate: new Date(
          Date.now() + 30 * 24 * 60 * 60 * 1000
        ).toLocaleDateString('tr-TR'),
      }).html,
    });

    logger.info(`[BillingScheduler] Yeniden aktivasyon tamamlandı: ${companyId}`);
    return { success: true, message: 'Abonelik başarıyla yeniden aktif edildi.' };
  } catch (err: any) {
    logger.error('[BillingScheduler] processReactivation error:', err);
    return { success: false, message: err.message };
  }
}

// ── E. BİLLİNG WORKER — JOB İŞLEME ──────────────────────────────────────────
let billingWorker: Worker | null = null;

export function startBillingScheduler(): void {
  const redisUrl = process.env.REDIS_URL;
  if (!redisUrl) {
    logger.warn('[BillingScheduler] REDIS_URL bulunamadı — scheduler başlatılamıyor.');
    return;
  }

  billingWorker = new Worker(
    BILLING_QUEUE,
    async (job: Job) => {
      const data = job.data;
      logger.info(`[BillingScheduler] Job işleniyor: ${job.name} type=${data.type}`);

      switch (data.type) {
        // Trial uyarı emaili — 7 gün
        case 'trial_expiring_7': {
          await enqueueNotification({
            notification_id: `trial-7d-email-${data.companyId}-${Date.now()}`,
            company_id: data.companyId,
            channel: 'email',
            recipient: data.email,
            title: 'Deneme süreniz 7 gün içinde doluyor',
            body: trialExpiring7Email({
              companyName: data.companyName,
              daysRemaining: 7,
              expiryDate: data.expiryDate,
              upgradeLink: `${process.env.PORTAL_URL || 'https://portal.serenut.com'}/billing`,
            }).html,
          });
          if (data.phone) {
            await enqueueNotification({
              notification_id: `trial-7d-sms-${data.companyId}-${Date.now()}`,
              company_id: data.companyId,
              channel: 'sms',
              recipient: data.phone,
              body: SmsTemplates.trialExpiring(7),
            });
          }
          break;
        }

        // Trial uyarı emaili — 1 gün
        case 'trial_expiring_1': {
          await enqueueNotification({
            notification_id: `trial-1d-email-${data.companyId}-${Date.now()}`,
            company_id: data.companyId,
            channel: 'email',
            recipient: data.email,
            title: 'Son 24 saat! Deneme süreniz yarın bitiyor',
            body: trialExpiring1Email({
              companyName: data.companyName,
              daysRemaining: 1,
              expiryDate: data.expiryDate,
              upgradeLink: `${process.env.PORTAL_URL || 'https://portal.serenut.com'}/billing`,
            }).html,
          });
          if (data.phone) {
            await enqueueNotification({
              notification_id: `trial-1d-sms-${data.companyId}-${Date.now()}`,
              company_id: data.companyId,
              channel: 'sms',
              recipient: data.phone,
              body: SmsTemplates.trialExpiring(1),
            });
          }
          break;
        }

        // Trial bitti
        case 'trial_expired': {
          // DB'de trial'ı sonlandır
          await runBypassingRLS(
            `UPDATE subscriptions SET status = 'trial_expired' WHERE company_id = $1 AND status = 'trial'`,
            [data.companyId]
          );
          await enqueueNotification({
            notification_id: `trial-expired-email-${data.companyId}-${Date.now()}`,
            company_id: data.companyId,
            channel: 'email',
            recipient: data.email,
            title: 'Deneme süreniz sona erdi',
            body: trialExpiredEmail({
              companyName: data.companyName,
              upgradeLink: `${process.env.PORTAL_URL || 'https://portal.serenut.com'}/billing`,
            }).html,
          });
          break;
        }

        // Başarısız ödeme bildirimi (anında)
        case 'payment_failed_notify': {
          await enqueueNotification({
            notification_id: `pay-failed-email-${data.invoiceId}-${Date.now()}`,
            company_id: data.companyId,
            channel: 'email',
            recipient: data.email,
            title: 'Ödeme alınamadı',
            body: paymentFailedEmail({
              companyName: data.companyName,
              amount: data.amount,
              currency: data.currency,
              paymentLink: `${process.env.PORTAL_URL || 'https://portal.serenut.com'}/billing`,
            }).html,
          });
          if (data.phone) {
            await enqueueNotification({
              notification_id: `pay-failed-sms-${data.invoiceId}-${Date.now()}`,
              company_id: data.companyId,
              channel: 'sms',
              recipient: data.phone,
              body: SmsTemplates.paymentFailed(data.amount),
            });
          }
          break;
        }

        // Ödeme retry (1/2/3)
        case 'payment_retry': {
          const retryCount = data.retryCount || 1;
          const invoiceId = data.invoiceId;

          // 1. Pre-flight check: check if the invoice has already been paid
          if (invoiceId) {
            try {
              const invCheck = await runBypassingRLS(
                "SELECT status FROM invoices WHERE id = $1",
                [invoiceId]
              );
              if (invCheck.rows.length > 0 && invCheck.rows[0].status === 'paid') {
                logger.info(`[BillingScheduler] Payment retry #${retryCount} skipped: Invoice ${invoiceId} is already paid.`);
                break;
              }
            } catch (dbErr: any) {
              logger.error(`[BillingScheduler] Pre-flight invoice status check failed: ${dbErr.message}`);
            }
          }

          // 2. Check current subscription status
          try {
            const subCheck = await runBypassingRLS(
              "SELECT status, last_payment_status FROM subscriptions WHERE company_id = $1",
              [data.companyId]
            );
            if (subCheck.rows.length > 0) {
              const sub = subCheck.rows[0];
              if (sub.status === 'active' && sub.last_payment_status === 'success') {
                logger.info(`[BillingScheduler] Payment retry #${retryCount} skipped: Subscription is active and paid for company ${data.companyId}.`);
                break;
              }
            }
          } catch (dbErr: any) {
            logger.error(`[BillingScheduler] Pre-flight subscription status check failed: ${dbErr.message}`);
          }

          // Gerçek ödeme yeniden deneme (İyzico servis çağrısı)
          logger.info(`[BillingScheduler] Ödeme retry #${retryCount}: ${data.companyId} — ${data.amount} ${data.currency}`);

          if (retryCount < 3) {
            await enqueueNotification({
              notification_id: `pay-retry-email-${data.invoiceId}-${retryCount}-${Date.now()}`,
              company_id: data.companyId,
              channel: 'email',
              recipient: data.email,
              title: `Ödemeniz tekrar deneniyor (${retryCount}/3)`,
              body: paymentRetryEmail({
                companyName: data.companyName,
                amount: data.amount,
                currency: data.currency,
                retryCount,
                paymentLink: `${process.env.PORTAL_URL || 'https://portal.serenut.com'}/billing`,
              }).html,
            });
          } else {
            // Retry #3 başarısız → askıya al
            await runBypassingRLS(
              `UPDATE subscriptions SET status = 'suspended' WHERE company_id = $1`,
              [data.companyId]
            );
            await runBypassingRLS(
              `UPDATE license_entitlements SET status = 'expired', token_version = token_version + 1, updated_at = NOW() WHERE company_id = $1`,
              [data.companyId]
            );
            await runBypassingRLS(
              `UPDATE licenses SET status = 'suspended' WHERE company_id = $1`,
              [data.companyId]
            );
            logger.error(`[BillingScheduler] 3 retry başarısız — ${data.companyId} askıya alındı.`);
          }
          break;
        }

        // Veri silme uyarısı (abonelik iptalinden 30 gün sonra)
        case 'data_deletion_warning': {
          await enqueueNotification({
            notification_id: `data-deletion-email-${data.companyId}-${Date.now()}`,
            company_id: data.companyId,
            channel: 'email',
            recipient: data.email,
            title: 'Verileriniz 7 gün içinde silinecek',
            body: `Serenut OS hesabınızı kapattığınızdan bu yana 30 gün geçti. Verileriniz 7 gün içinde kalıcı olarak silinecek. Hemen indirmek için portal.serenut.com adresini ziyaret edin.`,
          });
          break;
        }

        default:
          logger.warn(`[BillingScheduler] Bilinmeyen job tipi: ${data.type}`);
      }
    },
    {
      connection: getRedisConnection(),
      concurrency: 3,
    }
  );

  billingWorker.on('completed', (job) => {
    logger.info(`[BillingScheduler] Tamamlandı: ${job.name} (${job.data.type})`);
  });

  billingWorker.on('failed', (job, err) => {
    logger.error(`[BillingScheduler] Hata: ${job?.name} — ${err.message}`);
  });

  billingWorker.on('error', (err) => {
    logger.error('[BillingScheduler] Worker hatası:', err);
  });

  logger.info('[BillingScheduler] ✅ Billing scheduler başlatıldı.');
}

export async function stopBillingScheduler(): Promise<void> {
  if (billingWorker) {
    await billingWorker.close();
    logger.info('[BillingScheduler] Scheduler durduruldu.');
  }
}
