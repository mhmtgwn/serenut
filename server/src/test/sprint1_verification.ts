import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import { runMigrations } from '../migrations';

async function setupDatabase() {
  console.log('🔄 Cleaning up database schema...');
  const client = await pgPool.connect();
  try {
    // Force drop all existing tables to guarantee 100% clean test environment
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    console.log('✅ Public schema reset.');
  } finally {
    client.release();
  }

  // Run migrations to create schema
  await runMigrations(pgPool);
  
  // Create non-superuser role for testing PostgreSQL Row Level Security (RLS)
  const client2 = await pgPool.connect();
  try {
    await client2.query("DROP ROLE IF EXISTS serenut_rls_test_role");
    await client2.query("CREATE ROLE serenut_rls_test_role WITH LOGIN");
    await client2.query("GRANT USAGE ON SCHEMA public TO serenut_rls_test_role");
    await client2.query("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO serenut_rls_test_role");
    await client2.query("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO serenut_rls_test_role");
    await client2.query("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO serenut_rls_test_role");
  } finally {
    client2.release();
  }
  console.log('✅ Master schema v1.0 and RLS test role generated successfully.');
}

async function seedData() {
  console.log('🌱 Seeding mock tenants, users, roles, and stores...');
  const client = await pgPool.connect();
  try {
    // 1. Create Companies (Tenants)
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status) VALUES 
       ('comp-A', 'Tenant A Market', '1111111111', 'Kadıköy V.D.', 'active'),
       ('comp-B', 'Tenant B POS', '2222222222', 'Çankaya V.D.', 'active')`
    );

    // 2. Create Roles
    await client.query(
      `INSERT INTO roles (id, name, description) VALUES 
       ('role-owner', 'owner', 'Company owner'),
       ('role-cashier', 'cashier', 'Cashier cashier')`
    );

    // 3. Create Permissions
    await client.query(
      `INSERT INTO permissions (id, code, description) VALUES 
       ('perm-sales-read', 'sales:read', 'Read sales'),
       ('perm-sales-create', 'sales:create', 'Create sales'),
       ('perm-stores-read', 'stores:read', 'Read stores')`
    );

    // 4. Map Roles to Permissions
    await client.query(
      `INSERT INTO role_permissions (role_id, permission_id) VALUES 
       ('role-owner', 'perm-sales-read'),
       ('role-owner', 'perm-sales-create'),
       ('role-owner', 'perm-stores-read'),
       ('role-cashier', 'perm-sales-create')`
    );

    // 5. Create Users (hashed passwords)
    const hashA1 = await AuthService.hashPassword('passA1');
    const hashA2 = await AuthService.hashPassword('passA2');
    const hashB1 = await AuthService.hashPassword('passB1');

    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES 
       ('user-A1', 'comp-A', 'Ahmet Owner A', 'ahmet@owner.com', $1, true),
       ('user-A2', 'comp-A', 'Kamil Cashier A', 'kamil@cashier.com', $2, true),
       ('user-B1', 'comp-B', 'Mehmet Owner B', 'mehmet@owner.com', $3, true)`,
      [hashA1, hashA2, hashB1]
    );

    // Map Users to Roles
    await client.query(
      `INSERT INTO user_roles (user_id, role_id) VALUES 
       ('user-A1', 'role-owner'),
       ('user-A2', 'role-cashier'),
       ('user-B1', 'role-owner')`
    );

    // 6. Create Stores (Mağazalar)
    await client.query(
      `INSERT INTO stores (id, company_id, name, address) VALUES 
       ('store-A1', 'comp-A', 'Kadıköy Şubesi Tenant A', 'Kadıköy İstanbul'),
       ('store-B1', 'comp-B', 'Çankaya Şubesi Tenant B', 'Çankaya Ankara')`
    );

    console.log('✅ Seed data successfully populated.');
  } finally {
    client.release();
  }
}

