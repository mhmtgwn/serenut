import crypto from 'crypto';

const DEFAULT_GRAPH_VERSION = 'v23.0';
const REQUEST_TIMEOUT_MS = 15_000;

export interface WhatsAppTemplatePayload {
  template_name: string;
  language_code: string;
  parameters: string[];
}

export interface VerifiedWhatsAppNumber {
  phoneNumberId: string;
  displayPhoneNumber: string | null;
  verifiedName: string | null;
}

export interface MetaMessageTemplate {
  id?: string;
  name: string;
  language: string;
  status: string;
  category?: string;
  rejected_reason?: string;
}

export const STANDARD_WHATSAPP_TEMPLATES = [
  { eventKey: 'sale_created', name: 'serenut_satis_bildirimi', text: 'Merhaba {{1}}, {{2}} numaralı satış işleminiz tamamlandı. Toplam tutar: {{3}}. {{4}}', examples: ['Ayşe Yılmaz', 'S-1024', '450,00 TL', 'Örnek İşletme'] },
  { eventKey: 'debt_created', name: 'serenut_borc_bildirimi', text: 'Merhaba {{1}}, {{2}} numaralı işlem sonrası güncel bakiyeniz {{3}}. {{4}}', examples: ['Ayşe Yılmaz', 'S-1024', '150,00 TL', 'Örnek İşletme'] },
  { eventKey: 'collection_recorded', name: 'serenut_tahsilat_bildirimi', text: 'Merhaba {{1}}, {{2}} tutarındaki ödemeniz alınmıştır. Kalan bakiye: {{3}}. {{4}}', examples: ['Ayşe Yılmaz', '100,00 TL', '50,00 TL', 'Örnek İşletme'] },
  { eventKey: 'order_created', name: 'serenut_siparis_alindi', text: 'Merhaba {{1}}, {{2}} numaralı siparişiniz alınmıştır. Toplam tutar: {{3}}. {{4}}', examples: ['Ayşe Yılmaz', 'SP-1024', '450,00 TL', 'Örnek İşletme'] },
  { eventKey: 'order_preparing', name: 'serenut_siparis_hazirlaniyor', text: 'Merhaba {{1}}, {{2}} numaralı siparişiniz hazırlanıyor. {{3}}', examples: ['Ayşe Yılmaz', 'SP-1024', 'Örnek İşletme'] },
  { eventKey: 'order_ready', name: 'serenut_siparis_hazir', text: 'Merhaba {{1}}, {{2}} numaralı siparişiniz hazırdır. {{3}}', examples: ['Ayşe Yılmaz', 'SP-1024', 'Örnek İşletme'] },
  { eventKey: 'order_delivered', name: 'serenut_siparis_teslim', text: 'Merhaba {{1}}, {{2}} numaralı siparişiniz teslim edilmiştir. {{3}}', examples: ['Ayşe Yılmaz', 'SP-1024', 'Örnek İşletme'] },
  { eventKey: 'order_cancelled', name: 'serenut_siparis_iptal', text: 'Merhaba {{1}}, {{2}} numaralı siparişiniz iptal edilmiştir. {{3}}', examples: ['Ayşe Yılmaz', 'SP-1024', 'Örnek İşletme'] },
] as const;

export class WhatsAppProviderError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly httpStatus: number,
    public readonly retryable: boolean,
  ) {
    super(message);
    this.name = 'WhatsAppProviderError';
  }
}

function graphVersion(): string {
  return process.env.WHATSAPP_GRAPH_API_VERSION || DEFAULT_GRAPH_VERSION;
}

function graphUrl(path: string): string {
  return `https://graph.facebook.com/${graphVersion()}/${path.replace(/^\//, '')}`;
}

function requiredConfig(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new WhatsAppProviderError(`${name} yapılandırılmamış.`, 'configuration_missing', 503, false);
  return value;
}

export function getEmbeddedSignupConfig() {
  return {
    appId: requiredConfig('META_APP_ID'),
    configId: requiredConfig('WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID'),
    graphVersion: graphVersion(),
  };
}

function encryptionKey(): Buffer {
  const secret = requiredConfig('WHATSAPP_CREDENTIAL_ENCRYPTION_KEY');
  if (secret.length < 32) {
    throw new WhatsAppProviderError(
      'WHATSAPP_CREDENTIAL_ENCRYPTION_KEY en az 32 karakter olmalıdır.',
      'weak_encryption_key',
      503,
      false,
    );
  }
  return crypto.createHash('sha256').update(secret, 'utf8').digest();
}

