// server/src/modules/whatsapp/evolution.service.ts
// Serenut Platform — Evolution API v2 HTTP İstemcisi
//
// Evolution API, QR kod tabanlı WhatsApp bağlantısı sağlar.
// Her şirket = Evolution üzerinde 1 ayrı instance.
// Meta onayı, WABA veya şablon gerektirmez.
//
// Dökümantasyon: https://doc.evolution-api.com

import { logger } from '../../config/logger';

const REQUEST_TIMEOUT_MS = 20_000;

// ── YAPILANDIRMA ──────────────────────────────────────────────────────────────

function getEvolutionConfig() {
  const url = process.env.EVOLUTION_API_URL?.replace(/\/$/, '');
  const apiKey = process.env.EVOLUTION_API_KEY;

  if (!url || !apiKey) {
    throw new EvolutionConfigError(
      'EVOLUTION_API_URL ve EVOLUTION_API_KEY ortam değişkenleri tanımlanmalıdır.',
    );
  }

  return { url, apiKey };
}

/** Şirket ID'sinden Evolution instance adı üretir. Alfanümerik ve _ dışı karakterler kaldırılır. */
export function instanceId(companyId: string): string {
  return `serenut_${companyId.replace(/[^a-zA-Z0-9]/g, '_')}`;
}

// ── HATA TÜRLERİ ─────────────────────────────────────────────────────────────

export class EvolutionConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EvolutionConfigError';
  }
}

export class EvolutionApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly code?: string,
  ) {
    super(message);
    this.name = 'EvolutionApiError';
  }
}

// ── TİP TANIMLARI ─────────────────────────────────────────────────────────────

export type EvolutionConnectionStatus = 'open' | 'connecting' | 'close';

export interface EvolutionQRResponse {
  /** base64 PNG veri URL'si (data:image/png;base64,...) */
  qrcode: string;
  /** QR'ın süresi dolana kadar kalan süre (ms) */
  expiresInMs?: number;
}

export interface EvolutionStatusResponse {
  status: EvolutionConnectionStatus;
  /** Bağlı telefon numarası (sadece status='open' iken dolu) */
  phone?: string;
  /** Bağlı profil adı */
  name?: string;
}

// ── HTTP YARDIMCI ─────────────────────────────────────────────────────────────

