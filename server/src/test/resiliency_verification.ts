import { LockManager } from '../utils/lock-manager';
import { AlertingSystem } from '../utils/alerting-system';
import { FeatureFlagManager } from '../utils/feature-flag';
import { pgPool } from '../config/database';
import { Client } from 'pg';
import { idempotencyMiddleware } from '../middleware/idempotency';
import express, { Request, Response } from 'express';
import http from 'http';
import dotenv from 'dotenv';
dotenv.config();

let passed = 0;
let failed = 0;

function assert(condition: boolean, testName: string, message?: string) {
  if (condition) {
    console.log(`  ✔️ [PASS] ${testName}`);
    passed++;
  } else {
    console.error(`  ❌ [FAIL] ${testName}${message ? ': ' + message : ''}`);
    failed++;
  }
}

// Lightweight HTTP Client helper using native http module
function makeRequest(
  options: http.RequestOptions,
  payload?: any
): Promise<{ status: number; headers: http.IncomingHttpHeaders; body: any }> {
  return new Promise((resolve, reject) => {
    const postData = payload ? JSON.stringify(payload) : '';
    const mergedOptions: http.RequestOptions = {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
        ...options.headers
      }
    };

    const req = http.request(mergedOptions, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        let body = data;
        try {
          body = JSON.parse(data);
        } catch (_) {}
        resolve({
          status: res.statusCode || 0,
          headers: res.headers,
          body
        });
      });
    });

    req.on('error', (err) => reject(err));
    if (payload) {
      req.write(postData);
    }
    req.end();
  });
}

