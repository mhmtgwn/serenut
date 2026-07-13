// server/src/test/admin_entitlements.test.ts
// Serenut OS — Admin Entitlements Integration Test

import express from 'express';
import http from 'http';
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';

// Monkey-patch authentication middleware before importing admin router
require('../middleware/auth.middleware').authenticateUser = (req: any, res: any, next: any) => {
  req.user = { id: 'test-admin-uuid', role: 'sysadmin' };
  next();
};
require('../middleware/auth.middleware').requireRole = (role: string) => (req: any, res: any, next: any) => {
  next();
};

import adminRouter from '../modules/admin/admin.controller';

async function setupTestServer() {
  const app = express();
  app.use(express.json());
  
  app.use('/api/v1/admin', adminRouter);
  
  const server = http.createServer(app);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const address = server.address() as any;
  const port = address.port;
  const url = `http://localhost:${port}/api/v1/admin`;
  
  return {
    url,
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

async function setupDatabase() {
  console.log('🔄 Cleaning and migrating database for entitlements test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

async function run() {
  await setupDatabase();
  const server = await setupTestServer();

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    
    // Seed admin platform company
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('serenut_cloud', 'Serenut Cloud', '0000000000', 'Cloud', 'active')`
    );

    // Seed test company
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('comp-test-ent', 'Test Entitlements Company', '8888888888', 'Nisantasi', 'active')`
    );
    await client.query('COMMIT');

    console.log('🧪 Testing Manual License Creation...');
    // 1. Success case
    const createRes = await fetch(`${server.url}/licenses`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        company_id: 'comp-test-ent',
        tier: 'pro',
        allowed_devices_count: 5,
        expires_in_days: 100
      })
    });
    
    if (createRes.status !== 201) {
      const errTxt = await createRes.text();
      throw new Error(`Expected 201 status, got: ${createRes.status}, body: ${errTxt}`);
    }
    
    const createData = await createRes.json() as any;
    if (!createData.success || !createData.license_key) {
      throw new Error('License key creation response missing key.');
    }
    
    const licenseId = createData.license_id;
    const licenseKey = createData.license_key;
    console.log(`  ✔️ Created license ID: ${licenseId}, key: ${licenseKey}`);

    // Verify both tables have records
    const legacyLic = await client.query('SELECT * FROM licenses WHERE id = $1', [licenseId]);
    const entLic = await client.query('SELECT * FROM license_entitlements WHERE license_key = $1', [licenseKey]);
    
    if (legacyLic.rows.length === 0 || entLic.rows.length === 0) {
      throw new Error('License missing from one of the target tables.');
    }
    if (entLic.rows[0].plan_id !== 'plan-pro' || entLic.rows[0].device_limit !== 5) {
      throw new Error(`Entitlement fields incorrect. Plan ID: ${entLic.rows[0].plan_id}`);
    }
    console.log('  ✔️ Databases both have matching records.');

    // 2. Validate input constraints (negative limits)
    console.log('🧪 Testing input validation constraints...');
    const badRes = await fetch(`${server.url}/licenses`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        company_id: 'comp-test-ent',
        tier: 'pro',
        allowed_devices_count: -1, // invalid limit
        expires_in_days: 10
      })
    });
    if (badRes.status !== 400) {
      throw new Error(`Expected 400 status for invalid device limit, got: ${badRes.status}`);
    }
    console.log('  ✔️ Correctly rejected negative limits.');

    // 3. Test Renew Endpoint
    console.log('🧪 Testing Renew Endpoint...');
    const renewRes = await fetch(`${server.url}/licenses/${licenseId}/renew`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ additional_days: 30 })
    });
    if (renewRes.status !== 200) {
      throw new Error(`Expected 200 status, got: ${renewRes.status}`);
    }
    
    const entLicAfterRenew = await client.query('SELECT * FROM license_entitlements WHERE license_key = $1', [licenseKey]);
    if (entLicAfterRenew.rows[0].token_version !== 2) {
      throw new Error(`Expected token version to be incremented to 2, got: ${entLicAfterRenew.rows[0].token_version}`);
    }
    console.log('  ✔️ Renewed license and verified token version incremented.');

    // 4. Test Suspend Endpoint
    console.log('🧪 Testing Suspend Endpoint...');
    const suspendRes = await fetch(`${server.url}/licenses/${licenseId}/suspend`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ suspend: true })
    });
    if (suspendRes.status !== 200) {
      throw new Error(`Expected 200 status, got: ${suspendRes.status}`);
    }
    
    const legacyLicSuspended = await client.query('SELECT status FROM licenses WHERE id = $1', [licenseId]);
    const entLicSuspended = await client.query('SELECT status FROM license_entitlements WHERE license_key = $1', [licenseKey]);
    if (legacyLicSuspended.rows[0].status !== 'suspended' || entLicSuspended.rows[0].status !== 'suspended') {
      throw new Error('Suspension status mismatch.');
    }
    console.log('  ✔️ Suspended license across both tables.');

    // 5. Test Revoke Endpoint
    console.log('🧪 Testing Revoke Endpoint...');
    // Seed active device activation linked to entitlement
    const entitlementId = entLic.rows[0].id;
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query(
      `INSERT INTO device_activations (id, company_id, entitlement_id, device_hash, device_name, status)
       VALUES ('act-1', 'comp-test-ent', $1, 'dev-hash-test', 'Test Terminal', 'active')`,
      [entitlementId]
    );

    const revokeRes = await fetch(`${server.url}/licenses/${licenseId}/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });
    if (revokeRes.status !== 200) {
      throw new Error(`Expected 200 status, got: ${revokeRes.status}`);
    }

    const legacyLicRevoked = await client.query('SELECT status FROM licenses WHERE id = $1', [licenseId]);
    const entLicRevoked = await client.query('SELECT status FROM license_entitlements WHERE license_key = $1', [licenseKey]);
    const deviceAct = await client.query('SELECT status FROM device_activations WHERE company_id = $1', ['comp-test-ent']);
    
    if (legacyLicRevoked.rows[0].status !== 'revoked' || entLicRevoked.rows[0].status !== 'revoked') {
      throw new Error('Revocation status mismatch.');
    }
    if (deviceAct.rows[0].status !== 'revoked') {
      throw new Error('Device activations were not revoked.');
    }
    console.log('  ✔️ Revoked license and active device activations successfully.');

    console.log('🏆 AC Admin Entitlements Tests: PASS');
    await server.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Admin Entitlements Tests: FAIL', err);
    await server.close();
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
