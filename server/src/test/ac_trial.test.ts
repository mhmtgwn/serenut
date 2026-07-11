// server/src/test/ac_trial.test.ts
// Serenut OS — Trial Acceptance Criteria Test
// Verification: AC 1.2, 1.3

import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import { LicenseService } from '../modules/license/license.service';
import { runMigrations } from '../migrations';

async function setup() {
  console.log('🔄 Setting up database for Trial Test...');
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

    console.log('🌱 Seeding company, subscription, license, entitlement, and user...');
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('trial-comp', 'Trial Co', '1234567890', 'Ankara', 'active')`
    );

    await client.query(
      `INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end, trial_started_at, trial_ends_at, payment_retry_count)
       VALUES ('sub-trial', 'trial-comp', 'plan-free', 'inactive', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days', NULL, NULL, 0)`
    );

    await client.query(
      `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
       VALUES ('lic-trial', 'trial-comp', 'trial-key-123', 'pro', 2, 'active', CURRENT_TIMESTAMP + INTERVAL '30 days')`
    );

    await client.query(
      `INSERT INTO license_entitlements (id, company_id, subscription_id, plan_id, status, device_limit, store_limit, valid_from, valid_until, license_key)
       VALUES ('ent-trial', 'trial-comp', 'sub-trial', 'plan-free', 'trial', 2, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days', 'trial-key-123')`
    );

    const hash = await AuthService.hashPassword('password123');
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active)
       VALUES ('trial-user', 'trial-comp', 'Test User', 'test@trial.com', $1, true)`,
      [hash]
    );

    // Initial state check
    const initialSub = await client.query(
      `SELECT status, trial_started_at FROM subscriptions WHERE company_id = 'trial-comp'`
    );
    if (initialSub.rows[0].trial_started_at !== null) {
      throw new Error('Trial started date is not null at registration!');
    }
    console.log('  ✔️ Subscription created with trial_started_at = NULL.');

    await client.query('COMMIT');

    // Login — trial should NOT start yet (should remain NULL)
    console.log('🔑 Performing login (should not start trial)...');
    const loginResponse = await AuthService.login('test@trial.com', 'password123');
    if (loginResponse.trial_started) {
      throw new Error('Login should not start trial anymore!');
    }

    const midSub = await pgPool.query(
      `SELECT status, trial_started_at FROM subscriptions WHERE company_id = 'trial-comp'`
    );
    if (midSub.rows[0].trial_started_at !== null) {
      throw new Error('Trial started date was incorrectly set on login!');
    }
    console.log('  ✔️ Login did not start the trial.');

    // POS Activation — this should start the trial
    console.log('📱 Performing POS Activation (should start trial)...');
    const activationResult = await LicenseService.activate(
      'trial-key-123',
      'dev-hash-test-trial',
      'Trial Device',
      'trial-comp'
    );

    if (activationResult.status !== 'activated') {
      throw new Error('License activation failed!');
    }

    const postSub = await pgPool.query(
      `SELECT status, trial_started_at FROM subscriptions WHERE company_id = 'trial-comp'`
    );
    if (postSub.rows[0].trial_started_at === null) {
      throw new Error('Trial started date is still null after device activation!');
    }
    if (postSub.rows[0].status !== 'trialing') {
      throw new Error(`Expected subscription status to be 'trialing', got: ${postSub.rows[0].status}`);
    }

    console.log('  ✔️ Trial successfully started on POS device activation at:', postSub.rows[0].trial_started_at);
    console.log('🏆 AC Trial Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Trial Tests: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
