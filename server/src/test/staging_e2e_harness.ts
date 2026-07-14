import { execSync, spawn, ChildProcess } from 'child_process';

import dotenv from 'dotenv';
import path from 'path';

const envFile = process.env.NODE_ENV === 'test' ? '.env.test' : '.env';
dotenv.config({ path: path.resolve(process.cwd(), envFile) });

const PORT = process.env.PORT || 3000;
const BASE_URL = `http://localhost:${PORT}`;

// Test identifiers
const TEST_ID = Date.now().toString();
const TEST_EMAIL = `test-e2e-${TEST_ID}@serenut.com`;
const TEST_PASSWORD = 'SecurePassword123!';
const COMPANY_NAME = `Test Company ${TEST_ID}`;

// Data structures
let jwtToken = '';
let companyId = '';
let userId = '';
let productId = `prod-${TEST_ID}`;
let serverProcess: ChildProcess | null = null;

async function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function waitForServer() {
  console.log('⏳ Waiting for server to start...');
  for (let i = 0; i < 30; i++) {
    try {
      const res = await fetch(`${BASE_URL}/health`);
      if (res.ok) {
        console.log('✅ Server is up and running.');
        return;
      }
    } catch (e) {
      // ignore
    }
    await sleep(1000);
  }
  throw new Error('Server did not start in time.');
}

async function runE2E() {
  console.log('🚀 STARTING API RUNTIME E2E SCENARIO (STAGING HARNESS)');
  console.log('================================================================');

  try {
    // 1. Signup / Registration
    console.log(`\n⏳ STEP 1: Registration (${TEST_EMAIL})`);
    const regRes = await fetch(`${BASE_URL}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: 'E2E User',
        email: TEST_EMAIL,
        password: TEST_PASSWORD,
        company_name: COMPANY_NAME
      })
    });
    if (!regRes.ok) throw new Error(`Registration failed: ${await regRes.text()}`);
    const regData: any = await regRes.json();
    companyId = regData.user?.company_id;
    userId = regData.user?.id;
    jwtToken = regData.access_token;
    console.log('✅ Registration successful. Received JWT token.');

    // 2. Profile Fetch (Verification)
    console.log(`\n⏳ STEP 2: Fetch Profile`);
    const profileRes = await fetch(`${BASE_URL}/api/v1/auth/me`, {
      headers: { 'Authorization': `Bearer ${jwtToken}` }
    });
    if (!profileRes.ok) throw new Error('Profile fetch failed');
    console.log('✅ Token authorization successful. Profile fetched.');

    // 3. Admin State Transition: Suspend Tenant
    console.log(`\n⏳ STEP 3: Admin State Transition - Suspend Company`);
    // Note: We simulate admin DB change directly since we don't have a superadmin JWT handy.
    execSync(`psql "${process.env.DATABASE_URL}" -c "UPDATE companies SET status = 'suspended' WHERE id = '${companyId}'"`);
    console.log('✅ Company suspended in DB.');

    // 4. Verify Access Rejection
    console.log(`\n⏳ STEP 4: Verify Access Rejection (Suspended)`);
    const rejectedRes = await fetch(`${BASE_URL}/api/v1/auth/me`, {
      headers: { 'Authorization': `Bearer ${jwtToken}` }
    });
    if (rejectedRes.ok) throw new Error('Access should have been rejected for suspended tenant!');
    console.log(`✅ Access correctly rejected with status: ${rejectedRes.status}`);

    // 5. Admin State Transition: Reactivate Tenant
    console.log(`\n⏳ STEP 5: Admin State Transition - Reactivate Company`);
    execSync(`psql "${process.env.DATABASE_URL}" -c "UPDATE companies SET status = 'active' WHERE id = '${companyId}'"`);
    console.log('✅ Company reactivated in DB.');

    // 6. Verify Access Recovery
    console.log(`\n⏳ STEP 6: Verify Access Recovery`);
    const recoveredRes = await fetch(`${BASE_URL}/api/v1/auth/me`, {
      headers: { 'Authorization': `Bearer ${jwtToken}` }
    });
    if (!recoveredRes.ok) throw new Error('Access should have been recovered!');
    console.log('✅ Access correctly recovered.');

    // 7. Push a Sale (Sync)
    console.log(`\n⏳ STEP 7: Sync Push (Sale Upload)`);
    const saleId = `sale-${TEST_ID}`;
    const salePayload = {
      id: saleId,
      total_amount: 150.0,
      paid_amount: 150.0,
      payment_method: 'cash',
      status: 'completed',
      idempotency_key: `idem-${TEST_ID}`,
      created_at: new Date().toISOString()
    };

    const saleRes = await fetch(`${BASE_URL}/api/v1/sales/sync`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${jwtToken}` },
      body: JSON.stringify({ sales: [salePayload] })
    });
    
    if (!saleRes.ok) throw new Error(`Sale sync failed: ${await saleRes.text()}`);
    console.log('✅ Sale synced to server successfully.');

    console.log('\n================================================================');
    console.log('🎉 E2E API RUNTIME VERIFIED (STAGING HARNESS): ALL PASSED');
    console.log('================================================================');
    
  } catch (err: any) {
    console.error('\n❌ E2E TEST FAILED:', err.message);
    process.exit(1);
  } finally {
    // Cleanup
    console.log(`\n🧹 Cleaning up generated test data for tenant ${companyId}...`);
    try {
      execSync(`psql "${process.env.DATABASE_URL}" -c "DELETE FROM users WHERE company_id = '${companyId}'"`);
      execSync(`psql "${process.env.DATABASE_URL}" -c "DELETE FROM companies WHERE id = '${companyId}'"`);
    } catch(e) {
      console.log('Cleanup error (non-fatal):', e);
    }
    
    if (serverProcess) {
      serverProcess.kill();
    }
  }
}

async function main() {
  if (process.env.NODE_ENV !== 'test') {
    console.error('❌ FATAL: Harness must run with NODE_ENV=test.');
    process.exit(1);
  }

  const testDbUrl = process.env.TEST_DATABASE_URL;
  if (!testDbUrl) {
    console.error('❌ FATAL: TEST_DATABASE_URL is not set.');
    process.exit(1);
  }
  process.env.DATABASE_URL = testDbUrl;

  console.log('🚀 Spawning background test server...');
  serverProcess = spawn('npx', ['ts-node', 'src/server.ts'], { 
    env: process.env,
    stdio: 'ignore',
    shell: true
  });

  try {
    await waitForServer();
    await runE2E();
  } catch (err) {
    console.error('Harness error:', err);
    if (serverProcess) serverProcess.kill();
    process.exit(1);
  }
}

main();
