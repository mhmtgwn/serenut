import express from 'express';
import { pgPool } from '../config/database';
import { AuthService } from '../modules/auth/auth.service';
import syncRouter from '../modules/sync/sync.controller';
import * as http from 'http';

const mockCompanyId = 'test-company-123';
const mockUserId = 'test-user-123';
const productId = 'prod-test-01';
const prod2Id = 'prod-test-02';

async function setup() {
  console.log('🔄 Setting up database for Stock Regression Test...');
  const client = await pgPool.connect();
  try {
    await client.query('DELETE FROM sale_items WHERE product_id = $1 OR product_id = $2', [productId, prod2Id]);
    await client.query('DELETE FROM sales WHERE company_id = $1', [mockCompanyId]);
    await client.query('DELETE FROM products WHERE id = $1 OR id = $2', [productId, prod2Id]);
    await client.query('DELETE FROM user_roles WHERE user_id = $1', [mockUserId]);
    await client.query('DELETE FROM users WHERE id = $1', [mockUserId]);
    await client.query('DELETE FROM companies WHERE id = $1', [mockCompanyId]);

    const hash = await AuthService.hashPassword('password123');
    await client.query(`INSERT INTO companies (id, name, tax_number, status) VALUES ($1, 'Test Company', '1234567890', 'active')`, [mockCompanyId]);
    await client.query(`INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES ($1, $2, 'Test User', 'testuser@stock.com', $3, true)`, [mockUserId, mockCompanyId, hash]);
    await client.query(
      `INSERT INTO subscriptions
         (id, company_id, status, current_period_start, current_period_end)
       VALUES ($1, $2, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days')`,
      [`sub-${mockCompanyId}`, mockCompanyId],
    );

    await client.query(`
      INSERT INTO products (id, company_id, name, price, quantity, status) 
      VALUES ($1, $2, 'Test Product', 50.00, 100, 'active')
    `, [productId, mockCompanyId]);
    
    await client.query(`
      INSERT INTO products (id, company_id, name, price, quantity, status) 
      VALUES ($1, $2, 'Test Product 2', 20.00, 50, 'active')
    `, [prod2Id, mockCompanyId]);
  } finally {
    client.release();
  }
}