async function runTests() {
  console.log('\n🧪 --- STARTING SPRINT 1 INTEGRATION TESTS ---');

  // Test 1: Successful Login & Payload verification
  console.log('\n▶️ Test 1: Login Verification...');
  const authA1 = await AuthService.login('ahmet@owner.com', 'passA1', '127.0.0.1', 'Mozilla/Test');
  if (!authA1.access_token || !authA1.refresh_token) {
    throw new Error('Test 1 Failed: Missing token pair');
  }
  const decodedA1 = AuthService.verifyAccessToken(authA1.access_token);
  if (decodedA1.company_id !== 'comp-A' || !decodedA1.roles.includes('owner') || !decodedA1.permissions.includes('stores:read')) {
    throw new Error('Test 1 Failed: Invalid token claims payload');
  }
  console.log('  ✔️ Successful login, access token parsed. Company ID Context: comp-A');

  // Test 2: Hatalı Şifre Kilitlenmesi (Brute force protection)
  console.log('\n▶️ Test 2: Account Lockout Verification...');
  let lockedThrown = false;
  for (let i = 0; i < 5; i++) {
    try {
      await AuthService.login('ahmet@owner.com', 'wrong-pass');
    } catch (err: any) {
      // Expected credentials error for first 4 attempts, 5th attempt might trigger lock depending on logic
    }
  }
  try {
    // 6th attempt must throw account_locked
    await AuthService.login('ahmet@owner.com', 'passA1');
  } catch (err: any) {
    if (err.message === 'account_locked') {
      lockedThrown = true;
    }
  }
  if (!lockedThrown) {
    throw new Error('Test 2 Failed: Account was not locked after multiple failures');
  }
  console.log('  ✔️ Account successfully locked after 5 failed login attempts.');

  // Reset Lockout for remaining tests
  await pgPool.query('UPDATE users SET failed_login_attempts = 0, locked_until = NULL WHERE id = \'user-A1\'');

  // Test 3: Password change
  console.log('\n▶️ Test 3: Change Password Verification...');
  await AuthService.changePassword('user-A1', 'comp-A', 'passA1', 'new-passA1');
  const authNew = await AuthService.login('ahmet@owner.com', 'new-passA1');
  if (!authNew.access_token) {
    throw new Error('Test 3 Failed: Cannot login with new password');
  }
  let oldLoginFailed = false;
  try {
    await AuthService.login('ahmet@owner.com', 'passA1');
  } catch (_) {
    oldLoginFailed = true;
  }
  if (!oldLoginFailed) {
    throw new Error('Test 3 Failed: Old password still working');
  }
  console.log('  ✔️ Password successfully changed and verified.');

  // Test 4: RTR & Replay Attack Prevention
  console.log('\n▶️ Test 4: Refresh Token Rotation (RTR) & Replay Attack...');
  const authRTR = await AuthService.login('ahmet@owner.com', 'new-passA1');
  const refreshRes1 = await AuthService.refresh(authRTR.refresh_token);
  if (!refreshRes1.access_token || !refreshRes1.refresh_token) {
    throw new Error('Test 4 Failed: RTR did not issue new tokens');
  }
  console.log('  ✔️ RTR issued new token pair on first refresh call.');

  let replayBlocked = false;
  try {
    // Try to refresh using the old token again (replay attack)
    await AuthService.refresh(authRTR.refresh_token);
  } catch (err: any) {
    replayBlocked = true;
  }
  if (!replayBlocked) {
    throw new Error('Test 4 Failed: Replay attack with used refresh token was not blocked');
  }

  // Verify that all user sessions were revoked because of replay attack
  const activeSess = await pgPool.query('SELECT COUNT(*) FROM sessions WHERE user_id = \'user-A1\' AND is_revoked = FALSE');
  if (parseInt(activeSess.rows[0].count, 10) !== 0) {
    throw new Error('Test 4 Failed: Replay detection did not revoke user sessions');
  }
  console.log('  ✔️ Replay attack successfully blocked and ALL active sessions revoked.');

  // Test 5: Multi-Tenant Data Isolation (PostgreSQL Row Level Security / Tenant separation)
  console.log('\n▶️ Test 5: Multi-Tenant Data Isolation (RLS)...');
  const client = await pgPool.connect();
  try {
    // Enable RLS context for Tenant A inside a transaction as non-superuser
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.current_company_id = 'comp-A'");
    const resA = await client.query('SELECT id, name FROM stores');
    await client.query('RESET ROLE');
    await client.query('COMMIT');
    
    // Check if Tenant B's store is leaked
    const hasTenantBStore = resA.rows.some(row => row.id === 'store-B1');
    if (hasTenantBStore) {
      throw new Error('Test 5 Failed: Tenant B data leaked to Tenant A context!');
    }
    if (resA.rows.length === 0 || resA.rows[0].id !== 'store-A1') {
      throw new Error('Test 5 Failed: Cannot read Tenant A stores');
    }
    console.log(`  ✔️ RLS verified: Tenant A queried only Tenant A stores (Found: ${resA.rows.length} store).`);

    // Enable RLS context for Tenant B inside a transaction as non-superuser
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.current_company_id = 'comp-B'");
    const resB = await client.query('SELECT id, name FROM stores');
    await client.query('RESET ROLE');
    await client.query('COMMIT');

    const hasTenantAStore = resB.rows.some(row => row.id === 'store-A1');
    if (hasTenantAStore) {
      throw new Error('Test 5 Failed: Tenant A data leaked to Tenant B context!');
    }
    console.log(`  ✔️ RLS verified: Tenant B queried only Tenant B stores (Found: ${resB.rows.length} store).`);
  } finally {
    client.release();
  }

  console.log('\n🏆 ALL INTEGRATION TESTS PASSED SUCCESSFULLY! 🏆');
}

async function main() {
  try {
    await setupDatabase();
    await seedData();
    await runTests();
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Verification Failed:', err);
    process.exit(1);
  }
}

main();
