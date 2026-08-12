-- Repair ready-catalogue EAN-8 aliases produced when Excel converted a text
-- barcode such as 07031652 into the numeric value 7031652. Only exact
-- seven/eight-digit pairs with the same tenant, name and price are merged.
CREATE TEMP TABLE product_identity_merge_v89 ON COMMIT DROP AS
SELECT a.id AS alias_id, c.id AS canonical_id, a.company_id
FROM products a
JOIN products c
  ON c.id = '0' || a.id
 AND c.company_id = a.company_id
WHERE a.id ~ '^[0-9]{7}$'
  AND c.id ~ '^0[0-9]{7}$'
  AND a.status = 'active' AND NOT COALESCE(a.is_deleted, FALSE)
  AND c.status = 'active' AND NOT COALESCE(c.is_deleted, FALSE)
  AND lower(btrim(a.name)) = lower(btrim(c.name))
  AND abs(a.price - c.price) <= 0.01;

CREATE UNIQUE INDEX ON product_identity_merge_v89(alias_id);
CREATE UNIQUE INDEX ON product_identity_merge_v89(canonical_id);

UPDATE sale_items si
SET product_id = m.canonical_id
FROM product_identity_merge_v89 m
WHERE si.product_id = m.alias_id;

UPDATE customer_order_items oi
SET product_id = m.canonical_id
FROM product_identity_merge_v89 m
WHERE oi.product_id = m.alias_id;

UPDATE refund_items ri
SET product_id = m.canonical_id
FROM product_identity_merge_v89 m
WHERE ri.product_id = m.alias_id;

UPDATE inventory_movements im
SET product_id = m.canonical_id
FROM product_identity_merge_v89 m
WHERE im.product_id = m.alias_id;

-- Operational values come from the most recently updated row. The existing
-- valid EAN-8 identity and any available image are retained.
UPDATE products c
SET name = CASE WHEN a.updated_at > c.updated_at THEN a.name ELSE c.name END,
    description = CASE WHEN a.updated_at > c.updated_at THEN a.description ELSE c.description END,
    price = CASE WHEN a.updated_at > c.updated_at THEN a.price ELSE c.price END,
    purchase_price = CASE WHEN a.updated_at > c.updated_at THEN a.purchase_price ELSE c.purchase_price END,
    quantity = CASE WHEN a.updated_at > c.updated_at THEN a.quantity ELSE c.quantity END,
    min_stock = CASE WHEN a.updated_at > c.updated_at THEN a.min_stock ELSE c.min_stock END,
    brand = CASE WHEN a.updated_at > c.updated_at THEN a.brand ELSE c.brand END,
    unit = CASE WHEN a.updated_at > c.updated_at THEN a.unit ELSE c.unit END,
    shelf_code = CASE WHEN a.updated_at > c.updated_at THEN a.shelf_code ELSE c.shelf_code END,
    category = CASE WHEN a.updated_at > c.updated_at THEN a.category ELSE c.category END,
    vat = CASE WHEN a.updated_at > c.updated_at THEN a.vat ELSE c.vat END,
    image_path = COALESCE(NULLIF(c.image_path, ''), NULLIF(a.image_path, '')),
    status = 'active',
    is_deleted = FALSE,
    deleted_at = NULL,
    deleted_by = NULL,
    updated_at = NOW()
FROM product_identity_merge_v89 m
JOIN products a ON a.id = m.alias_id
WHERE c.id = m.canonical_id;

UPDATE products a
SET status = 'inactive',
    is_deleted = TRUE,
    deleted_at = NOW(),
    deleted_by = 'migration-v89',
    updated_at = NOW()
FROM product_identity_merge_v89 m
WHERE a.id = m.alias_id;

-- Publish both sides of the merge through Sync V4 so installed devices do
-- not have to wait for their local migration to discover the repair.
INSERT INTO sync_v4_changes
  (tenant_id, mutation_id, device_id, entity_type, entity_id, operation, payload)
SELECT p.company_id,
       gen_random_uuid(),
       'migration-v89',
       'product',
       p.id,
       'UPSERT',
       jsonb_build_object(
         'id', p.id, 'name', p.name, 'description', COALESCE(p.description, ''),
         'price', p.price, 'purchase_price', COALESCE(p.purchase_price, 0),
         'quantity', p.quantity, 'min_stock', COALESCE(p.min_stock, 5),
         'brand', COALESCE(p.brand, ''), 'unit', COALESCE(p.unit, 'adet'),
         'shelf_code', COALESCE(p.shelf_code, ''), 'category', COALESCE(p.category, 'Genel'),
         'sku', COALESCE(p.sku, p.id), 'vat', p.vat,
         'image_url', COALESCE(p.image_path, ''), 'status', 'active',
         'is_active', 1, 'is_deleted', 0, 'created_at', p.created_at,
         'updated_at', p.updated_at
       )
FROM products p
JOIN product_identity_merge_v89 m ON m.canonical_id = p.id;

INSERT INTO sync_v4_changes
  (tenant_id, mutation_id, device_id, entity_type, entity_id, operation, payload)
SELECT m.company_id,
       gen_random_uuid(),
       'migration-v89',
       'product',
       m.alias_id,
       'DELETE',
       jsonb_build_object('id', m.alias_id, 'is_deleted', 1)
FROM product_identity_merge_v89 m;

INSERT INTO sync_v4_entities
  (tenant_id, entity_type, entity_id, is_deleted, payload, updated_revision)
SELECT c.tenant_id,
       c.entity_type,
       c.entity_id,
       c.operation = 'DELETE',
       c.payload,
       c.revision
FROM sync_v4_changes c
JOIN product_identity_merge_v89 m
  ON m.company_id = c.tenant_id
 AND (m.alias_id = c.entity_id OR m.canonical_id = c.entity_id)
WHERE c.device_id = 'migration-v89'
ON CONFLICT (tenant_id, entity_type, entity_id) DO UPDATE SET
  is_deleted = EXCLUDED.is_deleted,
  payload = EXCLUDED.payload,
  updated_revision = EXCLUDED.updated_revision,
  updated_at = NOW()
WHERE sync_v4_entities.updated_revision < EXCLUDED.updated_revision;
