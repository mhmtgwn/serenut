-- server/db/schema_v36.sql
-- Drop global unique constraint on license_key to allow historical audit rows and replace with a partial active unique index

ALTER TABLE license_entitlements DROP CONSTRAINT IF EXISTS uq_license_entitlements_key;
DROP INDEX IF EXISTS uq_active_license_key;
CREATE UNIQUE INDEX uq_active_license_key ON license_entitlements(license_key) WHERE status IN ('trial', 'active');
