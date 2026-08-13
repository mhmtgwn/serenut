import assert from 'assert';
import crypto from 'crypto';
import {
  decryptAccessToken,
  encryptAccessToken,
  normalizeWhatsAppRecipient,
  parseTemplatePayload,
  verifyWebhookSignature,
} from '../modules/whatsapp/whatsapp.service';
import { validateWhatsAppRuntimeConfig } from '../modules/whatsapp/whatsapp.config';

const previousKey = process.env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY;
const previousSecret = process.env.META_APP_SECRET;

try {
  process.env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY = 'test-only-key-with-at-least-thirty-two-characters';
  process.env.META_APP_SECRET = 'test-meta-app-secret';

  const token = 'EA-test-sensitive-token';
  const encrypted = encryptAccessToken(token);
  assert.notStrictEqual(encrypted.includes(token), true, 'ciphertext leaked the access token');
  assert.strictEqual(decryptAccessToken(encrypted), token, 'credential encryption did not round-trip');
  assert.throws(() => decryptAccessToken(`${encrypted}tampered`), /çözülemedi|geçersiz/);

  assert.deepStrictEqual(parseTemplatePayload({
    template_name: 'serenut_siparis_hazir',
    language_code: 'tr',
    parameters: ['Ayşe', 'SP-10', 'Örnek İşletme'],
  }), {
    template_name: 'serenut_siparis_hazir',
    language_code: 'tr',
    parameters: ['Ayşe', 'SP-10', 'Örnek İşletme'],
  });
  assert.throws(() => parseTemplatePayload({ template_name: 'Invalid Name!' }), /geçersiz/);

  assert.strictEqual(normalizeWhatsAppRecipient('0555 111 22 33'), '905551112233');
  assert.strictEqual(normalizeWhatsAppRecipient('+90 555 111 22 33'), '905551112233');
  assert.throws(() => normalizeWhatsAppRecipient('123'), /geçersiz/);

  const rawBody = Buffer.from(JSON.stringify({ object: 'whatsapp_business_account' }));
  const signature = `sha256=${crypto.createHmac('sha256', process.env.META_APP_SECRET).update(rawBody).digest('hex')}`;
  assert.strictEqual(verifyWebhookSignature(rawBody, signature), true);
  assert.strictEqual(verifyWebhookSignature(rawBody, 'sha256=deadbeef'), false);

  assert.deepStrictEqual(validateWhatsAppRuntimeConfig({
    NOTIFICATION_ENABLED_CHANNELS: 'sms,email',
  }), []);
  const invalidRuntime = validateWhatsAppRuntimeConfig({
    NOTIFICATION_ENABLED_CHANNELS: 'sms,email,whatsapp',
    META_APP_ID: 'not-numeric',
    META_APP_SECRET: 'secret',
    WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID: '2051947882108806',
    WHATSAPP_WEBHOOK_VERIFY_TOKEN: 'short',
    WHATSAPP_CREDENTIAL_ENCRYPTION_KEY: 'short',
    WHATSAPP_GRAPH_API_VERSION: '23',
  });
  assert.ok(invalidRuntime.some((item) => item.includes('META_APP_ID')));
  assert.ok(invalidRuntime.some((item) => item.includes('WHATSAPP_WEBHOOK_VERIFY_TOKEN')));
  assert.ok(invalidRuntime.some((item) => item.includes('WHATSAPP_CREDENTIAL_ENCRYPTION_KEY')));
  assert.ok(invalidRuntime.some((item) => item.includes('WHATSAPP_GRAPH_API_VERSION')));

  console.log('✔ WhatsApp credential, template, recipient and webhook security contracts passed.');
} finally {
  if (previousKey === undefined) delete process.env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY;
  else process.env.WHATSAPP_CREDENTIAL_ENCRYPTION_KEY = previousKey;
  if (previousSecret === undefined) delete process.env.META_APP_SECRET;
  else process.env.META_APP_SECRET = previousSecret;
}
