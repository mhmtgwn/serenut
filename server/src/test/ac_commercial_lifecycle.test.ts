// server/src/test/ac_commercial_lifecycle.test.ts
// Serenut OS — Onboarding & Commercial Entitlement Lifecycle Adversarial Test

import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { AuthService } from '../modules/auth/auth.service';
import { LicenseService } from '../modules/license/license.service';
import { CommercialLifecycleService } from '../modules/billing/commercial_lifecycle.service';

async function setup() {
  console.log('🔄 Setting up database for Commercial Lifecycle Integration Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

async function runAdversarialTest() {
  await setup();

  const companyId = `comp-adv-${Date.now()}`;
  const ownerEmail = `owner-${Date.now()}@test.com`;
  const ownerPassword = 'Password123!';
  const companyName = 'Adversarial Trial Market';

  console.log('🌱 Step 1: Simulating Web Registration targeting "Professional" (Pro) plan...');
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Insert user and company using the exact business logic inside registration
    const passwordHash = await AuthService.hashPassword(ownerPassword);
    const taxNumber = `TAX-${Date.now()}`;
    await client.query(
      "INSERT INTO companies (id, name, tax_number, status) VALUES ($1, $2, $3, 'active')",
      [companyId, companyName, taxNumber]
    );

    const userId = `usr-adv-${Date.now()}`;
    await client.query(
      "INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES ($1, $2, $3, $4, $5, true)",
      [userId, companyId, 'Test Owner', ownerEmail, passwordHash]
    );

    await client.query("INSERT INTO roles (id, name) VALUES ('owner', 'owner') ON CONFLICT DO NOTHING");
    await client.query(
      "INSERT INTO user_roles (user_id, role_id) VALUES ($1, 'owner')",
      [userId]
    );

    // Create subscription storing selected plan target ('plan-pro' / growth)
    const subId = `sub-adv-${Date.now()}`;
    await client.query(
      `INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end)
       VALUES ($1, $2, 'plan-pro', 'trialing', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days')`,
      [subId, companyId]
    );

    // Enforce that trial starts with plan-free limits (1 device)
    const licenseKey = 'KEY-ADV-TRIAL-123';
    await client.query(`
      INSERT INTO license_entitlements (id, company_id, subscription_id, plan_id, status, device_limit, store_limit, valid_from, valid_until, license_key)
      VALUES ($1, $2, $3, 'plan-free', 'trial', 1, 1, NOW(), NOW() + INTERVAL '30 days', $4)
    `, [`ent-adv-${Date.now()}`, companyId, subId, licenseKey]);

    await client.query(`
      INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
      VALUES ($1, $2, $3, 'trial', 1, 'active', NOW() + INTERVAL '30 days')
    `, [`lic-adv-${Date.now()}`, companyId, licenseKey]);

    await client.query('COMMIT');
    console.log('  ✔️ Trial provisioning (limited to 1 device) complete.');

    console.log('🌱 Step 2: Simulating POS Device Activation 1...');
    const actRes1 = await LicenseService.activate(licenseKey, 'dev-hash-adv-1', 'Cashier 1', companyId);
    if (actRes1.status !== 'activated') {
      throw new Error('Device 1 activation failed!');
    }
    console.log('  ✔️ Device 1 activated successfully.');

    console.log('🌱 Step 3: Simulating POS Device Activation 2 (Adversarial test: should fail!)...');
    try {
      await LicenseService.activate(licenseKey, 'dev-hash-adv-2', 'Cashier 2', companyId);
      throw new Error('Adversarial Test Failed: Pro limit features accessed without payment/approval!');
    } catch (err: any) {
      if (err.message === 'device_limit_exceeded') {
        console.log('  ✔️ Success: Activation rejected with "device_limit_exceeded" as expected.');
      } else {
        throw err;
      }
    }

    console.log('🌱 Step 4: Simulating Admin Bank Wire Approval of Subscription upgrade...');
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await CommercialLifecycleService.activatePaidSubscription(client, {
      companyId,
      planId: 'plan-pro',
      grantType: 'bank_transfer',
    });
    await client.query('COMMIT');
    console.log('  ✔️ Admin approval simulation complete.');

    console.log('🌱 Step 5: Simulating POS Device Activation 2 again (should now succeed!)...');
    const actRes2 = await LicenseService.activate(licenseKey, 'dev-hash-adv-2', 'Cashier 2', companyId);
    if (actRes2.status !== 'activated') {
      throw new Error('Device 2 activation failed after upgrade approval!');
    }
    console.log('  ✔️ Device 2 activated successfully after upgrade!');

    console.log('🏆 COMMERCIAL LIFECYCLE ADVERSARIAL INTEGRATION TEST: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ COMMERCIAL LIFECYCLE ADVERSARIAL INTEGRATION TEST: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runAdversarialTest();
