// server/src/config/error-codes.ts
// Serenut OS — Centralized Error Code Catalog
// Single Source of Truth: blueprints/error_code_catalog.md
// Rule: ALL API errors must use codes from this catalog.
//       If a new error is needed, ADD it here FIRST, then use it.

export const ErrorCodes = {
  // ── AUTH ─────────────────────────────────────────────────────────────────────
  AUTH001: {
    code: 'AUTH001',
    http: 401,
    message: 'E-posta veya şifre hatalı. Lütfen tekrar deneyin.',
    internal: 'Invalid email or password.',
  },
  AUTH002: {
    code: 'AUTH002',
    http: 401,
    message: 'Oturumunuz sona erdi. Lütfen tekrar giriş yapın.',
    internal: 'Expired or invalid JWT.',
  },
  AUTH003: {
    code: 'AUTH003',
    http: 403,
    message: 'Hesabınız askıya alınmıştır. Destek ile iletişime geçin.',
    internal: 'Account suspended.',
  },
  AUTH004: {
    code: 'AUTH004',
    http: 429,
    message: 'Çok fazla hatalı giriş denemesi. 15 dakika bekleyin.',
    internal: 'Too many login attempts — account temporarily locked.',
  },
  AUTH005: {
    code: 'AUTH005',
    http: 403,
    message: 'Bu işlem için yetkiniz bulunmuyor.',
    internal: 'Insufficient role/permission.',
  },

  // ── LICENSE ──────────────────────────────────────────────────────────────────
  LICENSE101: {
    code: 'LICENSE101',
    http: 404,
    message: 'Girdiğiniz lisans anahtarı geçerli değil.',
    internal: 'License key not found or invalid.',
  },
  LICENSE102: {
    code: 'LICENSE102',
    http: 403,
    message: 'Lisansınızın süresi dolmuştur. Lütfen yenileyin.',
    internal: 'License expired.',
  },
  LICENSE103: {
    code: 'LICENSE103',
    http: 409,
    message: 'Cihaz limitinize ulaştınız. Portaldan eski bir cihazı kaldırın.',
    internal: 'Device limit exceeded for this license.',
  },
  LICENSE104: {
    code: 'LICENSE104',
    http: 429,
    message: 'Bu ay cihaz değişim hakkınızı doldurdunuz.',
    internal: 'Monthly device swap limit reached (max 2).',
  },
  LICENSE105: {
    code: 'LICENSE105',
    http: 423,
    message: 'Bu cihaz başka bir hesaba kayıtlı. Desteğe başvurun.',
    internal: 'Device UUID is bound to a different company.',
  },
  LICENSE106: {
    code: 'LICENSE106',
    http: 402,
    message: 'Ödemeniz alınamadı. Lütfen ödeme bilgilerinizi güncelleyin.',
    internal: 'Payment failed — subscription could not be renewed.',
  },

  // ── SYNC ─────────────────────────────────────────────────────────────────────
  SYNC201: {
    code: 'SYNC201',
    http: 409,
    message: 'Mükerrer istek tespit edildi.',
    internal: 'Idempotency key conflict — request already processed.',
  },
  SYNC202: {
    code: 'SYNC202',
    http: 422,
    message: 'Veri senkronizasyonunda hata oluştu. Destek kodu: SYNC202',
    internal: 'Push payload failed schema validation.',
  },
  SYNC203: {
    code: 'SYNC203',
    http: 503,
    message: 'Senkronizasyon geçici olarak duraklatıldı. Verileriniz güvende.',
    internal: 'Server temporarily refusing push (maintenance mode).',
  },
  SYNC204: {
    code: 'SYNC204',
    http: 409,
    message: 'Veri çakışması tespit edildi. Sunucu değeri esas alındı.',
    internal: 'Conflicting update — Admin Override applied.',
  },

  // ── PAYMENT ──────────────────────────────────────────────────────────────────
  PAYMENT301: {
    code: 'PAYMENT301',
    http: 402,
    message: 'Kartınız reddedildi. Lütfen farklı bir ödeme yöntemi deneyin.',
    internal: 'Card declined.',
  },
  PAYMENT302: {
    code: 'PAYMENT302',
    http: 402,
    message: 'Kartınızda yeterli bakiye bulunmuyor.',
    internal: 'Insufficient funds.',
  },
  PAYMENT303: {
    code: 'PAYMENT303',
    http: 402,
    message: 'Güvenli ödeme doğrulaması tamamlanamadı. Tekrar deneyin.',
    internal: '3D Secure verification incomplete.',
  },
  PAYMENT304: {
    code: 'PAYMENT304',
    http: 402,
    message: 'Ödeme işlemi zaman aşımına uğradı. Lütfen tekrar deneyin.',
    internal: 'Payment gateway timeout.',
  },
  PAYMENT305: {
    code: 'PAYMENT305',
    http: 402,
    message: 'Ödeme anlaşmazlığı nedeniyle hesabınız geçici olarak askıya alındı.',
    internal: 'Chargeback detected — account frozen pending review.',
  },

  // ── COMPANY ──────────────────────────────────────────────────────────────────
  COMPANY401: {
    code: 'COMPANY401',
    http: 409,
    message: 'Bu şubede aktif cihaz var. Önce cihazı kaldırın.',
    internal: 'Branch has active licenses or devices — cannot delete.',
  },
  COMPANY402: {
    code: 'COMPANY402',
    http: 409,
    message: 'Hesap silme talebiniz alındı. 7 gün içinde iptal edebilirsiniz.',
    internal: 'Company deletion in 7-day grace window.',
  },
  COMPANY403: {
    code: 'COMPANY403',
    http: 429,
    message: 'Deneme süresini yalnızca destek ekibi uzatabilir.',
    internal: 'Trial extension requires sysadmin role.',
  },

  // ── DEVICE ───────────────────────────────────────────────────────────────────
  DEVICE501: {
    code: 'DEVICE501',
    http: 403,
    message: 'Bu cihaz lisansınıza bağlı değil. Portaldan ekleyin.',
    internal: 'Device UUID not linked to any active license.',
  },
  DEVICE502: {
    code: 'DEVICE502',
    http: 423,
    message: 'Bu cihaz güvenlik nedeniyle engellendi. Desteğe başvurun.',
    internal: 'Device blocked by sysadmin (abuse detection).',
  },
  DEVICE503: {
    code: 'DEVICE503',
    http: 403,
    message: 'Cihaz saati geçersiz. Sistem saatini doğrulayın.',
    internal: 'Clock manipulation detected — device locked.',
  },
} as const;

