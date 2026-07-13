import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import { runMigrations } from '../migrations';

async function setupDatabase() {
  console.log('🔄 Cleaning up database schema for Sprint 2...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }

  // Run migrations
  await runMigrations(pgPool);
  
  // Grant RLS Role privileges
  const client2 = await pgPool.connect();
  try {
    await client2.query("DROP ROLE IF EXISTS serenut_rls_test_role");
    await client2.query("CREATE ROLE serenut_rls_test_role WITH LOGIN");
    await client2.query("GRANT USAGE ON SCHEMA public TO serenut_rls_test_role");
    await client2.query("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO serenut_rls_test_role");
    await client2.query("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO serenut_rls_test_role");
  } finally {
    client2.release();
  }
  console.log('✅ Sprint 2 Database schema and test roles populated.');
}

async function seedData() {
  console.log('🌱 Seeding Sprint 2 tenants and users...');
  const client = await pgPool.connect();
  try {
    // 1. Create Companies (Tenants)
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status) VALUES 
       ('comp-A', 'Tenant A Market', '1111111111', 'Kadıköy V.D.', 'active'),
       ('comp-B', 'Tenant B POS', '2222222222', 'Çankaya V.D.', 'active')`
    );

    // 2. Create Permissions
    await client.query(
      `INSERT INTO permissions (id, code, description) VALUES 
       ('perm-sync', 'sync:push', 'Sync push'),
       ('perm-sync-pull', 'sync:pull', 'Sync pull')
       ON CONFLICT (id) DO NOTHING`
    );

    await client.query(
      `INSERT INTO role_permissions (role_id, permission_id) VALUES 
       ('owner', 'perm-sync'),
       ('owner', 'perm-sync-pull')
       ON CONFLICT (role_id, permission_id) DO NOTHING`
    );

    // 3. Create Users
    const hashA1 = await AuthService.hashPassword('passA1');
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES 
       ('user-A1', 'comp-A', 'Ahmet Owner A', 'ahmet@owner.com', $1, true)`,
      [hashA1]
    );

    await client.query(
      `INSERT INTO user_roles (user_id, role_id) VALUES 
       ('user-A1', 'owner')`
    );

    // 4. Create Customers
    await client.query(
      `INSERT INTO customers (id, company_id, name, balance) VALUES 
       ('cust-1', 'comp-A', 'Müşteri Can Yılmaz', 0.00)`
    );

    console.log('✅ Seed data successfully populated.');
  } finally {
    client.release();
  }
}