async function runTests() {
  console.log('🧪 RUNNING PRODUCTION RESILIENCY & HARDENING INTEGRATION TESTS...');
  console.log('===============================================================');

  // Ensure DB seed is setup
  await pgPool.query("INSERT INTO companies (id, name, tax_number, tax_office, status) VALUES ('serenut_cloud', 'Serenut Cloud Admin', '0000000000', 'Admin Office', 'active') ON CONFLICT (id) DO NOTHING");

  // --- 1. Lock Manager Test ---
  console.log('\n▶️ Verification: Distributed Lock Manager (PostgreSQL)...');
  const lockKey = 'test:lock:uuid-123';
  
  // Establish Client A to represent separate session A
  const clientA = new Client({ connectionString: process.env.DATABASE_URL });
  await clientA.connect();
  
  // Lock the key on Session A
  const lockId = -1188471385; // hash of 'test:lock:uuid-123'
  await clientA.query('SELECT pg_advisory_lock($1)', [lockId]);
  console.log('  [Session A] Acquired lock.');

  // Try to acquire the same lock on LockManager (which runs in session B from pool)
  // This should be rejected since Session A holds it exclusively database-wide!
  const secondAcquire = await LockManager.tryAcquireLock(lockKey, 'token-1');
  assert(secondAcquire === false, 'LockManager: duplicate acquire from different session rejected correctly (locked)');

  // Disconnect Client A (terminates session A, automatically releasing the lock!)
  await clientA.end();
  console.log('  [Session A] Disconnected (lock auto-released).');

  // Now, session B should be able to acquire the lock successfully!
  const thirdAcquire = await LockManager.tryAcquireLock(lockKey, 'token-2');
  assert(thirdAcquire === true, 'LockManager: acquiring after session release succeeded');
  
  // Clean release on session B
  await LockManager.releaseLock(lockKey, 'token-2');

  // --- 2. Alerting System Test ---
  console.log('\n▶️ Verification: Alerting System & Incident Logging...');
  try {
    await AlertingSystem.triggerAlert('fatal', 'TEST_INCIDENT', 'This is a simulated critical database error.', 'serenut_cloud', { query: 'SELECT *', error: 'Timeout' });
    const dbInc = await pgPool.query("SELECT severity, title, status FROM system_incidents WHERE title = 'TEST_INCIDENT' ORDER BY created_at DESC LIMIT 1");
    assert(dbInc.rows.length > 0, 'AlertingSystem: incident written to system_incidents table');
    assert(dbInc.rows[0].severity === 'SEV-1', 'AlertingSystem: severity mapped correctly to SEV-1');
    assert(dbInc.rows[0].status === 'open', 'AlertingSystem: status set to open by default');
  } catch (err: any) {
    assert(false, 'AlertingSystem exception', err.message);
  }

  // --- 3. Feature Flag Test ---
  console.log('\n▶️ Verification: Feature Flag Manager...');
  const cloudWs = await FeatureFlagManager.isFeatureEnabled('serenut_cloud', 'websocket');
  assert(cloudWs === true, 'FeatureFlagManager: cloud company has websocket feature enabled');
  
  const cloudNewSync = await FeatureFlagManager.isFeatureEnabled('serenut_cloud', 'new-sync-engine');
  assert(cloudNewSync === true, 'FeatureFlagManager: cloud company has new-sync-engine override enabled');

  const otherWs = await FeatureFlagManager.isFeatureEnabled('other_company', 'websocket');
  assert(otherWs === true, 'FeatureFlagManager: wildcard fallback enabled for websocket');

  const otherSync = await FeatureFlagManager.isFeatureEnabled('other_company', 'new-sync-engine');
  assert(otherSync === false, 'FeatureFlagManager: unrecognized features disable by default');

  // --- 4. Idempotency Key Collisions & Response Replay Test ---
  console.log('\n▶️ Verification: Idempotency Payload and Response Replay Middleware...');
  
  const app = express();
  app.use(express.json());
  app.use(idempotencyMiddleware);
  
  app.post('/test/idemp', (req: Request, res: Response) => {
    res.status(201).json({ result: 'success', data: req.body });
  });

  const server = http.createServer(app);
  
  await new Promise<void>((resolve) => server.listen(4003, resolve));

  try {
    const payloadA = { amount: 100, target: 'order-1' };
    const payloadB = { amount: 200, target: 'order-2' }; // different payload
    const key = `key-idemp-test-${Date.now()}`;

    // Request 1: Succeeds
    const res1 = await makeRequest({
      hostname: 'localhost',
      port: 4003,
      path: '/test/idemp',
      method: 'POST',
      headers: { 'Idempotency-Key': key }
    }, payloadA);
    assert(res1.status === 201, 'Idempotency Middleware: first mutating request processed');

    // Request 2: Replay identical payload -> HIT (returns cached response)
    const res2 = await makeRequest({
      hostname: 'localhost',
      port: 4003,
      path: '/test/idemp',
      method: 'POST',
      headers: { 'Idempotency-Key': key }
    }, payloadA);
    assert(res2.status === 201, 'Idempotency Middleware: replayed identical payload succeeds');
    assert(res2.headers['x-cache-lookup'] === 'HIT - Idempotency Replay', 'Idempotency Middleware: cached response replay confirmed');

    // Request 3: Key Collision -> Should return 422 Unprocessable Entity
    const res3 = await makeRequest({
      hostname: 'localhost',
      port: 4003,
      path: '/test/idemp',
      method: 'POST',
      headers: { 'Idempotency-Key': key }
    }, payloadB);
    assert(res3.status === 422, 'Idempotency Middleware: key collision correctly blocked with 422');
    assert(res3.body?.code === 'IDEMPOTENCY_KEY_COLLISION', 'Idempotency Middleware: collision error code matched');

  } catch (err: any) {
    console.error('HTTP Test client encountered error:', err.message);
  } finally {
    server.close();
  }

  // Cleanup testing incidents
  await pgPool.query("DELETE FROM system_incidents WHERE title = 'TEST_INCIDENT'");
  await pgPool.end();

  console.log('\n===============================================================');
  console.log(`🏁 VERIFICATION COMPLETE. PASSED: ${passed} | FAILED: ${failed}`);
  
  process.exit(failed === 0 ? 0 : 1);
}

runTests().catch(console.error);
