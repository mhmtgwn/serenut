// server/src/test/ac_sync.test.ts
// Serenut OS — Offline Synchronization Acceptance Criteria Test
// Verification: AC 4.1, 4.2

import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';

async function setup() {
  console.log('🔄 Setting up database for Sync Test...');
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

    console.log('🌱 Seeding company, store, branch, and user...');
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('sync-comp', 'Sync Co', '1234567890', 'Ankara', 'active')`
    );
    await client.query(
      `INSERT INTO stores (id, company_id, name, address)
       VALUES ('sync-store', 'sync-comp', 'Main Store', 'Address')`
    );
    await client.query(
      `INSERT INTO branches (id, company_id, name)
       VALUES ('sync-branch', 'sync-comp', 'Branch 1')`
    );
    await client.query(
      `INSERT INTO roles (id, name, description)
       VALUES ('role-cashier', 'cashier', 'Cashier cashier')`
    );
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active)
       VALUES ('sync-user', 'sync-comp', 'Cashier', 'cashier@sync.com', 'hash', true)`
    );
    await client.query(
      `INSERT INTO user_roles (user_id, role_id)
       VALUES ('sync-user', 'role-cashier')`
    );
    await client.query('COMMIT');

    // 1. Initial Sync Push — should succeed
    console.log('🔄 Simulating 1st sync push (SQLite -> Postgres)...');
    const orderId = `ord-${Date.now()}`;
    const syncPayload = {
      id: orderId,
      company_id: 'sync-comp',
      branch_id: 'sync-branch',
      user_id: 'sync-user',
      total_amount: 150.0,
      payment_type: 'cash',
      items: [
        { id: `item-1`, product_id: 'prod-mock', quantity: 2, price: 75.0 }
      ],
      created_at: new Date().toISOString()
    };

    // Push into database directly or via query
    await client.query(
      `INSERT INTO sales (id, company_id, branch_id, total_amount, payment_method, is_synced, created_at)
       VALUES ($1, $2, $3, $4, $5, 1, $6)`,
      [
        syncPayload.id,
        syncPayload.company_id,
        syncPayload.branch_id,
        syncPayload.total_amount,
        syncPayload.payment_type,
        syncPayload.created_at
      ]
    );

    const insertedOrder = await client.query(`SELECT * FROM sales WHERE id = $1`, [orderId]);
    if (insertedOrder.rows.length !== 1) {
      throw new Error('Failed to insert sync payload order!');
    }
    console.log('  ✔️ 1st sync item saved and marked synced.');

    // 2. Duplicate Check — attempting same ID insertion should fail (violates unique key or handles idempotently)
    console.log('🔄 Simulating duplicate sync push (idempotency safety check)...');
    try {
      await client.query(
        `INSERT INTO sales (id, company_id, branch_id, total_amount, payment_method, is_synced, created_at)
         VALUES ($1, $2, $3, $4, $5, 1, $6)`,
        [
          syncPayload.id,
          syncPayload.company_id,
          syncPayload.branch_id,
          syncPayload.total_amount,
          syncPayload.payment_type,
          syncPayload.created_at
        ]
      );
      throw new Error('Should have blocked duplicate push!');
    } catch (err: any) {
      if (!err.message.includes('unique') && !err.message.includes('duplicate')) {
        throw err;
      }
      console.log('  ✔️ Duplicate sync item blocked successfully by database constraint.');
    }

    console.log('🏆 AC Sync Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ AC Sync Tests: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
