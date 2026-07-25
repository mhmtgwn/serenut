-- Migration v49: Add sku column to products table
-- Products pushed from Flutter clients include a sku field which was missing in the server schema.
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku TEXT;
-- Backfill existing rows: use id as fallback sku
UPDATE products SET sku = id WHERE sku IS NULL;
