-- Preserve the label that was valid when a sale/order line was recorded.
ALTER TABLE sale_items
  ADD COLUMN IF NOT EXISTS product_name TEXT;
ALTER TABLE customer_order_items
  ADD COLUMN IF NOT EXISTS product_name TEXT;

UPDATE sale_items si
   SET product_name = p.name
  FROM products p
 WHERE p.id = si.product_id
   AND (si.product_name IS NULL OR si.product_name = '');

UPDATE customer_order_items oi
   SET product_name = p.name
  FROM products p
 WHERE p.id = oi.product_id
   AND (oi.product_name IS NULL OR oi.product_name = '');