export function encryptAccessToken(token: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1.${iv.toString('base64url')}.${tag.toString('base64url')}.${ciphertext.toString('base64url')}`;
}

export function decryptAccessToken(value: string): string {
  const [version, ivValue, tagValue, ciphertextValue] = value.split('.');
  if (version !== 'v1' || !ivValue || !tagValue || !ciphertextValue) {
    throw new WhatsAppProviderError('WhatsApp kimlik bilgisi biçimi geçersiz.', 'credential_invalid', 500, false);
  }
  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(), Buffer.from(ivValue, 'base64url'));
    decipher.setAuthTag(Buffer.from(tagValue, 'base64url'));
    return Buffer.concat([
      decipher.update(Buffer.from(ciphertextValue, 'base64url')),
      decipher.final(),
    ]).toString('utf8');
  } catch (_) {
    throw new WhatsAppProviderError('WhatsApp kimlik bilgisi çözülemedi.', 'credential_decryption_failed', 500, false);
  }
}

async function metaRequest<T>(url: string, init: RequestInit): Promise<T> {
  let response: Response;
  try {
    response = await fetch(url, { ...init, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
  } catch (error) {
    throw new WhatsAppProviderError(
      error instanceof Error ? error.message : 'Meta bağlantısı kurulamadı.',
      'provider_unreachable',
      503,
      true,
    );
  }

  const text = await response.text();
  let payload: any = {};
  try { payload = text ? JSON.parse(text) : {}; } catch (_) { payload = { raw: text }; }

  if (!response.ok) {
    const metaError = payload?.error || {};
    const code = String(metaError.code || metaError.error_subcode || `http_${response.status}`);
    throw new WhatsAppProviderError(
      String(metaError.message || 'Meta WhatsApp isteği başarısız oldu.'),
      code,
      response.status,
      response.status === 429 || response.status >= 500,
    );
  }
  return payload as T;
}

export async function exchangeEmbeddedSignupCode(code: string): Promise<string> {
  const query = new URLSearchParams({
    client_id: requiredConfig('META_APP_ID'),
    client_secret: requiredConfig('META_APP_SECRET'),
    code,
  });
  const result = await metaRequest<{ access_token?: string }>(
    `https://graph.facebook.com/${graphVersion()}/oauth/access_token?${query.toString()}`,
    { method: 'GET' },
  );
  if (!result.access_token) {
    throw new WhatsAppProviderError('Meta erişim belirteci dönmedi.', 'token_exchange_failed', 502, false);
  }
  return result.access_token;
}

export async function verifyPhoneBelongsToWaba(
  accessToken: string,
  wabaId: string,
  phoneNumberId: string,
): Promise<VerifiedWhatsAppNumber> {
  const result = await metaRequest<{ data?: Array<{ id: string; display_phone_number?: string; verified_name?: string }> }>(
    graphUrl(`${encodeURIComponent(wabaId)}/phone_numbers?fields=id,display_phone_number,verified_name`),
    { method: 'GET', headers: { Authorization: `Bearer ${accessToken}` } },
  );
  const phone = result.data?.find((item) => String(item.id) === phoneNumberId);
  if (!phone) {
    throw new WhatsAppProviderError('Seçilen telefon numarası bu WhatsApp Business hesabına ait değil.', 'phone_waba_mismatch', 400, false);
  }
  return {
    phoneNumberId,
    displayPhoneNumber: phone.display_phone_number || null,
    verifiedName: phone.verified_name || null,
  };
}

export async function subscribeWaba(accessToken: string, wabaId: string): Promise<void> {
  await metaRequest<{ success?: boolean }>(
    graphUrl(`${encodeURIComponent(wabaId)}/subscribed_apps`),
    { method: 'POST', headers: { Authorization: `Bearer ${accessToken}` } },
  );
}

export async function unsubscribeWaba(accessToken: string, wabaId: string): Promise<void> {
  await metaRequest<{ success?: boolean }>(
    graphUrl(`${encodeURIComponent(wabaId)}/subscribed_apps`),
    { method: 'DELETE', headers: { Authorization: `Bearer ${accessToken}` } },
  );
}

