// server/src/test/ac_trial.test.ts
// Serenut OS — Trial Acceptance Criteria Test
// Verification: AC 1.2, 1.3

import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
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

    console.log('🌱 Seeding company, subscription and user...');
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('trial-comp', 'Trial Co', '1234567890', 'Ankara', 'active')`
    );

    await client.query(
      `INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end, trial_started_at, trial_ends_at, payment_retry_count)
       VALUES ('sub-trial', 'trial-comp', 'plan-free', 'trialing', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days', NULL, NULL, 0)`
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
    if (initialSub.rows.length === 0) {
      throw new Error('Subscription was not created during company registration!');
    }
    if (initialSub.rows[0].trial_started_at !== null) {
      throw new Error('Trial started date is not null at registration!');
    }
    console.log('  ✔️ Subscription created with trial_started_at = NULL.');

    await client.query('COMMIT');

    // 1st Login — should set trial_started_at
    console.log('🔑 Performing 1st login...');
    const login1 = await AuthService.login('test@trial.com', 'password123');
    if (!login1.trial_started) {
      throw new Error('1st login should flag trial_started = true');
    }

    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const sub1 = await client.query(
      `SELECT status, trial_started_at FROM subscriptions WHERE company_id = 'trial-comp'`
    );
    const start1 = sub1.rows[0].trial_started_at;
    if (start1 === null) {
      throw new Error('trial_started_at is still null after first login');
    }
    if (sub1.rows[0].status !== 'trialing') {
      throw new Error(`Expected subscription status to be 'trialing', got: ${sub1.rows[0].status}`);
    }
    console.log('  ✔️ 1st login started trial successfully at:', start1);
    await client.query('COMMIT');

    // 2nd Login — should NOT overwrite trial_started_at
    console.log('🔑 Performing 2nd login...');
    const login2 = await AuthService.login('test@trial.com', 'password123');
    if (login2.trial_started) {
      throw new Error('2nd login should not flag trial_started = true');
    }

    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const sub2 = await client.query(
      `SELECT status, trial_started_at FROM subscriptions WHERE company_id = 'trial-comp'`
    );
    const start2 = sub2.rows[0].trial_started_at;
    if (start1.getTime() !== start2.getTime()) {
      throw new Error('trial_started_at was modified on second login!');
    }
    console.log('  ✔️ 2nd login preserved original trial start date.');
    await client.query('COMMIT');

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
