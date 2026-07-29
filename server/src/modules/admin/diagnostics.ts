const sensitiveKeys = new Set([
  'authorization',
  'password',
  'password_hash',
  'access_token',
  'refresh_token',
  'token',
  'secret',
  'client_secret',
  'pin',
  'cvv',
  'pan',
  'card_number',
]);

export type DiagnosticSeverity = 'critical' | 'error' | 'warning' | 'info';

export interface DiagnosticRecord {
  id: string;
  source: 'server' | 'client' | 'crash';
  severity: DiagnosticSeverity;
  occurred_at: string | null;
  title: string;
  explanation: string;
  suggested_action: string;
  message: string;
  error_type: string | null;
  context: string | null;
  correlation_id: string | null;
  company_id: string | null;
  company_name: string | null;
  user_id: string | null;
  user_name: string | null;
  device_id: string | null;
  app_version: string | null;
  platform: string | null;
  ip_address: string | null;
  stack_trace: string | null;
  metadata: Record<string, unknown>;
}

export function sanitizeDiagnosticMetadata(
  value: unknown,
  depth = 0,
): unknown {
  if (depth > 5) return '[MAX_DEPTH]';
  if (Array.isArray(value)) {
    return value.slice(0, 100).map((item) => sanitizeDiagnosticMetadata(item, depth + 1));
  }
  if (!value || typeof value !== 'object') return value;

  const sanitized: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    sanitized[key] = sensitiveKeys.has(key.toLowerCase())
      ? '[REDACTED]'
      : sanitizeDiagnosticMetadata(item, depth + 1);
  }
  return sanitized;
}

function text(value: unknown): string {
  return value == null ? '' : String(value);
}

function optionalText(value: unknown): string | null {
  const result = text(value).trim();
  return result || null;
}

export function normalizeSeverity(value: unknown): DiagnosticSeverity {
  const normalized = text(value).toLowerCase();
  if (normalized === 'fatal' || normalized === 'critical') return 'critical';
  if (normalized === 'warn' || normalized === 'warning') return 'warning';
  if (normalized === 'debug' || normalized === 'info' || normalized === 'log') return 'info';
  return 'error';
}

export function explainDiagnostic(input: {
  event?: unknown;
  context?: unknown;
  errorType?: unknown;
  message?: unknown;
  statusCode?: unknown;
}): Pick<DiagnosticRecord, 'title' | 'explanation' | 'suggested_action'> {
  const event = text(input.event).toLowerCase();
  const context = text(input.context);
  const errorType = text(input.errorType);
  const message = text(input.message);
  const haystack = `${event} ${context} ${errorType} ${message}`.toLowerCase();
  const statusCode = Number(input.statusCode);

  if (event === 'crash' || haystack.includes('unhandled exception')) {
    return {
      title: 'Uygulama beklenmeyen şekilde kapandı',
      explanation: 'Windows veya Android uygulamasında yakalanamayan bir hata oluştu.',
      suggested_action: 'Uygulama sürümü ve cihazı doğrulayın; stack trace içindeki ilk uygulama dosyasını ve aynı zamandaki senkronizasyon kayıtlarını inceleyin.',
    };
  }
  if (haystack.includes('foreign key') || haystack.includes('constraint_foreignkey')) {
    return {
      title: 'İlişkili kayıt bulunamadı',
      explanation: 'Bir satış veya sipariş satırı, cihaz veritabanında bulunmayan ürün ya da üst kayda bağlanmaya çalıştı.',
      suggested_action: 'Correlation ID ile aynı senkronizasyon oturumunu inceleyin; ürün ve üst kayıtların önce uygulandığını doğrulayın.',
    };
  }
  if (haystack.includes('sync') || haystack.includes('syncnotifier')) {
    return {
      title: 'Senkronizasyon işlemi başarısız',
      explanation: 'Cihaz, yerel değişiklikleri gönderirken veya sunucudaki değişiklikleri yerel veritabanına uygularken hata aldı.',
      suggested_action: 'Cihaz, firma ve correlation ID alanlarını kullanarak aynı oturumdaki ilk hatayı bulun; sonraki tekrar kayıtları ikincil olabilir.',
    };
  }
  if (haystack.includes('websocket') || haystack.includes('ws_handshake')) {
    return {
      title: 'Canlı bağlantı kurulamadı',
      explanation: 'Anlık bildirim kanalı bağlantı kuramadı veya koptu. Periyodik senkronizasyon çalışmaya devam edebilir.',
      suggested_action: 'Token yenileme kayıtlarını ve bağlantının sonraki denemede başarıyla kurulup kurulmadığını kontrol edin.',
    };
  }
  if (statusCode === 401 || haystack.includes('invalid_access_token')) {
    return {
      title: 'Oturum anahtarı geçersiz',
      explanation: 'İstemci süresi dolmuş veya geçersiz erişim anahtarıyla istek gönderdi.',
      suggested_action: 'Aynı isteğin token yenilemeden sonra 200 dönüp dönmediğini kontrol edin; sürekli tekrarlanıyorsa oturum yenileme akışını inceleyin.',
    };
  }
  if (statusCode === 429 || haystack.includes('rate limit')) {
    return {
      title: 'İstek sınırı aşıldı',
      explanation: 'Aynı cihaz veya kullanıcı kısa sürede izin verilenden fazla istek gönderdi.',
      suggested_action: 'İstemcinin tekrar aralığını ve sunucudaki endpoint bazlı rate-limit politikasını kontrol edin.',
    };
  }
  if ([502, 503, 504].includes(statusCode) || /\b50[234]\b/.test(haystack)) {
    return {
      title: 'Sunucu geçici olarak erişilemedi',
      explanation: 'Proxy, dağıtım veya backend yeniden başlatması sırasında istek tamamlanamadı.',
      suggested_action: 'Aynı dakikadaki deploy ve health kayıtlarını kontrol edin; hata dağıtım dışında sürüyorsa backend logunu inceleyin.',
    };
  }
  if (haystack.includes('column') && haystack.includes('does not exist')) {
    return {
      title: 'Veritabanı şeması kodla uyumsuz',
      explanation: 'Backend, canlı veritabanında bulunmayan bir kolonu sorguladı.',
      suggested_action: 'İlgili migration’ın uygulandığını ve sorgunun canlı şemayla aynı sürümde olduğunu doğrulayın.',
    };
  }

  return {
    title: errorType || event || 'Uygulama hatası',
    explanation: 'İşlem beklenmeyen bir hata nedeniyle tamamlanamadı.',
    suggested_action: 'Ham mesajı, stack trace’i ve correlation ID ile aynı zamandaki diğer kayıtları birlikte inceleyin.',
  };
}

