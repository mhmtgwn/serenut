-- server/db/schema_v27.sql
-- Serenut OS -- Commercial Lifecycle V3 -- Phase 2 (License Key Migration to Entitlements)

-- 1. ADD COLUMN TO CANONICAL ENTITLEMENTS TABLE
ALTER TABLE license_entitlements ADD COLUMN IF NOT EXISTS license_key VARCHAR(100);

-- 2. MIGRATE EXISTING LICENSE KEYS FROM LEGACY TABLE
UPDATE license_entitlements le
SET license_key = l.license_key
FROM licenses l
WHERE le.company_id = l.company_id
  AND le.license_key IS NULL;

-- 3. ENSURE UNIQUE CONSTRAINT ON LICENSE KEY
-- In order to add UNIQUE constraint safely, we first generate keys for any NULL rows (should not exist in prod, but safe)
DO $$
DECLARE
    rec RECORD;
    new_key VARCHAR(100);
BEGIN
    FOR rec IN SELECT id, company_id FROM license_entitlements WHERE license_key IS NULL LOOP
        new_key := 'SRNT-' || 
                   upper(substring(md5(random()::text) from 1 for 4)) || '-' ||
                   upper(substring(md5(random()::text) from 5 for 4)) || '-' ||
                   upper(substring(md5(random()::text) from 9 for 4)) || '-' ||
                   upper(substring(md5(random()::text) from 13 for 4));
        UPDATE license_entitlements SET license_key = new_key WHERE id = rec.id;
    END LOOP;
END $$;

-- Now add unique constraint (if not already existing)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_license_entitlements_key'
    ) THEN
        ALTER TABLE license_entitlements ADD CONSTRAINT uq_license_entitlements_key UNIQUE (license_key);
    END IF;
END $$;
