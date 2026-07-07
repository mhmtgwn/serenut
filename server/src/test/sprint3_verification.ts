import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import { LicenseService } from '../modules/license/license.service';
import { runMigrations } from '../migrations';

async function setupDatabase() {
  console.log('🔄 Cleaning up database schema for Sprint 3...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }

  // Run migrations
  await runMigrations(pgPool);
  console.log('✅ Sprint 3 Database schema generated.');
}

async function seedData() {
  console.log('🌱 Seeding Sprint 3 tenants, users, and licenses...');
  const client = await pgPool.connect();
  try {
    // 1. Create Company
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status) VALUES 
       ('comp-A', 'Tenant A Market', '1111111111', 'Kadıköy V.D.', 'active')`
    );

    // 2. Create Users
    const hashA1 = await AuthService.hashPassword('passA1');
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES 
       ('user-A1', 'comp-A', 'Ahmet Owner A', 'ahmet@owner.com', $1, true)`,
      [hashA1]
    );

    // 3. Create License Key with 2 Allowed Devices
    await client.query(
      `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
       VALUES ('lic-id-1', 'comp-A', 'SRNT-2-DEVS-KEY', 'pro', 2, 'active', CURRENT_TIMESTAMP + INTERVAL '30 days')`
    );

    // 4. Create Expired License Key
    await client.query(
      `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
       VALUES ('lic-id-expired', 'comp-A', 'SRNT-EXPIRED-KEY', 'pro', 1, 'active', CURRENT_TIMESTAMP - INTERVAL '1 day')`
    );

    console.log('✅ Seed data successfully populated.');
  } finally {
    client.release();
  }
}

async function runTests() {
  console.log('\n🧪 --- STARTING SPRINT 3 INTEGRATION TESTS ---');

  // Test 1: Device Binding & Limits
  console.log('\n▶️ Test 1: Device Binding & Limit limits verification...');
  // Activate Device 1
  const act1 = await LicenseService.activate('SRNT-2-DEVS-KEY', 'dev-hash-1', 'Kasa 1');
  if (act1.status !== 'activated' || !act1.signature) {
    throw new Error('Test 1 Failed: Cannot activate Device 1');
  }
  console.log('  ✔️ Device 1 activated successfully.');

  // Activate Device 2
  const act2 = await LicenseService.activate('SRNT-2-DEVS-KEY', 'dev-hash-2', 'Kasa 2');
  if (act2.status !== 'activated') {
    throw new Error('Test 1 Failed: Cannot activate Device 2');
  }
  console.log('  ✔️ Device 2 activated successfully.');

  // Activate Device 3 (Should fail)
  let limitThrown = false;
  try {
    await LicenseService.activate('SRNT-2-DEVS-KEY', 'dev-hash-3', 'Kasa 3');
  } catch (err: any) {
    if (err.message === 'device_limit_exceeded') {
      limitThrown = true;
    }
  }
  if (!limitThrown) {
    throw new Error('Test 1 Failed: Exceeded devices limit but did not throw error');
  }
  console.log('  ✔️ Device 3 activation blocked. Slot limits verified successfully.');

  // Test 2: Heartbeat validation
  console.log('\n▶️ Test 2: Heartbeat Verification...');
  const heartbeat1 = await LicenseService.heartbeat('SRNT-2-DEVS-KEY', 'dev-hash-1');
  if (heartbeat1.status !== 'valid' || !heartbeat1.signature) {
    throw new Error('Test 2 Failed: Heartbeat failed for valid license/device');
  }
  console.log('  ✔️ Heartbeat validated successfully.');

  // Test 3: License Revocation (Banning)
  console.log('\n▶️ Test 3: License Revocation & Device block Verification...');
  await LicenseService.revoke('SRNT-2-DEVS-KEY');

  // Verify license suspended in database
  const licRes = await pgPool.query("SELECT status FROM licenses WHERE license_key = 'SRNT-2-DEVS-KEY'");
  if (licRes.rows[0].status !== 'suspended') {
    throw new Error('Test 3 Failed: License status is not suspended');
  }

  // Verify devices blocked
  const devRes = await pgPool.query("SELECT status FROM devices WHERE device_hash = 'dev-hash-1'");
  if (devRes.rows[0].status !== 'blocked') {
    throw new Error('Test 3 Failed: Associated device was not blocked');
  }

  // Heartbeat query on suspended license must fail
  let heartbeatFailed = false;
  try {
    await LicenseService.heartbeat('SRNT-2-DEVS-KEY', 'dev-hash-1');
  } catch (err: any) {
    if (err.message === 'license_suspended' || err.message === 'device_blocked') {
      heartbeatFailed = true;
    }
  }
  if (!heartbeatFailed) {
    throw new Error('Test 3 Failed: Heartbeat did not fail on revoked license');
  }
  console.log('  ✔️ License revoked. All bound devices blocked and heartbeat denied successfully.');

  // Test 4: License Renewal
  console.log('\n▶️ Test 4: License Renewal Verification...');
  let expiredActFailed = false;
  try {
    // Attempting to activate expired license must fail
    await LicenseService.activate('SRNT-EXPIRED-KEY', 'dev-hash-expired', 'Kasa Expired');
  } catch (err: any) {
    if (err.message === 'license_expired') {
      expiredActFailed = true;
    }
  }
  if (!expiredActFailed) {
    throw new Error('Test 4 Failed: Expired license was activated');
  }

  // Renew the license by 30 days
  const renewRes = await LicenseService.renew('SRNT-EXPIRED-KEY', 30);
  if (renewRes.status !== 'renewed' || !renewRes.signature) {
    throw new Error('Test 4 Failed: Renewal failed');
  }

  // Verify we can now activate the renewed license
  const actRenewed = await LicenseService.activate('SRNT-EXPIRED-KEY', 'dev-hash-expired', 'Kasa Expired');
  if (actRenewed.status !== 'activated') {
    throw new Error('Test 4 Failed: Cannot activate renewed license');
  }
  console.log('  ✔️ License successfully renewed. Expiry extended and validated.');

  console.log('\n🏆 ALL SPRINT 3 LICENSE PLATFORM INTEGRATION TESTS PASSED SUCCESSFULLY! 🏆');
}

async function main() {
  try {
    await setupDatabase();
    await seedData();
    await runTests();
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Sprint 3 Verification Failed:', err);
    process.exit(1);
  }
}

main();
