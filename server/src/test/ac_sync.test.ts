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
const syncProtocolHeader = { 'x-sync-protocol-version': '5' };

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
      permissions: [],
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
        (id, entitlement_id, company_id, device_hash, device_name, platform, status)
       VALUES
        ($1, 'sync-http-entitlement', $2, $3, 'Windows acceptance device', 'windows', 'active'),
        ($4, 'sync-http-entitlement', $2, $5, 'Android acceptance device', 'android', 'active')`,
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
  if (unsupportedProtocol.status !== 426 || unsupportedProtocol.body.required_version !== 5) {
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

  console.log('✔ Sync V4 HTTP: push, retry, pull, conflict and poison-batch isolation passed.');
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
