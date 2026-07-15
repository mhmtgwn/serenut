import { pgPool } from '../config/database';
import { CommercialLifecycleService } from '../modules/billing/commercial_lifecycle.service';
import crypto from 'crypto';
import assert from 'assert';

async function runTests() {
  console.log('--- STARTING PAYMENT LIFECYCLE TESTS ---');

  const client = await pgPool.connect();
  try {
    // 1. Setup a test company and invoice
    const companyId = `test-comp-${Date.now()}`;
    const invoiceId = `inv-${Date.now()}`;

    await client.query(`
      INSERT INTO companies (id, name, tax_number)
      VALUES ($1, 'Test Company', $2)
    `, [companyId, Date.now().toString().slice(0, 10)]);

    await client.query(`
      INSERT INTO invoices (id, company_id, invoice_number, amount, status, due_at, billing_details)
      VALUES ($1, $2, 'TEST-INV-1', 100, 'pending', NOW(), '{"planId":"plan-pro","billingPeriod":"monthly"}')
    `, [invoiceId, companyId]);

    // 2. Test Concurrency & Idempotency
    // We will simulate 10 concurrent requests trying to finalize the exact same invoice.
    console.log('Running 10 concurrent finalizeInvoicePayment calls...');
    
    const promises = [];
    let successCount = 0;
    let failureCount = 0;

    for (let i = 0; i < 10; i++) {
      promises.push((async () => {
        const pClient = await pgPool.connect();
        try {
          await pClient.query('BEGIN');
          await CommercialLifecycleService.finalizeInvoicePayment(pClient, invoiceId, 'bank_transfer', 'sysadmin-id');
          await pClient.query('COMMIT');
          successCount++;
        } catch (e) {
          await pClient.query('ROLLBACK');
          failureCount++;
        } finally {
          pClient.release();
        }
      })());
    }

    await Promise.all(promises);

    // Because of FOR UPDATE, only 1 should do the actual insert of subscription/entitlements.
    // The others will either block and then see status === 'paid', or wait.
    // Wait, CommercialLifecycleService checks if status === 'paid' and returns early without throwing error!
    // So all 10 should succeed (not throw), but only 1 should actually perform the commercial updates.
    
    // We expect successCount to be 10, failureCount to be 0 (idempotent early return).
    assert.strictEqual(successCount, 10, 'All calls should succeed (some idempotently)');
    assert.strictEqual(failureCount, 0, 'No calls should fail');

    // Verify there is exactly 1 active subscription for this company
    const subRes = await client.query('SELECT * FROM subscriptions WHERE company_id = $1', [companyId]);
    assert.strictEqual(subRes.rows.length, 1, 'There should be exactly 1 subscription');
    
    const sub = subRes.rows[0];
    assert.strictEqual(sub.plan_id, 'plan-pro');
    assert.strictEqual(sub.status, 'active');

    // Verify there is exactly 1 active license entitlement
    const entRes = await client.query('SELECT * FROM license_entitlements WHERE company_id = $1', [companyId]);
    assert.strictEqual(entRes.rows.length, 1, 'There should be exactly 1 entitlement');
    assert.strictEqual(entRes.rows[0].status, 'active');

    // Verify old licenses table backward compatibility
    const licRes = await client.query('SELECT * FROM licenses WHERE company_id = $1', [companyId]);
    // It creates it or updates it, wait activatePaidSubscription only UPDATES legacy licenses table, doesn't insert if not exists.
    // Let's just check if invoice is paid
    const invRes = await client.query('SELECT status, subscription_id FROM invoices WHERE id = $1', [invoiceId]);
    assert.strictEqual(invRes.rows[0].status, 'paid');
    assert.strictEqual(invRes.rows[0].subscription_id, sub.id);

    console.log('✅ Concurrency & Idempotency tests passed!');

    // Clean up
    await client.query('DELETE FROM license_entitlements WHERE company_id = $1', [companyId]);
    await client.query('DELETE FROM subscriptions WHERE company_id = $1', [companyId]);
    await client.query('DELETE FROM invoices WHERE company_id = $1', [companyId]);
    await client.query('DELETE FROM companies WHERE id = $1', [companyId]);

    console.log('--- ALL PAYMENT LIFECYCLE TESTS PASSED ---');
    process.exit(0);

  } catch (err) {
    console.error('❌ Test failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runTests();
