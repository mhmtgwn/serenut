import axios from 'axios';
import { logger } from '../src/config/logger';

const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL || '';
const SLACK_WEBHOOK_URL = process.env.SLACK_WEBHOOK_URL || '';

export interface AlertPayload {
  title: string;
  severity: 'SEV-1' | 'SEV-2' | 'SEV-3' | 'SEV-4';
  message: string;
  details?: any;
}

/**
 * Dispatches a system alert to Discord/Slack webhooks.
 * Features rate limiting to prevent webhook spamming.
 */
const alertCache = new Map<string, number>();
const SPAM_COOLDOWN_MS = 60000; // 1 minute per alert type

export async function sendSystemAlert(alert: AlertPayload) {
  const cacheKey = `${alert.severity}:${alert.title}`;
  const now = Date.now();
  if (alertCache.has(cacheKey) && (now - alertCache.get(cacheKey)!) < SPAM_COOLDOWN_MS) {
    logger.info(`Alert throttled to prevent spam: ${alert.title}`);
    return;
  }
  alertCache.set(cacheKey, now);

  const colors = {
    'SEV-1': 15158332, // Red
    'SEV-2': 15105570, // Orange
    'SEV-3': 10181046, // Purple
    'SEV-4': 3447003,  // Blue
  };

  const discordPayload = {
    embeds: [{
      title: `🚨 ${alert.severity} Incident Alert: ${alert.title}`,
      description: alert.message,
      color: colors[alert.severity],
      fields: [
        { name: 'Severity', value: alert.severity, inline: true },
        { name: 'Timestamp', value: new Date().toISOString(), inline: true },
        { name: 'Details', value: alert.details ? JSON.stringify(alert.details, null, 2).substring(0, 1000) : 'None' }
      ]
    }]
  };

  // Dispatch to Discord
  if (DISCORD_WEBHOOK_URL) {
    try {
      await axios.post(DISCORD_WEBHOOK_URL, discordPayload);
    } catch (err: any) {
      logger.error('Failed to send alert to Discord Webhook', { error: err.message });
    }
  }

  // Dispatch to Slack
  if (SLACK_WEBHOOK_URL) {
    try {
      const slackPayload = {
        text: `*🚨 ${alert.severity} Alert: ${alert.title}*\n>${alert.message}\n*Details:* \`\`\`${JSON.stringify(alert.details || {})}\`\`\``
      };
      await axios.post(SLACK_WEBHOOK_URL, slackPayload);
    } catch (err: any) {
      logger.error('Failed to send alert to Slack Webhook', { error: err.message });
    }
  }

  logger.warn(`ALERT DISPATCHED: [${alert.severity}] ${alert.title}`);
}
