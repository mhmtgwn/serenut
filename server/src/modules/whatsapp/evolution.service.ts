// server/src/modules/whatsapp/evolution.service.ts
// Serenut Platform — Evolution API v2 HTTP İstemcisi
//
// Evolution API, QR kod tabanlı WhatsApp bağlantısı sağlar.
// Her şirket = Evolution üzerinde 1 ayrı instance.
// Şablon onayı gerektirmeden metin mesajları gönderebilir.
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
 * Yanıtta QR kodu dönebilir (Evolution v2 create yanıtı).
 */
export async function createInstance(companyId: string): Promise<any> {
  const name = instanceId(companyId);
  logger.info(`[Evolution] createInstance: ${name}`);

  try {
    const res = await evolutionFetch<any>('POST', '/instance/create', {
      instanceName: name,
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true,
    });
    return res;
  } catch (error) {
    // 409 veya 400 (already exists) → sorun değil
    if (error instanceof EvolutionApiError) {
      const msg = error.message.toLowerCase();
      if (
        error.status === 409 ||
        (error.status === 400 &&
          (msg.includes('already') ||
            msg.includes('exists') ||
            msg.includes('zaten')))
      ) {
        logger.info(`[Evolution] Instance zaten mevcut: ${name}`);
        return null;
      }
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

  // 1. Önce bağlantı durumunu kontrol et — zaten bağlıysa QR üretmeye gerek yok
  try {
    const status = await getConnectionStatus(companyId);
    if (status.status === 'open') {
      return {
        qrcode: 'already_connected',
        expiresInMs: 0,
      };
    }
  } catch (err) {
    logger.warn(`[Evolution] getConnectionStatus ön kontrol uyarısı: ${(err as Error).message}`);
  }

  // 2. Instance oluşturmayı dene (zaten varsa createInstance null döner)
  let createRes: any = null;
  try {
    createRes = await createInstance(companyId);
  } catch (err) {
    logger.warn(`[Evolution] createInstance deneme uyarısı: ${(err as Error).message}`);
  }

  // Evolution v2 create yanıtında doğrudan QR dönebilir
  let rawBase64 =
    createRes?.qrcode?.base64 ||
    createRes?.base64 ||
    createRes?.qrcode?.code ||
    createRes?.code;

  // 3. Eğer create yanıtında QR yoksa /instance/connect/${name} çağır (ve gerekirse retry et)
  if (!rawBase64) {
    const maxAttempts = 3;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const response = await evolutionFetch<any>(
          'GET',
          `/instance/connect/${name}`,
        );

        rawBase64 =
          response?.base64 ||
          response?.qrcode?.base64 ||
          response?.code ||
          response?.qrcode?.code;

        if (rawBase64) break;

        // Instance bağlı olabilir
        const countOrState = response?.count ?? response?.state;
        if (countOrState === 'open' || response?.state === 'open') {
          return {
            qrcode: 'already_connected',
            expiresInMs: 0,
          };
        }
      } catch (error) {
        if (error instanceof EvolutionApiError) {
          const msg = error.message.toLowerCase();
          // Instance henüz yoksa (404 veya 400 not exist) oluşturup tekrar dene
          if (
            error.status === 404 ||
            (error.status === 400 &&
              (msg.includes('not exist') || msg.includes('bulunamadı')))
          ) {
            await createInstance(companyId);
          } else if (msg.includes('already connected') || msg.includes('open')) {
            return {
              qrcode: 'already_connected',
              expiresInMs: 0,
            };
          } else if (attempt === maxAttempts) {
            throw error;
          }
        } else if (attempt === maxAttempts) {
          throw error;
        }
      }

      if (attempt < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 1200));
      }
    }
  }

  if (!rawBase64) {
    throw new EvolutionApiError(
      'QR kodu henüz oluşturulmadı. Lütfen birkaç saniye bekleyip tekrar deneyin.',
      202,
    );
  }

  return {
    qrcode: rawBase64.startsWith('data:')
      ? rawBase64
      : `data:image/png;base64,${rawBase64}`,
    expiresInMs: 60_000,
  };
}

/**
 * Instance'ın bağlantı durumunu döndürür.
 * 404 veya 400 (instance yok) → { status: 'close' } döndürür.
 */
