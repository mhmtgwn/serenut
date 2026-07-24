-- Explicitly link order branches to physical stores used by device records.
ALTER TABLE branches
  ADD COLUMN IF NOT EXISTS store_id VARCHAR(100)
  REFERENCES stores(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_branches_store_id
  ON branches(store_id)
  WHERE store_id IS NOT NULL;

-- Backfill only unambiguous same-tenant, same-name matches.
UPDATE branches b
SET store_id = matched.store_id
FROM (
  SELECT b2.id AS branch_id, MIN(s.id) AS store_id
  FROM branches b2
  JOIN stores s
    ON s.company_id = b2.company_id
   AND LOWER(TRIM(s.name)) = LOWER(TRIM(b2.name))
  WHERE b2.store_id IS NULL
  GROUP BY b2.id
  HAVING COUNT(s.id) = 1
) matched
WHERE b.id = matched.branch_id;