async function evolutionFetch<T = unknown>(
  method: 'GET' | 'POST' | 'DELETE',
  path: string,
  body?: unknown,
): Promise<T> {
  const { url, apiKey } = getEvolutionConfig();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(`${url}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        apikey: apiKey,
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => 'unknown');
      throw new EvolutionApiError(
        `Evolution API hatası [${method} ${path}]: ${response.status} — ${errorText}`,
        response.status,
      );
    }

    const text = await response.text();
    return text ? (JSON.parse(text) as T) : ({} as T);
  } catch (error) {
    if (error instanceof EvolutionApiError) throw error;
    if ((error as Error).name === 'AbortError') {
      throw new EvolutionApiError(`Evolution API zaman aşımı (${REQUEST_TIMEOUT_MS}ms)`, 408);
    }
    throw new EvolutionApiError(
      `Evolution API bağlantı hatası: ${(error as Error).message}`,
      0,
    );
  } finally {
    clearTimeout(timeout);
  }
}

// ── INSTANCE YÖNETİMİ ─────────────────────────────────────────────────────────

/**
 * Evolution API'de yeni bir instance oluşturur.
 * Zaten varsa hata VERMEZ (idempotent).
 */
export async function createInstance(companyId: string): Promise<void> {
  const name = instanceId(companyId);
  logger.info(`[Evolution] createInstance: ${name}`);

  try {
    await evolutionFetch('POST', '/instance/create', {
      instanceName: name,
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true,
    });
  } catch (error) {
    // 409 = zaten var → sorun değil
    if (error instanceof EvolutionApiError && error.status === 409) {
      logger.info(`[Evolution] Instance zaten mevcut: ${name}`);
      return;
    }
    throw error;
  }
}

/**
 * Instance'ın QR kodunu döndürür.
 * Henüz instance yoksa önce oluşturur.
 */
export async function getQRCode(companyId: string): Promise<EvolutionQRResponse> {
  const name = instanceId(companyId);
  logger.info(`[Evolution] getQRCode: ${name}`);

  try {
    const response = await evolutionFetch<{ qrcode?: { base64?: string; code?: string } }>(
      'GET',
      `/instance/connect/${name}`,
    );

    const base64 = response?.qrcode?.base64;
    if (!base64) {
      throw new EvolutionApiError('QR kodu henüz oluşturulmadı. Lütfen birkaç saniye bekleyip tekrar deneyin.', 202);
    }

    return {
      qrcode: base64.startsWith('data:') ? base64 : `data:image/png;base64,${base64}`,
      expiresInMs: 60_000, // Evolution QR'ı ~60s geçerli
    };
  } catch (error) {
    // Instance yok → oluştur ve tekrar dene
    if (error instanceof EvolutionApiError && error.status === 404) {
      await createInstance(companyId);
      return getQRCode(companyId);
    }
    throw error;
  }
}

/**
 * Instance'ın bağlantı durumunu döndürür.
 * 404 (instance yok) → { status: 'close' } döndürür.
 */
export async function getConnectionStatus(companyId: string): Promise<EvolutionStatusResponse> {
  const name = instanceId(companyId);

  try {
    const response = await evolutionFetch<{
      instance?: { state?: string; profileName?: string; ownerJid?: string };
    }>('GET', `/instance/fetchInstances?instanceName=${name}`);

    const instance = Array.isArray(response) ? (response as any[])[0]?.instance : response?.instance;
    const rawStatus = instance?.state ?? 'close';

    const status: EvolutionConnectionStatus =
      rawStatus === 'open' ? 'open'
      : rawStatus === 'connecting' ? 'connecting'
      : 'close';

    // JID formatı: 905xxxxxxxxx@s.whatsapp.net
    const jid = instance?.ownerJid ?? '';
    const phone = jid.split('@')[0] || undefined;

    return {
      status,
      phone: status === 'open' ? phone : undefined,
      name: status === 'open' ? instance?.profileName : undefined,
    };
  } catch (error) {
    if (error instanceof EvolutionApiError && error.status === 404) {
      return { status: 'close' };
    }
    throw error;
  }
}

/**
 * WhatsApp oturumunu kapatır ve instance'ı siler.
 */
export async function deleteInstance(companyId: string): Promise<void> {
  const name = instanceId(companyId);
  logger.info(`[Evolution] deleteInstance: ${name}`);

  try {
    await evolutionFetch('DELETE', `/instance/delete/${name}`);
  } catch (error) {
    // 404 = zaten yok → sorun değil
    if (error instanceof EvolutionApiError && error.status === 404) return;
    throw error;
  }
}

/**
 * Instance için webhook URL'si ayarlar.
 * Durum değişikliklerini (bağlandı, kesildi) Serenut sunucusuna bildirir.
 */
export async function setWebhook(companyId: string, webhookUrl: string): Promise<void> {
  const name = instanceId(companyId);
  logger.info(`[Evolution] setWebhook: ${name} → ${webhookUrl}`);

  await evolutionFetch('POST', `/webhook/set/${name}`, {
    enabled: true,
    url: webhookUrl,
    webhookByEvents: true,
    webhookBase64: false,
    events: [
      'QRCODE_UPDATED',
      'CONNECTION_UPDATE',
      'STATUS_INSTANCE',
    ],
  });
}

// ── MESAJ GÖNDERİMİ ──────────────────────────────────────────────────────────

/**
 * Belirtilen telefon numarasına WhatsApp metin mesajı gönderir.
 * @param companyId - Gönderici şirket ID'si (bağlı instance için)
 * @param phone - Alıcı telefon numarası (örn: "905551234567", + işareti olmadan)
 * @param text - Gönderilecek mesaj metni
 * @returns Evolution API mesaj ID'si
 */
export async function sendTextMessage(
  companyId: string,
  phone: string,
  text: string,
): Promise<string> {
  const name = instanceId(companyId);

  // Numara normalizasyonu: +, boşluk, tire temizlenir
  const normalizedPhone = phone.replace(/[^\d]/g, '');
  // JID formatı: 905xxxxxxxxx@s.whatsapp.net
  const jid = `${normalizedPhone}@s.whatsapp.net`;

  logger.info(`[Evolution] sendTextMessage: ${name} → ${jid}`);

  const response = await evolutionFetch<{ key?: { id?: string }; messageId?: string }>(
    'POST',
    `/message/sendText/${name}`,
    {
      number: jid,
      text,
      delay: 1000, // Spam koruması için 1 saniyelik gecikme
    },
  );

  const messageId = response?.key?.id ?? response?.messageId ?? 'unknown';
  return messageId;
}

// ── RUNTIME DOĞRULAMASI ──────────────────────────────────────────────────────

/**
 * Evolution API ayarlarını doğrular.
 * WhatsApp kanalı etkin değilse kontrol yapılmaz.
 */
export function validateEvolutionConfig(env: NodeJS.ProcessEnv = process.env): string[] {
  const channels = (env.NOTIFICATION_ENABLED_CHANNELS || 'sms,email')
    .split(',')
    .map((c) => c.trim().toLowerCase());

  if (!channels.includes('whatsapp')) return [];
  if (env.WHATSAPP_GATEWAY !== 'evolution') return [];

  const errors: string[] = [];
  if (!env.EVOLUTION_API_URL?.trim()) errors.push('EVOLUTION_API_URL is required when WHATSAPP_GATEWAY=evolution');
  if (!env.EVOLUTION_API_KEY?.trim()) errors.push('EVOLUTION_API_KEY is required when WHATSAPP_GATEWAY=evolution');

  return errors;
}