export async function getConnectionStatus(companyId: string): Promise<EvolutionStatusResponse> {
  const name = instanceId(companyId);

  try {
    let rawStatus = 'close';
    let phone: string | undefined;
    let profileName: string | undefined;

    // 1. fetchInstances üzerinden bağlantı durumunu, JID'i ve profil adını al
    try {
      const response = await evolutionFetch<any>(
        'GET',
        `/instance/fetchInstances?instanceName=${name}`,
      );

      const instances = Array.isArray(response)
        ? response
        : response ? [response] : [];
      const found =
        instances.find((i: any) => i?.name === name || i?.instance?.instanceName === name) ||
        instances[0];

      if (found) {
        const inst = found.instance || found;
        rawStatus =
          inst.connectionStatus ||
          found.connectionStatus ||
          inst.state ||
          found.state ||
          inst.status ||
          found.status ||
          'close';

        const jid = inst.ownerJid || found.ownerJid || inst.owner || found.owner || '';
        if (jid) {
          phone = jid.split('@')[0];
        }
        profileName = inst.profileName || found.profileName || inst.name || found.name;
      }
    } catch (fetchErr) {
      logger.warn(`[Evolution] fetchInstances sorgu uyarısı: ${(fetchErr as Error).message}`);
    }

    // 2. Eğer rawStatus 'open' değilse connectionState ile anlık durumu da doğrula
    if (rawStatus !== 'open') {
      try {
        const stateRes = await evolutionFetch<any>(
          'GET',
          `/instance/connectionState/${name}`,
        );
        const stateVal = stateRes?.instance?.state || stateRes?.state;
        if (stateVal) {
          rawStatus = stateVal;
        }
      } catch (_) {
        // Yoksa veya kapalıysa sessizce devam et
      }
    }

    const status: EvolutionConnectionStatus =
      rawStatus === 'open'
        ? 'open'
        : rawStatus === 'connecting'
          ? 'connecting'
          : 'close';

    return {
      status,
      phone: status === 'open' ? phone : undefined,
      name: status === 'open' ? profileName : undefined,
    };
  } catch (error) {
    if (
      error instanceof EvolutionApiError &&
      (error.status === 404 || error.status === 400)
    ) {
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
    // 404 veya 400 = zaten yok → sorun değil
    if (
      error instanceof EvolutionApiError &&
      (error.status === 404 || error.status === 400)
    ) {
      return;
    }
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
    webhook: {
      enabled: true,
      url: webhookUrl,
      byEvents: true,
      base64: false,
      events: [
        'QRCODE_UPDATED',
        'CONNECTION_UPDATE',
        'STATUS_INSTANCE',
        'MESSAGES_UPDATE',
        'SEND_MESSAGE',
      ],
    },
  });
}

// ── MESAJ GÖNDERİMİ ──────────────────────────────────────────────────────────

/**
 * Loglarda KVKK ve güvenlik gereği telefon numarasını maskeler (örn: 9055****67).
 */
export function maskPhoneForLog(phone: string): string {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.length <= 4) return '****';
  if (digits.length <= 7) return `${digits.slice(0, 2)}****${digits.slice(-2)}`;
  return `${digits.slice(0, 4)}****${digits.slice(-2)}`;
}

export type NormalizedEvolutionStatusCategory = 'delivered' | 'server_ack' | 'failed' | 'pending' | 'unknown';

export interface NormalizedEvolutionStatus {
  category: NormalizedEvolutionStatusCategory;
  providerStatus: string;
}

/**
 * Evolution API v2.3.7 ve Baileys tarafından iletilen durum kodlarını ve metinlerini normalize eder.
 *
 * Baileys WAMessageStatus:
 * 0 -> ERROR (failed)
 * 1 -> PENDING (pending)
 * 2 -> SERVER_ACK (server_ack — tek gri tik, teslimat SAYILMAZ)
 * 3 -> DELIVERY_ACK (delivered — çift gri tik)
 * 4 -> READ (delivered — çift mavi tik)
 * 5 -> PLAYED (delivered — sesli mesaj dinlendi)
 *
 * Metinsel karşılıklar:
 * 'DELIVERY_ACK', 'DELIVERED', 'READ', 'PLAYED' -> category: 'delivered'
 * 'SERVER_ACK', 'SENT' -> category: 'server_ack'
 * 'ERROR', 'FAILED' -> category: 'failed'
 * 'PENDING' -> category: 'pending'
 * Bilinmeyen tüm durumlar -> category: 'unknown' (asla delivered sayılmaz)
 */
