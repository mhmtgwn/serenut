// server/src/modules/notification/notification_worker.ts
// Serenut Platform — Automated Notification Queue Worker (Sprint 9)
// Processes messages, handles mock gateway dispatch, deducts credits, and manages retries.
// Created: 04 Jul 2026

import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';

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

/**
 * Main worker loop.
 * Fetches pending/retryable messages using SKIP LOCKED to avoid concurrency issues.
 */
export async function executeNotificationWorker(): Promise<void> {
  // Fetch up to 10 queue items that are ready for delivery (taking scheduled_at into account)
  const batch = await runBypassingRLS(`
    SELECT * FROM notification_queue
    WHERE (status = 'queued' AND (scheduled_at IS NULL OR scheduled_at <= NOW()))
       OR (status = 'retrying' AND next_retry_at <= NOW())
    ORDER BY created_at ASC
    LIMIT 10
    FOR UPDATE SKIP LOCKED
  `);

  if (batch.rows.length === 0) return;

  logger.info(`[NotificationWorker] Processing ${batch.rows.length} messages...`);

  for (const item of batch.rows) {
    // 1. Lock item by updating status to sending
    await runBypassingRLS(
      "UPDATE notification_queue SET status = 'sending' WHERE id = $1",
      [item.id]
    );

    try {
      // 2. Dispatch to specific channel gateway
      const deliverySuccess = await dispatchGateway(item.channel, item.recipient, item.title, item.body);

      if (deliverySuccess) {
        // Successful transmission
        await runBypassingRLS(`
          UPDATE notification_queue 
          SET status = 'sent', delivered_at = NOW(), error_message = null
          WHERE id = $1
        `, [item.id]);

        // Deduct company credit
        await deductCredits(item.company_id, item.channel);
        logger.info(`[NotificationWorker] Message ${item.id} successfully sent via ${item.channel}`);
      } else {
        throw new Error('Simulated gateway dispatch failure.');
      }

    } catch (err: any) {
      const nextRetryCount = item.retry_count + 1;
      const maxRetries = item.max_retries || 3;

      if (nextRetryCount < maxRetries) {
        // Calculate exponential backoff: next_retry = NOW() + 2^retry_count minutes
        const backoffMinutes = Math.pow(2, nextRetryCount);
        const nextRetryAt = new Date();
        nextRetryAt.setMinutes(nextRetryAt.getMinutes() + backoffMinutes);

        await runBypassingRLS(`
          UPDATE notification_queue 
          SET status = 'retrying', retry_count = $1, next_retry_at = $2, error_message = $3
          WHERE id = $4
        `, [nextRetryCount, nextRetryAt, err.message || 'unknown_gateway_error', item.id]);

        logger.warn(`[NotificationWorker] Message ${item.id} failed. Scheduled retry in ${backoffMinutes}m.`);
      } else {
        // Max retries exceeded, mark as failed permanently
        await runBypassingRLS(`
          UPDATE notification_queue 
          SET status = 'failed', error_message = 'Max retries exceeded'
          WHERE id = $1
        `, [item.id]);

        logger.error(`[NotificationWorker] Message ${item.id} failed permanently (Max retries exceeded)`);
      }
    }
  }
}

// Simulated gateway dispatcher (NettGsm/Sendgrid/Twilio mocks)
async function dispatchGateway(channel: string, recipient: string, title: string | null, body: string): Promise<boolean> {
  // Mock failure: If recipient ends in '9', simulate a gateway error to test retry flow
  if (recipient.endsWith('9')) {
    return false;
  }

  if (channel === 'sms') {
    const isMock = !process.env.SMS_API_KEY || process.env.SMS_API_KEY.startsWith('YOUR_') || process.env.SMS_API_KEY === 'mock';
    if (isMock) {
      logger.info(`[SMS][MOCK] Sending to ${recipient}: "${body.substring(0, 30)}..."`);
      await new Promise((resolve) => setTimeout(resolve, 100));
      return true;
    }

    logger.info(`[SMS] Sending to ${recipient} via Netgsm...`);
    try {
      const response = await fetch('https://api.netgsm.com.tr/sms/send/get/', {
        method: 'POST',
        body: new URLSearchParams({
          usercode: process.env.SMS_API_KEY!,
          password: process.env.SMS_API_SECRET!,
          gsmno: recipient,
          message: body,
          msgheader: process.env.SMS_SENDER_ID!,
        })
      });
      const text = await response.text();
      if (!text.startsWith('00')) {
        throw new Error(`Netgsm error: ${text}`);
      }
      return true;
    } catch (err: any) {
      logger.error(`[SMS] Failed to send SMS to ${recipient}:`, err);
      throw err;
    }
  } else if (channel === 'email') {
    const isMock = !process.env.SMTP_API_KEY || process.env.SMTP_API_KEY.startsWith('YOUR_') || process.env.SMTP_API_KEY === 'mock';
    if (isMock) {
      logger.info(`[EMAIL][MOCK] Sending to ${recipient}: "${title || 'Serenut OS'}"`);
      await new Promise((resolve) => setTimeout(resolve, 100));
      return true;
    }

    logger.info(`[EMAIL] Sending to ${recipient} via Postmark...`);
    try {
      const response = await fetch('https://api.postmarkapp.com/email', {
        method: 'POST',
        headers: {
          'X-Postmark-Server-Token': process.env.SMTP_API_KEY!,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          From: `${process.env.SMTP_FROM_NAME} <${process.env.SMTP_FROM_EMAIL}>`,
          To: recipient,
          Subject: title || 'Serenut OS',
          HtmlBody: body,
          MessageStream: 'outbound'
        })
      });
      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Postmark error: ${response.status} - ${errorText}`);
      }
      return true;
    } catch (err: any) {
      logger.error(`[EMAIL] Failed to send email to ${recipient}:`, err);
      throw err;
    }
  } else {
    logger.info(`[GatewaySim] Dispatched mock [${channel.toUpperCase()}] to [${recipient}]. Content: "${body.substring(0, 30)}..."`);
    return true;
  }
}

// Deduct company credits based on channel (Skip push since notifications are free of credits)
async function deductCredits(companyId: string, channel: string) {
  if (channel === 'push') return;
  
  let creditCol = 'sms_credits';
  if (channel === 'whatsapp') creditCol = 'whatsapp_credits';
  if (channel === 'email') creditCol = 'email_credits';

  await runBypassingRLS(`
    INSERT INTO company_notification_credits (company_id) 
    VALUES ($1)
    ON CONFLICT (company_id) DO UPDATE SET
      ${creditCol} = GREATEST(company_notification_credits.${creditCol} - 1, 0)
  `, [companyId]);
}
