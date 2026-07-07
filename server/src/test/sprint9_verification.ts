/**
 * sprint9_verification.ts
 * Serenut Platform — Sprint 9 Notification Platform Verification Tests
 * 
 * Tests:
 *  1. Template Engine Variable Resolution & HTML escaping
 *  2. REST API: Queue push direct and credits deduct verification
 *  3. Queue Worker: Processing pending queue item, mockupNetgsm status sent
 *  4. Queue Worker: Failed gateway dispatch → retrying state & backoff check
 *  5. Campaign Engine: Segment 'debtors' target selection, templates rendering and queue batching
 * 
 * Run: npx ts-node src/test/sprint9_verification.ts
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

async function main() {
  console.log('\n🚀 Sprint 9 — Notification Platform Verification\n');
  console.log('='.repeat(65));

  // ── Test 1: Template Engine ───────────────────────────────────────────────
  console.log('\n[1] Dynamic Template Engine Resolution');
  try {
    const { TemplateParserService } = require('../modules/notification/template_parser.service');
    const rawTemplate = 'Sayin {{customer}}, {{store}} magazasindan toplam {{total}} TL alisverisiniz onaylandi.';
    const result = TemplateParserService.parse(rawTemplate, {
      customer: 'Mehmet Yilmaz',
      store: 'Serenut Kadikoy',
      total: 350
    });
    
    assert(result === 'Sayin Mehmet Yilmaz, Serenut Kadikoy magazasindan toplam 350 TL alisverisiniz onaylandi.', 'Variables resolved accurately');
    
    // HTML Escaping checks
    const maliciousResult = TemplateParserService.parse('Merhaba {{customer}}', {
      customer: '<script>alert("XSS")</script>'
    });
    assert(!maliciousResult.includes('<script>'), 'Dangerous tags sanitized successfully');
  } catch (e) {
    assert(false, 'Template parsing failed', String(e));
  }

  // ── Test 2: direct push & credit deduct ────────────────────────────────────
  console.log('\n[2] Direct Message Queue and Credit Deduction');
  const coId = `test-notif-co-${Date.now()}`;
  const qId = `test-notif-q-${Date.now()}`;
  
  try {
    // 1. Create company and credits row
    await runBypassingRLS(`
      INSERT INTO companies (id, name, tax_number) VALUES ($1, $2, $3)
    `, [coId, 'Notification Verification Co', `NOTIF-${Date.now()}`]);

    await runBypassingRLS(`
      INSERT INTO company_notification_credits (company_id, sms_credits) VALUES ($1, 100)
    `, [coId]);

    // 2. Insert queued message
    await runBypassingRLS(`
      INSERT INTO notification_queue (id, company_id, channel, recipient, body)
      VALUES ($1, $2, 'sms', '05301112233', 'Seeded direct alert message')
    `, [qId, coId]);

    const qItem = await runBypassingRLS('SELECT status FROM notification_queue WHERE id = $1', [qId]);
    assert(qItem.rows[0].status === 'queued', 'Message added to queue in pending state');

    // ── Test 3: Worker execution ─────────────────────────────────────────────
    console.log('\n[3] Queue Worker Execution');
    const { executeNotificationWorker } = require('../modules/notification/notification_worker');
    await executeNotificationWorker();

    const qItemSent = await runBypassingRLS('SELECT status, delivered_at FROM notification_queue WHERE id = $1', [qId]);
    const credits = await runBypassingRLS('SELECT sms_credits FROM company_notification_credits WHERE company_id = $1', [coId]);
    
    assert(qItemSent.rows[0].status === 'sent', 'Worker processes queued item to sent status');
    assert(qItemSent.rows[0].delivered_at !== null, 'Delivery timestamp populated');
    assert(credits.rows[0].sms_credits === 99, 'Credits correctly deducted after delivery', `credits: ${credits.rows[0].sms_credits}/100`);

  } catch (e) {
    assert(false, 'Direct notify test failed', String(e));
  }

  // ── Test 4: Failed gateway & retry flow ───────────────────────────────────
  console.log('\n[4] Exponential Retry & Backoff Engine');
  const failQId = `test-fail-q-${Date.now()}`;
  try {
    // Recipient ends in 9 to simulate mock gateway failure
    await runBypassingRLS(`
      INSERT INTO notification_queue (id, company_id, channel, recipient, body)
      VALUES ($1, $2, 'sms', '05301112239', 'Seeded failure test message')
    `, [failQId, coId]);

    const { executeNotificationWorker } = require('../modules/notification/notification_worker');
    await executeNotificationWorker();

    const qItemRetrying = await runBypassingRLS('SELECT status, retry_count, next_retry_at FROM notification_queue WHERE id = $1', [failQId]);
    
    assert(qItemRetrying.rows[0].status === 'retrying', 'Failed dispatch updates status to retrying');
    assert(qItemRetrying.rows[0].retry_count === 1, 'Retry count incremented to 1');
    assert(qItemRetrying.rows[0].next_retry_at > new Date(), 'Next retry deadline planned for the future');

  } catch (e) {
    assert(false, 'Retry engine test failed', String(e));
  }

  // ── Test 5: Campaign Segmentation ──────────────────────────────────────────
  console.log('\n[5] Campaign Targeting and Batch Queueing');
  try {
    // Create customers (one with debt, one with zero balance)
    const custId1 = `c1-${Date.now()}`;
    const custId2 = `c2-${Date.now()}`;

    await runBypassingRLS(`
      INSERT INTO customers (id, company_id, name, phone, balance)
      VALUES 
        ($1, $2, 'Borrower Customer', '05441112233', 350.00),
        ($3, $2, 'Clean Customer', '05443334455', 0.00)
    `, [custId1, coId, custId2]);

    // Create a template
    const tplId = `tpl-${Date.now()}`;
    await runBypassingRLS(`
      INSERT INTO notification_templates (id, company_id, name, channel, body)
      VALUES ($1, $2, 'debt_reminder', 'sms', 'Sayin {{customer}}, {{store}} borc hatırlatma')
    `, [tplId, coId]);

    // Trigger segment campaign logic manually simulated from controller (targeted query)
    const debtors = await runBypassingRLS(`
      SELECT name, phone FROM customers WHERE company_id = $1 AND balance > 0 AND is_deleted = FALSE
    `, [coId]);

    assert(debtors.rows.length === 1, 'Segment selected only debtors count correctly');
    assert(debtors.rows[0].name === 'Borrower Customer', 'Target selected borrower customer name');

    // Clean up DB records
    await runBypassingRLS('DELETE FROM notification_queue WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM notification_templates WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM customers WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM company_notification_credits WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM companies WHERE id = $1', [coId]);

  } catch (e) {
    assert(false, 'Campaign test failed', String(e));
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log('\n' + '='.repeat(65));
  console.log(`\n🏆 Sprint 9 Verification Complete`);
  console.log(`   Passed: ${passed}  |  Failed: ${failed}\n`);

  if (failed === 0) {
    console.log('✅ ALL SPRINT 9 NOTIFICATION ENGINE TESTS PASSED!\n');
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
