/** Validate the sole WhatsApp gateway before the backend is deployed. */
export function validateWhatsAppRuntimeConfig(env: NodeJS.ProcessEnv = process.env): string[] {
  const enabled = (env.NOTIFICATION_ENABLED_CHANNELS || 'sms,email,whatsapp')
    .split(',')
    .map((value) => value.trim().toLowerCase());
  if (!enabled.includes('whatsapp')) return [];

  const errors: string[] = [];
  if (!env.EVOLUTION_API_URL?.trim()) {
    errors.push('EVOLUTION_API_URL is required when WhatsApp is enabled');
  }
  if (!env.EVOLUTION_API_KEY?.trim()) {
    errors.push('EVOLUTION_API_KEY is required when WhatsApp is enabled');
  }
  return errors;
}