export function normalizeClientDiagnostic(row: Record<string, any>): DiagnosticRecord {
  const metadata = sanitizeDiagnosticMetadata(row.metadata || {}) as Record<string, unknown>;
  const event = optionalText(metadata.event) || optionalText(row.metric_name) || 'client_event';
  const message = optionalText(metadata.error_message) || optionalText(metadata.message) || event;
  const context = optionalText(metadata.context);
  const errorType = optionalText(metadata.error_type);
  const severity = normalizeSeverity(metadata.level || row.severity || 'error');
  const guidance = explainDiagnostic({
    event,
    context,
    errorType,
    message,
    statusCode: metadata.status_code,
  });

  return {
    id: `client-${row.id}`,
    source: 'client',
    severity,
    occurred_at: optionalText(row.occurred_at),
    ...guidance,
    message,
    error_type: errorType,
    context,
    correlation_id: optionalText(metadata.correlationId || metadata.correlation_id),
    company_id: optionalText(row.company_id),
    company_name: optionalText(row.company_name),
    user_id: optionalText(row.user_id),
    user_name: optionalText(row.user_name),
    device_id: optionalText(metadata.device_id || metadata.device_hash || metadata.device_activation_id),
    app_version: optionalText(metadata.app_version || row.app_version),
    platform: optionalText(metadata.platform || row.user_agent),
    ip_address: optionalText(row.ip_address),
    stack_trace: optionalText(metadata.stack_trace),
    metadata,
  };
}

export function normalizeCrashDiagnostic(row: Record<string, any>): DiagnosticRecord {
  const guidance = explainDiagnostic({
    event: 'crash',
    errorType: row.error_type,
    message: row.error_message,
  });
  return {
    id: `crash-${row.id}`,
    source: 'crash',
    severity: 'critical',
    occurred_at: optionalText(row.created_at),
    ...guidance,
    message: text(row.error_message) || 'Bilinmeyen uygulama çökmesi',
    error_type: optionalText(row.error_type),
    context: null,
    correlation_id: optionalText(row.correlation_id),
    company_id: optionalText(row.company_id),
    company_name: optionalText(row.company_name),
    user_id: null,
    user_name: null,
    device_id: optionalText(row.device_id),
    app_version: optionalText(row.app_version),
    platform: optionalText(row.device_name),
    ip_address: null,
    stack_trace: optionalText(row.stack_trace),
    metadata: {},
  };
}

export function normalizeServerDiagnostic(
  row: Record<string, any>,
  index: number,
): DiagnosticRecord {
  const message = text(row.message || row.error || row);
  const severity = normalizeSeverity(row.level || row.severity || 'error');
  const guidance = explainDiagnostic({
    event: 'server_error',
    context: row.context || row.route,
    errorType: row.name || row.error_type,
    message,
    statusCode: row.statusCode || row.status_code,
  });
  const metadata = sanitizeDiagnosticMetadata(row) as Record<string, unknown>;
  return {
    id: `server-${text(row.timestamp || row.time || 'unknown')}-${index}`,
    source: 'server',
    severity,
    occurred_at: optionalText(row.timestamp || row.time),
    ...guidance,
    message,
    error_type: optionalText(row.name || row.error_type),
    context: optionalText(row.context || row.route || row.url),
    correlation_id: optionalText(row.correlationId || row.correlation_id),
    company_id: optionalText(row.company_id),
    company_name: optionalText(row.company_name),
    user_id: optionalText(row.user_id),
    user_name: optionalText(row.user_name),
    device_id: optionalText(row.device_id),
    app_version: optionalText(row.app_version),
    platform: optionalText(row.platform || row.user_agent),
    ip_address: optionalText(row.ip || row.ip_address),
    stack_trace: optionalText(row.stack || row.trace),
    metadata,
  };
}
