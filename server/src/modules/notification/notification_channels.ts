export type NotificationChannel = 'sms' | 'email' | 'whatsapp' | 'push';

const knownChannels = new Set<NotificationChannel>([
  'sms',
  'email',
  'whatsapp',
  'push',
]);

/**
 * WhatsApp is served only through the Evolution API. Push remains disabled
 * until its provider is configured and deployed.
 */
export function isNotificationChannelEnabled(channel: unknown): channel is NotificationChannel {
  if (typeof channel !== 'string' || !knownChannels.has(channel as NotificationChannel)) {
    return false;
  }
  const enabled = (process.env.NOTIFICATION_ENABLED_CHANNELS || 'sms,email,whatsapp')
    .split(',')
    .map((value) => value.trim().toLowerCase());
  return enabled.includes(channel);
}

export function assertNotificationChannelEnabled(channel: unknown): asserts channel is NotificationChannel {
  if (!isNotificationChannelEnabled(channel)) {
    throw new Error(`notification_channel_not_enabled:${String(channel)}`);
  }
}
