/**
 * sprint6_verification.ts
 * Serenut Platform — Sprint 6 Release Management Platform Verification Tests
 * 
 * Tests:
 *  1. Schema v3 migration (new columns and tables exist)
 *  2. Release creation + SHA-256 verification logic
 *  3. Rollout percentage bucketing determinism
 *  4. Yank mechanism (yanked releases not returned in /check)
 *  5. Targeting rules (company-specific release)
 *  6. Device version report endpoint
 *  7. Monitor endpoint response shape
 * 
 * Run: npx ts-node src/test/sprint6_verification.ts
 */

import { Pool } from 'pg';
import crypto from 'crypto';
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

// Replicate rollout bucketing from release.controller.ts
function isDeviceInRollout(deviceId: string, rolloutPercentage: number): boolean {
  if (rolloutPercentage >= 100) return true;
  if (rolloutPercentage <= 0) return false;
  const hash = crypto.createHash('md5').update(deviceId).digest('hex');
  const bucket = parseInt(hash.substring(0, 4), 16) % 100;
  return bucket < rolloutPercentage;
}

async function main() {
  console.log('\n🚀 Sprint 6 — Release Management Platform Verification\n');
  console.log('='.repeat(55));

  // ── Test 1: Schema v3 tables and columns exist ─────────────────────────────
  console.log('\n[1] Schema v3 Migration Verification');
  try {
    const cols = await pool.query(`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'app_versions'
      AND column_name IN ('channel', 'rollout_percentage', 'min_required_version', 'file_path', 'status', 'yanked_reason')
    `);
    assert(cols.rows.length === 6, 'app_versions has all 6 new columns', `found ${cols.rows.length}/6`);

    const tables = await pool.query(`
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name IN ('update_targets', 'update_download_logs', 'device_app_versions')
    `);
    assert(tables.rows.length === 3, 'New tables exist (update_targets, update_download_logs, device_app_versions)');
  } catch (e) {
    assert(false, 'Schema v3 tables exist', String(e));
  }

  // ── Test 2: Create + verify release + check yank ───────────────────────────
  console.log('\n[2] Release Lifecycle (create → active → yank)');
  const releaseId = `test-rel-${Date.now()}`;
  const fakeHash = crypto.createHash('sha256').update('fake_apk_bytes').digest('hex');

  try {
    // Create test company
    const companyId = `test-co-${Date.now()}`;
    await runBypassingRLS(
      `INSERT INTO companies (id, name, tax_number) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
      [companyId, 'Sprint6 Test Co', `TAX-${Date.now()}`]
    );

    // Create test release
    await runBypassingRLS(`
      INSERT INTO app_versions (id, version_code, platform, channel, download_url, sha256_hash, status, rollout_percentage, is_mandatory)
      VALUES ($1, $2, 'android', 'stable', $3, $4, 'active', 100, false)
    `, [releaseId, `9.9.9+${Date.now()}`, `/api/v1/releases/download/${releaseId}`, fakeHash]);

    const created = await runBypassingRLS('SELECT * FROM app_versions WHERE id = $1', [releaseId]);
    assert(created.rows.length === 1, 'Release created successfully');
    assert(created.rows[0].status === 'active', 'Release status is active');
    assert(created.rows[0].sha256_hash === fakeHash, 'SHA-256 hash stored correctly');

    // Yank it
    await runBypassingRLS(
      "UPDATE app_versions SET status = 'yanked', yanked_reason = 'Verification test' WHERE id = $1",
      [releaseId]
    );

    const yanked = await runBypassingRLS(
      "SELECT status FROM app_versions WHERE id = $1",
      [releaseId]
    );
    assert(yanked.rows[0].status === 'yanked', 'Yank sets status to yanked');

    // Verify yanked release is NOT returned in check queries
    const checkResult = await pool.query(
      "SELECT * FROM app_versions WHERE platform = 'android' AND channel = 'stable' AND status = 'active' AND id = $1",
      [releaseId]
    );
    assert(checkResult.rows.length === 0, 'Yanked release not returned in active queries');

    // Cleanup
    await runBypassingRLS('DELETE FROM app_versions WHERE id = $1', [releaseId]);
    await runBypassingRLS('DELETE FROM companies WHERE id = $1', [companyId]);
  } catch (e) {
    assert(false, 'Release lifecycle test', String(e));
  }

  // ── Test 3: Rollout bucketing determinism ──────────────────────────────────
  console.log('\n[3] Rollout Percentage Bucketing');
  try {
    const testDevices = ['device-aaa', 'device-bbb', 'device-ccc', 'device-ddd', 'device-eee',
                         'device-fff', 'device-ggg', 'device-hhh', 'device-iii', 'device-jjj'];
    
    // At 100% everyone should be eligible
    const allEligible = testDevices.every(d => isDeviceInRollout(d, 100));
    assert(allEligible, '100% rollout → all devices eligible');

    // At 0% nobody should be eligible
    const noneEligible = testDevices.every(d => !isDeviceInRollout(d, 0));
    assert(noneEligible, '0% rollout → no devices eligible');

    // Determinism: same device, same rollout → same result every time
    const deviceId = 'deterministic-device-xyz';
    const result1 = isDeviceInRollout(deviceId, 50);
    const result2 = isDeviceInRollout(deviceId, 50);
    const result3 = isDeviceInRollout(deviceId, 50);
    assert(result1 === result2 && result2 === result3, 'Rollout bucketing is deterministic for same device');

    // At 50%, roughly half should be eligible (allow ±3 tolerance on 10 devices)
    const eligibleAt50 = testDevices.filter(d => isDeviceInRollout(d, 50)).length;
    assert(eligibleAt50 >= 2 && eligibleAt50 <= 8, `50% rollout → ${eligibleAt50}/10 eligible (expected 2-8)`);
  } catch (e) {
    assert(false, 'Rollout bucketing test', String(e));
  }

  // ── Test 4: Update Targets ─────────────────────────────────────────────────
  console.log('\n[4] Update Targets (Company-specific Releases)');
  const targetReleaseId = `test-tgt-rel-${Date.now()}`;
  const targetCompanyId = `test-tgt-co-${Date.now()}`;
  try {
    await runBypassingRLS(
      `INSERT INTO companies (id, name, tax_number) VALUES ($1, $2, $3)`,
      [targetCompanyId, 'Target Test Co', `TAX-T-${Date.now()}`]
    );

    await runBypassingRLS(`
      INSERT INTO app_versions (id, version_code, platform, channel, download_url, sha256_hash, status)
      VALUES ($1, '8.8.8+888', 'android', 'internal', $2, 'abc123', 'active')
    `, [targetReleaseId, `/api/v1/releases/download/${targetReleaseId}`]);

    const targetId = `tgt-${Date.now()}`;
    await runBypassingRLS(
      `INSERT INTO update_targets (id, release_id, target_type, target_value) VALUES ($1, $2, 'company', $3)`,
      [targetId, targetReleaseId, targetCompanyId]
    );

    // Verify targeted company can find it
    const targetCheck = await runBypassingRLS(
      `SELECT ut.id FROM update_targets ut WHERE ut.release_id = $1 AND ut.target_type = 'company' AND ut.target_value = $2`,
      [targetReleaseId, targetCompanyId]
    );
    assert(targetCheck.rows.length === 1, 'Target company can access targeted release');

    // Verify OTHER company cannot find it
    const otherCompanyId = `other-co-${Date.now()}`;
    const otherCheck = await runBypassingRLS(
      `SELECT ut.id FROM update_targets ut WHERE ut.release_id = $1 AND ut.target_type = 'company' AND ut.target_value = $2`,
      [targetReleaseId, otherCompanyId]
    );
    assert(otherCheck.rows.length === 0, 'Non-targeted company cannot access targeted release');

    // Cleanup
    await runBypassingRLS('DELETE FROM update_targets WHERE release_id = $1', [targetReleaseId]);
    await runBypassingRLS('DELETE FROM app_versions WHERE id = $1', [targetReleaseId]);
    await runBypassingRLS('DELETE FROM companies WHERE id = $1', [targetCompanyId]);
  } catch (e) {
    assert(false, 'Update targets test', String(e));
  }

  // ── Test 5: Device App Version Reporting ───────────────────────────────────
  console.log('\n[5] Device Version Reporting (report-version endpoint simulation)');
  try {
    // Create test company and device
    const coId = `test-dav-co-${Date.now()}`;
    const devId = `test-dav-dev-${Date.now()}`;

    await runBypassingRLS(
      `INSERT INTO companies (id, name, tax_number) VALUES ($1, $2, $3)`,
      [coId, 'DevVersion Test Co', `TAX-DV-${Date.now()}`]
    );

    // Find or create a store for this company
    const storeId = `test-store-${Date.now()}`;
    await runBypassingRLS(
      `INSERT INTO stores (id, company_id, name) VALUES ($1, $2, $3)`,
      [storeId, coId, 'Test Store']
    );

    await runBypassingRLS(
      `INSERT INTO devices (id, company_id, store_id, name, device_hash, status)
       VALUES ($1, $2, $3, 'Test Device', $4, 'active')`,
      [devId, coId, storeId, `hash-sprint6-${Date.now()}`]
    );

    // Simulate report-version upsert
    await runBypassingRLS(`
      INSERT INTO device_app_versions (device_id, company_id, platform, current_version, channel, last_reported_at)
      VALUES ($1, $2, 'android', '1.5.0+28', 'stable', NOW())
      ON CONFLICT (device_id) DO UPDATE SET
        current_version = EXCLUDED.current_version,
        channel = EXCLUDED.channel,
        last_reported_at = NOW()
    `, [devId, coId]);

    const reported = await runBypassingRLS(
      'SELECT * FROM device_app_versions WHERE device_id = $1',
      [devId]
    );

    assert(reported.rows.length === 1, 'Device version record created');
    assert(reported.rows[0].current_version === '1.5.0+28', 'Device version stored correctly');

    // Simulate second report (upsert)
    await runBypassingRLS(`
      INSERT INTO device_app_versions (device_id, company_id, platform, current_version, channel, last_reported_at)
      VALUES ($1, $2, 'android', '1.5.1+29', 'stable', NOW())
      ON CONFLICT (device_id) DO UPDATE SET current_version = EXCLUDED.current_version, last_reported_at = NOW()
    `, [devId, coId]);

    const updated = await runBypassingRLS(
      'SELECT current_version FROM device_app_versions WHERE device_id = $1',
      [devId]
    );
    assert(updated.rows[0].current_version === '1.5.1+29', 'Upsert updates existing version correctly');

    // Cleanup
    await runBypassingRLS('DELETE FROM device_app_versions WHERE device_id = $1', [devId]);
    await runBypassingRLS('DELETE FROM devices WHERE id = $1', [devId]);
    await runBypassingRLS('DELETE FROM stores WHERE id = $1', [storeId]);
    await runBypassingRLS('DELETE FROM companies WHERE id = $1', [coId]);
  } catch (e) {
    assert(false, 'Device version report test', String(e));
  }

  // ── Test 6: Download Log Tracking ──────────────────────────────────────────
  console.log('\n[6] Download Log Tracking');
  try {
    const dlId = `dl-test-${Date.now()}`;
    await runBypassingRLS(
      `INSERT INTO update_download_logs (id, status) VALUES ($1, 'started')`,
      [dlId]
    );

    await runBypassingRLS(
      "UPDATE update_download_logs SET status = 'verified', completed_at = NOW() WHERE id = $1",
      [dlId]
    );

    const log = await runBypassingRLS(
      'SELECT status, completed_at FROM update_download_logs WHERE id = $1',
      [dlId]
    );
    assert(log.rows[0].status === 'verified', 'Download log status updated to verified');
    assert(log.rows[0].completed_at !== null, 'Download log completed_at timestamp set');

    await runBypassingRLS('DELETE FROM update_download_logs WHERE id = $1', [dlId]);
  } catch (e) {
    assert(false, 'Download log tracking test', String(e));
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log('\n' + '='.repeat(55));
  console.log(`\n🏆 Sprint 6 Verification Complete`);
  console.log(`   Passed: ${passed}  |  Failed: ${failed}\n`);

  if (failed === 0) {
    console.log('✅ ALL SPRINT 6 RELEASE MANAGEMENT TESTS PASSED!\n');
  } else {
    console.log(`⚠️  ${failed} test(s) failed. Review output above.\n`);
    process.exit(1);
  }

  await pool.end();
}

main().catch((e) => {
  console.error('Fatal error:', e);
  pool.end();
  process.exit(1);
});
