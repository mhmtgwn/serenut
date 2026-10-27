import assert from 'node:assert/strict';
import { upsertSale } from '../modules/sync_v4/sync-v4.materializer';

// Minimal mock PoolClient to test upsertSale calculation and query execution
function createMockClient() {
  const executedQueries: Array<{ sql: string; params?: any[] }> = [];
  return {
    executedQueries,
    query: async (sql: string, params?: any[]) => {
      executedQueries.push({ sql, params });
      if (sql.includes('FROM sales WHERE id = $1')) {
        return { rowCount: 0, rows: [] };
      }
      if (sql.includes('FROM customers WHERE id = $1')) {
        return { rowCount: 1, rows: [{ id: params?.[0] }] };
      }
      return { rowCount: 1, rows: [] };
    },
  } as any;
}

async function testWeighedKuruyemisPrecision() {
  const mockClient = createMockClient();
  const companyId = 'company-test';
  const saleId = 'sale-precision-1';

  // 3 weighed products with fractional quantities and prices that produce floating point decimals
  const payload = {
    customer_id: null,
    payment_method: 'cash',
    total_amount: 371.65,
    paid_amount: 371.65,
    discount_amount: 0,
    items: [
      {
        id: 'item-1',
        product_id: 'prod-findik',
        product_name: 'Giresun Fındık',
        quantity: 0.355,
        unit_price: 425.50,
        subtotal: 151.05, // half-up: 425.50 * 0.355 = 151.0525 -> 151.05
      },
      {
        id: 'item-2',
        product_id: 'prod-badem',
        product_name: 'Kavrulmuş Badem',
        quantity: 0.240,
        unit_price: 680.00,
        subtotal: 163.20, // 680.00 * 0.240 = 163.20
      },
      {
        id: 'item-3',
        product_id: 'prod-leblebi',
        product_name: 'Sarı Leblebi',
        quantity: 0.185,
        unit_price: 310.25,
        subtotal: 57.40, // half-up: 310.25 * 0.185 = 57.39625 -> 57.40
      },
    ],
  };

  await upsertSale(mockClient, companyId, saleId, payload);

  // Verify that INSERT INTO sales received the exact clientTotal and effectivePaidAmount
  const insertSaleQuery = mockClient.executedQueries.find((q: any) => q.sql.includes('INSERT INTO sales'));
  assert.ok(insertSaleQuery, 'INSERT INTO sales query must be executed');
  assert.equal(insertSaleQuery.params?.[3], 371.65, 'Total amount must match 371.65 TL');
  assert.equal(insertSaleQuery.params?.[4], 371.65, 'Paid amount must match 371.65 TL');

  // Verify sale_items received kurus-accurate subtotals
  const insertItemQueries = mockClient.executedQueries.filter((q: any) => q.sql.includes('INSERT INTO sale_items'));
  assert.equal(insertItemQueries.length, 3, 'Must insert 3 sale items');
  assert.equal(insertItemQueries[0].params?.[6], 151.05, 'Item 1 subtotal must be 151.05');
  assert.equal(insertItemQueries[1].params?.[6], 163.20, 'Item 2 subtotal must be 163.20');
  assert.equal(insertItemQueries[2].params?.[6], 57.40, 'Item 3 subtotal must be 57.40');

  console.log('✅ Weighed kuruyemiş kuruş precision test passed with zero floating drift.');
}

async function testSaleTotalMismatchRejection() {
  const mockClient = createMockClient();
  const companyId = 'company-test';
  const saleId = 'sale-mismatch-1';

  // Intentionally corrupted total_amount by > 0.05 TL
  const payload = {
    customer_id: null,
    payment_method: 'cash',
    total_amount: 500.00, // actual should be ~100.00
    paid_amount: 500.00,
    items: [
      {
        id: 'item-1',
        product_id: 'prod-1',
        quantity: 1,
        unit_price: 100.00,
        subtotal: 100.00,
      },
    ],
  };

  let threw = false;
  try {
    await upsertSale(mockClient, companyId, saleId, payload);
  } catch (err: any) {
    threw = true;
    assert.equal(err.message, 'sale_total_mismatch');
  }
  assert.ok(threw, 'Must throw sale_total_mismatch on fraudulent total');
  console.log('✅ Corrupted sale total was correctly rejected.');
}

async function run() {
  await testWeighedKuruyemisPrecision();
  await testSaleTotalMismatchRejection();
  console.log('🎉 All sync v4 precision tests passed.');
}

run().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
