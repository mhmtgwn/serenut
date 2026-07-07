import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import { runMigrations } from '../migrations';

async function setupDatabase() {
  console.log('🔄 Cleaning up database schema for Sprint 5...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }

  // Run migrations
  await runMigrations(pgPool);

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

  console.log('✅ Sprint 5 Database schema, migrations v2 and RLS test role generated.');
}

async function seedData() {
  console.log('🌱 Seeding Sprint 5 verification roles, users, and tickets...');
  const client = await pgPool.connect();
  try {
    // 1. Create Roles
    await client.query(
      `INSERT INTO roles (id, name, description) VALUES 
       ('role-sysadmin', 'sysadmin', 'System Administrator'),
       ('role-owner', 'owner', 'Company Owner')`
    );

    // 2. Create Companies
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status) VALUES 
       ('serenut_cloud', 'Serenut Cloud Admin', '0000000000', 'Admin Office', 'active'),
       ('comp-A', 'Sirket A Ltd.', '1111111111', 'Kadikoy V.D.', 'active'),
       ('comp-B', 'Sirket B Ltd.', '2222222222', 'Cankaya V.D.', 'active')`
    );

    // 3. Create Users
    const hashSysadmin = await AuthService.hashPassword('adminpass');
    const hashOwnerA = await AuthService.hashPassword('ownerApass');
    const hashOwnerB = await AuthService.hashPassword('ownerBpass');

    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES 
       ('user-sysadmin', 'serenut_cloud', 'System Admin', 'sysadmin@serenut.com', $1, true),
       ('user-ownerA', 'comp-A', 'Ahmet Sirket A', 'ahmet@owner.com', $2, true),
       ('user-ownerB', 'comp-B', 'Mehmet Sirket B', 'mehmet@owner.com', $3, true)`,
      [hashSysadmin, hashOwnerA, hashOwnerB]
    );

    // Assign Roles
    await client.query(
      `INSERT INTO user_roles (user_id, role_id) VALUES 
       ('user-sysadmin', 'role-sysadmin'),
       ('user-ownerA', 'role-owner'),
       ('user-ownerB', 'role-owner')`
    );

    // 4. Create Support Ticket for Company A
    await client.query(
      `INSERT INTO support_tickets (id, company_id, title, description, priority, status)
       VALUES ('tkt-1', 'comp-A', 'POS Sync Error', 'Cihazlar senkronize olmuyor.', 'high', 'open')`
    );

    await client.query(
      `INSERT INTO support_ticket_messages (id, ticket_id, sender_id, sender_name, message)
       VALUES ('msg-1', 'tkt-1', 'user-ownerA', 'Ahmet Sirket A', 'Cihazlar senkronize olmuyor.')`
    );

    // 5. Create SMS Log for Company B
    await client.query(
      `INSERT INTO sms_logs (id, company_id, phone, message, status)
       VALUES ('sms-1', 'comp-B', '05551234567', 'Giris kodu: 9812', 'sent')`
    );

    console.log('✅ Sprint 5 Seed data successfully populated.');
  } finally {
    client.release();
  }
}

async function runTests() {
  console.log('\n🧪 --- STARTING SPRINT 5 CONTROL CENTER INTEGRATION TESTS ---');

  const client = await pgPool.connect();
  try {
    // Test 1: RLS Isolation check for Tenant A
    console.log('\n▶️ Test 1: PostgreSQL RLS tenant isolation check...');
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.current_company_id = 'comp-A'");
    const resA = await client.query('SELECT * FROM support_tickets');
    await client.query('RESET ROLE');
    await client.query('COMMIT');
    
    if (resA.rows.length !== 1 || resA.rows[0].id !== 'tkt-1') {
      throw new Error('Test 1 Failed: Tenant A sees other tenant tickets or no tickets.');
    }
    console.log('  ✔️ Tenant A isolated correctly and sees only tkt-1.');

    // Test 2: RLS Isolation check for Tenant B (should see no tickets)
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.current_company_id = 'comp-B'");
    const resB = await client.query('SELECT * FROM support_tickets');
    await client.query('RESET ROLE');
    await client.query('COMMIT');
    
    if (resB.rows.length !== 0) {
      throw new Error('Test 2 Failed: Tenant B sees Tenant A tickets.');
    }
    console.log('  ✔️ Tenant B isolated correctly and sees no tickets.');

    // Test 3: Sysadmin RLS Bypass verification
    console.log('\n▶️ Test 2: Sysadmin RLS bypass validation...');
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const resAll = await client.query('SELECT * FROM support_tickets');
    await client.query('RESET ROLE');
    await client.query('COMMIT');
    if (resAll.rows.length !== 1) {
      throw new Error('Test 3 Failed: Sysadmin cannot bypass RLS to read all support tickets.');
    }
    console.log('  ✔️ Sysadmin bypassed RLS successfully and read all records.');
    await client.query('COMMIT');

    // Test 4: Support Ticket Reply integration
    console.log('\n▶️ Test 3: Support ticket message reply flow validation...');
    // Sysadmin replies to Tenant A's ticket
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query(
      `INSERT INTO support_ticket_messages (id, ticket_id, sender_id, sender_name, message)
       VALUES ('msg-reply-1', 'tkt-1', 'user-sysadmin', 'Serenut Destek', 'Sorunu inceledik, sunucu baglantisi duzeldi.')`
    );
    await client.query("UPDATE support_tickets SET status = 'replied', updated_at = NOW() WHERE id = 'tkt-1'");
    await client.query('RESET ROLE');
    await client.query('COMMIT');

    // Verify Tenant A can see the reply under RLS
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.current_company_id = 'comp-A'");
    const messages = await client.query('SELECT * FROM support_ticket_messages WHERE ticket_id = \'tkt-1\' ORDER BY created_at ASC');
    await client.query('RESET ROLE');
    await client.query('COMMIT');

    if (messages.rows.length !== 2 || messages.rows[1].sender_name !== 'Serenut Destek') {
      throw new Error('Test 4 Failed: Tenant A cannot see the admin reply to support ticket.');
    }
    console.log('  ✔️ Support ticket reply flow converged successfully.');

    // Test 5: SMS logs statistics aggregation
    console.log('\n▶️ Test 4: SMS quota analytics check...');
    await client.query('BEGIN');
    await client.query('SET ROLE serenut_rls_test_role');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const smsCount = await client.query("SELECT COUNT(*) FROM sms_logs WHERE status = 'sent'");
    await client.query('RESET ROLE');
    await client.query('COMMIT');

    if (parseInt(smsCount.rows[0].count, 10) !== 1) {
      throw new Error('Test 5 Failed: SMS stats count is incorrect.');
    }
    console.log('  ✔️ SMS statistics returned correct data.');

    console.log('\n🏆 ALL SPRINT 5 CLOUD ADMIN INTEGRATION TESTS PASSED SUCCESSFULLY! 🏆');
  } finally {
    client.release();
  }
}

async function main() {
  try {
    await setupDatabase();
    await seedData();
    await runTests();
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Sprint 5 Verification Failed:', err);
    process.exit(1);
  }
}

main();