export async function listMessageTemplates(accessToken: string, wabaId: string): Promise<MetaMessageTemplate[]> {
  const result = await metaRequest<{ data?: MetaMessageTemplate[] }>(
    graphUrl(`${encodeURIComponent(wabaId)}/message_templates?fields=id,name,language,status,category,rejected_reason&limit=100`),
    { method: 'GET', headers: { Authorization: `Bearer ${accessToken}` } },
  );
  return result.data || [];
}

export async function createMessageTemplate(
  accessToken: string,
  wabaId: string,
  definition: typeof STANDARD_WHATSAPP_TEMPLATES[number],
): Promise<void> {
  await metaRequest<{ id?: string; status?: string; category?: string }>(
    graphUrl(`${encodeURIComponent(wabaId)}/message_templates`),
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: definition.name,
        language: 'tr',
        category: 'UTILITY',
        components: [{
          type: 'BODY',
          text: definition.text,
          example: { body_text: [Array.from(definition.examples)] },
        }],
      }),
    },
  );
}

export async function sendTemplateMessage(args: {
  accessToken: string;
  phoneNumberId: string;
  recipient: string;
  payload: WhatsAppTemplatePayload;
}): Promise<string> {
  const bodyParameters = args.payload.parameters.map((text) => ({ type: 'text', text: String(text) }));
  const components = bodyParameters.length > 0
    ? [{ type: 'body', parameters: bodyParameters }]
    : undefined;
  const result = await metaRequest<{ messages?: Array<{ id?: string }> }>(
    graphUrl(`${encodeURIComponent(args.phoneNumberId)}/messages`),
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${args.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: normalizeWhatsAppRecipient(args.recipient),
        type: 'template',
        template: {
          name: args.payload.template_name,
          language: { code: args.payload.language_code },
          ...(components ? { components } : {}),
        },
      }),
    },
  );
  const messageId = result.messages?.[0]?.id;
  if (!messageId) throw new WhatsAppProviderError('Meta mesaj kimliği dönmedi.', 'message_id_missing', 502, true);
  return messageId;
}

export function parseTemplatePayload(value: unknown): WhatsAppTemplatePayload {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new WhatsAppProviderError('WhatsApp şablon verisi zorunludur.', 'template_payload_missing', 400, false);
  }
  const input = value as Record<string, unknown>;
  const templateName = String(input.template_name || '').trim();
  const languageCode = String(input.language_code || 'tr').trim();
  const parameters = Array.isArray(input.parameters) ? input.parameters.map((item) => String(item)) : [];
  if (!/^[a-z0-9_]{1,512}$/.test(templateName)) {
    throw new WhatsAppProviderError('WhatsApp şablon adı geçersiz.', 'template_name_invalid', 400, false);
  }
  if (!/^[a-z]{2,3}(?:_[A-Z]{2})?$/.test(languageCode)) {
    throw new WhatsAppProviderError('WhatsApp şablon dili geçersiz.', 'template_language_invalid', 400, false);
  }
  if (parameters.length > 20 || parameters.some((item) => item.length > 1024)) {
    throw new WhatsAppProviderError('WhatsApp şablon parametreleri sınırı aşıldı.', 'template_parameters_invalid', 400, false);
  }
  return { template_name: templateName, language_code: languageCode, parameters };
}

export function normalizeWhatsAppRecipient(value: string): string {
  let digits = String(value || '').replace(/\D/g, '');
  const defaultCountryCode = (process.env.WHATSAPP_DEFAULT_COUNTRY_CODE || '90').replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = `${defaultCountryCode}${digits.slice(1)}`;
  if (digits.length === 10) digits = `${defaultCountryCode}${digits}`;
  if (digits.length < 8 || digits.length > 15) {
    throw new WhatsAppProviderError('WhatsApp alıcı telefonu geçersiz.', 'recipient_invalid', 400, false);
  }
  return digits;
}

export function verifyWebhookSignature(rawBody: Buffer | undefined, signatureHeader: string | undefined): boolean {
  const secret = process.env.META_APP_SECRET;
  if (!secret || !rawBody || !signatureHeader?.startsWith('sha256=')) return false;
  const expected = `sha256=${crypto.createHmac('sha256', secret).update(rawBody).digest('hex')}`;
  const actualBuffer = Buffer.from(signatureHeader, 'utf8');
  const expectedBuffer = Buffer.from(expected, 'utf8');
  return actualBuffer.length === expectedBuffer.length && crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}
