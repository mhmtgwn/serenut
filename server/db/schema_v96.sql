-- schema_v96.sql
-- Allow decimal/fractional stock quantities and min_stock for weighted and bulk products.

ALTER TABLE products
  ALTER COLUMN quantity TYPE NUMERIC(14, 3) USING quantity::numeric,
  ALTER COLUMN min_stock TYPE NUMERIC(14, 3) USING min_stock::numeric;
