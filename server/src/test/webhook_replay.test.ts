// server/src/test/webhook_replay.test.ts
// Serenut OS — Iyzico Webhook Replay & Idempotency Acceptance Criteria Test

import express from 'express';
import http from 'http';
import crypto from 'crypto';
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import billingRouter from '../modules/billing/billing.controller';

const IYZICO_SECRET = 'test-secret-key-123';
process.env.IYZICO_SECRET_KEY = IYZICO_SECRET;
process.env.NODE_ENV = 'test';

// Mock Redis client
const mockRedisDb = new Map<string, string>();
const mockRedisClient = {
  isOpen: true,
  get: async (key: string) => mockRedisDb.get(key) || null,
  set: async (key: string, value: string, options?: any) => {
    if (options?.NX && mockRedisDb.has(key)) {
      return null;
    }
    mockRedisDb.set(key, value);
    return 'OK';
  },
  del: async (key: string) => {
    mockRedisDb.delete(key);
    return 1;
  },
  incr: async (key: string) => {
    const val = Number(mockRedisDb.get(key) || 0) + 1;
    mockRedisDb.set(key, val.toString());
    return val;
  },
  expire: async (key: string, seconds: number) => {
    return 1;
  }
};

// Monkey-patch database module's redisClient
require('../config/database').redisClient = mockRedisClient;

async function setupTestServer() {
  const app = express();
  app.use(express.json());
  
  app.use('/api/v1/billing', billingRouter);
  
  const server = http.createServer(app);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const address = server.address() as any;
  const port = address.port;
  const url = `http://localhost:${port}/api/v1/billing`;
  
  return {
    url,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

async function setupDatabase() {
  console.log('🔄 Cleaning and migrating database for webhook test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

function signPayload(payload: any): string {
  const rawBody = Buffer.from(JSON.stringify(payload));
  return crypto.createHmac('sha256', IYZICO_SECRET).update(rawBody).digest('hex');
}

async function run() {
  await setupDatabase();
  const server = await setupTestServer();
  const client = await pgPool.connect();

  try {
    console.log('🌱 Seeding database with company and invoice...');
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('comp-webhook-test', 'Webhook Co', '1234567890', 'Bebek', 'active')`
    );
    await client.query(
      `INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end)
       VALUES ('sub-webhook-test', 'comp-webhook-test', 'plan-pro', 'past_due', NOW() - INTERVAL '35 days', NOW() - INTERVAL '5 days')`
    );
    await client.query(
      `INSERT INTO invoices (id, company_id, amount, status, payment_gateway_reference)
       VALUES ('inv-webhook-test', 'comp-webhook-test', 299.00, 'unpaid', 'iyz-token-123')`
    );
    await client.query('COMMIT');

    // Scenario 1: Missing signature header
    console.log('🧪 Scenario 1: Rejecting request with missing signature header...');
    const resNoSig = await fetch(`${server.url}/webhook/iyzico`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ iyziReferenceCode: 'event-1' })
    });
    if (resNoSig.status !== 400) {
      throw new Error(`Expected 400, got: ${resNoSig.status}`);
    }
    console.log('  ✔️ Correctly rejected missing signature.');

    // Scenario 2: Stale / missing timestamp (Replay Attack Protection)
    console.log('🧪 Scenario 2: Rejecting request with missing / stale eventTime...');
    const stalePayload = {
      status: 'SUCCESS',
      token: 'iyz-token-123',
      conversationId: 'sub-webhook-test',
      timestamp: Date.now() - 360 * 1000 // 6 minutes old (stale)
    };
    
    const resStale = await fetch(`${server.url}/webhook/iyzico`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-iyz-signature': stalePayload ? signPayload(stalePayload) : ''
      },
      body: JSON.stringify(stalePayload)
    });
    if (resStale.status !== 400) {
      throw new Error(`Expected 400, got: ${resStale.status}`);
    }
    console.log('  ✔️ Correctly rejected stale event timestamp.');

    // Scenario 3: Valid payment webhook success and processing
    console.log('🧪 Scenario 3: Processing valid webhook SUCCESS event...');
    const validPayload = {
      status: 'SUCCESS',
      token: 'iyz-token-123',
      conversationId: 'sub-webhook-test',
      timestamp: Date.now(),
      iyziReferenceCode: 'ref-code-valid-1'
    };

    const resValid = await fetch(`${server.url}/webhook/iyzico`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-iyz-signature': signPayload(validPayload)
      },
      body: JSON.stringify(validPayload)
    });
    
    if (resValid.status !== 200) {
      const txt = await resValid.text();
      throw new Error(`Expected 200, got: ${resValid.status}, response: ${txt}`);
    }
    const validJson = await resValid.json() as any;
    if (validJson.status !== 'OK') {
      throw new Error(`Expected status OK, got: ${validJson.status}`);
    }

    // Verify DB update
    const subCheck = await client.query('SELECT status FROM subscriptions WHERE id = $1', ['sub-webhook-test']);
    const invCheck = await client.query('SELECT status FROM invoices WHERE payment_gateway_reference = $1', ['iyz-token-123']);
    if (subCheck.rows[0].status !== 'active' || invCheck.rows[0].status !== 'paid') {
      throw new Error(`DB updates failed. sub: ${subCheck.rows[0].status}, inv: ${invCheck.rows[0].status}`);
    }
    console.log('  ✔️ Successfully processed payment and activated subscription/entitlements.');

    // Scenario 4: Deduplication / Idempotency check (Re-submitting the same event)
    console.log('🧪 Scenario 4: Webhook deduplication using Redis lock (Idempotency)...');
    const resDuplicate = await fetch(`${server.url}/webhook/iyzico`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-iyz-signature': signPayload(validPayload)
      },
      body: JSON.stringify(validPayload)
    });

    if (resDuplicate.status !== 200) {
      throw new Error(`Expected 200 on duplicate request, got: ${resDuplicate.status}`);
    }
    const dupJson = await resDuplicate.json() as any;
    if (dupJson.message !== 'already_processed') {
      throw new Error(`Expected already_processed, got: ${dupJson.message}`);
    }
    console.log('  ✔️ Correctly bypassed processing and returned already_processed.');

    // Scenario 5: Database processing failure / Redis lock release
    console.log('🧪 Scenario 5: Redis lock cleanup on processing failure...');
    const failPayload = {
      status: 'SUCCESS',
      token: 'iyz-token-fail',
      conversationId: 'sub-fail',
      timestamp: Date.now(),
      iyziReferenceCode: 'ref-code-fail-1'
    };

    // Trigger database failure by dropping the subscriptions table
    await client.query('DROP TABLE subscriptions CASCADE');

    const resFail = await fetch(`${server.url}/webhook/iyzico`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-iyz-signature': signPayload(failPayload)
      },
      body: JSON.stringify(failPayload)
    });

    if (resFail.status !== 500) {
      throw new Error(`Expected 500 on database error, got: ${resFail.status}`);
    }

    // Verify Redis lock key was released (deleted)
    const redisKey = `webhook:processed:ref-code-fail-1`;
    const lockExists = mockRedisDb.has(redisKey);
    if (lockExists) {
      throw new Error('Redis lock key was NOT deleted after database failure!');
    }
    console.log('  ✔️ Redis lock key successfully deleted on database failure.');

    console.log('🏆 AC Webhook Replay Tests: PASS');
    await server.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Webhook Replay Tests: FAIL', err);
    await server.close();
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
