-- Tenant-scoped custom roles and agreed commercial limits.
ALTER TABLE roles ADD COLUMN IF NOT EXISTS company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE;
ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_name_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_global_name
  ON roles(name) WHERE company_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_company_name
  ON roles(company_id, LOWER(name)) WHERE company_id IS NOT NULL;

UPDATE plans SET device_limit = 2, store_limit = 1, user_limit = 4 WHERE id = 'plan-basic';
UPDATE plans SET device_limit = 6, store_limit = 3, user_limit = 11 WHERE id = 'plan-pro';
