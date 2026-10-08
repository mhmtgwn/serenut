-- schema_v93.sql
-- Add discount_amount to sales and customer_orders for cross-device sync fidelity.

ALTER TABLE sales
  ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00;

ALTER TABLE customer_orders
  ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00;
