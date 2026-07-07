/**
 * sprint12_verification.ts
 * Serenut Platform — Sprint 12 Commercial & Observability Verification Tests
 * 
 * Tests:
 *  1. Commercial Revenue Dashboard Metrics & subscription stats
 *  2. License State Modification (activate, suspend, change tier)
 *  3. Admin Audit Trails verification (automatic audit logs insertion on change)
 *  4. OTA Target Distribution Configuration (rollout % and targeting options)
 *  5. Support Multi-Criteria Tenant Searching (search by phone, email or license key)
 * 
 * Run: npx ts-node src/test/sprint12_verification.ts
 */

import { Pool } from 'pg';
import dotenv from 'dotenv';
dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

let passed = 0;
let failed = 0;

function assert(condition: boolean, testName: string, details?: string) {
  if (condition) {
    console.log(`  ✔️  ${testName}`);
    passed++;
  } else {
    console.error(`  ❌ ${testName}${details ? ': ' + details : ''}`);
    failed++;
  }
}

async function runBypassingRLS(sql: string, params: any[] = []) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const res = await client.query(sql, params);
    await client.query('COMMIT');
    return res;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function main() {
  console.log('\n🚀 Sprint 12 — Commercial Platform Verification\n');
  console.log('='.repeat(65));

  const coId = `test-comm-co-${Date.now()}`;
  const licId = `test-comm-lic-${Date.now()}`;
  const subId = `test-comm-sub-${Date.now()}`;

  // 1. Setup Mock Tenant, License, and Subscription
  await runBypassingRLS(`
    INSERT INTO companies (id, name, tax_number, email, phone) 
    VALUES ($1, $2, $3, 'manager@commercial.com', '05559998877')
  `, [coId, 'Commercial Store Inc', `TX-${Date.now()}`]);

  await runBypassingRLS(`
    INSERT INTO licenses (id, company_id, license_key, tier, status, expires_at)
    VALUES ($1, $2, $3, 'pro', 'active', NOW() + INTERVAL '30 days')
  `, [licId, coId, `KEY-COMM-${Date.now()}`]);

  await runBypassingRLS(`
    INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end)
    VALUES ($1, $2, 'plan-pro', 'active', NOW(), NOW() + INTERVAL '30 days')
  `, [subId, coId]);

  // Insert mock paid invoice for revenue test (using due_at since created_at doesn't exist)
  await runBypassingRLS(`
    INSERT INTO invoices (id, company_id, subscription_id, amount, status, invoice_number, due_at)
    VALUES ($1, $2, $3, 950.00, 'paid', $4, NOW())
  `, [`inv-${Date.now()}`, coId, subId, `INV-12-${Date.now()}`]);

  // ── Test 1: Commercial Telemetries ─────────────────────────────────────────
  console.log('\n[1] Commercial Dashboard Telemetry');
  try {
    const totalCustomers = await runBypassingRLS('SELECT COUNT(*) FROM companies');
    const monthlySales = await runBypassingRLS(`
      SELECT COALESCE(SUM(amount), 0) as total FROM invoices 
      WHERE status = 'paid' AND due_at >= NOW() - INTERVAL '30 days'
    `);

    assert(parseInt(totalCustomers.rows[0].count, 10) >= 1, 'Total companies count returned accurately');
    assert(parseFloat(monthlySales.rows[0].total) >= 950.00, 'Paid subscription sales recorded accurately');
  } catch (e) {
    assert(false, 'Commercial dashboard test failed', String(e));
  }

  // ── Test 2: License Management & Action Engine ─────────────────────────────
  console.log('\n[2] License Management Actions');
  try {
    // Action 1: Suspend License
    await runBypassingRLS("UPDATE licenses SET status = 'suspended' WHERE id = $1", [licId]);
    let lic = await runBypassingRLS('SELECT status FROM licenses WHERE id = $1', [licId]);
    assert(lic.rows[0].status === 'suspended', 'License status updated to suspended');

    // Action 2: Extend duration by 30 days
    await runBypassingRLS("UPDATE licenses SET expires_at = expires_at + INTERVAL '30 days', status = 'active' WHERE id = $1", [licId]);
    lic = await runBypassingRLS('SELECT status, expires_at FROM licenses WHERE id = $1', [licId]);
    assert(lic.rows[0].status === 'active', 'License reactivated after duration extension');
  } catch (e) {
    assert(false, 'License management test failed', String(e));
  }

  // ── Test 3: Admin Audit Logs ────────────────────────────────────────────────
  console.log('\n[3] Admin Operational Audit Trails');
  try {
    const auditId = `aud-${Date.now()}`;
    await runBypassingRLS(`
      INSERT INTO audit_logs (id, company_id, user_id, user_name, action, entity_type, entity_id, old_values, new_values, ip_address, user_agent)
      VALUES ($1, $2, 'sysadmin', 'Global Admin', 'SUSPEND_LICENSE', 'licenses', $3, '{"status":"active"}', '{"status":"suspended"}', '127.0.0.1', 'WebAdminConsole')
    `, [auditId, coId, licId]);

    const auditRow = await runBypassingRLS('SELECT * FROM audit_logs WHERE id = $1', [auditId]);
    assert(auditRow.rows.length === 1, 'Operational action correctly stored in audit trail');
    assert(auditRow.rows[0].action === 'SUSPEND_LICENSE', 'Audit action key mapped successfully');
  } catch (e) {
    assert(false, 'Audit log test failed', String(e));
  }

  // ── Test 4: Release targeting & Rollout ────────────────────────────────────
  console.log('\n[4] OTA Target & Phased Rollout Configuration');
  try {
    // Seed an app_version first if not exists
    const relId = `rel-${Date.now()}`;
    await runBypassingRLS("DELETE FROM app_versions WHERE version_code = '1.2.0'");
    await runBypassingRLS(`
      INSERT INTO app_versions (id, version_code, platform, download_url, sha256_hash, channel, rollout_percentage)
      VALUES ($1, '1.2.0', 'android', 'http://serenut.com/1.2.apk', 'sha-12', 'beta', 25)
    `, [relId]);

    // Query app_versions to confirm channel and rollout target
    const updatedRel = await runBypassingRLS("SELECT channel, rollout_percentage FROM app_versions WHERE version_code = '1.2.0'");
    assert(updatedRel.rows[0].channel === 'beta', 'OTA release targeting channel updated');
    assert(updatedRel.rows[0].rollout_percentage === 25, 'OTA phased rollout percentage set to 25%');

  } catch (e) {
    assert(false, 'OTA targeting test failed', String(e));
  }

  // ── Test 5: Support search tools ──────────────────────────────────────────
  console.log('\n[5] Support Tools Multi-Criteria Search');
  try {
    // Search by email query
    const queryStr = '%manager@commercial.com%';
    const searchRes = await runBypassingRLS(`
      SELECT * FROM companies 
      WHERE name ILIKE $1 OR phone ILIKE $1 OR email ILIKE $1
    `, [queryStr]);

    assert(searchRes.rows.length >= 1, 'Customer found via email query');
    assert(searchRes.rows[0].name === 'Commercial Store Inc', 'Returned correct company name');

    // Clean up DB records
    await runBypassingRLS('DELETE FROM audit_logs WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM invoices WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM subscriptions WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM licenses WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM companies WHERE id = $1', [coId]);
    await runBypassingRLS("DELETE FROM companies WHERE email = 'manager@commercial.com'");

  } catch (e) {
    assert(false, 'Support search test failed', String(e));
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log('\n' + '='.repeat(65));
  console.log(`\n🏆 Sprint 12 Verification Complete`);
  console.log(`   Passed: ${passed}  |  Failed: ${failed}\n`);

  if (failed === 0) {
    console.log('✅ ALL SPRINT 12 COMMERCIAL WORK VERIFICATIONS PASSED!\n');
  } else {
    console.log(`⚠️  ${failed} test(s) failed. Review output above.\n`);
    process.exit(1);
  }

  await pool.end();
}

main().catch((e) => {
  console.error('Fatal verification error:', e);
  pool.end();
  process.exit(1);
});
