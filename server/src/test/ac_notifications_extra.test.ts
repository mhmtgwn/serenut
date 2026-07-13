// server/src/test/ac_notifications_extra.test.ts
// Serenut OS — Sync Local Idempotency & Queue RBAC Acceptance Criteria Test

import dotenv from 'dotenv';
import path from 'path';

// Force environment variables setup
dotenv.config();

import express from 'express';
import http from 'http';
import jwt from 'jsonwebtoken';
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import notificationRouter from '../modules/notification/notification.controller';
import telemetryRouter from '../modules/analytics/telemetry.controller';

const JWT_SECRET = process.env.JWT_SECRET || 'test_jwt_secret_must_be_32_characters_minimum';
process.env.JWT_SECRET = JWT_SECRET;

const PORT = 4099;
let passed = 0;
let failed = 0;

function assert(condition: boolean, testName: string, details?: string) {
  if (condition) {
    console.log(`  ✔️  ${testName}`);
    passed++;
  } else {
    console.error(`  ❌ ${testName}${details ? ': ' + details : ''}`);
    failed++;
  }
}

async function setupDatabase() {
  console.log('🔄 Cleaning up database schema for Notifications Extra Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    console.log('✅ Public schema reset.');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

async function seedData() {
  console.log('🌱 Seeding roles, permissions, users, and company context...');
  const client = await pgPool.connect();
  try {
    // 1. Seed Company
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('test-comp', 'Deduplication Corp', '9999999999', 'Kadıköy', 'active')`
    );

    // 2. Seed Users
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active, token_version) VALUES
       ('user-admin', 'test-comp', 'Admin User', 'admin@dedup.com', 'mock', true, 1),
       ('user-cashier', 'test-comp', 'Cashier User', 'cashier@dedup.com', 'mock', true, 1)`
    );

    // 3. Map Users to Roles
    await client.query(
      `INSERT INTO user_roles (user_id, role_id) VALUES
       ('user-admin', 'owner'),
       ('user-cashier', 'cashier')`
    );

    // 4. Seed permissions
    await client.query(
      `INSERT INTO permissions (id, code, description) VALUES
       ('perm-history-read', 'notifications.history.read', 'SMS and Notification History Read'),
       ('perm-telemetry-view', 'telemetry.view', 'System Telemetry and Audit Logs Read'),
       ('perm-campaign-send', 'notifications.campaign.send', 'Send campaigns'),
       ('perm-templates-manage', 'notifications.templates.manage', 'Manage notification templates')
       ON CONFLICT (code) DO NOTHING`
    );

    // 5. Map Roles to Permissions
    await client.query(
      `INSERT INTO role_permissions (role_id, permission_id)
       SELECT 'owner', id FROM permissions WHERE code IN ('notifications.history.read', 'telemetry.view', 'notifications.campaign.send', 'notifications.templates.manage')
       ON CONFLICT DO NOTHING`
    );

    console.log('✅ Seed data successfully populated.');
  } finally {
    client.release();
  }
}

async function main() {
  try {
    await setupDatabase();
    await seedData();

    // Start local Express server
    console.log('📡 Launching express test server...');
    const app = express();
    app.use(express.json());
    app.use('/api/v1/notifications', notificationRouter);
    app.use('/api/v1/telemetry', telemetryRouter);

    const server = http.createServer(app);
    await new Promise<void>((resolve) => server.listen(PORT, resolve));
    console.log(`📡 Express test server listening on port ${PORT}`);

    // Generate JWT tokens
    const adminToken = jwt.sign(
      {
        jti: 'jti-admin',
        id: 'user-admin',
        name: 'Admin User',
        email: 'admin@dedup.com',
        company_id: 'test-comp',
        roles: ['owner'],
        permissions: ['notifications.history.read', 'telemetry.view', 'notifications.campaign.send', 'notifications.templates.manage'],
        token_version: 1,
      },
      JWT_SECRET,
      { expiresIn: '15m', issuer: 'serenut.com', audience: 'serenut-pos' }
    );

    const cashierToken = jwt.sign(
      {
        jti: 'jti-cashier',
        id: 'user-cashier',
        name: 'Cashier User',
        email: 'cashier@dedup.com',
        company_id: 'test-comp',
        roles: ['cashier'],
        permissions: [],
        token_version: 1,
      },
      JWT_SECRET,
      { expiresIn: '15m', issuer: 'serenut.com', audience: 'serenut-pos' }
    );

    // Test 1: Deduplication (Idempotency) via /sync-local (Concurrent Race Condition Check)
    console.log('\n▶️ Test 1: sync-local idempotency test (10 concurrent requests)...');
    const clientMessageId = `msg-id-race-${Date.now()}`;

    const requests = Array.from({ length: 10 }).map(() =>
      fetch(`http://localhost:${PORT}/api/v1/notifications/sync-local`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${adminToken}`,
        },
        body: JSON.stringify({
          recipient: '5551234567',
          body: 'Merhaba bu bir test mesajıdır.',
          status: 'sent',
          client_message_id: clientMessageId,
          channel: 'sms',
        }),
      })
    );

    const responses = await Promise.all(requests);
    const results = await Promise.all(responses.map((r) => r.json() as Promise<any>));

    let deduplicatedFalseCount = 0;
    let deduplicatedTrueCount = 0;
    let successfulStatuses = 0;

    for (let i = 0; i < responses.length; i++) {
      if (responses[i].status === 201) {
        successfulStatuses++;
      }
      const data = results[i];
      if (data.success === true) {
        if (data.deduplicated === false) {
          deduplicatedFalseCount++;
          assert(data.queue_id !== null, `Winner request returned queue_id: ${data.queue_id}`);
        } else if (data.deduplicated === true) {
          deduplicatedTrueCount++;
          assert(data.queue_id === null, 'Deduplicated request returned queue_id: null');
        }
      }
    }

    assert(successfulStatuses === 10, `All 10 concurrent requests returned 201 status (actual: ${successfulStatuses})`);
    assert(deduplicatedFalseCount === 1, `Exactly 1 request registered successfully (actual: ${deduplicatedFalseCount})`);
    assert(deduplicatedTrueCount === 9, `Exactly 9 requests were deduplicated (actual: ${deduplicatedTrueCount})`);

    // DB verification of single record insertion
    const dbCountRes = await pgPool.query(
      "SELECT COUNT(*) FROM notification_queue WHERE client_message_id = $1",
      [clientMessageId]
    );
    const dbCount = parseInt(dbCountRes.rows[0].count, 10);
    assert(dbCount === 1, `DB count for client_message_id = 1 (actual: ${dbCount})`);

    // Test 2: GET /queue authorization (RBAC)
    console.log('\n▶️ Test 2: GET /queue authorization checks...');

    // GET /queue with Cashier (Should fail with 403)
    const resGetCashier = await fetch(`http://localhost:${PORT}/api/v1/notifications/queue`, {
      headers: {
        'Authorization': `Bearer ${cashierToken}`,
      },
    });
    assert(resGetCashier.status === 403, 'GET /queue with Cashier token returns 403 Forbidden');
    const errorCashier: any = await resGetCashier.json();
    assert(errorCashier.error === 'forbidden', 'GET /queue with Cashier token returns error: forbidden');

    // GET /queue with Admin (Should succeed with 200)
    const resGetAdmin = await fetch(`http://localhost:${PORT}/api/v1/notifications/queue`, {
      headers: {
        'Authorization': `Bearer ${adminToken}`,
      },
    });
    assert(resGetAdmin.status === 200, 'GET /queue with Admin token returns 200 OK');
    const listAdmin: any = await resGetAdmin.json();
    assert(Array.isArray(listAdmin), 'GET /queue with Admin token returns array list');

    // GET /queue without token (Should fail with 401)
    const resGetNoToken = await fetch(`http://localhost:${PORT}/api/v1/notifications/queue`);
    assert(resGetNoToken.status === 401, 'GET /queue without token returns 401 Unauthorized');

    // Test 3: Telemetry Router authorization checks
    console.log('\n▶️ Test 3: Telemetry Router authorization checks...');

    // GET /health-status with Cashier (Should fail with 403)
    const resTelHealthCashier = await fetch(`http://localhost:${PORT}/api/v1/telemetry/health-status`, {
      headers: { 'Authorization': `Bearer ${cashierToken}` },
    });
    assert(resTelHealthCashier.status === 403, 'GET /telemetry/health-status with Cashier token returns 403 Forbidden');

    // GET /health-status with Admin (Should succeed with 200)
    const resTelHealthAdmin = await fetch(`http://localhost:${PORT}/api/v1/telemetry/health-status`, {
      headers: { 'Authorization': `Bearer ${adminToken}` },
    });
    assert(resTelHealthAdmin.status === 200, 'GET /telemetry/health-status with Admin token returns 200 OK');

    // GET /audit-logs with Cashier (Should fail with 403)
    const resTelLogsCashier = await fetch(`http://localhost:${PORT}/api/v1/telemetry/audit-logs`, {
      headers: { 'Authorization': `Bearer ${cashierToken}` },
    });
    assert(resTelLogsCashier.status === 403, 'GET /telemetry/audit-logs with Cashier token returns 403 Forbidden');

    // GET /audit-logs with Admin (Should succeed with 200)
    const resTelLogsAdmin = await fetch(`http://localhost:${PORT}/api/v1/telemetry/audit-logs`, {
      headers: { 'Authorization': `Bearer ${adminToken}` },
    });
    assert(resTelLogsAdmin.status === 200, 'GET /telemetry/audit-logs with Admin token returns 200 OK');


    // Test 4: Campaign and Template Router authorization checks
    console.log('\n▶️ Test 4: Campaign and Template authorization checks...');

    // POST /campaign with Cashier (Should fail with 403)
    const resCampCashier = await fetch(`http://localhost:${PORT}/api/v1/notifications/campaign`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${cashierToken}`,
      },
      body: JSON.stringify({ segment: 'all_customers', channel: 'sms', template_name: 'test' }),
    });
    assert(resCampCashier.status === 403, 'POST /notifications/campaign with Cashier token returns 403 Forbidden');

    // POST /campaign with Admin (Should pass validation and return 404 template_not_found instead of 403)
    const resCampAdmin = await fetch(`http://localhost:${PORT}/api/v1/notifications/campaign`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${adminToken}`,
      },
      body: JSON.stringify({ segment: 'all_customers', channel: 'sms', template_name: 'test' }),
    });
    assert(resCampAdmin.status === 404, 'POST /notifications/campaign with Admin token passes auth and returns 404 (template not found)');

    // POST /templates with Cashier (Should fail with 403)
    const resTplCashier = await fetch(`http://localhost:${PORT}/api/v1/notifications/templates`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${cashierToken}`,
      },
      body: JSON.stringify({ name: 'tpl', channel: 'sms', body: 'hello' }),
    });
    assert(resTplCashier.status === 403, 'POST /notifications/templates with Cashier token returns 403 Forbidden');

    // POST /templates with Admin (Should succeed with 200 OK)
    const resTplAdmin = await fetch(`http://localhost:${PORT}/api/v1/notifications/templates`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${adminToken}`,
      },
      body: JSON.stringify({ name: 'tpl', channel: 'sms', body: 'hello' }),
    });
    assert(resTplAdmin.status === 200, 'POST /notifications/templates with Admin token returns 200 OK');

    console.log('\nStopping express test server...');
    await new Promise<void>((resolve) => server.close(() => resolve()));

    console.log('\n==================================================');
    console.log(`📊 TEST RESULTS: ${passed} PASSED, ${failed} FAILED`);
    console.log('==================================================');

    if (failed > 0) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  } catch (err) {
    console.error('\n❌ Extra Notification Acceptance Criteria Test Failed:', err);
    process.exit(1);
  }
}

main();
