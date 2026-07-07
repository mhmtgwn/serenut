import { pgPool } from '../config/database';
import { logger } from '../config/logger';

export type AlertLevel = 'info' | 'warn' | 'error' | 'fatal';

export class AlertingSystem {
  /**
   * Dispatch a system-wide alert.
   * Logs to logger, creates database incident (system_incidents) and triggers external channel alerts.
   */
  public static async triggerAlert(
    level: AlertLevel,
    title: string,
    description: string,
    companyId: string | null = null,
    details: any = null
  ): Promise<void> {
    const incidentId = `inc-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    
    // Map level to DB severity
    let severity = 'SEV-4'; // Low
    if (level === 'fatal') severity = 'SEV-1';
    else if (level === 'error') severity = 'SEV-2';
    else if (level === 'warn') severity = 'SEV-3';

    // Log internally
    const logMsg = `[ALERT] [${severity}] ${title}: ${description}`;
    if (level === 'fatal' || level === 'error') {
      logger.error(logMsg, { details });
    } else if (level === 'warn') {
      logger.warn(logMsg, { details });
    } else {
      logger.info(logMsg, { details });
    }

    // 1. Record incident in system_incidents DB table
    try {
      const client = await pgPool.connect();
      try {
        await client.query('BEGIN');
        // RLS Bypass helper inline
        await client.query("SET LOCAL app.bypass_rls = 'true'");
        await client.query(`
          INSERT INTO system_incidents (id, company_id, severity, title, description, status)
          VALUES ($1, $2, $3, $4, $5, 'open')
        `, [
          incidentId,
          companyId,
          severity,
          title,
          `${description}${details ? '\nDetails: ' + JSON.stringify(details) : ''}`
        ]);
        await client.query('COMMIT');
      } catch (dbErr: any) {
        await client.query('ROLLBACK');
        logger.error(`Failed to write system incident to DB: ${dbErr.message}`);
      } finally {
        client.release();
      }
    } catch (err: any) {
      logger.error(`Database connection failed on alert trigger: ${err.message}`);
    }

    // 2. Simulate dispatch to integrations (Slack, Telegram, SMTP)
    this.dispatchExternalAlert(severity, title, description, details);
  }

  private static dispatchExternalAlert(severity: string, title: string, description: string, details: any) {
    const slackUrl = process.env.SLACK_WEBHOOK_URL;
    const twilioSid = process.env.TWILIO_ACCOUNT_SID;
    const twilioAuthToken = process.env.TWILIO_AUTH_TOKEN;
    const twilioFrom = process.env.TWILIO_FROM_NUMBER;
    const adminPhone = process.env.ADMIN_ALERT_PHONE;

    // Log simulation fallback
    logger.info(`📡 [AlertingSystem] Dispatching external alerts: [${severity}] ${title}`);

    if (slackUrl) {
      fetch(slackUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: `🚨 *[${severity}] ${title}*\n${description}\n${details ? '```' + JSON.stringify(details, null, 2) + '```' : ''}`
        })
      })
      .then((res) => {
        if (!res.ok) logger.error(`[Slack Alert] Webhook returned status: ${res.status}`);
      })
      .catch((err) => logger.error(`[Slack Alert] Failed to send webhook: ${err.message}`));
    }

    if (severity === 'SEV-1' && twilioSid && twilioAuthToken && twilioFrom && adminPhone) {
      const auth = Buffer.from(`${twilioSid}:${twilioAuthToken}`).toString('base64');
      fetch(`https://api.twilio.com/2010-04-01/Accounts/${twilioSid}/Messages.json`, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          From: twilioFrom,
          To: adminPhone,
          Body: `[CRITICAL ALERT] ${title}: ${description.substring(0, 100)}`
        })
      })
      .then((res) => {
        if (!res.ok) logger.error(`[Twilio Alert] API returned status: ${res.status}`);
      })
      .catch((err) => logger.error(`[Twilio Alert] Failed to send SMS: ${err.message}`));
    }
  }
}
