ALTER TABLE customer_orders
  ADD COLUMN IF NOT EXISTS order_number VARCHAR(180);

-- Orders created before the cloud schema stored order numbers still need a
-- stable value when bootstrapped into SQLite, where the column is NOT NULL.
UPDATE customer_orders
SET order_number = 'SYNC-' || id
WHERE order_number IS NULL OR BTRIM(order_number) = '';

ALTER TABLE customer_orders
  ALTER COLUMN order_number SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customer_orders_company_order_number
  ON customer_orders(company_id, order_number);
