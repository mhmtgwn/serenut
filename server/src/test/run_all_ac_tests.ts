// server/src/test/run_all_ac_tests.ts
// Serenut OS — Master Go/No-Go Gate Test Runner
// Runs all Acceptance Criteria tests sequentially and outputs the Pilot RC1 approval report.

import dotenv from 'dotenv';
dotenv.config();

import { exec } from 'child_process';
import path from 'path';

// ---------------------------------------------------------
// FAIL-FAST GUARD: DATABASE ISOLATION
// ---------------------------------------------------------
if (process.env.NODE_ENV !== 'test') {
  console.error('❌ FATAL: Test suite must run with NODE_ENV=test.');
  process.exit(1);
}

const testDbUrl = process.env.TEST_DATABASE_URL;
if (!testDbUrl) {
  console.error('❌ FATAL: TEST_DATABASE_URL is not set for tests.');
  process.exit(1);
}

const prodDbUrl = process.env.DATABASE_URL;
if (prodDbUrl && testDbUrl === prodDbUrl) {
  console.error('❌ FATAL: TEST_DATABASE_URL and DATABASE_URL resolve to the same destination. Tests aborted to prevent data loss.');
  process.exit(1);
}

// Check against known production identifiers
const prodIdentifiers = ['serenut.com', 'production', 'prod_db', 'supabase', 'rds.amazonaws.com'];
for (const id of prodIdentifiers) {
  if (testDbUrl.includes(id)) {
    console.error(`❌ FATAL: TEST_DATABASE_URL contains production identifier '${id}'. Tests aborted to prevent data loss.`);
    process.exit(1);
  }
}

// Must explicitly state test or local DB
if (!testDbUrl.includes('test') && !testDbUrl.includes('localhost') && !testDbUrl.includes('127.0.0.1')) {
  console.error('❌ FATAL: TEST_DATABASE_URL does not look like a local or test database. Aborting.');
  process.exit(1);
}

// Override DATABASE_URL for child processes
process.env.DATABASE_URL = testDbUrl;

console.log('✅ DATABASE ISOLATION VERIFIED: Running against safe test environment.');
// ---------------------------------------------------------

const testFiles = [
  'ac_saas_foundation.test.ts',
  'ac_trial.test.ts',
  'ac_license.test.ts',
  'ac_billing.test.ts',
  'ac_sync.test.ts',
  'ac_support.test.ts',
  'ac_monitoring.test.ts',
  'ac_e2e_launch.test.ts',
  'ac_commercial_lifecycle.test.ts',
  'stock_regression.test.ts'
];

function runTest(filename: string): Promise<{ success: boolean; output: string }> {
  return new Promise((resolve) => {
    const filePath = path.join(__dirname, filename);
    console.log(`⏳ Running ${filename}...`);
    
    exec(`npx ts-node "${filePath}"`, { env: process.env }, (error, stdout, stderr) => {
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
