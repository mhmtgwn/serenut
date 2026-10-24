// server/src/config/test-db-guard.ts
// Serenut OS — PostgreSQL Test Veritabanı Fail-Closed İzolasyon Koruma Modülü

export const FORBIDDEN_DATABASE_PATTERNS = [
  'nutopiano',
  'production',
  'prod_db',
  'prod',
  'live',
  'customer',
  'primary',
  'serenut_db',
  'serenut_dev',
  'shaman',
  'supabase',
  'rds.amazonaws.com',
  'serenut.com',
];

export const ALLOWED_TEST_DB_NAME_REGEX = /^(serenut_test|serenut_[a-z0-9_-]+_test|[a-z0-9_-]+_test|test_[a-z0-9_-]+)$/i;

export interface TestDbValidationResult {
  isValid: boolean;
  error?: string;
  databaseName?: string;
  host?: string;
  port?: string;
}

/**
 * Verilen veritabanı bağlantı dizesini statik olarak inceler.
 * Ağ bağlantısı yapmaz; fail-closed kurallarına göre reddeder veya onaylar.
 */
export function validateTestDatabaseUrl(url: string | undefined): TestDbValidationResult {
  if (!url || typeof url !== 'string' || url.trim().length === 0) {
    return { isValid: false, error: 'DATABASE_URL_EMPTY: Test veritabanı bağlantı dizesi belirtilmemiş.' };
  }

  const trimmed = url.trim();
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch (err: any) {
    return { isValid: false, error: `DATABASE_URL_MALFORMED: Geçersiz URL formatı: ${err?.message}` };
  }

  if (parsed.protocol !== 'postgres:' && parsed.protocol !== 'postgresql:') {
    return { isValid: false, error: `INVALID_PROTOCOL: Yalnızca postgresql: protokolü desteklenir (Alınan: ${parsed.protocol})` };
  }

  const rawDbName = parsed.pathname.replace(/^\//, '').trim();
  if (!rawDbName) {
    return { isValid: false, error: 'DATABASE_NAME_MISSING: Bağlantı dizesinde veritabanı adı belirtilmemiş.' };
  }

  const lowerDbName = rawDbName.toLowerCase();
  const lowerUrl = trimmed.toLowerCase();

  // 1. Yasaklı kelimeler (Blacklist) denetimi
  for (const forbidden of FORBIDDEN_DATABASE_PATTERNS) {
    if (lowerDbName.includes(forbidden) || lowerUrl.includes(forbidden)) {
      return {
        isValid: false,
        databaseName: rawDbName,
        error: `FORBIDDEN_DATABASE_IDENTIFIER: Bağlantı '${forbidden}' ifadesini içeriyor. Canlı veya geliştirme veritabanında test çalıştırılamaz!`,
      };
    }
  }

  // 2. İzin verilen test adı deseni (Whitelist) denetimi
  if (!ALLOWED_TEST_DB_NAME_REGEX.test(rawDbName)) {
    return {
      isValid: false,
      databaseName: rawDbName,
      error: `DATABASE_NAME_NOT_TEST: Veritabanı adı '${rawDbName}' izin verilen test deseniyle uyuşmuyor (Örn: serenut_test veya *_test olmalıdır).`,
    };
  }

  return {
    isValid: true,
    databaseName: rawDbName,
    host: parsed.hostname,
    port: parsed.port,
  };
}

/**
 * Ortam değişkenlerini (NODE_ENV, TEST_DATABASE_URL / DATABASE_URL) denetler.
 * Uyumsuzluk durumunda Error fırlatır (Fail-Closed).
 */
export function assertSafeTestEnvironment(options?: {
  nodeEnv?: string;
  connectionString?: string;
  baseDatabaseUrl?: string;
}): { databaseName: string } {
  const currentEnv = options && 'nodeEnv' in options ? options.nodeEnv : process.env.NODE_ENV;
  if (!currentEnv || currentEnv !== 'test') {
    throw new Error(
      `FATAL_TEST_DB_GUARD: NODE_ENV değeri kesinlikle 'test' olmalıdır (Mevcut: '${currentEnv || 'tanımsız'}'). Geliştirme ortamında test çalıştırılamaz.`
    );
  }

  const connectionString =
    options?.connectionString ?? process.env.TEST_DATABASE_URL ?? process.env.DATABASE_URL;

  const validation = validateTestDatabaseUrl(connectionString);
  if (!validation.isValid) {
    throw new Error(`FATAL_TEST_DB_GUARD: ${validation.error}`);
  }

  // Geliştirme/üretim DATABASE_URL ile TEST_DATABASE_URL çakışması denetimi
  const baseDb = options?.baseDatabaseUrl ?? (process.env.DATABASE_URL !== connectionString ? process.env.DATABASE_URL : undefined);
  if (baseDb && baseDb === connectionString) {
    const baseValidation = validateTestDatabaseUrl(baseDb);
    if (!baseValidation.isValid) {
      throw new Error(
        'FATAL_TEST_DB_GUARD: TEST_DATABASE_URL ile geliştirme DATABASE_URL aynı hedefe yönleniyor. Veri kaybını önlemek için testler durduruldu.'
      );
    }
  }

  return { databaseName: validation.databaseName! };
}

/**
 * Bağlantı havuzuna veya istemcisine canlı SQL sorgusu (`SELECT current_database()`) atarak
 * fiziksel olarak bağlı olunan veritabanının gerçek adını teyit eder.
 * Ad uyuşmazsa veya test kriterini karşılamıyorsa derhal hata fırlatarak işlemi durdurur.
 */
export async function assertIsolatedTestDatabase(
  clientOrPool: { query: (sql: string, params?: any[]) => Promise<any> },
  expectedDbName?: string
): Promise<{ confirmedDatabase: string }> {
  // Önce statik ortam denetimi
  const envCheck = assertSafeTestEnvironment();
  const targetDb = expectedDbName ?? envCheck.databaseName;

  const result = await clientOrPool.query('SELECT current_database() AS db_name');
  const actualDbName = (result?.rows?.[0]?.db_name || '').toString().trim();

  if (!actualDbName) {
    throw new Error('FATAL_TEST_DB_GUARD: current_database() sorgusundan veritabanı adı alınamadı.');
  }

  const validation = validateTestDatabaseUrl(`postgres://localhost/${actualDbName}`);
  if (!validation.isValid) {
    throw new Error(
      `FATAL_TEST_DB_GUARD: Fiziksel olarak bağlanılan veritabanı ('${actualDbName}') güvenli bir test veritabanı değildir! Sebep: ${validation.error}`
    );
  }

  if (targetDb && actualDbName.toLowerCase() !== targetDb.toLowerCase()) {
    throw new Error(
      `FATAL_TEST_DB_GUARD: Beklenen test veritabanı '${targetDb}' iken bağlanılan veritabanı '${actualDbName}'. Bağlantı saptırması şüphesiyle testler durduruldu.`
    );
  }

  return { confirmedDatabase: actualDbName };
}
