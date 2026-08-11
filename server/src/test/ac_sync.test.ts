// Sync V4 HTTP acceptance test.
//
// This intentionally does not write business rows as a stand-in for sync. It
// seeds only the isolated tenant/auth fixture, then exercises the same push and
// pull routes used by Windows and Android clients.

import jwt from 'jsonwebtoken';
import request from 'supertest';
import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { app } from '../server';

const companyId = 'sync-http-company';
const userId = 'sync-http-user';
const activationA = 'sync-http-activation-a';
const activationB = 'sync-http-activation-b';
const installationA = 'sync-http-installation-a';
const installationB = 'sync-http-installation-b';
const syncProtocolHeader = { 'x-sync-protocol-version': '6' };

function fail(message: string): never {
  throw new Error(`Sync V4 HTTP acceptance failed: ${message}`);
}

function tokenForDevice(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) fail('JWT_SECRET is required for the HTTP acceptance test.');
  return jwt.sign(
    {
      id: userId,
      name: 'Sync Owner',
      email: 'owner@sync-http.test',
      company_id: companyId,
      roles: ['owner'],
      permissions: ['settings:printer', 'settings:database'],
      token_version: 1,
      entitlement_state: 'active',
      entitlement_valid_until: Date.now() + 60 * 60 * 1000,
    },
    secret,
    { expiresIn: '15m', issuer: 'serenut.com', audience: 'serenut-pos' },
  );
}

