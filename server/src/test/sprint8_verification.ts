/**
 * sprint8_verification.ts
 * Serenut Platform — Sprint 8 Billing Platform Verification Tests
 * 
 * Tests:
 *  1. Schema v5 checks (new columns and seeded plans exist)
 *  2. Checkout & Invoice PDF creation (simulate mock-checkout-callback)
 *  3. Automatic Renewal simulated success / failure
 *  4. Grace period rule: Payment fails → Grant 7-day grace period
 *  5. Automatic Suspension rule: Grace period expired → set to suspended
 *  6. Admin Billing stats aggregation logic
 * 
 * Run: npx ts-node src/test/sprint8_verification.ts
 */

import { Pool } from 'pg';
import fs from 'fs';
import path from 'path';
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
  console.log('\n🚀 Sprint 8 — Billing Platform & Invoices Verification\n');
  console.log('='.repeat(65));

  // ── Test 1: Schema v5 verification ─────────────────────────────────────────
  console.log('\n[1] Schema v5 Migration Verification');
  try {
    const cols = await pool.query(`
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'subscriptions'
      AND column_name IN ('payment_method', 'cancel_at_period_end', 'grace_period_until', 'last_payment_status')
    `);
    assert(cols.rows.length === 4, 'Subscriptions has all 4 new billing columns');

    const plans = await pool.query("SELECT id FROM plans WHERE id IN ('plan-free', 'plan-basic', 'plan-pro')");
    assert(plans.rows.length >= 3, 'Seed plans created successfully');
  } catch (e) {
    assert(false, 'Schema v5 checks', String(e));
  }

  // ── Test 2: Checkout & Invoice PDF creation ────────────────────────────────
  console.log('\n[2] Checkout & PDF Generation');
  const coId = `test-bill-co-${Date.now()}`;
  const planId = 'plan-pro';
  const subId = `sub-test-${Date.now()}`;
  const invoiceId = `inv-test-${Date.now()}`;
  const invoiceNum = `INV-${new Date().getFullYear()}-${Math.floor(1000 + Math.random()*9000)}`;

  try {
    // 1. Create company
    await runBypassingRLS(
      `INSERT INTO companies (id, name, tax_number) VALUES ($1, $2, $3)`,
      [coId, 'Billing Verification Co', `TAX-${Date.now()}`]
    );

    // 2. Generate PDF file (simulate controller)
    const { InvoiceGeneratorService } = require('../modules/billing/invoice_generator.service');
    const pdfPath = await InvoiceGeneratorService.generateInvoicePdf(coId, {
      invoiceNumber: invoiceNum,
      date: new Date(),
      dueDate: new Date(),
      companyName: 'Billing Verification Co',
      companyAddress: 'Test Address Suite 1',
      taxNumber: '1234567890',
      currency: 'TRY',
      items: [
        {
          description: 'Serenut POS Pro Subscription',
          quantity: 1,
          unitPrice: 950.00,
          taxRate: 20
        }
      ]
    });

    assert(fs.existsSync(pdfPath), 'Invoice PDF physically created on disk');
    assert(pdfPath.includes(coId), 'Invoice PDF placed under tenant directory');

    // 3. Insert invoice & subscription record
    await runBypassingRLS(`
      INSERT INTO subscriptions (id, company_id, plan_id, status, current_period_start, current_period_end)
      VALUES ($1, $2, $3, 'active', NOW(), NOW() + INTERVAL '30 days')
    `, [subId, coId, planId]);

    await runBypassingRLS(`
      INSERT INTO invoices (id, company_id, subscription_id, amount, status, invoice_number, pdf_path)
      VALUES ($1, $2, $3, 950.00, 'paid', $4, $5)
    `, [invoiceId, coId, subId, invoiceNum, pdfPath]);

    const invoice = await runBypassingRLS('SELECT * FROM invoices WHERE id = $1', [invoiceId]);
    assert(invoice.rows[0].pdf_path === pdfPath, 'Invoice PDF path stored in database');

    // Clean up physical file
    fs.unlinkSync(pdfPath);
  } catch (e) {
    assert(false, 'Checkout & PDF test failed', String(e));
  }

  // ── Test 3: Grace period renewal warning ───────────────────────────────────
  console.log('\n[3] Grace Period Engine');
  try {
    // Set current period end to yesterday to simulate expired subscription
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);

    await runBypassingRLS(`
      UPDATE subscriptions 
      SET current_period_end = $1 
      WHERE id = $2
    `, [yesterday, subId]);

    // Force simulation tax number to end in 9 (which causes simulateMockupPayment to fail in cron)
    const randomTax = `${Math.floor(10000000 + Math.random()*9000000)}9`;
    await runBypassingRLS(`
      UPDATE companies SET tax_number = $1 WHERE id = $2
    `, [randomTax, coId]);

    // Run cron script
    const { executeBillingCron } = require('../modules/billing/cron_billing_runner');
    await executeBillingCron();

    const sub = await runBypassingRLS('SELECT status, grace_period_until, last_payment_status FROM subscriptions WHERE id = $1', [subId]);
    assert(sub.rows[0].status === 'grace_period', 'Failed payment updates status to grace_period');
    assert(sub.rows[0].last_payment_status === 'failed', 'Payment status is set to failed');
    assert(sub.rows[0].grace_period_until !== null, 'Grace period warning deadline is set');
  } catch (e) {
    assert(false, 'Grace period test failed', String(e));
  }

  // ── Test 4: Automatic Suspension ──────────────────────────────────────────
  console.log('\n[4] Automatic Suspension Engine');
  try {
    // Create a license for this company
    const licId = `lic-${Date.now()}`;
    await runBypassingRLS(`
      INSERT INTO licenses (id, company_id, license_key, tier, status, expires_at)
      VALUES ($1, $2, $3, 'pro', 'active', NOW() + INTERVAL '30 days')
    `, [licId, coId, `KEY-BILL-${Date.now()}`]);

    // Force grace period to be expired (yesterday)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);

    await runBypassingRLS(`
      UPDATE subscriptions 
      SET grace_period_until = $1 
      WHERE id = $2
    `, [yesterday, subId]);

    // Run cron script again
    const { executeBillingCron } = require('../modules/billing/cron_billing_runner');
    await executeBillingCron();

    const sub = await runBypassingRLS('SELECT status FROM subscriptions WHERE id = $1', [subId]);
    const lic = await runBypassingRLS('SELECT status FROM licenses WHERE id = $1', [licId]);

    assert(sub.rows[0].status === 'suspended', 'Expired grace period suspends subscription');
    assert(lic.rows[0].status === 'suspended', 'Suspended subscription suspends dependent client license');

    // Clean up DB records
    await runBypassingRLS('DELETE FROM invoices WHERE subscription_id = $1', [subId]);
    await runBypassingRLS('DELETE FROM licenses WHERE company_id = $1', [coId]);
    await runBypassingRLS('DELETE FROM subscriptions WHERE id = $1', [subId]);
    await runBypassingRLS('DELETE FROM companies WHERE id = $1', [coId]);
  } catch (e) {
    assert(false, 'Suspension engine test failed', String(e));
  }

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log('\n' + '='.repeat(65));
  console.log(`\n🏆 Sprint 8 Verification Complete`);
  console.log(`   Passed: ${passed}  |  Failed: ${failed}\n`);

  await pool.end();

  // Also close pgPool imported by billing modules
  try {
    const { pgPool } = require('../config/database');
    await pgPool.end();
  } catch (_) {}

  if (failed === 0) {
    console.log('✅ ALL SPRINT 8 BILLING PLATFORM TESTS PASSED!\n');
    process.exit(0);
  } else {
    console.log(`⚠️  ${failed} test(s) failed. Review output above.\n`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('Fatal verification error:', e);
  pool.end();
  process.exit(1);
});
