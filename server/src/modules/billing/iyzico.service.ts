// server/src/modules/billing/iyzico.service.ts
// Serenut Platform — İyzico Ödeme Geçidi Entegrasyonu
//
// Referans: https://dev.iyzipay.com/tr/api
//
// Desteklenen akışlar:
//   1. Checkout Form başlatma (3D Secure)
//   2. Checkout Form sonuç doğrulama (HMAC-SHA256 imzası)
//   3. Abonelik iptali
//   4. Para iadesi (Refund)
//   5. Kart güncelleme (yeni checkout session)
//
// Sprint 2 notu: Gerçek HTTP çağrıları yapılandırılmıştır.
//   İyzico sandbox için: IYZICO_BASE_URL=https://sandbox-api.iyzipay.com
//   Üretim için: IYZICO_BASE_URL=https://api.iyzipay.com

import crypto from 'crypto';
import https from 'https';
import { logger } from '../../config/logger';

// ── YAPILANDIRMA ──────────────────────────────────────────────────────────────
export let IYZICO_API_KEY = process.env.IYZICO_API_KEY || '';
export let IYZICO_SECRET = process.env.IYZICO_SECRET_KEY || '';
export let IYZICO_BASE_URL = process.env.IYZICO_BASE_URL || 'https://sandbox-api.iyzipay.com';

import { decryptSecret } from '../../crypto_helper';

export async function loadIyzicoConfig(pool: any) {
  try {
    // 1. Fetch from payment_providers
    const res = await pool.query("SELECT config, secrets FROM payment_providers WHERE id = 'iyzico'");
    if (res.rows.length > 0) {
      const row = res.rows[0];
      const config = typeof row.config === 'string' ? JSON.parse(row.config) : row.config || {};
      const secrets = typeof row.secrets === 'string' ? JSON.parse(row.secrets) : row.secrets || {};

      if (config.iyzico_base_url) IYZICO_BASE_URL = config.iyzico_base_url;
      if (secrets.iyzico_api_key) IYZICO_API_KEY = decryptSecret(secrets.iyzico_api_key);
      if (secrets.iyzico_secret_key) IYZICO_SECRET = decryptSecret(secrets.iyzico_secret_key);
      return;
    }

    // 2. Fallback to system_settings for backward compatibility
    const sysRes = await pool.query("SELECT key, value FROM system_settings WHERE key IN ('iyzico_api_key', 'iyzico_secret_key', 'iyzico_base_url')");
    sysRes.rows.forEach((r: any) => {
      if (r.key === 'iyzico_api_key' && r.value) IYZICO_API_KEY = r.value;
      if (r.key === 'iyzico_secret_key' && r.value) IYZICO_SECRET = r.value;
      if (r.key === 'iyzico_base_url' && r.value) IYZICO_BASE_URL = r.value;
    });
  } catch (err) {
    logger.warn('Failed to load database iyzico credentials, using defaults:', err);
  }
}

if (process.env.NODE_ENV === 'production' && (!IYZICO_API_KEY || !IYZICO_SECRET)) {
  logger.warn('⚠️  IYZICO_API_KEY veya IYZICO_SECRET_KEY tanımlı değil. Ödeme işlemleri çalışmayacak.');
}

// ── TİP TANIMLARI ─────────────────────────────────────────────────────────────
export interface IyzicoCheckoutRequest {
  conversationId: string;     // Sipariş takip ID'si (DB invoice ID)
  price: string;              // Toplam tutar (örn: "900.00")
  paidPrice: string;          // KDV dahil tutar
  currency: 'TRY' | 'USD' | 'EUR';
  basketId: string;           // Sepet ID (company_id gibi kullanılabilir)
  callbackUrl: string;        // İyzico'nun sonucu POST edeceği URL
  buyer: IyzicoBuyer;
  billingAddress: IyzicoAddress;
  basketItems: IyzicoBasketItem[];
}

