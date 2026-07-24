// server/src/test/ac_license.test.ts
// Serenut OS — License Acceptance Criteria Test
// Verification: AC 5.1, 5.2, LICENSE103, LICENSE104, LICENSE105, DEVICE502

import { pgPool } from '../config/database';
import { LicenseFSM } from '../modules/license/license.fsm';
import { runMigrations } from '../migrations';

async function setup() {
  console.log('🔄 Setting up database for License Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}
async function run() {
  await setup();

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    console.log('🌱 Seeding companies and licenses...');
    // Seed Company A & B
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status) VALUES
       ('comp-A', 'Sirket A', '1111111111', 'Kadikoy', 'active'),
       ('comp-B', 'Sirket B', '2222222222', 'Cankaya', 'active')`
    );

    // Seed License A (allowed_devices_count = 1, tier = 'BASIC')
    await client.query(
      `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, fsm_state, status, expires_at)
       VALUES ('lic-A', 'comp-A', 'KEY-BASIC-A', 'BASIC', 1, 'unassigned', 'active', '2030-01-01T00:00:00Z')`
    );

    // Seed License B (allowed_devices_count = 3, tier = 'PRO', suspended)
    await client.query(
      `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, fsm_state, status, expires_at)
       VALUES ('lic-B', 'comp-B', 'KEY-PRO-B', 'PRO', 3, 'suspended', 'suspended', '2030-01-01T00:00:00Z')`
    );

    await client.query('COMMIT');

    // Test 1: Cross-Company Lock (LICENSE105)
    console.log('🛡️ Testing Cross-Company lock (LICENSE105)...');
    try {
      await LicenseFSM.activate('KEY-BASIC-A', 'device-hash-B', 'Terminal B', 'comp-B');
      throw new Error('Should have blocked cross-company activation!');
    } catch (err: any) {
      if (err.code !== 'LICENSE105') {
        throw new Error(`Expected error code LICENSE105, got: ${err.code}`);
      }
      console.log('  ✔️ Correctly blocked cross-company binding.');
    }

    // Test 2: Suspension Lock (DEVICE502)
    console.log('🛡️ Testing Suspension lock (DEVICE502)...');
    try {
      await LicenseFSM.activate('KEY-PRO-B', 'device-hash-B', 'Terminal B', 'comp-B');
      throw new Error('Should have blocked suspended license activation!');
    } catch (err: any) {
      if (err.code !== 'DEVICE502') {
        throw new Error(`Expected error code DEVICE502, got: ${err.code}`);
      }
      console.log('  ✔️ Correctly blocked suspended license activation.');
    }

    // Test 3: Normal Activation
    console.log('🛡️ Testing normal activation...');
    const act = await LicenseFSM.activate('KEY-BASIC-A', 'dev-1', 'Device 1', 'comp-A');
    if (act.status !== 'active' || act.slotsAvailable !== 0) {
      throw new Error('Normal activation failed!');
    }
    console.log('  ✔️ Activation successful.');

    // Test 4: Device Capacity Limit (LICENSE103)
    console.log('🛡️ Testing Device Capacity Limit (LICENSE103)...');
    try {
      await LicenseFSM.activate('KEY-BASIC-A', 'dev-2', 'Device 2', 'comp-A');
      throw new Error('Should have blocked capacity overflow!');
    } catch (err: any) {
      if (err.code !== 'LICENSE103') {
        throw new Error(`Expected error code LICENSE103, got: ${err.code}`);
      }
      console.log('  ✔️ Correctly blocked activation above capacity limit.');
    }

    // Test 5: Monthly Swap Limit (LICENSE104)
    console.log('🛡️ Testing Monthly Swap Limit (LICENSE104)...');
    // Deactivate dev-1 (this is swap action #1)
    await LicenseFSM.deactivate('KEY-BASIC-A', 'dev-1', 'comp-A');
    // Activate dev-2 (this is swap action #2)
    await LicenseFSM.activate('KEY-BASIC-A', 'dev-2', 'Device 2', 'comp-A');
    // Deactivate dev-2 (this is swap action #3 - exceeds monthly limit of 2)
    await LicenseFSM.deactivate('KEY-BASIC-A', 'dev-2', 'comp-A');

    try {
      await LicenseFSM.activate('KEY-BASIC-A', 'dev-1', 'Device 1', 'comp-A');
      throw new Error('Should have blocked activation exceeding swap limit!');
    } catch (err: any) {
      if (err.code !== 'LICENSE104') {
        throw new Error(`Expected error code LICENSE104, got: ${err.code}`);
      }
      console.log('  ✔️ Correctly blocked activation exceeding monthly swap limit.');
    }

    console.log('🏆 AC License Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ AC License Tests: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
