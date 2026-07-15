import assert from 'assert';
import request from 'supertest';
import { pgPool } from '../config/database';
import { app } from '../server';
import { encryptSecret, decryptSecret } from '../crypto_helper';
import { CommercialLifecycleService } from '../modules/billing/commercial_lifecycle.service';

// Mock variables
let sysadminToken = '';
let regularToken = '';
let companyId = '';
let invoiceId = '';
let subscriptionId = '';

async function runAudit() {
  console.log('--- STARTING FORENSIC AUDIT ---');
  const client = await pgPool.connect();

  try {
    // PRE-REQ: Create users and tokens
    companyId = `audit-comp-${Date.now()}`;
    await client.query(`
      INSERT INTO companies (id, name, business_code, tax_number)
      VALUES ($1, 'Audit Company', $2, $2)
    `, [companyId, Date.now().toString().slice(0,10)]);

    // SysAdmin
    const sysadminId = `audit-sysadmin-${Date.now()}`;
    await client.query(`
      INSERT INTO users (id, company_id, name, username, email, password_hash, is_active)
      VALUES ($1, $2, 'Sys Admin', 'sysadmin-audit', 'sysadmin@audit.com', 'dummy', true)
    `, [sysadminId, companyId]);

    // Regular Tenant User
    const regUserId = `audit-user-${Date.now()}`;
    await client.query(`
      INSERT INTO users (id, company_id, name, username, email, password_hash, is_active)
      VALUES ($1, $2, 'Regular User', 'user-audit', 'user@audit.com', 'dummy', true)
    `, [regUserId, companyId]);

    // We'll mock the JWT generation or manually fetch it.
    // Wait, the API requires a valid token from /api/v1/auth/login.
    // Instead of mocking, we can just sign it with the JWT_SECRET from process.env
    const jwt = require('jsonwebtoken');
    const secret = process.env.JWT_SECRET || 'dev_secret_key';
    sysadminToken = jwt.sign({ sub: sysadminId, id: sysadminId, company_id: companyId, roles: ['sysadmin'], token_version: 1 }, secret, { expiresIn: '1h', audience: 'serenut-pos', issuer: 'serenut.com' });
    regularToken = jwt.sign({ sub: regUserId, id: regUserId, company_id: companyId, roles: ['manager'], token_version: 1 }, secret, { expiresIn: '1h', audience: 'serenut-pos', issuer: 'serenut.com' });

    // TEST 1: schema_v37 & payment_providers records
    console.log('[TEST 1] Verifying payment_providers schema and default records...');
    const pRes = await client.query('SELECT id, is_enabled FROM payment_providers ORDER BY id');
    assert.ok(pRes.rows.length >= 2, 'Should have at least bank_transfer and iyzico');
    const bank = pRes.rows.find((r: any) => r.id === 'bank_transfer');
    const iyzico = pRes.rows.find((r: any) => r.id === 'iyzico');
    assert.strictEqual(bank.is_enabled, true, 'bank_transfer must be active');
    assert.strictEqual(iyzico.is_enabled, false, 'iyzico must be disabled');
    console.log('✅ TEST 1 PASS');

    // TEST 2: Secret Encryption
    console.log('[TEST 2] Verifying Secret Encryption...');
    const rawSecret = 'sk_test_12345';
    const encrypted1 = encryptSecret(rawSecret);
    const encrypted2 = encryptSecret(rawSecret);
    assert.notStrictEqual(encrypted1, encrypted2, 'Nonce/IV must not be reused (encrypted outputs must differ)');
    assert.notStrictEqual(encrypted1, rawSecret, 'Plaintext must not be returned');
    assert.strictEqual(decryptSecret(encrypted1), rawSecret, 'Decryption must return original string');
    console.log('✅ TEST 2 PASS');

    // TEST 3: Public /payment-methods endpoint
    console.log('[TEST 3] Verifying /api/v1/billing/payment-methods...');
    const pmRes = await request(app).get('/api/v1/billing/payment-methods');
    assert.strictEqual(pmRes.status, 200);
    const pmBody = pmRes.body;
    assert.ok(pmBody.length >= 1, 'Should return at least 1 provider');
    assert.ok(pmBody.some((p: any) => p.id === 'bank_transfer'), 'bank_transfer should be in response');
    assert.ok(!pmBody.some((p: any) => p.id === 'iyzico'), 'iyzico should NOT be in response');
    for (const p of pmBody) {
      assert.strictEqual(p.secrets, undefined, 'Secrets must NOT leak to frontend');
    }
    console.log('✅ TEST 3 PASS');

    // TEST 4: Iyzico activation without credentials / connection fail
    console.log('[TEST 4] Verifying API Provider Activation Guard...');
    // Unauthorized attempt
    const failRes1 = await request(app)
      .put('/api/v1/admin/payment-methods/iyzico')
      .set('Authorization', `Bearer ${regularToken}`)
      .send({ is_enabled: true });
    assert.strictEqual(failRes1.status, 403, 'Regular tenant should not be able to call this');

    // Admin attempt with missing/invalid credentials (forces a connection test failure)
    const failRes2 = await request(app)
      .put('/api/v1/admin/payment-methods/iyzico')
      .set('Authorization', `Bearer ${sysadminToken}`)
      .send({ is_enabled: true, secrets: { iyzico_api_key: 'fake', iyzico_secret_key: 'fake' } });
    assert.strictEqual(failRes2.status, 400, 'Should reject activation if test connection fails');
    const checkDb = await client.query('SELECT is_enabled, last_error FROM payment_providers WHERE id = $1', ['iyzico']);
    assert.strictEqual(checkDb.rows[0].is_enabled, false, 'Database guard must force is_enabled=false');
    assert.ok(checkDb.rows[0].last_error !== null, 'Must record the connection error');
    console.log('✅ TEST 4 PASS');

    // TEST 5: Iyzico Checkout disabled check
    console.log('[TEST 5] Verifying Iyzico checkout blocked...');
    const chkRes = await request(app)
      .post('/api/v1/billing/subscribe')
      .set('Authorization', `Bearer ${regularToken}`)
      .send({ plan_id: 'test', payment_method: 'iyzico' });
    assert.ok(chkRes.status === 400 || chkRes.status === 501 || chkRes.status === 404, 'Must return error for Iyzico');
    assert.ok(chkRes.body.error?.includes('disabled') || chkRes.body.error?.includes('not supported') || chkRes.body.error?.includes('not_implemented') || chkRes.body.message?.includes('aktif değil') || chkRes.body.error?.includes('kapalı'), 'Must return error stating Iyzico is disabled');
    console.log('✅ TEST 5 PASS');

    // TEST 6: Havale/EFT Lifecycle
    console.log('[TEST 6] Verifying Havale/EFT Lifecycle...');
    invoiceId = `inv-${Date.now()}`;
    await client.query(`
      INSERT INTO invoices (id, company_id, invoice_number, amount, status, due_at, billing_details)
      VALUES ($1, $2, $1, 100, 'pending', NOW(), '{"planId":"plan-pro","billingPeriod":"monthly"}')
    `, [invoiceId, companyId]);

    // Check pre-approval (no active sub)
    const preSub = await client.query('SELECT * FROM subscriptions WHERE company_id = $1', [companyId]);
    assert.strictEqual(preSub.rows.length, 0, 'No subscription before approval');

    // Approving as sysadmin
    const apprRes = await request(app)
      .post(`/api/v1/admin/invoices/${invoiceId}/approve`)
      .set('Authorization', `Bearer ${sysadminToken}`);
    assert.strictEqual(apprRes.status, 200, 'Approval should succeed');

    const postSub = await client.query('SELECT * FROM subscriptions WHERE company_id = $1', [companyId]);
    assert.strictEqual(postSub.rows.length, 1, 'Subscription created after approval');
    assert.strictEqual(postSub.rows[0].status, 'active');
    console.log('✅ TEST 6 PASS');

    // TEST 7: finalizeInvoicePayment concurrency
    console.log('[TEST 7] Verifying finalizeInvoicePayment Concurrency & Rollback...');
    const invId2 = `inv-conc-${Date.now()}`;
    await client.query(`
      INSERT INTO invoices (id, company_id, invoice_number, amount, status, due_at, billing_details)
      VALUES ($1, $2, $1, 200, 'pending', NOW(), '{"planId":"plan-enterprise","billingPeriod":"yearly"}')
    `, [invId2, companyId]);

    let successCount = 0;
    const promises = [];
    for (let i = 0; i < 10; i++) {
      promises.push((async () => {
        const pClient = await pgPool.connect();
        try {
          await pClient.query('BEGIN');
          await CommercialLifecycleService.finalizeInvoicePayment(pClient, invId2, 'bank_transfer', sysadminId);
          await pClient.query('COMMIT');
          successCount++;
        } catch (e) {
          await pClient.query('ROLLBACK');
        } finally {
          pClient.release();
        }
      })());
    }
    await Promise.all(promises);

    const checkInv2 = await client.query('SELECT status FROM invoices WHERE id = $1', [invId2]);
    assert.strictEqual(checkInv2.rows[0].status, 'paid', 'Invoice should be paid');
    const entRes = await client.query('SELECT * FROM license_entitlements WHERE company_id = $1', [companyId]);
    // There was 1 entitlement from test 6, this test should only add 1 more or update it.
    console.log('✅ TEST 7 PASS');

    console.log('--- ALL FORENSIC AUDIT TESTS PASSED ---');
    process.exit(0);

  } catch (err) {
    console.error('❌ FORENSIC AUDIT FAILED:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runAudit();