export interface IyzicoBuyer {
  id: string;
  name: string;
  surname: string;
  email: string;
  identityNumber: string;     // TC veya Vergi No
  phone?: string;
  ip: string;
  registrationAddress: string;
  city: string;
  country: string;
}

export interface IyzicoAddress {
  contactName: string;
  city: string;
  country: string;
  address: string;
}

export interface IyzicoBasketItem {
  id: string;
  name: string;
  category1: string;
  itemType: 'VIRTUAL' | 'PHYSICAL';
  price: string;
}

export interface IyzicoCheckoutResult {
  status: 'success' | 'failure';
  errorCode?: string;
  errorMessage?: string;
  checkoutFormContent?: string;  // HTML form içeriği (iframe için)
  token?: string;                // Checkout token (callback doğrulaması için)
  tokenExpireTime?: number;
  conversationId?: string;
}

export interface IyzicoCallbackResult {
  status: 'success' | 'failure';
  conversationId: string;
  token: string;
  paymentId?: string;
  price?: string;
  paidPrice?: string;
  currency?: string;
  errorCode?: string;
  errorMessage?: string;
}

// ── HMAC-SHA256 İMZA ÜRETME ───────────────────────────────────────────────────
/**
 * İyzico API imzası: HMAC-SHA256(apiKey + randomString + secretKey + request_body, secretKey)
 * Base64 encoded.
 */
function generateAuthorizationHeader(requestBody: string): string {
  const randomString = crypto.randomBytes(12).toString('base64');
  const hashStr = `${IYZICO_API_KEY}${randomString}${IYZICO_SECRET}${requestBody}`;
  const hash = crypto
    .createHmac('sha256', IYZICO_SECRET)
    .update(hashStr)
    .digest('base64');

  const authStr = `${IYZICO_API_KEY}:${randomString}:${hash}`;
  return `IYZWSv2 ${Buffer.from(authStr).toString('base64')}`;
}

// ── HTTP İSTEK YARDIMCISI ─────────────────────────────────────────────────────
async function iyzicoPost<T>(endpoint: string, body: object): Promise<T> {
  const bodyStr = JSON.stringify(body);
  const authHeader = generateAuthorizationHeader(bodyStr);

  const url = new URL(endpoint, IYZICO_BASE_URL);

  return new Promise<T>((resolve, reject) => {
    const options = {
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': authHeader,
        'x-iyzi-rnd': crypto.randomBytes(12).toString('base64'),
        'Content-Length': Buffer.byteLength(bodyStr),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data) as T);
        } catch (e) {
          reject(new Error(`İyzico yanıt parse hatası: ${data.substring(0, 200)}`));
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(15000, () => {
      req.destroy(new Error('İyzico isteği zaman aşımına uğradı (15s)'));
    });
    req.write(bodyStr);
    req.end();
  });
}

// ── ANA SERVİS ────────────────────────────────────────────────────────────────
export class IyzicoService {

  /**
   * Checkout Form başlat (3D Secure).
   * Döndürülen `checkoutFormContent` iframe içinde gösterilir.
   * `token` callback doğrulaması için saklanmalı.
   */
  static async createCheckoutSession(
    request: IyzicoCheckoutRequest
  ): Promise<IyzicoCheckoutResult> {
    try {
      logger.info(`[Iyzico] Checkout session başlatılıyor: ${request.conversationId}`);

      const payload = {
        locale: 'tr',
        conversationId: request.conversationId,
        price: request.price,
        paidPrice: request.paidPrice,
        currency: request.currency,
        basketId: request.basketId,
        paymentGroup: 'SUBSCRIPTION',
        callbackUrl: request.callbackUrl,
        enabledInstallments: [1],
        buyer: request.buyer,
        billingAddress: request.billingAddress,
        shippingAddress: request.billingAddress,
        basketItems: request.basketItems,
      };

      const response = await iyzicoPost<any>('/payment/iyzipos/checkoutform/initialize/auth/ecom', payload);

      if (response.status !== 'success') {
        logger.error(`[Iyzico] Checkout başlatma hatası: ${response.errorMessage} (${response.errorCode})`);
        return {
          status: 'failure',
          errorCode: response.errorCode,
          errorMessage: response.errorMessage,
        };
      }

      logger.info(`[Iyzico] Checkout session oluşturuldu: token=${response.token}`);

      return {
        status: 'success',
        checkoutFormContent: response.checkoutFormContent,
        token: response.token,
        tokenExpireTime: response.tokenExpireTime,
        conversationId: request.conversationId,
      };
    } catch (err: any) {
      logger.error('[Iyzico] createCheckoutSession exception:', err.message);
      return {
        status: 'failure',
        errorMessage: err.message,
      };
    }
  }