async function setup() {
  let client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);

  client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ($1, 'Sync HTTP Co', '1234567890', 'Ankara', 'active')`,
      [companyId],
    );
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active, token_version)
       VALUES ($1, $2, 'Sync Owner', 'owner@sync-http.test', 'fixture-not-used', true, 1)`,
      [userId, companyId],
    );
    await client.query(
      `INSERT INTO license_entitlements
        (id, company_id, plan_id, status, device_limit, store_limit, valid_from, valid_until, license_key)
       VALUES ('sync-http-entitlement', $1, 'plan-free', 'active', 2, 1, NOW(), NOW() + INTERVAL '1 day', 'sync-http-license')`,
      [companyId],
    );
    await client.query(
      `INSERT INTO device_activations
        (id, entitlement_id, company_id, device_hash, device_name, platform, status, last_seen_at)
       VALUES
        ($1, 'sync-http-entitlement', $2, $3, 'Windows acceptance device', 'windows', 'active', NOW()),
        ($4, 'sync-http-entitlement', $2, $5, 'Android acceptance device', 'android', 'active', NOW())`,
      [activationA, companyId, installationA, activationB, installationB],
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function run() {
  await setup();
  const bearer = `Bearer ${tokenForDevice()}`;
  const productMutation = {
    mutation_id: '11111111-1111-4111-8111-111111111111',
    entity_type: 'product',
    entity_id: 'sync-http-product',
    operation: 'UPSERT',
    base_revision: 0,
    payload: {
      name: 'HTTP Senkron Ürün', price: 42.5, quantity: 7,
      category: 'Test', sku: 'HTTP-42', vat: 20,
    },
  };

  const noActivation = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_id: installationA, mutations: [productMutation] });
  if (noActivation.status !== 400) fail(`missing activation must be 400, got ${noActivation.status}`);

  const unsupportedProtocol = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set('x-sync-protocol-version', '4')
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [productMutation],
    });
  if (unsupportedProtocol.status !== 426 || unsupportedProtocol.body.required_version !== 6) {
    fail(`outdated sync protocol was not rejected safely: ${unsupportedProtocol.status}`);
  }

  const pushed = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [productMutation],
    });
  if (pushed.status !== 200 || pushed.body.results?.length !== 1) {
    fail(`device A push rejected: ${pushed.status} ${JSON.stringify(pushed.body)}`);
  }

  const duplicate = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [productMutation],
    });
  if (duplicate.status !== 200 || duplicate.body.results?.length !== 1) {
    fail(`idempotent retry was not acknowledged: ${duplicate.status}`);
  }

  const deleteProduct = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [{
        mutation_id: '11111111-1111-4111-8111-111111111112',
        entity_type: 'product', entity_id: productMutation.entity_id,
        operation: 'DELETE', base_revision: Number(pushed.body.results[0].revision),
        payload: { is_deleted: 1 },
      }],
    });
  const deleteRevision = Number(deleteProduct.body.results?.[0]?.revision);
  if (deleteProduct.status !== 200 || !Number.isSafeInteger(deleteRevision)) {
    fail(`product tombstone was not accepted: ${deleteProduct.status} ${JSON.stringify(deleteProduct.body)}`);
  }

  const reactivateProduct = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [{
        ...productMutation,
        mutation_id: '11111111-1111-4111-8111-111111111113',
        base_revision: deleteRevision,
        payload: {
          ...productMutation.payload,
          is_deleted: 0,
          reactivate_deleted: true,
        },
      }],
    });
  const reactivatedRow = await pgPool.query(
    'SELECT status,is_deleted FROM products WHERE company_id=$1 AND id=$2',
    [companyId, productMutation.entity_id],
  );
  if (reactivateProduct.status !== 200 ||
      reactivateProduct.body.results?.length !== 1 ||
      reactivatedRow.rows[0]?.status !== 'active' ||
      reactivatedRow.rows[0]?.is_deleted !== false) {
    fail(`explicit catalogue reactivation failed: ${reactivateProduct.status} ${JSON.stringify(reactivateProduct.body)}`);
  }

  const pulled = await request(app)
    .get(`/api/v4/sync/pull?cursor=0&limit=200&device_activation_id=${activationB}&device_id=${installationB}`)
    .set('Authorization', bearer)
    .set(syncProtocolHeader);
  const received = (pulled.body.changes ?? []).find((change: any) =>
    change.entity_type === 'product' && change.entity_id === productMutation.entity_id,
  );
  if (pulled.status !== 200 || !received || received.payload?.name !== 'HTTP Senkron Ürün') {
    fail(`device B did not receive device A product: ${pulled.status} ${JSON.stringify(pulled.body)}`);
  }

  const stored = await pgPool.query(
    'SELECT name, quantity FROM products WHERE id = $1 AND company_id = $2',
    [productMutation.entity_id, companyId],
  );
  if (stored.rowCount !== 1 || stored.rows[0].name !== 'HTTP Senkron Ürün') {
    fail('HTTP push was acknowledged without materializing the canonical product.');
  }

  const staleConcurrentWrite = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationB,
      device_id: installationB,
      mutations: [{ ...productMutation,
        mutation_id: '22222222-2222-4222-8222-222222222222',
        payload: { ...productMutation.payload, name: 'Stale overwrite' },
      }],
    });
  if (staleConcurrentWrite.status !== 200 || staleConcurrentWrite.body.conflicts?.length !== 1) {
    fail(`stale concurrent write was not recorded: ${staleConcurrentWrite.status} ${JSON.stringify(staleConcurrentWrite.body)}`);
  }

  const duplicateConflict = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationB,
      device_id: installationB,
      mutations: [{ ...productMutation,
        mutation_id: '22222222-2222-4222-8222-222222222222',
        payload: { ...productMutation.payload, name: 'Stale overwrite' },
      }],
    });
  if (duplicateConflict.status !== 200 || duplicateConflict.body.conflicts?.length !== 1) {
    fail(`conflict retry was not idempotent: ${duplicateConflict.status} ${JSON.stringify(duplicateConflict.body)}`);
  }

  const poisonBatch = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [
        {
          mutation_id: '33333333-3333-4333-8333-333333333333',
          entity_type: 'product', entity_id: 'invalid-product',
          operation: 'UPSERT', base_revision: 0, payload: {},
        },
        {
          mutation_id: '44444444-4444-4444-8444-444444444444',
          entity_type: 'product', entity_id: 'valid-after-invalid',
          operation: 'UPSERT', base_revision: 0,
          payload: { name: 'Sağlam Paket Ürünü', price: 10, quantity: 2 },
        },
      ],
    });
  if (poisonBatch.status !== 200 || poisonBatch.body.rejected?.length !== 1 ||
      poisonBatch.body.results?.length !== 1) {
    fail(`one invalid mutation poisoned its healthy batch peer: ${poisonBatch.status} ${JSON.stringify(poisonBatch.body)}`);
  }
  const healthyPeer = await pgPool.query(
    'SELECT name FROM products WHERE id = $1 AND company_id = $2',
    ['valid-after-invalid', companyId],
  );
  if (healthyPeer.rowCount !== 1 || healthyPeer.rows[0].name !== 'Sağlam Paket Ürünü') {
    fail('healthy mutation after a rejected peer was not materialized.');
  }

  const historicalAggregate = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [
        {
          mutation_id: '55555555-5555-4555-8555-555555555555',
          entity_type: 'customer',
          entity_id: 'historical-customer',
          operation: 'UPSERT',
          base_revision: 0,
          payload: { name: 'Tarihsel Müşteri' },
        },
        {
          mutation_id: '66666666-6666-4666-8666-666666666666',
          entity_type: 'order',
          entity_id: 'historical-order',
          operation: 'UPSERT',
          base_revision: 0,
          payload: {
            customer_id: 'historical-customer',
            status: 'completed',
            total_amount: 42.5,
            items: [{
              id: 'historical-order-item',
              product_id: productMutation.entity_id,
              quantity: 1,
              unit_price: 42.5,
            }],
          },
        },
      ],
    });
  if (historicalAggregate.status !== 200 || historicalAggregate.body.results?.length !== 2) {
    fail(`historical order fixture was not materialized through sync: ${historicalAggregate.status}`);
  }

  const deletedProduct = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      mutations: [{
        mutation_id: '77777777-7777-4777-8777-777777777777',
        entity_type: 'product',
        entity_id: productMutation.entity_id,
        operation: 'DELETE',
        base_revision: pushed.body.results[0].revision,
        payload: {},
      }],
    });
  if (deletedProduct.status !== 200 || deletedProduct.body.results?.length !== 1) {
    fail(`historical product tombstone was not accepted: ${deletedProduct.status}`);
  }

  const bootstrap = await request(app)
    .get(`/api/v4/sync/bootstrap?device_activation_id=${activationB}&device_id=${installationB}`)
    .set('Authorization', bearer)
    .set(syncProtocolHeader);
  const productSnapshot = (bootstrap.body.changes ?? []).find((change: any) =>
    change.entity_type === 'product' && change.entity_id === productMutation.entity_id,
  );
  const orderSnapshot = (bootstrap.body.changes ?? []).find((change: any) =>
    change.entity_type === 'order' && change.entity_id === 'historical-order',
  );
  if (bootstrap.status !== 200 || productSnapshot?.operation !== 'UPSERT' ||
      productSnapshot?.payload?.is_deleted !== 1 ||
      orderSnapshot?.payload?.items?.[0]?.product_id !== productMutation.entity_id) {
    fail(`bootstrap did not preserve a deleted product referenced by history: ${bootstrap.status} ${JSON.stringify(bootstrap.body)}`);
  }

  const registeredPrinter = await request(app)
    .put('/api/v4/sync/shared-hardware/presence')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA,
      device_id: installationA,
      hardware: [{
        id: 'receipt-primary', name: 'Ana Kasa Yazıcısı',
        type: 'receiptPrinter', connection_type: 'windows',
        language: 'escPos', sharing_scope: 'company', enabled: true,
        configuration: { printerName: 'Acceptance Printer' },
        capabilities: { paperWidthMm: 80 },
      }],
    });
  if (registeredPrinter.status !== 200 || registeredPrinter.body.registered !== 1) {
    fail(`shared printer registration failed: ${registeredPrinter.status} ${JSON.stringify(registeredPrinter.body)}`);
  }

  const sharedList = await request(app)
    .post('/api/v4/sync/shared-hardware/list')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationB, device_id: installationB });
  const sharedPrinter = (sharedList.body.hardware ?? []).find((item: any) =>
    item.name === 'Ana Kasa Yazıcısı');
  if (sharedList.status !== 200 || !sharedPrinter?.online || sharedPrinter?.is_local) {
    fail(`device B cannot discover device A printer: ${sharedList.status} ${JSON.stringify(sharedList.body)}`);
  }

  const remoteJobBody = {
    device_activation_id: activationB,
    device_id: installationB,
    hardware_id: sharedPrinter.id,
    operation: 'printReceipt',
    idempotency_key: 'acceptance-shared-print-1',
    payload: { bytes_base64: 'G0AK', copies: 1 },
  };
  const queuedJob = await request(app)
    .post('/api/v4/sync/hardware-jobs')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send(remoteJobBody);
  const duplicateJob = await request(app)
    .post('/api/v4/sync/hardware-jobs')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send(remoteJobBody);
  if (queuedJob.status !== 202 || duplicateJob.status !== 202 ||
      queuedJob.body.job?.id !== duplicateJob.body.job?.id) {
    fail(`remote print enqueue is not idempotent: ${queuedJob.status}/${duplicateJob.status}`);
  }

  const claimedJob = await request(app)
    .post('/api/v4/sync/hardware-jobs/claim')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationA, device_id: installationA });
  if (claimedJob.status !== 200 || claimedJob.body.job?.id !== queuedJob.body.job.id) {
    fail(`owner device did not claim its print job: ${claimedJob.status} ${JSON.stringify(claimedJob.body)}`);
  }
  const startedJob = await request(app)
    .post(`/api/v4/sync/hardware-jobs/${claimedJob.body.job.id}/start`)
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationA, device_id: installationA });
  const completedJob = await request(app)
    .post(`/api/v4/sync/hardware-jobs/${claimedJob.body.job.id}/result`)
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationA, device_id: installationA,
      state: 'succeeded', result: { transport: 'windowsSpooler' },
    });
  if (startedJob.status !== 200 || completedJob.status !== 200 ||
      completedJob.body.job?.state !== 'succeeded') {
    fail(`remote print execution lifecycle failed: ${startedJob.status}/${completedJob.status} ${JSON.stringify(completedJob.body)}`);
  }

  const sharedJobs = await request(app)
    .post('/api/v4/sync/hardware-jobs/list')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationB, device_id: installationB });
  if (sharedJobs.status !== 200 || sharedJobs.body.jobs?.[0]?.state !== 'succeeded' ||
      !sharedJobs.body.jobs?.[0]?.requested_here) {
    fail(`requester cannot observe physical result: ${sharedJobs.status} ${JSON.stringify(sharedJobs.body)}`);
  }

  const uncertainJob = await request(app)
    .post('/api/v4/sync/hardware-jobs')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      ...remoteJobBody,
      idempotency_key: 'acceptance-shared-print-uncertain',
    });
  const uncertainClaim = await request(app)
    .post('/api/v4/sync/hardware-jobs/claim')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationA, device_id: installationA });
  const uncertainStart = await request(app)
    .post(`/api/v4/sync/hardware-jobs/${uncertainJob.body.job.id}/start`)
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationA, device_id: installationA });
  await pgPool.query(
    `UPDATE hardware_jobs SET lease_expires_at = NOW() - INTERVAL '1 minute' WHERE id = $1`,
    [uncertainJob.body.job.id],
  );
  const claimAfterCrash = await request(app)
    .post('/api/v4/sync/hardware-jobs/claim')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationA, device_id: installationA });
  const uncertainList = await request(app)
    .post('/api/v4/sync/hardware-jobs/list')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationB, device_id: installationB });
  const uncertainSummary = (uncertainList.body.jobs ?? []).find((job: any) =>
    job.id === uncertainJob.body.job.id);
  if (uncertainJob.status !== 202 || uncertainClaim.body.job?.id !== uncertainJob.body.job.id ||
      uncertainStart.status !== 200 || claimAfterCrash.body.job != null ||
      uncertainSummary?.state !== 'requires_confirmation') {
    fail(`an uncertain physical print could be duplicated: ${JSON.stringify({
      enqueue: uncertainJob.status,
      claim: uncertainClaim.body,
      start: uncertainStart.status,
      afterCrash: claimAfterCrash.body,
      summary: uncertainSummary,
    })}`);
  }
  const confirmedPrinted = await request(app)
    .post(`/api/v4/sync/hardware-jobs/${uncertainJob.body.job.id}/action`)
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationB,
      device_id: installationB,
      action: 'confirmPrinted',
    });
  if (confirmedPrinted.status !== 200 || confirmedPrinted.body.job?.state !== 'succeeded') {
    fail(`uncertain print could not be resolved safely: ${confirmedPrinted.status} ${JSON.stringify(confirmedPrinted.body)}`);
  }

  const operationalReset = await request(app)
    .post('/api/v4/sync/operational-reset')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({ device_activation_id: activationA, device_id: installationA });
  if (operationalReset.status !== 200 ||
      !Number.isSafeInteger(Number(operationalReset.body.reset_revision))) {
    fail(`operational reset failed: ${operationalReset.status} ${JSON.stringify(operationalReset.body)}`);
  }
  const resetRevision = Number(operationalReset.body.reset_revision);
  const staleAfterReset = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .set(syncProtocolHeader)
    .send({
      device_activation_id: activationB,
      device_id: installationB,
      mutations: [{
        mutation_id: '30000000-0000-4000-8000-000000000001',
        entity_type: 'product', entity_id: 'stale-after-reset', operation: 'UPSERT',
        base_revision: Math.max(0, resetRevision - 1),
        payload: { name: 'Stale Product', price: 1, quantity: 1 },
      }],
    });
  if (staleAfterReset.status !== 200 ||
      staleAfterReset.body.rejected?.[0]?.error !== 'stale_before_operational_reset') {
    fail(`pre-reset offline mutation was not rejected: ${staleAfterReset.status} ${JSON.stringify(staleAfterReset.body)}`);
  }
  const resetRows = await pgPool.query(
    `SELECT
      (SELECT COUNT(*) FROM products WHERE company_id=$1) AS products,
      (SELECT COUNT(*) FROM sales WHERE company_id=$1) AS sales,
      (SELECT COUNT(*) FROM financial_transactions WHERE company_id=$1) AS financial_transactions`,
    [companyId],
  );
  if (Number(resetRows.rows[0].products) !== 0 || Number(resetRows.rows[0].sales) !== 0 ||
      Number(resetRows.rows[0].financial_transactions) !== 0) {
    fail(`operational reset left business rows behind: ${JSON.stringify(resetRows.rows[0])}`);
  }

  console.log('✔ Sync V4 HTTP: push, retry, pull, conflict, reset barrier and poison-batch isolation passed.');
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
