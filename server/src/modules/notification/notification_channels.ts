export type NotificationChannel = 'sms' | 'email' | 'whatsapp' | 'push';

const knownChannels = new Set<NotificationChannel>([
  'sms',
  'email',
  'whatsapp',
  'push',
]);

/**
 * A channel is usable only when it is explicitly enabled for this deployment.
 * SMS and email are the production defaults; WhatsApp and push stay disabled
 * until their real providers are configured and deployed.
 */
export function isNotificationChannelEnabled(channel: unknown): channel is NotificationChannel {
  if (typeof channel !== 'string' || !knownChannels.has(channel as NotificationChannel)) {
    return false;
  }
  const enabled = (process.env.NOTIFICATION_ENABLED_CHANNELS || 'sms,email')
    .split(',')
    .map((value) => value.trim().toLowerCase());
  return enabled.includes(channel);
}

export function assertNotificationChannelEnabled(channel: unknown): asserts channel is NotificationChannel {
  if (!isNotificationChannelEnabled(channel)) {
    throw new Error(`notification_channel_not_enabled:${String(channel)}`);
  }
}
