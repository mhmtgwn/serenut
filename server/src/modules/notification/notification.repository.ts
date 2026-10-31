// server/src/modules/notification/notification.repository.ts
import { pgPool, redisClient } from '../../config/database';
import { logger } from '../../config/logger';
import { TemplateParserService } from './template_parser.service';
import { dispatchNotificationOutboxBatch } from '../../workers/notification.worker';

export class NotificationRepository {
  async runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
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

  async runBypassingRLS(sql: string, params: any[] = []) {
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

  async hasSufficientCredits(companyId: string, channel: string): Promise<boolean> {
    let creditCol = 'sms_credits';
    if (channel === 'whatsapp') creditCol = 'whatsapp_credits';
    if (channel === 'email') creditCol = 'email_credits';

    const cacheKey = `notif_credits:${companyId}:${channel}`;
    if (redisClient && redisClient.isOpen) {
      try {
        const cached = await redisClient.get(cacheKey);
        if (cached !== null) {
          return parseInt(cached, 10) > 0;
        }
      } catch (err) {
        logger.debug('Redis credit cache check error, falling back to db', { err });
      }
    }

    const client = await pgPool.connect();
    try {
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const res = await client.query(`SELECT ${creditCol} AS credits FROM company_notification_credits WHERE company_id = $1`, [companyId]);
      if (res.rows.length === 0) return true;
      const count = Number(res.rows[0].credits);
      if (redisClient && redisClient.isOpen) {
        await redisClient.setEx(cacheKey, 60, String(count));
      }
      return count > 0;
    } catch (err) {
      logger.error('Failed to verify notification credits:', err);
      return false;
    } finally {
      client.release();
    }
  }

  async pollSmsGateway(companyId: string, deviceId: string, limit: number): Promise<{ success: boolean; error?: string; messages?: any[] }> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
      const gateway = await client.query(
        `UPDATE company_sms_gateways g SET last_poll_at = NOW()
         FROM device_activations d
         WHERE g.company_id = $1::varchar AND g.device_activation_id = d.id AND d.device_hash = $2::varchar
         RETURNING g.device_activation_id`,
        [companyId, deviceId]
      );
      if (gateway.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'not_primary_sms_gateway' };
      }
      await client.query(
        `UPDATE notification_queue
         SET status = 'retrying', error_message = 'sms_gateway_interrupted',
             retry_count = retry_count + 1, gateway_updated_at = NOW()
         WHERE company_id = $1 AND channel = 'sms'
           AND status IN ('delivered_to_device', 'sending')
           AND gateway_updated_at < NOW() - INTERVAL '5 minutes'`,
        [companyId]
      );
      await client.query(
        `UPDATE notification_queue SET status = 'failed', error_message = 'sms_gateway_timeout', gateway_updated_at = NOW()
            WHERE company_id = $1::varchar AND channel = 'sms' AND status IN ('queued','pending','retrying')
           AND created_at < NOW() - INTERVAL '24 hours'`,
        [companyId]
      );
      const gatewayActivationId = gateway.rows[0].device_activation_id;
      const jobs = await client.query(
        `WITH selected AS (
           SELECT id FROM notification_queue
           WHERE company_id = $1 AND channel = 'sms' AND status IN ('queued','pending','retrying')
             AND COALESCE(scheduled_at, created_at) <= NOW()
             AND created_at >= NOW() - INTERVAL '24 hours'
            ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT $3::integer
         )
         UPDATE notification_queue q
          SET status = 'delivered_to_device', gateway_device_id = $2::varchar,
             gateway_claimed_at = NOW(), gateway_updated_at = NOW()
         FROM selected WHERE q.id = selected.id
         RETURNING q.id, q.recipient, q.body, q.client_message_id, q.created_at`,
        [companyId, gatewayActivationId, limit]
      );
      await client.query('COMMIT');
      return { success: true, messages: jobs.rows };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async enqueueCampaignRecipients(params: {
    companyId: string;
    userId: string;
    channel: string;
    recipients: any[];
    templateTitle?: string;
    templateBody: string;
  }): Promise<number> {
    const { companyId, userId, channel, recipients, templateTitle, templateBody } = params;
    const client = await pgPool.connect();
    let queuedCount = 0;

    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      for (const rec of recipients) {
        const hasCredit = await this.hasSufficientCredits(companyId, channel);
        const creditCol = channel === 'sms' ? 'sms_credits' : channel === 'whatsapp' ? 'whatsapp_credits' : 'email_credits';
        const remRes = await client.query(`SELECT ${creditCol} AS rem FROM company_notification_credits WHERE company_id = $1`, [companyId]);
        const remCredits = remRes.rows.length > 0 ? Number(remRes.rows[0].rem || 0) : 100;
        if (!hasCredit || queuedCount >= remCredits) {
          logger.warn(`Campaign aborted midway for company ${companyId} due to out of credits.`);
          break;
        }

        const recipientAddr = channel === 'email' ? rec.email : rec.phone;
        if (!recipientAddr) continue;

        const resolvedBody = TemplateParserService.parse(templateBody, {
          customer: rec.name,
          store: 'Serenut OS'
        });

        const id = `notif-camp-${Date.now()}-${Math.floor(Math.random()*10000)}`;

        await client.query(`
          INSERT INTO notification_queue (id, company_id, channel, recipient, title, body, created_by_user_id)
          VALUES ($1, $2, $3, $4, $5, $6, $7)
        `, [id, companyId, channel, recipientAddr, templateTitle || null, resolvedBody, userId]);

        queuedCount++;
      }

      await client.query('COMMIT');
      dispatchNotificationOutboxBatch().catch(() => {});
      return queuedCount;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
}

export const notificationRepository = new NotificationRepository();
