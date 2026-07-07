// server/src/test/run_all_ac_tests.ts
// Serenut OS — Master Go/No-Go Gate Test Runner
// Runs all Acceptance Criteria tests sequentially and outputs the Pilot RC1 approval report.

import dotenv from 'dotenv';
dotenv.config();

import { exec } from 'child_process';
import path from 'path';

const testFiles = [
  'ac_trial.test.ts',
  'ac_license.test.ts',
  'ac_billing.test.ts',
  'ac_sync.test.ts',
  'ac_support.test.ts',
  'ac_monitoring.test.ts',
  'ac_e2e_launch.test.ts'
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
    console.log('\n⭐ Pilot RC1 Approved: YES ⭐\n');
    process.exit(0);
  } else {
    console.log('\n❌ Pilot RC1 Approved: NO (Fix failing acceptance tests) ❌\n');
    process.exit(1);
  }
}

runAll();