export function normalizeEvolutionMessageStatus(rawStatus: unknown): NormalizedEvolutionStatus {
  if (rawStatus === null || rawStatus === undefined) {
    return { category: 'unknown', providerStatus: 'unknown' };
  }

  if (typeof rawStatus === 'number') {
    switch (rawStatus) {
      case 0:
        return { category: 'failed', providerStatus: 'error' };
      case 1:
        return { category: 'pending', providerStatus: 'pending' };
      case 2:
        return { category: 'server_ack', providerStatus: 'server_ack' };
      case 3:
        return { category: 'delivered', providerStatus: 'delivery_ack' };
      case 4:
        return { category: 'delivered', providerStatus: 'read' };
      case 5:
        return { category: 'delivered', providerStatus: 'played' };
      default:
        return { category: 'unknown', providerStatus: String(rawStatus) };
    }
  }

  const str = String(rawStatus).trim().toUpperCase();
  if (/^\d+$/.test(str)) {
    return normalizeEvolutionMessageStatus(parseInt(str, 10));
  }

  if (str === 'DELIVERY_ACK' || str === 'DELIVERED') {
    return { category: 'delivered', providerStatus: 'delivery_ack' };
  }
  if (str === 'READ' || str === 'PLAYED') {
    return { category: 'delivered', providerStatus: str.toLowerCase() };
  }
  if (str === 'SERVER_ACK' || str === 'SENT') {
    return { category: 'server_ack', providerStatus: 'server_ack' };
  }
  if (str === 'ERROR' || str === 'FAILED') {
    return { category: 'failed', providerStatus: 'failed' };
  }
  if (str === 'PENDING') {
    return { category: 'pending', providerStatus: 'pending' };
  }

  return { category: 'unknown', providerStatus: str.toLowerCase() };
}

/**
 * Belirtilen telefon numarasına ülkeye özel normalizasyon ve E.164 format doğrulaması uygular.
 * Desteklenen girdiler:
 * - "+905551234567"
 * - "00905551234567"
 * - "05551234567"
 * - "5551234567"
 * - "905551234567"
 * - Parantez, boşluk veya tire içeren formatlar: "(0555) 123-4567"
 *
 * Geçersiz, boş veya E.164 sınırları (8-15 basamak) dışındaki numaralarda EvolutionApiError fırlatır.
 */
export function normalizeEvolutionPhone(phone: string): string {
  if (!phone || typeof phone !== 'string') {
    throw new EvolutionApiError('Alıcı telefon numarası boş veya geçersiz.', 400, 'invalid_phone');
  }

  let digits = phone.replace(/\D/g, '');
  if (!digits) {
    throw new EvolutionApiError('Alıcı telefon numarası rakam içermelidir.', 400, 'invalid_phone');
  }

  const defaultCountryCode = (process.env.WHATSAPP_DEFAULT_COUNTRY_CODE || '90').replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = `${defaultCountryCode}${digits.slice(1)}`;
  if (digits.length === 10) digits = `${defaultCountryCode}${digits}`;

  // ITU-T E.164 standardı: en az 8, en fazla 15 basamak
  if (digits.length < 8 || digits.length > 15) {
    throw new EvolutionApiError(
      `Alıcı telefon numarası geçersiz basamak sayısına sahip (${digits.length} basamak, beklenen: 8-15).`,
      400,
      'invalid_phone',
    );
  }

  return digits;
}

/**
 * Evolution API üzerinden metin mesajı gönderir.
 * Şablon onayı gerektirmez. Müşteri serbest metin alır.
 *
 * Güvenlik ve Mimari İlkeleri:
 * 1. Alıcı kimliği olarak doğrulanmış ve normalleştirilmiş E.164 telefon numarası kullanılır.
 * 2. Evolution API v2 `/message/sendText` uç noktasına doğrudan E.164 formatında gönderilir.
 * 3. Loglarda telefon numaraları maskelenir; mesaj içeriği veya hassas veriler loglanmaz.
 * 4. Mükerrer gönderim yapılmaz; 800ms bekleme veya ikinci gönderim kaldırılmıştır.
 *
 * @param companyId - Şirket ID'si (tenant)
 * @param phone - Alıcı telefon numarası
 * @param text - Gönderilecek mesaj metni
 * @returns Evolution API mesaj ID'si
 */
export async function sendTextMessage(
  companyId: string,
  phone: string,
  text: string,
): Promise<string> {
  const name = instanceId(companyId);

  // Numara normalizasyonu ve doğrulama
  const normalizedPhone = normalizeEvolutionPhone(phone);
  const maskedPhone = maskPhoneForLog(normalizedPhone);

  logger.info(`[Evolution] sendTextMessage: ${name} → ${maskedPhone}`);

  const response = await evolutionFetch<{ key?: { id?: string }; messageId?: string }>(
    'POST',
    `/message/sendText/${name}`,
    {
      number: normalizedPhone,
      text,
      delay: 0, // Anında gönderim
    },
  );

  const messageId = response?.key?.id ?? response?.messageId;
  if (!messageId) {
    throw new EvolutionApiError(
      'Evolution API geçerli bir mesaj kimliği (messageId) döndürmedi.',
      502,
      'missing_message_id',
    );
  }

  return messageId;
}
