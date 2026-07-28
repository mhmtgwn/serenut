-- Unify branch visibility. `branches` is the management model; each branch
-- keeps a one-to-one `stores` row for device and legacy sales references.

-- Preserve branch-only records by creating their physical store counterpart.
INSERT INTO stores (id, company_id, name, address)
SELECT 'store-' || MD5(b.id), b.company_id, b.name, b.address
FROM branches b
WHERE b.store_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM stores s
    WHERE s.company_id = b.company_id
      AND LOWER(TRIM(s.name)) = LOWER(TRIM(b.name))
  )
ON CONFLICT DO NOTHING;

-- Link branches to an unambiguous same-company store.
UPDATE branches b
SET store_id = s.id
FROM stores s
WHERE b.store_id IS NULL
  AND s.company_id = b.company_id
  AND LOWER(TRIM(s.name)) = LOWER(TRIM(b.name))
  AND NOT EXISTS (
    SELECT 1 FROM stores duplicate
    WHERE duplicate.company_id = s.company_id
      AND LOWER(TRIM(duplicate.name)) = LOWER(TRIM(s.name))
      AND duplicate.id <> s.id
  );

-- Existing companies created without a location receive a real default store.
INSERT INTO stores (id, company_id, name, address)
SELECT 'store-default-' || MD5(c.id), c.id, 'Merkez Şube', c.address
FROM companies c
WHERE NOT EXISTS (SELECT 1 FROM stores s WHERE s.company_id = c.id)
ON CONFLICT DO NOTHING;

-- Backfill a management branch for every physical store that is not represented.
INSERT INTO branches (id, company_id, store_id, name, address, is_active)
SELECT 'branch-' || MD5(s.id), s.company_id, s.id, s.name, s.address, TRUE
FROM stores s
WHERE NOT EXISTS (SELECT 1 FROM branches b WHERE b.store_id = s.id)
  AND NOT EXISTS (
    SELECT 1 FROM branches b
    WHERE b.company_id = s.company_id
      AND LOWER(TRIM(b.name)) = LOWER(TRIM(s.name))
  )
ON CONFLICT DO NOTHING;

CREATE UNIQUE INDEX IF NOT EXISTS idx_branches_store_id
  ON branches(store_id)
  WHERE store_id IS NOT NULL;