export type ErrorCode = keyof typeof ErrorCodes;

// ── HELPER ────────────────────────────────────────────────────────────────────
/**
 * Creates a standardized error response body.
 * Usage: res.status(ErrorCodes.AUTH001.http).json(createError('AUTH001'))
 *
 * @param code  - ErrorCode key from the catalog
 * @param hint  - Optional extra hint shown in the response
 * @param extra - Optional extra fields merged into the error object
 */
export function createError(
  code: ErrorCode,
  hint?: string,
  extra?: Record<string, unknown>
): { error: { code: string; message: string; hint?: string } & Record<string, unknown> } {
  const entry = ErrorCodes[code];
  return {
    error: {
      code: entry.code,
      message: entry.message,
      ...(hint ? { hint } : {}),
      ...(extra ?? {}),
    },
  };
}

/**
 * Maps legacy internal error strings to catalog codes.
 * Used in catch blocks of existing services that throw raw strings.
 */
export function mapLegacyError(internalMsg: string): ErrorCode | null {
  const mapping: Record<string, ErrorCode> = {
    invalid_license_key: 'LICENSE101',
    license_inactive: 'LICENSE102',
    license_expired: 'LICENSE102',
    device_blocked: 'DEVICE502',
    device_limit_exceeded: 'LICENSE103',
    invalid_credentials: 'AUTH001',
    account_suspended: 'AUTH003',
    account_locked: 'AUTH004',
    insufficient_permissions: 'AUTH005',
  };
  return mapping[internalMsg] ?? null;
}
