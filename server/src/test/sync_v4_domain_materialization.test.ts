import { pgPool } from '../config/database';
import { runMigrations } from '../migrations';
import { applyDomainMutation } from '../modules/sync_v4/sync-v4.routes';

async function run() {
  const setupClient = await pgPool.connect();
  try {
    await setupClient.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public;');
  } finally {
    setupClient.release();
  }
  await runMigrations(pgPool);

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.current_company_id', $1, true)", ['sync-v4-company']);
    await client.query(
      `INSERT INTO companies (id, name, tax_number, tax_office, status)
       VALUES ('sync-v4-company', 'Sync V4 Co', '1234567890', 'Ankara', 'active')`,
    );

    await applyDomainMutation(client, 'sync-v4-company', {
      entity_type: 'product', entity_id: 'product-1', operation: 'UPSERT', base_revision: 0,
      payload: { name: 'Çay', price: 15, quantity: 20, category: 'İçecek', vat: 10 },
    });
    await applyDomainMutation(client, 'sync-v4-company', {
      entity_type: 'customer', entity_id: 'customer-1', operation: 'UPSERT', base_revision: 0,
      payload: { name: 'Ayşe', balance: 0, credit_limit: 0 },
    });
    const sale = {
      entity_type: 'sale', entity_id: 'sale-1', operation: 'UPSERT' as const, base_revision: 0,
      payload: {
        customer_id: 'customer-1', total_amount: 30, paid_amount: 30,
        payment_method: 'cash', status: 'completed',
        items: [{ id: 'sale-item-1', product_id: 'product-1', quantity: 2, unit_price: 15 }],
      },
    };
    await applyDomainMutation(client, 'sync-v4-company', sale);
    await applyDomainMutation(client, 'sync-v4-company', sale); // idempotent materialization
    await applyDomainMutation(client, 'sync-v4-company', {
      entity_type: 'order', entity_id: 'order-1', operation: 'UPSERT', base_revision: 0,
      payload: {
        customer_id: 'customer-1', status: 'created', total_amount: 15,
        items: [{ id: 'order-item-1', product_id: 'product-1', quantity: 1, unit_price: 15 }],
      },
    });
    await applyDomainMutation(client, 'sync-v4-company', {
      entity_type: 'financial_transaction', entity_id: 'ledger-1', operation: 'UPSERT', base_revision: 0,
      payload: { type: 'sale', customer_id: 'customer-1', amount: 30, paid_amount: 30, debt_amount: 0, date: '2026-07-27T00:00:00.000Z' },
    });
    await client.query('COMMIT');
    client.release();

    const [saleRows, saleItemRows, orderRows, orderItemRows, ledgerRows] = await Promise.all([
      pgPool.query("SELECT id FROM sales WHERE company_id = 'sync-v4-company'"),
      pgPool.query("SELECT id FROM sale_items WHERE sale_id = 'sale-1'"),
      pgPool.query("SELECT id FROM customer_orders WHERE company_id = 'sync-v4-company'"),
      pgPool.query("SELECT id FROM customer_order_items WHERE order_id = 'order-1'"),
      pgPool.query("SELECT id FROM financial_transactions WHERE company_id = 'sync-v4-company'"),
    ]);
    if (saleRows.rowCount !== 1 || saleItemRows.rowCount !== 1 || orderRows.rowCount !== 1 || orderItemRows.rowCount !== 1 || ledgerRows.rowCount !== 1) {
      throw new Error('Sync V4 mutation was not materialized exactly once in all domain tables.');
    }
    console.log('✔ Sync V4 materializes product/customer/sale/order/ledger aggregates transactionally.');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

run().then(() => process.exit(0)).catch((error) => {
  console.error('❌ Sync V4 domain materialization test failed', error);
  process.exit(1);
});
