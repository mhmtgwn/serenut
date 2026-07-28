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
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
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
    payload: {
      name: 'HTTP Senkron Ürün', price: 42.5, quantity: 7,
      category: 'Test', sku: 'HTTP-42', vat: 20,
    },
  };

  const noActivation = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
    .send({ device_id: installationA, mutations: [productMutation] });
  if (noActivation.status !== 400) fail(`missing activation must be 400, got ${noActivation.status}`);

  const pushed = await request(app)
    .post('/api/v4/sync/push')
    .set('Authorization', bearer)
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
    .set('Authorization', bearer);
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

  console.log('✔ Sync V4 HTTP: authorized device A push → idempotent retry → device B pull passed.');
}

run()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
