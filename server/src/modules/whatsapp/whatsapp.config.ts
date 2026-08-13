const REQUIRED_WHATSAPP_ENV = [
  'META_APP_ID',
  'META_APP_SECRET',
  'WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID',
  'WHATSAPP_WEBHOOK_VERIFY_TOKEN',
  'WHATSAPP_CREDENTIAL_ENCRYPTION_KEY',
] as const;

function enabledChannels(env: NodeJS.ProcessEnv): Set<string> {
  return new Set(
    (env.NOTIFICATION_ENABLED_CHANNELS || 'sms,email')
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean),
  );
}

/**
 * WhatsApp stays optional until Meta approval. Once explicitly enabled, every
 * credential must be present so production cannot start in a half-configured
 * state that silently drops customer notifications.
 */
export function validateWhatsAppRuntimeConfig(env: NodeJS.ProcessEnv = process.env): string[] {
  if (!enabledChannels(env).has('whatsapp')) return [];

  const errors: string[] = [];
  for (const name of REQUIRED_WHATSAPP_ENV) {
    if (!env[name]?.trim()) errors.push(`${name} is required when WhatsApp is enabled`);
  }

  if (env.META_APP_ID && !/^\d+$/.test(env.META_APP_ID.trim())) {
    errors.push('META_APP_ID must be numeric');
  }
  if (env.WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID && !/^\d+$/.test(env.WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID.trim())) {
    errors.push('WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID must be numeric');
  }
  if (env.WHATSAPP_WEBHOOK_VERIFY_TOKEN && env.WHATSAPP_WEBHOOK_VERIFY_TOKEN.trim().length < 32) {
    errors.push('WHATSAPP_WEBHOOK_VERIFY_TOKEN must be at least 32 characters');
  }
  if (env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY && env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY.trim().length < 32) {
    errors.push('WHATSAPP_CREDENTIAL_ENCRYPTION_KEY must be at least 32 characters');
  }
  if (env.WHATSAPP_GRAPH_API_VERSION && !/^v\d+\.0$/.test(env.WHATSAPP_GRAPH_API_VERSION.trim())) {
    errors.push('WHATSAPP_GRAPH_API_VERSION must use the vNN.0 format');
  }

  return errors;
}

