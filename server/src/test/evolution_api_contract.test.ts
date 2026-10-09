import assert from 'node:assert/strict';
import { sendTextMessage, setWebhook } from '../modules/whatsapp/evolution.service';

async function main(): Promise<void> {
  const previousUrl = process.env.EVOLUTION_API_URL;
  const previousKey = process.env.EVOLUTION_API_KEY;
  const previousFetch = global.fetch;
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];

  process.env.EVOLUTION_API_URL = 'https://evolution.example.test/';
  process.env.EVOLUTION_API_KEY = 'contract-test-key';
  global.fetch = (async (input: string | URL, init?: { body?: unknown }) => {
    calls.push({
      url: input.toString(),
      body: JSON.parse(String(init?.body)) as Record<string, unknown>,
    });
    return new Response(JSON.stringify({ key: { id: 'message-1' } }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }) as typeof fetch;

  try {
    await setWebhook('company-1', 'https://api.serenut.com/api/v1/whatsapp/webhook');
    const webhook = calls[0].body.webhook as Record<string, unknown>;
    assert.equal(calls[0].url, 'https://evolution.example.test/webhook/set/serenut_company_1');
    assert.deepEqual(webhook, {
      enabled: true,
      url: 'https://api.serenut.com/api/v1/whatsapp/webhook',
      byEvents: true,
      base64: false,
      events: [
        'QRCODE_UPDATED',
        'CONNECTION_UPDATE',
        'STATUS_INSTANCE',
        'MESSAGES_UPDATE',
        'SEND_MESSAGE',
      ],
    });

    const messageId = await sendTextMessage('company-1', '0555 123 4567', 'test');
    assert.equal(messageId, 'message-1');
    assert.equal(calls[1].url, 'https://evolution.example.test/message/sendText/serenut_company_1');
    assert.deepEqual(calls[1].body, {
      number: '905551234567',
      text: 'test',
      delay: 0,
    });
    console.log('✅ Evolution API contract verified.');
  } finally {
    global.fetch = previousFetch;
    if (previousUrl === undefined) delete process.env.EVOLUTION_API_URL;
    else process.env.EVOLUTION_API_URL = previousUrl;
    if (previousKey === undefined) delete process.env.EVOLUTION_API_KEY;
    else process.env.EVOLUTION_API_KEY = previousKey;
  }
}

void main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
