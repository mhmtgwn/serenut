import assert from 'assert';
import {
  normalizeClientDiagnostic,
  normalizeCrashDiagnostic,
  normalizeServerDiagnostic,
} from '../modules/admin/diagnostics';

const client = normalizeClientDiagnostic({
  id: 'evt-1',
  company_id: 'company-1',
  company_name: 'Örnek Firma',
  user_id: 'user-1',
  user_name: 'Test Kullanıcı',
  metric_name: 'operational_event',
  occurred_at: '2026-07-29T10:00:00.000Z',
  ip_address: '127.0.0.1',
  metadata: {
    event: 'sync_apply_failed',
    level: 'ERROR',
    error_type: 'Constraint_ForeignKey',
    error_message: 'FOREIGN KEY constraint failed',
    correlationId: 'corr-123',
    platform: 'android',
    app_version: '1.2.0+43',
    access_token: 'must-not-leak',
    nested: { password: 'must-not-leak-either' },
  },
});

assert.equal(client.source, 'client');
assert.equal(client.severity, 'error');
assert.equal(client.title, 'İlişkili kayıt bulunamadı');
assert.equal(client.correlation_id, 'corr-123');
assert.equal(client.company_name, 'Örnek Firma');
assert.equal(client.metadata.access_token, '[REDACTED]');
assert.equal((client.metadata.nested as Record<string, unknown>).password, '[REDACTED]');

const legacyConnected = normalizeClientDiagnostic({
  id: 'evt-legacy-connected',
  metric_name: 'ws_connected',
  occurred_at: '2026-08-06T10:00:00.000Z',
  metadata: {},
});
assert.equal(legacyConnected.severity, 'info');
assert.equal(legacyConnected.title, 'Canlı bağlantı kuruldu');

const legacyDisconnected = normalizeClientDiagnostic({
  id: 'evt-legacy-disconnected',
  metric_name: 'ws_disconnected',
  occurred_at: '2026-08-06T10:01:00.000Z',
  metadata: {},
});
assert.equal(legacyDisconnected.severity, 'warning');

const legacyFailure = normalizeClientDiagnostic({
  id: 'evt-legacy-failure',
  metric_name: 'sync_apply_failed',
  occurred_at: '2026-08-06T10:02:00.000Z',
  metadata: {},
});
assert.equal(legacyFailure.severity, 'error');

const server = normalizeServerDiagnostic({
  timestamp: '2026-07-29T11:00:00.000Z',
  level: 'error',
  message: 'Too many requests',
  statusCode: 429,
  authorization: 'Bearer must-not-leak',
  ip: '10.0.0.2',
}, 0);

assert.equal(server.title, 'İstek sınırı aşıldı');
assert.equal(server.ip_address, '10.0.0.2');
assert.equal(server.metadata.authorization, '[REDACTED]');

const crash = normalizeCrashDiagnostic({
  id: 'crash-1',
  company_id: 'company-1',
  device_id: 'device-1',
  error_message: 'Unhandled exception',
  stack_trace: 'at App.run',
  app_version: '1.2.0+43',
  created_at: '2026-07-29T12:00:00.000Z',
});

assert.equal(crash.severity, 'critical');
assert.equal(crash.title, 'Uygulama beklenmeyen şekilde kapandı');
assert.equal(crash.stack_trace, 'at App.run');

console.log('admin diagnostics normalization tests passed');
