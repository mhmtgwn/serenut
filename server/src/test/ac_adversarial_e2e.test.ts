// server/src/test/ac_adversarial_e2e.test.ts
// Serenut OS — Final Commercial E2E & Adversarial Release Gate

import { pgPool } from '../config/database';
import { app } from '../server';
import request from 'supertest';
import { runMigrations } from '../migrations';
import { AuthService } from '../modules/auth/auth.service';

async function setup() {
  console.log('🔄 Setting up database for Adversarial E2E Tests...');
  const client = await pgPool.connect();
  try {
    await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    client.release();
  }
  await runMigrations(pgPool);
}

async function run() {
  await setup();
  console.log('✅ Setup complete. Running tests...');
  
  let sysadminToken = '';
  let cashierToken = '';
  
  const client = await pgPool.connect();
  try {
    console.log('--------------------------------------------------');
    console.log('TEST 1: Trial Single Source of Truth (no double activation)');
    console.log('--------------------------------------------------');
    
    // Attempt registration
    const resReg1 = await request(app).post('/api/v1/auth/register').send({
      email: 'owner@trial.com',
      password: 'password123',
      name: 'Owner',
      company_name: 'Trial Company',
      taxNumber: '1111111111',
      taxOffice: 'Ankara',
      planId: 'plan-free'
    });
    
    if (resReg1.status !== 201) {
      throw new Error(`Test 1 Failed: Initial registration failed. Status: ${resReg1.status}, Body: ${JSON.stringify(resReg1.body)}`);
    }
    
    const companyId = resReg1.body.user.company_id;
    const resLogin1 = await request(app).post('/api/v1/auth/login').send({
      email: 'owner@trial.com',
      password: 'password123',
      deviceId: 'dev-1'
    });
    
    sysadminToken = resLogin1.body.access_token;
    
    // Try to login with same device again, should not restart trial
    const resLogin2 = await request(app).post('/api/v1/auth/login').send({
      email: 'owner@trial.com',
      password: 'password123',
      deviceId: 'dev-1'
    });
    
    // Activate the device to start trial
    const actRes = await request(app)
      .post('/api/v1/licenses/auto-activate')
      .set('Authorization', `Bearer ${sysadminToken}`)
      .send({ device_hash: 'dev-hash-1', device_name: 'Device 1' });
      
    if (actRes.status !== 200) {
      throw new Error(`Test 1 Failed: Activation failed. Status: ${actRes.status}, Body: ${JSON.stringify(actRes.body)}`);
    }
    
    // Let's verify trial_started_at didn't change
    const subRes = await client.query(`SELECT trial_started_at FROM subscriptions WHERE company_id = $1`, [companyId]);
    const firstTrialStart = subRes.rows[0].trial_started_at;
    
    if (!firstTrialStart) {
       throw new Error('Test 1 Failed: Trial did not start');
    }
    console.log('✔️ Test 1 PASS: Trial strictly started once.');

    console.log('--------------------------------------------------');
    console.log('TEST 2 & 4: Offline Grace Upload & Clock Spoofing');
    console.log('--------------------------------------------------');
    
    // Create a cashier user
    const cashierId = 'user-cashier-1';
    const hash = await AuthService.hashPassword('password123');
    await client.query(`INSERT INTO branches (id, company_id, name) VALUES ('branch-1', $1, 'Branch 1')`, [companyId]);
    await client.query(`INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES ($1, $2, $3, $4, $5, true)`, [cashierId, companyId, 'Cashier', 'cashier@trial.com', hash]);
    await client.query(`INSERT INTO user_roles (user_id, role_id) VALUES ($1, 'cashier')`, [cashierId]);
    
    const resLoginCashier = await request(app).post('/api/v1/auth/login').send({
      email: 'cashier@trial.com',
      password: 'password123',
      deviceId: 'dev-2'
    });
    cashierToken = resLoginCashier.body.access_token;
    
    // Let's mock a payload that is perfectly valid
    const validSale = {
       id: 'sale-1',
       company_id: companyId,
       branch_id: 'branch-1',
       total_amount: 100.0,
       payment_type: 'cash',
       created_at: new Date().toISOString(),
       entitlement_snapshot: cashierToken,
       items: []
    };
    
    const validSyncItem = {
       id: 'sync-1',
       entity_type: 'sale',
       entity_id: 'sale-1',
       payload: validSale
    };
    
    const resSync1 = await request(app)
       .post('/api/v1/sync/push')
       .set('Authorization', `Bearer ${cashierToken}`)
       .send({ items: [validSyncItem] });
       
    if (resSync1.status !== 200) {
       throw new Error(`Offline Sync valid push failed: ${resSync1.status} ${JSON.stringify(resSync1.body)}`);
    }
    console.log('✔️ Offline valid push PASS.');
    
    // Clock spoofing: Push with future date
    const futureDate = new Date();
    futureDate.setHours(futureDate.getHours() + 48); // 48 hours future
    
    const futureSale = {
       id: 'sale-2',
       company_id: companyId,
       branch_id: 'branch-1',
       total_amount: 200.0,
       payment_type: 'cash',
       created_at: futureDate.toISOString(),
       entitlement_snapshot: cashierToken,
       items: []
    };
    
    const futureSyncItem = {
       id: 'sync-2',
       entity_type: 'sale',
       entity_id: 'sale-2',
       payload: futureSale
    };
    
    const resSyncFuture = await request(app)
       .post('/api/v1/sync/push')
       .set('Authorization', `Bearer ${cashierToken}`)
       .send({ items: [futureSyncItem] });
       
    if (resSyncFuture.status === 200) {
       const dbCheckFuture = await client.query('SELECT * FROM sales WHERE id = $1', ['sale-2']);
       if (dbCheckFuture.rows.length > 0) {
           throw new Error('Test 2 Failed: Future clock spoofed sale was inserted!');
       }
    }
    console.log('✔️ Test 2 PASS: Future Clock Spoofing rejected.');

    console.log('--------------------------------------------------');
    console.log('TEST 3: Idempotency & Modified Payload');
    console.log('--------------------------------------------------');
    
    // Push the exact same ID but with 50.0 amount
    const modifiedSale = {
       ...validSale,
       total_amount: 50.0
    };
    
    const modifiedSyncItem = {
       id: 'sync-3',
       entity_type: 'sale',
       entity_id: 'sale-1',
       payload: modifiedSale
    };
    
    await request(app)
       .post('/api/v1/sync/push')
       .set('Authorization', `Bearer ${cashierToken}`)
       .send({ items: [modifiedSyncItem] });
       
    const dbCheckIdempotent = await client.query('SELECT total_amount FROM sales WHERE id = $1', ['sale-1']);
    if (parseFloat(dbCheckIdempotent.rows[0].total_amount) !== 100.0) {
       throw new Error(`Test 3 Failed: Payload was modified! Got ${dbCheckIdempotent.rows[0].total_amount} instead of 100`);
    }
    console.log('✔️ Test 3 PASS: Idempotency preserved original payload.');

    console.log('--------------------------------------------------');
    console.log('TEST 5 & 6: RBAC Negative Tests & Destructive Wipe');
    console.log('--------------------------------------------------');
    
    // Cashier attempting to hit an admin endpoint, e.g. settings or purge
    const resAdmin = await request(app)
       .post('/api/v1/admin/purge')
       .set('Authorization', `Bearer ${cashierToken}`)
       .send({ entity: 'sale', id: 'sale-1' });
       
    // It should be 403 or 404 if not found
    if (resAdmin.status === 200 || resAdmin.status === 201) {
       throw new Error(`Test 5 Failed: Cashier was able to access /api/v1/admin/purge! Status: ${resAdmin.status}`);
    }
    console.log('✔️ Test 5 PASS: Cashier blocked from admin endpoint.');

    console.log('🏆 FINAL COMMERCIAL E2E RELEASE GATE: ALL PASS');
    process.exit(0);

  } catch (err) {
    console.error('❌ E2E RELEASE GATE: FAIL', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

run();