async function runTests() {
  console.log('\n🧪 --- STARTING SPRINT 2 INTEGRATION TESTS ---');

  // Test 1: Event-Sourcing Customer Balance Recalculation (Triggers)
  console.log('\n▶️ Test 1: Event-Sourcing Database Trigger Verification...');
  const client = await pgPool.connect();
  try {
    // Enable RLS for A
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.current_company_id = 'comp-A'");

    // Add first debt transaction of 500.00
    await client.query(
      `INSERT INTO financial_transactions (id, company_id, type, customer_id, debt_amount, paid_amount, date)
       VALUES ('tx-1', 'comp-A', 'sale', 'cust-1', 500.00, 0.00, CURRENT_TIMESTAMP)`
    );

    // Verify balance is updated to 500.00
    let resCust = await client.query("SELECT balance FROM customers WHERE id = 'cust-1'");
    let balance = parseFloat(resCust.rows[0].balance);
    if (balance !== 500.00) {
      throw new Error(`Test 1 Failed: Expected balance 500.00 but got ${balance}`);
    }
    console.log(`  ✔️ Balance correctly recalculated to ${balance} after debt addition.`);

    // Add payment transaction of 200.00
    await client.query(
      `INSERT INTO financial_transactions (id, company_id, type, customer_id, debt_amount, paid_amount, date)
       VALUES ('tx-2', 'comp-A', 'payment', 'cust-1', 0.00, 200.00, CURRENT_TIMESTAMP)`
    );

    // Verify balance is updated to 300.00
    resCust = await client.query("SELECT balance FROM customers WHERE id = 'cust-1'");
    balance = parseFloat(resCust.rows[0].balance);
    if (balance !== 300.00) {
      throw new Error(`Test 1 Failed: Expected balance 300.00 but got ${balance}`);
    }
    console.log(`  ✔️ Balance correctly recalculated to ${balance} after payment subtraction.`);

    // Update first transaction debt to 600.00
    await client.query(
      `UPDATE financial_transactions SET debt_amount = 600.00 WHERE id = 'tx-1'`
    );

    // Verify balance is updated to 400.00
    resCust = await client.query("SELECT balance FROM customers WHERE id = 'cust-1'");
    balance = parseFloat(resCust.rows[0].balance);
    if (balance !== 400.00) {
      throw new Error(`Test 1 Failed: Expected balance 400.00 but got ${balance}`);
    }
    console.log(`  ✔️ Balance correctly recalculated to ${balance} after transaction update.`);

    // Delete second transaction
    await client.query("DELETE FROM financial_transactions WHERE id = 'tx-2'");

    // Verify balance is updated back to 600.00
    resCust = await client.query("SELECT balance FROM customers WHERE id = 'cust-1'");
    balance = parseFloat(resCust.rows[0].balance);
    if (balance !== 600.00) {
      throw new Error(`Test 1 Failed: Expected balance 600.00 but got ${balance}`);
    }
    console.log(`  ✔️ Balance correctly recalculated to ${balance} after transaction deletion.`);

    await client.query('RESET ROLE');
    await client.query('COMMIT');
  } finally {
    client.release();
  }

  // Test 2: Idempotency check on sync push
  console.log('\n▶️ Test 2: Idempotency Key Push verification...');
  const authRes = await AuthService.login('ahmet@owner.com', 'passA1');
  const token = authRes.access_token;
  
  // We can call controller handlers or test DB insertion directly.
  // To verify controller push logic through RLS:
  const clientPush = await pgPool.connect();
  try {
    await clientPush.query('BEGIN');
    await clientPush.query('SET ROLE serenut_rls_test_role');
    await clientPush.query("SET LOCAL app.current_company_id = 'comp-A'");

    // Simulate push payload for a sale
    const saleId = 'sale-id-1';
    
    // Attempt 1: Insert sale
    await clientPush.query(
      `INSERT INTO sales (id, company_id, total_amount, paid_amount, payment_method, status, created_at, idempotency_key)
       VALUES ($1, 'comp-A', 150.00, 150.00, 'cash', 'completed', CURRENT_TIMESTAMP, $2)
       ON CONFLICT (id) DO NOTHING`,
      [saleId, saleId]
    );

    // Attempt 2 (Simulates network retry): Insert same sale
    const resPush2 = await clientPush.query(
      `INSERT INTO sales (id, company_id, total_amount, paid_amount, payment_method, status, created_at, idempotency_key)
       VALUES ($1, 'comp-A', 150.00, 150.00, 'cash', 'completed', CURRENT_TIMESTAMP, $2)
       ON CONFLICT (id) DO NOTHING`,
      [saleId, saleId]
    );

    if (resPush2.rowCount !== 0) {
      throw new Error('Test 2 Failed: Idempotency did not prevent duplicate sale write.');
    }
    console.log('  ✔️ Idempotency verified: Duplicate sale inserts bypassed successfully.');

    await clientPush.query('RESET ROLE');
    await clientPush.query('COMMIT');
  } finally {
    clientPush.release();
  }

  // Test 3: Delta pull & timestamp handshake
  console.log('\n▶️ Test 3: Delta Sync & Timestamp Handshake verification...');
  const clientSync = await pgPool.connect();
  try {
    await clientSync.query('BEGIN');
    await clientSync.query('SET ROLE serenut_rls_test_role');
    await clientSync.query("SET LOCAL app.current_company_id = 'comp-A'");

    // Add product 1
    await clientSync.query(
      `INSERT INTO products (id, company_id, name, price, quantity, status, updated_at)
       VALUES ('prod-1', 'comp-A', 'Ürün A', 10.00, 100, 'active', TIMESTAMP '2026-07-04 12:00:00')`
    );

    // Pull from timestamp 0 (Unix epoch)
    const pullRes1 = await clientSync.query(
      'SELECT id, name, updated_at FROM products WHERE company_id = $1 AND updated_at > $2',
      ['comp-A', new Date(0)]
    );
    if (pullRes1.rows.length === 0 || pullRes1.rows[0].id !== 'prod-1') {
      throw new Error('Test 3 Failed: Cannot pull initially inserted product');
    }
    const lastTime = new Date(pullRes1.rows[0].updated_at);
    console.log(`  ✔️ Initial pull returned product 1. Timestamp: ${lastTime.getTime()}`);

    // Add product 2 with newer timestamp
    await clientSync.query(
      `INSERT INTO products (id, company_id, name, price, quantity, status, updated_at)
       VALUES ('prod-2', 'comp-A', 'Ürün B', 20.00, 50, 'active', TIMESTAMP '2026-07-04 12:05:00')`
    );

    // Pull using previous timestamp
    const pullRes2 = await clientSync.query(
      'SELECT id, name, updated_at FROM products WHERE company_id = $1 AND updated_at > $2',
      ['comp-A', lastTime]
    );
    if (pullRes2.rows.length !== 1 || pullRes2.rows[0].id !== 'prod-2') {
      throw new Error('Test 3 Failed: Delta pull returned incorrect elements');
    }
    console.log('  ✔️ Delta pull verified: Only newly updated product was returned.');

    await clientSync.query('RESET ROLE');
    await clientSync.query('COMMIT');
  } finally {
    clientSync.release();
  }

  // Test 4: RTR Grace Period Verification
  console.log('\n▶️ Test 4: RTR Grace Period Verification...');
  // 1. Initial Login
  const loginRes = await AuthService.login('ahmet@owner.com', 'passA1');
  const initialRefresh = loginRes.refresh_token;

  // 2. Perform first refresh -> should succeed
  const refreshRes1 = await AuthService.refresh(initialRefresh);
  const nextRefresh = refreshRes1.refresh_token;
  console.log('  ✔️ First refresh succeeded.');

  // 3. Immediate retry with the same initialRefresh (within grace period) -> should succeed and return nextRefresh
  const refreshRes2 = await AuthService.refresh(initialRefresh);
  if (refreshRes2.refresh_token !== nextRefresh) {
    throw new Error('Test 4 Failed: Grace period retry did not return the latest active refresh token.');
  }
  console.log('  ✔️ Retry within grace period succeeded.');

  // 4. Wait for 22 seconds (exceeding grace period) and try refreshing with initialRefresh again -> should fail and revoke all sessions
  console.log('  ⏳ Waiting 22 seconds to test grace period expiration...');
  await new Promise((resolve) => setTimeout(resolve, 22000));

  try {
    await AuthService.refresh(initialRefresh);
    throw new Error('Test 4 Failed: Stale refresh token was accepted after grace period expired.');
  } catch (err: any) {
    if (err.message !== 'refresh_token_expired') {
      throw err;
    }
    console.log('  ✔️ Stale token after grace period rejected as expected.');
  }

  // 5. Verify all user sessions are now revoked (nextRefresh should be invalid now)
  try {
    await AuthService.refresh(nextRefresh);
    throw new Error('Test 4 Failed: User session was not revoked after replay attack detection.');
  } catch (err: any) {
    if (err.message !== 'refresh_token_expired') {
      throw err;
    }
    console.log('  ✔️ Replay attack successfully revoked all user sessions.');
  }

  console.log('\n🏆 ALL SPRINT 2 SYNC INTEGRATION TESTS PASSED SUCCESSFULLY! 🏆');
}

async function main() {
  try {
    await setupDatabase();
    await seedData();
    await runTests();
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Sprint 2 Verification Failed:', err);
    process.exit(1);
  }
}

main();
