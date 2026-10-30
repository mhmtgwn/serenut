// server/src/test/run_all_ac_tests.ts
// Serenut OS — Master Go/No-Go Gate Test Runner
// Runs all Acceptance Criteria tests sequentially and outputs the Pilot RC1 approval report.

import dotenv from 'dotenv';
dotenv.config();
process.env.NODE_ENV = 'test';

import { exec } from 'child_process';
import path from 'path';
import { assertSafeTestEnvironment } from '../config/test-db-guard';

// ---------------------------------------------------------
// FAIL-FAST GUARD: DATABASE ISOLATION
// ---------------------------------------------------------
const testDbUrl = process.env.TEST_DATABASE_URL;
if (!testDbUrl) {
  console.error('❌ FATAL: TEST_DATABASE_URL is not set for tests.');
  process.exit(1);
}

try {
  const verified = assertSafeTestEnvironment({
    nodeEnv: process.env.NODE_ENV,
    connectionString: testDbUrl,
    baseDatabaseUrl: process.env.DATABASE_URL,
  });
  // Override DATABASE_URL for child processes
  process.env.DATABASE_URL = testDbUrl;
  console.log(`✅ DATABASE ISOLATION VERIFIED: Running against safe test database '${verified.databaseName}'.`);
} catch (guardError: any) {
  console.error(`❌ FATAL: ${guardError?.message}`);
  process.exit(1);
}
// ---------------------------------------------------------

const testFiles = [
  'release_signing_contract.test.ts',
  'security_policy.test.ts',
  'password_recovery_lifecycle.test.ts',
  'ac_saas_foundation.test.ts',
  'ac_trial.test.ts',
  'ac_sync.test.ts',
  'sync_v4_domain_materialization.test.ts',
  'sync_rate_limit_key.test.ts',
  'evolution_api_contract.test.ts',
  'whatsapp_evolution_delivery.test.ts',
  'payment_lifecycle.test.ts',
  'refund_lifecycle.test.ts',
  'notification_credit_reservation.test.ts',
  'web_route_contract.test.ts',
  'schema_contract.test.ts',
  'release_registry.test.ts',
  'ac_support.test.ts',
  'ac_monitoring.test.ts',
  'ac_e2e_launch.test.ts',
  'ac_commercial_lifecycle.test.ts'
];

function runTest(filename: string): Promise<{ success: boolean; output: string }> {
  return new Promise((resolve) => {
    const filePath = path.join(__dirname, filename);
    console.log(`⏳ Running ${filename}...`);
    
    let tsNodeDist = '';
    try {
      tsNodeDist = require.resolve('ts-node/dist/bin.js', { paths: [path.resolve(__dirname, '../..')] });
    } catch {
      tsNodeDist = '';
    }
    const cmd = tsNodeDist
      ? `"${process.execPath}" "${tsNodeDist}" "${filePath}"`
      : `npx --yes ts-node "${filePath}"`;
    exec(cmd, { env: process.env, cwd: path.resolve(__dirname, '../..'), timeout: 45000 }, (error, stdout, stderr) => {
      const output = stdout + stderr;
      if (error) {
        resolve({ success: false, output });
      } else {
        resolve({ success: true, output });
      }
    });
  });
}

async function runAll() {
  console.log('==================================================');
  console.log('🏁 STARTING GO/NO-GO GATE ACCEPTANCE TEST SUITE');
  console.log('==================================================\n');

  const results: { filename: string; success: boolean; output: string }[] = [];
  let allPassed = true;

  for (const file of testFiles) {
    const res = await runTest(file);
    results.push({ filename: file, success: res.success, output: res.output });
    if (res.success) {
      console.log(`  ✅ ${file}: PASS\n`);
    } else {
      console.log(`  ❌ ${file}: FAIL`);
      console.log('--------------------------------------------------');
      console.log(res.output);
      console.log('--------------------------------------------------\n');
      allPassed = false;
    }
  }

  console.log('==================================================');
  console.log('📊 GO/NO-GO GATE FINAL REPORT');
  console.log('==================================================');
  
  results.forEach((r) => {
    console.log(`${r.success ? '✅ PASS' : '❌ FAIL'} | ${r.filename}`);
  });
  
  console.log('==================================================');

  if (allPassed) {
    console.log('\n⭐ Pilot RC2.3 Approved: YES ⭐\n');
    process.exit(0);
  } else {
    console.log('\n❌ Pilot RC2.3 Approved: NO (Fix failing acceptance tests) ❌\n');
    process.exit(1);
  }
}

runAll();
