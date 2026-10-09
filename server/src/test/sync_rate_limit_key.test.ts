import assert from 'node:assert/strict';
import type { Request } from 'express';
import { syncRateLimitKey } from '../middleware/rate-limit.middleware';

function mockRequest(
  deviceId: string,
  source: 'body' | 'query',
  companyId = 'company-1',
): Request {
  const request = {
    user: { company_id: companyId },
    header: () => undefined,
    body: source === 'body' ? { device_id: deviceId } : {},
    query: source === 'query' ? { device_id: deviceId } : {},
  };
  return request as unknown as Request;
}

assert.equal(syncRateLimitKey(mockRequest('device-a', 'body')), 'company-1:device-a');
assert.equal(syncRateLimitKey(mockRequest('device-b', 'query')), 'company-1:device-b');
assert.notEqual(
  syncRateLimitKey(mockRequest('device-a', 'body')),
  syncRateLimitKey(mockRequest('device-b', 'query')),
);
assert.equal(
  syncRateLimitKey(mockRequest('device-a', 'body', 'company-2')),
  'company-2:device-a',
);
console.log('✅ Sync rate-limit keys are isolated by tenant and device.');
