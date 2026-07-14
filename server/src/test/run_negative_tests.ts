import { exec } from 'child_process';
import path from 'path';
import fs from 'fs';

const precheckScript = path.join(__dirname, '../scripts/deployment-precheck.ts');
const envPath = path.join(__dirname, '../../.env');
const backupEnvPath = path.join(__dirname, '../../.env.backup');

function runWithEnv(envMap: Record<string, string>, expectFailure: boolean, name: string): Promise<boolean> {
  return new Promise((resolve) => {
    console.log(`⏳ Testing: ${name}...`);
    // Inject mock environment
    const testEnv = { ...process.env, ...envMap };
    
    exec(`npx ts-node "${precheckScript}"`, { env: testEnv }, (error, stdout, stderr) => {
      const output = stdout + stderr;
      const didFail = error !== null && error.code !== 0;
      
      if (expectFailure && didFail) {
        console.log(`  ✅ PASS: correctly rejected. Exit code: ${error.code}`);
        resolve(true);
      } else if (!expectFailure && !didFail) {
        console.log(`  ✅ PASS: correctly accepted.`);
        resolve(true);
      } else {
        console.log(`  ❌ FAIL: Expected failure: ${expectFailure}, but got failure: ${didFail}`);
        console.log(`  --- OUTPUT ---\n${output}\n  --------------`);
        resolve(false);
      }
    });
  });
}

async function runNegativeTests() {
  console.log('==================================================');
  console.log('🛡️ RUNNING NEGATIVE CONFIGURATION TESTS');
  console.log('==================================================\n');

  // Backup and remove .env so dotenvx doesn't override our injects
  if (fs.existsSync(envPath)) {
    fs.copyFileSync(envPath, backupEnvPath);
    fs.unlinkSync(envPath);
  }

  let allPassed = true;

  try {
    // 1. Missing JWT Secret
    allPassed = await runWithEnv({ 
      NODE_ENV: 'production', 
      JWT_SECRET: '',
      DATABASE_URL: 'postgres://test:test@127.0.0.1:5432/test_db',
      REDIS_URL: 'redis://127.0.0.1:6379',
      SMS_API_KEY: 'valid_key',
    }, true, 'Missing JWT Secret') && allPassed;

    // 2. Weak/Default JWT Secret
    allPassed = await runWithEnv({ 
      NODE_ENV: 'production', 
      JWT_SECRET: 'REPLACE_WITH_OPENSSL_RAND_HEX_64_OUTPUT',
      DATABASE_URL: 'postgres://test:test@127.0.0.1:5432/test_db',
      REDIS_URL: 'redis://127.0.0.1:6379',
      SMS_API_KEY: 'valid_key',
      SMTP_HOST: 'smtp.sendgrid.net',
      SMTP_USER: 'apikey',
    }, true, 'Weak JWT Secret (Default)') && allPassed;

    // 3. Mock SMS Credentials
    allPassed = await runWithEnv({ 
      NODE_ENV: 'production', 
      JWT_SECRET: 'super_secure_jwt_secret_which_is_long_enough_for_32_bytes_!@#',
      DATABASE_URL: 'postgres://test:test@127.0.0.1:5432/test_db',
      REDIS_URL: 'redis://127.0.0.1:6379',
      SMS_API_KEY: 'mock_sms_api_key_for_testing',
      SMTP_HOST: 'smtp.sendgrid.net',
      SMTP_USER: 'apikey',
    }, true, 'Mock SMS Credentials') && allPassed;

    // 4. Mock Email Credentials (Mailtrap)
    allPassed = await runWithEnv({ 
      NODE_ENV: 'production', 
      JWT_SECRET: 'super_secure_jwt_secret_which_is_long_enough_for_32_bytes_!@#',
      DATABASE_URL: 'postgres://test:test@127.0.0.1:5432/test_db',
      REDIS_URL: 'redis://127.0.0.1:6379',
      SMS_API_KEY: 'valid_key_here',
      SMTP_HOST: 'smtp.mailtrap.io',
      SMTP_USER: 'testuser',
    }, true, 'Mock Email Credentials (Mailtrap)') && allPassed;

    // 5. Unsafe Development Flags
    allPassed = await runWithEnv({ 
      NODE_ENV: 'production', 
      JWT_SECRET: 'super_secure_jwt_secret_which_is_long_enough_for_32_bytes_!@#',
      DATABASE_URL: 'postgres://test:test@127.0.0.1:5432/test_db',
      REDIS_URL: 'redis://127.0.0.1:6379',
      SMS_API_KEY: 'valid_key_here',
      SMTP_HOST: 'smtp.sendgrid.net',
      SMTP_USER: 'apikey',
      BYPASS_AUTH: 'true',
    }, true, 'Unsafe Development Flags (BYPASS_AUTH)') && allPassed;

  } finally {
    // Restore .env
    if (fs.existsSync(backupEnvPath)) {
      fs.copyFileSync(backupEnvPath, envPath);
      fs.unlinkSync(backupEnvPath);
    }
  }

  console.log('\n==================================================');
  if (allPassed) {
    console.log('🎉 ALL NEGATIVE TESTS PASSED.');
    process.exit(0);
  } else {
    console.log('❌ SOME NEGATIVE TESTS FAILED.');
    process.exit(1);
  }
}

runNegativeTests();
