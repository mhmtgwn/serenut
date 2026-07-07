// server/src/test/ac_billing.test.ts
// Serenut OS — Billing / Subscription Acceptance Criteria Test
// Verification: AC 2.2, 2.3, FSM transitions (active -> past_due -> canceled)

import { pgPool } from '../config/database';
import { SubscriptionService } from '../modules/subscription/subscription.service';
import { runMigrations } from '../migrations';

async function setup() {
  console.log('🔄 Setting up database for Billing Test...');
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

    console.log('🌱 Seeding company...');
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('billing-comp', 'Billing Tenant', '9999999999', 'Uskudar', 'active')`
    );

    await client.query(
      `INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end, trial_started_at, trial_ends_at, payment_retry_count)
       VALUES ('sub-billing', 'billing-comp', 'plan-free', 'trialing', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days', NULL, NULL, 0)`
    );

    await client.query('COMMIT');

    // Initial state check
    const initialSub = await client.query(
      `SELECT status FROM subscriptions WHERE company_id = 'billing-comp'`
    );
    if (initialSub.rows[0].status !== 'trialing') {
      throw new Error(`Expected initial status to be 'trialing', got: ${initialSub.rows[0].status}`);
    }
    console.log('  ✔️ Initial state is trialing.');

    // 1. Transition: trialing -> active
    console.log('🔔 Transitioning: trialing -> active...');
    await SubscriptionService.transition('billing-comp', 'active');

    const activeSub = await client.query(
      `SELECT status FROM subscriptions WHERE company_id = 'billing-comp'`
    );
    if (activeSub.rows[0].status !== 'active') {
      throw new Error(`Expected status to become 'active', got: ${activeSub.rows[0].status}`);
    }
    console.log('  ✔️ Subscription is now ACTIVE.');

    // 2. Transition: active -> past_due
    console.log('🔔 Transitioning: active -> past_due...');
    await SubscriptionService.transition('billing-comp', 'past_due');

    const pastDueSub = await client.query(
      `SELECT status FROM subscriptions WHERE company_id = 'billing-comp'`
    );
    if (pastDueSub.rows[0].status !== 'past_due') {
      throw new Error(`Expected status to become 'past_due', got: ${pastDueSub.rows[0].status}`);
    }
    console.log('  ✔️ Subscription transitioned to PAST_DUE.');

    // 3. Transition: past_due -> active (re-activation scenario)
    console.log('🔔 Transitioning: past_due -> active...');
    await SubscriptionService.transition('billing-comp', 'active');
    const reactivedSub = await client.query(
      `SELECT status FROM subscriptions WHERE company_id = 'billing-comp'`
    );
    if (reactivedSub.rows[0].status !== 'active') {
      throw new Error(`Expected status to become 'active', got: ${reactivedSub.rows[0].status}`);
    }
    console.log('  ✔️ Subscription re-activated back to ACTIVE.');

    // 4. Transition: active -> cancelled
    console.log('🔔 Transitioning: active -> cancelled...');
    await SubscriptionService.transition('billing-comp', 'cancelled');

    const canceledSub = await client.query(
      `SELECT status FROM subscriptions WHERE company_id = 'billing-comp'`
    );
    if (canceledSub.rows[0].status !== 'cancelled') {
      throw new Error(`Expected status to become 'cancelled', got: ${canceledSub.rows[0].status}`);
    }
    console.log('  ✔️ Subscription transitioned to CANCELLED.');

    console.log('🏆 AC Billing Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Billing Tests: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
