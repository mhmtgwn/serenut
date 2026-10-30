-- schema_v110.sql
-- Allow walk-in and quick orders without a pre-registered customer
ALTER TABLE customer_orders ALTER COLUMN customer_id DROP NOT NULL;

