import { pgPool } from '../config/database';
import { SyncService } from '../modules/sync/sync.service';

const mockCompanyId = 'test-company-123';
const mockUserId = 'test-user-123';
const productId = 'prod-test-01';

async function setup() {
  console.log('🔄 Setting up database for Stock Regression Test...');
  await pgPool.query('DELETE FROM sale_items WHERE product_id = $1', [productId]);
  await pgPool.query('DELETE FROM sales WHERE company_id = $1', [mockCompanyId]);
  await pgPool.query('DELETE FROM products WHERE id = $1', [productId]);
  await pgPool.query('DELETE FROM companies WHERE id = $1', [mockCompanyId]);

  await pgPool.query(`INSERT INTO companies (id, name, owner_id) VALUES ($1, 'Test Company', $2)`, [mockCompanyId, mockUserId]);
  await pgPool.query(`
    INSERT INTO products (id, company_id, name, price, quantity, status) 
    VALUES ($1, $2, 'Test Product', 50.00, 100, 'active')
  `, [productId, mockCompanyId]);
}

async function run() {
  await setup();
  console.log('🌱 Starting STOCK-01 to STOCK-05 tests...');

  try {
    let saleId1 = `sale-test-${Date.now()}`;

    // STOCK-01
    const payload1 = {
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

    await SyncService.processSyncPayload(mockCompanyId, payload1);
    
    let prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(prodRes.rows[0].quantity) !== 97) throw new Error('STOCK-01 FAILED');
    console.log('  ✔️ STOCK-01: Passed');

    // STOCK-02
    await SyncService.processSyncPayload(mockCompanyId, payload1);
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

    await Promise.all([
      SyncService.processSyncPayload(mockCompanyId, payload2),
      SyncService.processSyncPayload(mockCompanyId, payload2)
    ]);

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

    const res3 = await SyncService.processSyncPayload(mockCompanyId, payload3);
    if (res3.errors.length === 0) throw new Error('STOCK-04 FAILED: Expected error on invalid product');
    
    prodRes = await pgPool.query('SELECT quantity FROM products WHERE id = $1', [productId]);
    if (Number(prodRes.rows[0].quantity) !== 95) throw new Error('STOCK-04 FAILED: Stock modified despite rollback!');
    console.log('  ✔️ STOCK-04: Passed');

    console.log('🏆 Stock Regression Tests: PASS');
    process.exit(0);
  } catch (err) {
    console.error('❌ Stock Regression Tests: FAIL', err);
    process.exit(1);
  } finally {
    await pgPool.query('DELETE FROM sale_items WHERE product_id = $1', [productId]);
    await pgPool.query('DELETE FROM sales WHERE company_id = $1', [mockCompanyId]);
    await pgPool.query('DELETE FROM products WHERE id = $1', [productId]);
    await pgPool.query('DELETE FROM companies WHERE id = $1', [mockCompanyId]);
    pgPool.end();
  }
}

run();
