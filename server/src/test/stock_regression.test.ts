import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import request from 'supertest';
import { app } from '../server'; // Express App
import { pgPool } from '../db';

// Setup Mock User & Auth Token for testing
const mockCompanyId = 'test-company-123';
const mockUserId = 'test-user-123';
const mockToken = 'mock-test-token-valid';

// Helper to generate a deterministic mock product ID
const productId = 'prod-test-01';

beforeAll(async () => {
  // Clear any previous test data
  await pgPool.query('DELETE FROM sale_items WHERE product_id = $1', [productId]);
  await pgPool.query('DELETE FROM sales WHERE company_id = $1', [mockCompanyId]);
  await pgPool.query('DELETE FROM products WHERE id = $1', [productId]);
  await pgPool.query('DELETE FROM companies WHERE id = $1', [mockCompanyId]);

  // Insert test company
  await pgPool.query(`INSERT INTO companies (id, name, owner_id) VALUES ($1, 'Test Company', $2)`, [mockCompanyId, mockUserId]);
  
  // Insert test product with exactly 100 stock
  await pgPool.query(`
    INSERT INTO products (id, company_id, name, price, quantity, status) 
    VALUES ($1, $2, 'Test Product', 50.00, 100, 'active')
  `, [productId, mockCompanyId]);
});

afterAll(async () => {
  await pgPool.query('DELETE FROM sale_items WHERE product_id = $1', [productId]);
  await pgPool.query('DELETE FROM sales WHERE company_id = $1', [mockCompanyId]);
  await pgPool.query('DELETE FROM products WHERE id = $1', [productId]);
  await pgPool.query('DELETE FROM companies WHERE id = $1', [mockCompanyId]);
  await pgPool.end();
});

describe('Sale - Stock Synchronization Adversarial Regression (Phases 3)', () => {
  
  let saleId1 = `sale-test-${Date.now()}`;

  // STOCK-01: Normal Sale
  it('STOCK-01: Should process a normal sale and deduct stock exactly once', async () => {
    const payload = {
      items: [
        {
          id: saleId1,
          entity_type: 'sale',
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

    const res = await request(app)
      .post('/api/v1/sync/push')
      .set('Authorization', `Bearer ${mockToken}`) // Assumes standard auth or test bypass
      .send(payload);

    // Expect successful sync
    expect(res.status).toBe(200);

    // Verify Stock
    const prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    expect(Number(prodRes.rows[0].quantity)).toBe(97); // 100 - 3
  });

  // STOCK-02: Exact Duplicate Retry
  it('STOCK-02: Should safely ignore exact duplicate retry without double-deducting stock', async () => {
    const payload = {
      items: [
        {
          id: saleId1,
          entity_type: 'sale',
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

    const res = await request(app)
      .post('/api/v1/sync/push')
      .set('Authorization', `Bearer ${mockToken}`)
      .send(payload);

    expect(res.status).toBe(200);

    // Verify Stock is still 97!
    const prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    expect(Number(prodRes.rows[0].quantity)).toBe(97); 
  });

  // STOCK-03: Concurrent Duplicate Retry
  it('STOCK-03: Should safely handle concurrent duplicate payload pushes without race conditions', async () => {
    const saleId2 = `sale-test-concurrent-${Date.now()}`;
    const payload = {
      items: [
        {
          id: saleId2,
          entity_type: 'sale',
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

    // Fire two identical requests simultaneously
    const req1 = request(app).post('/api/v1/sync/push').set('Authorization', `Bearer ${mockToken}`).send(payload);
    const req2 = request(app).post('/api/v1/sync/push').set('Authorization', `Bearer ${mockToken}`).send(payload);

    await Promise.all([req1, req2]);

    // Verify Stock dropped by EXACTLY 2 (from 97 to 95)
    const prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    expect(Number(prodRes.rows[0].quantity)).toBe(95); 
  });
  
  // STOCK-04: Transaction Rollback Verification
  it('STOCK-04: Should rollback all partial mutations if one item fails', async () => {
    const saleId3 = `sale-test-rollback-${Date.now()}`;
    const payload = {
      items: [
        {
          id: saleId3,
          entity_type: 'sale',
          payload: {
            id: saleId3,
            total_amount: 100.00,
            items: [
              { id: `sitem-${saleId3}-1`, product_id: productId, quantity: 1, unit_price: 50.00 },
              { id: `sitem-${saleId3}-2`, product_id: 'NON_EXISTENT_PRODUCT', quantity: 1, unit_price: 50.00 } // This will cause foreign key violation
            ]
          }
        }
      ]
    };

    const res = await request(app)
      .post('/api/v1/sync/push')
      .set('Authorization', `Bearer ${mockToken}`)
      .send(payload);

    // One of the items fails, so the sync response might still be 200 but error in the array.
    expect(res.status).toBe(200);
    expect(res.body.errors.length).toBeGreaterThan(0);

    // Verify Stock is untouched (still 95)
    const prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    expect(Number(prodRes.rows[0].quantity)).toBe(95); 

    // Verify partial sale doesn't exist
    const saleRes = await pgPool.query('SELECT * FROM sales WHERE id = $1', [saleId3]);
    expect(saleRes.rows.length).toBe(0);
  });

  // STOCK-05: Multi-Product Sale
  it('STOCK-05: Should deduct stock proportionally for multi-product sales', async () => {
    const prod2Id = 'prod-test-02';
    await pgPool.query(`
      INSERT INTO products (id, company_id, name, price, quantity, status) 
      VALUES ($1, $2, 'Test Product 2', 20.00, 50, 'active')
    `, [prod2Id, mockCompanyId]);

    const saleId4 = `sale-test-multi-${Date.now()}`;
    const payload = {
      items: [
        {
          id: saleId4,
          entity_type: 'sale',
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

    await request(app).post('/api/v1/sync/push').set('Authorization', `Bearer ${mockToken}`).send(payload);

    // Stock for prod 1 drops by 1 (95 -> 94)
    const p1 = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    expect(Number(p1.rows[0].quantity)).toBe(94); 

    // Stock for prod 2 drops by 2 (50 -> 48)
    const p2 = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [prod2Id]);
    expect(Number(p2.rows[0].quantity)).toBe(48);

    await pgPool.query('DELETE FROM products WHERE id = $1', [prod2Id]);
  });

});
