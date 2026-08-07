import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { RefundService } from '../modules/order/refund.service';

async function refund(key: string, quantity: number) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    const result = await RefundService.create(client, {
      companyId: 'refund-company', saleId: 'refund-sale', actorId: 'refund-user',
      idempotencyKey: key, reason: 'Müşteri ürün iadesi', refundMethod: 'cash',
      items: [{ saleItemId: 'refund-sale-item', quantity }],
    });
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

async function run() {
  const setup = await pgPool.connect();
  try { await setup.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public'); }
  finally { setup.release(); }
  await runMigrations(pgPool);
  await pgPool.query("SET app.bypass_rls='true'");
  await pgPool.query(`INSERT INTO companies(id,name,tax_number,status) VALUES('refund-company','Refund Co','refund-tax','active')`);
  await pgPool.query(`INSERT INTO users(id,company_id,name,email,password_hash) VALUES('refund-user','refund-company','User','refund@test.local','x')`);
  await pgPool.query(`INSERT INTO customers(id,company_id,name,balance) VALUES('refund-customer','refund-company','Customer',0)`);
  await pgPool.query(`INSERT INTO products(id,company_id,name,price,quantity) VALUES('refund-product','refund-company','Product',50,8)`);
  await pgPool.query(`INSERT INTO sales(id,company_id,customer_id,total_amount,paid_amount,payment_method,status,fsm_state,created_at)
    VALUES('refund-sale','refund-company','refund-customer',100,100,'cash','completed','completed',NOW())`);
  await pgPool.query(`INSERT INTO sale_items(id,sale_id,product_id,quantity,unit_price,subtotal,company_id)
    VALUES('refund-sale-item','refund-sale','refund-product',2,50,100,'refund-company')`);

  const same = await Promise.all([refund('same-key', 1), refund('same-key', 1)]);
  if (same.filter(r => r.idempotent).length !== 1 || same[0].refundId !== same[1].refundId) {
    throw new Error('Concurrent idempotency did not converge to one refund.');
  }
  const [stock, refunds, movements, sale] = await Promise.all([
    pgPool.query(`SELECT quantity FROM products WHERE id='refund-product'`),
    pgPool.query(`SELECT count(*)::int count FROM refunds WHERE sale_id='refund-sale'`),
    pgPool.query(`SELECT count(*)::int count FROM inventory_movements WHERE reference_type='refund'`),
    pgPool.query(`SELECT refunded_amount,fsm_state FROM sales WHERE id='refund-sale'`),
  ]);
  if (Number(stock.rows[0].quantity) !== 9 || refunds.rows[0].count !== 1 || movements.rows[0].count !== 1 ||
      Number(sale.rows[0].refunded_amount) !== 50 || sale.rows[0].fsm_state !== 'partially_refunded') {
    throw new Error('Partial refund did not update stock and sale exactly once.');
  }
  await refund('final-key', 1);
  const final = await pgPool.query(`SELECT p.quantity,s.refunded_amount,s.fsm_state,
    (SELECT count(*) FROM refunds WHERE sale_id=s.id) refund_count
    FROM sales s JOIN products p ON p.id='refund-product' WHERE s.id='refund-sale'`);
  const row = final.rows[0];
  if (Number(row.quantity) !== 10 || Number(row.refunded_amount) !== 100 || row.fsm_state !== 'refunded' || Number(row.refund_count) !== 2) {
    throw new Error('Full refund invariant failed.');
  }
  let rejected = false;
  try { await refund('excess-key', 1); } catch (error: any) { rejected = error.message === 'sale_not_refundable'; }
  if (!rejected) throw new Error('Over-refund was not rejected.');
  console.log('✔ Refund aggregate is idempotent, stock-safe, immutable, and bounded by sold quantity.');
}

run().then(() => process.exit(0)).catch(error => { console.error('❌ Refund lifecycle test failed', error); process.exit(1); });