async function run() {
  let server: http.Server | null = null;
  
  try {
    await setup();
    
    // Mount syncRouter on a temporary Express app to avoid importing server.ts
    const app = express();
    app.use(express.json());
    app.use('/api/v1/sync', syncRouter);
    server = app.listen(9999);
    console.log('🌱 Starting STOCK-01 to STOCK-05 tests on port 9999...');

    const loginRes = await AuthService.login('testuser@stock.com', 'password123');
    const token = loginRes.access_token;

    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    };

    let saleId1 = `sale-test-${Date.now()}`;

    // STOCK-01
    const payload1 = {
      items: [
        {
          id: saleId1,
          entity_type: 'sale',
          entity_id: saleId1,
          payload: {
            id: saleId1,
            total_amount: 150.00,
            items: [
              { id: `sitem-${saleId1}`, product_id: productId, quantity: 3, unit_price: 50.00 }
            ]
          }
        }
      ]
    };

    let res = await fetch('http://localhost:9999/api/v1/sync/push', { method: 'POST', headers, body: JSON.stringify(payload1) });
    if (!res.ok) throw new Error('STOCK-01 Request Failed: ' + await res.text());
    
    let prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(prodRes.rows[0].quantity) !== 97) throw new Error('STOCK-01 FAILED');
    console.log('  ✔️ STOCK-01: Passed');

    // STOCK-02
    res = await fetch('http://localhost:9999/api/v1/sync/push', { method: 'POST', headers, body: JSON.stringify(payload1) });
    if (!res.ok) throw new Error('STOCK-02 Request Failed');
    
    prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(prodRes.rows[0].quantity) !== 97) throw new Error('STOCK-02 FAILED: Duplicate deduction!');
    console.log('  ✔️ STOCK-02: Passed');

    // STOCK-03 Concurrent
    const saleId2 = `sale-test-concurrent-${Date.now()}`;
    const payload2 = {
      items: [
        {
          id: saleId2,
          entity_type: 'sale',
          entity_id: saleId2,
          payload: {
            id: saleId2,
            total_amount: 100.00,
            items: [
              { id: `sitem-${saleId2}`, product_id: productId, quantity: 2, unit_price: 50.00 }
            ]
          }
        }
      ]
    };

    const req1 = fetch('http://localhost:9999/api/v1/sync/push', { method: 'POST', headers, body: JSON.stringify(payload2) });
    const req2 = fetch('http://localhost:9999/api/v1/sync/push', { method: 'POST', headers, body: JSON.stringify(payload2) });
    await Promise.all([req1, req2]);

    prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(prodRes.rows[0].quantity) !== 95) throw new Error('STOCK-03 FAILED: Race condition!');
    console.log('  ✔️ STOCK-03: Passed');

    // STOCK-04 Rollback
    const saleId3 = `sale-test-rollback-${Date.now()}`;
    const payload3 = {
      items: [
        {
          id: saleId3,
          entity_type: 'sale',
          entity_id: saleId3,
          payload: {
            id: saleId3,
            total_amount: 100.00,
            items: [
              { id: `sitem-${saleId3}-1`, product_id: productId, quantity: 1, unit_price: 50.00 },
              { id: `sitem-${saleId3}-2`, product_id: 'NON_EXISTENT_PRODUCT', quantity: 1, unit_price: 50.00 }
            ]
          }
        }
      ]
    };

    res = await fetch('http://localhost:9999/api/v1/sync/push', { method: 'POST', headers, body: JSON.stringify(payload3) });
    // Expect failure since NON_EXISTENT_PRODUCT should throw DB error that is caught and sent as JSON error array
    const jsonBody = await res.json() as any;
    if (!jsonBody.errors || jsonBody.errors.length === 0) throw new Error('STOCK-04 FAILED: Expected error on invalid product');
    
    prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(prodRes.rows[0].quantity) !== 95) throw new Error('STOCK-04 FAILED: Stock modified despite rollback!');
    console.log('  ✔️ STOCK-04: Passed');

    // STOCK-05
    const saleId4 = `sale-test-multi-${Date.now()}`;
    const payload4 = {
      items: [
        {
          id: saleId4,
          entity_type: 'sale',
          entity_id: saleId4,
          payload: {
            id: saleId4,
            total_amount: 90.00,
            items: [
              { id: `sitem-${saleId4}-1`, product_id: productId, quantity: 1, unit_price: 50.00 },
              { id: `sitem-${saleId4}-2`, product_id: prod2Id, quantity: 2, unit_price: 20.00 }
            ]
          }
        }
      ]
    };

    res = await fetch('http://localhost:9999/api/v1/sync/push', { method: 'POST', headers, body: JSON.stringify(payload4) });
    if (!res.ok) throw new Error('STOCK-05 Request Failed');
    
    const p1 = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(p1.rows[0].quantity) !== 94) throw new Error('STOCK-05 FAILED on Product 1');
    const p2 = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [prod2Id]);
    if (Number(p2.rows[0].quantity) !== 48) throw new Error('STOCK-05 FAILED on Product 2');
    console.log('  ✔️ STOCK-05: Passed');

    // STOCK-06: a colliding sale id owned by another tenant must not accept
    // child rows from the authenticated tenant.
    const foreignCompanyId = `foreign-company-${Date.now()}`;
    const foreignSaleId = `foreign-sale-${Date.now()}`;
    await pgPool.query(
      `INSERT INTO companies (id, name, tax_number, status)
       VALUES ($1, 'Foreign Company', $2, 'active')`,
      [foreignCompanyId, String(Date.now()).slice(-10)],
    );
    await pgPool.query(
      `INSERT INTO sales
         (id, company_id, total_amount, paid_amount, payment_method, status, created_at)
       VALUES ($1, $2, 10, 10, 'cash', 'completed', CURRENT_TIMESTAMP)`,
      [foreignSaleId, foreignCompanyId],
    );
    const collisionPayload = {
      items: [{
        id: `sync-${foreignSaleId}`,
        entity_type: 'sale',
        entity_id: foreignSaleId,
        payload: {
          id: foreignSaleId,
          total_amount: 50,
          items: [{
            id: `forged-item-${foreignSaleId}`,
            product_id: productId,
            quantity: 1,
            unit_price: 50,
          }],
        },
      }],
    };
    res = await fetch('http://localhost:9999/api/v1/sync/push', {
      method: 'POST',
      headers,
      body: JSON.stringify(collisionPayload),
    });
    const collisionBody = await res.json() as any;
    if (!collisionBody.errors?.length) {
      throw new Error('STOCK-06 FAILED: Cross-tenant sale collision was accepted');
    }
    const forgedItems = await pgPool.query(
      'SELECT COUNT(*) FROM sale_items WHERE id = $1',
      [`forged-item-${foreignSaleId}`],
    );
    if (Number(forgedItems.rows[0].count) !== 0) {
      throw new Error('STOCK-06 FAILED: Cross-tenant child row was inserted');
    }
    await pgPool.query('DELETE FROM sales WHERE id = $1', [foreignSaleId]);
    await pgPool.query('DELETE FROM companies WHERE id = $1', [foreignCompanyId]);
    console.log('  ✔️ STOCK-06: Cross-tenant collision blocked');

    console.log('🏆 Stock Regression Tests: PASS');
    if(server) server.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Stock Regression Tests: FAIL', err);
    if(server) server.close();
    process.exit(1);
  } finally {
    await pgPool.query('DELETE FROM sale_items WHERE product_id = $1 OR product_id = $2', [productId, prod2Id]);
    await pgPool.query('DELETE FROM sales WHERE company_id = $1', [mockCompanyId]);
    await pgPool.query('DELETE FROM products WHERE id = $1 OR id = $2', [productId, prod2Id]);
    await pgPool.query('DELETE FROM user_roles WHERE user_id = $1', [mockUserId]);
    await pgPool.query('DELETE FROM users WHERE id = $1', [mockUserId]);
    await pgPool.query('DELETE FROM companies WHERE id = $1', [mockCompanyId]);
    pgPool.end();
  }
}

run();