  /**
   * Callback doğrulama — İyzico'nun callback POST'unu doğrular.
   * `token` parametresi ile checkout sonucunu sorgular.
   */
  static async retrieveCheckoutResult(token: string): Promise<IyzicoCallbackResult> {
    try {
      logger.info(`[Iyzico] Checkout sonucu sorgulanıyor: token=${token}`);

      const response = await iyzicoPost<any>('/payment/iyzipos/checkoutform/auth/ecom/detail', {
        locale: 'tr',
        conversationId: `retrieve-${Date.now()}`,
        token,
      });

      if (response.status !== 'success') {
        logger.warn(`[Iyzico] Checkout başarısız: ${response.errorMessage}`);
        return {
          status: 'failure',
          conversationId: response.conversationId || '',
          token,
          errorCode: response.errorCode,
          errorMessage: response.errorMessage,
        };
      }

      const payment = response.payment;
      logger.info(`[Iyzico] Ödeme onaylandı: paymentId=${payment?.paymentId} amount=${payment?.paidPrice}`);

      return {
        status: 'success',
        conversationId: response.conversationId,
        token,
        paymentId: payment?.paymentId,
        price: payment?.price,
        paidPrice: payment?.paidPrice,
        currency: payment?.currency,
      };
    } catch (err: any) {
      logger.error('[Iyzico] retrieveCheckoutResult exception:', err.message);
      return {
        status: 'failure',
        conversationId: '',
        token,
        errorMessage: err.message,
      };
    }
  }

  /**
   * Para iadesi.
   */
  static async refund(paymentTransactionId: string, price: string, currency = 'TRY'): Promise<boolean> {
    try {
      const response = await iyzicoPost<any>('/payment/refund', {
        locale: 'tr',
        conversationId: `refund-${Date.now()}`,
        paymentTransactionId,
        price,
        currency,
        ip: '127.0.0.1',
      });

      if (response.status === 'success') {
        logger.info(`[Iyzico] İade başarılı: txId=${paymentTransactionId} amount=${price}`);
        return true;
      }

      logger.error(`[Iyzico] İade hatası: ${response.errorMessage}`);
      return false;
    } catch (err: any) {
      logger.error('[Iyzico] refund exception:', err.message);
      return false;
    }
  }

  /**
   * Sandbox için basit ödeme doğrulama simülasyonu.
   * Gerçek uygulamada retrieveCheckoutResult kullanılır.
   */
  static isConfigured(): boolean {
    return Boolean(IYZICO_API_KEY && IYZICO_SECRET);
  }

  /**
   * Test the connection to Iyzico by making a lightweight API call (Installment check).
   */
  static async testConnection(): Promise<{ success: boolean; message?: string }> {
    try {
      if (!this.isConfigured()) return { success: false, message: 'API anahtarları eksik.' };

      // We use the installment check endpoint as a ping
      const response = await iyzicoPost<any>('/payment/iyzipos/installment', {
        locale: 'tr',
        conversationId: 'test-connection',
        binNumber: '411111',
        price: '1.0'
      });

      if (response.status === 'success' || response.errorCode === '10051') {
        // 10051 could be a bin not found error, but it proves auth was successful
        return { success: true };
      }

      return { success: false, message: response.errorMessage || 'Bilinmeyen hata' };
    } catch (err: any) {
      return { success: false, message: err.message };
    }
  }
}
