-- server/db/schema_v23.sql
-- Serenut OS -- Commercial Lifecycle V2 -- Phase 1 (Core Model)
-- 1. Roles & Permissions seed
-- 2. Plans: device_limit, store_limit, user_limit, trial_days, is_active columns
-- 3. Companies: business_code
-- 4. Users: username, pin_hash

-- ── 1. ROLES & PERMISSIONS SEED ──────────────────────────────────────────────
INSERT INTO roles (id, name, description) VALUES
  ('sysadmin', 'sysadmin', 'Platform system administrator -- full access'),
  ('owner',    'owner',    'Business owner -- manages billing, users, devices'),
  ('manager',  'manager',  'Store manager -- inventory, devices, reports'),
  ('cashier',  'cashier',  'Cashier -- sales transactions only'),
  ('staff',    'staff',    'Staff -- read-only reports')
ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description;

INSERT INTO permissions (id, code, description) VALUES
  ('perm-billing-manage',     'billing:manage',      'Manage subscription and billing'),
  ('perm-billing-view',       'billing:view',        'View invoices and billing history'),
  ('perm-users-manage',       'users:manage',        'Create, edit, deactivate sub-users'),
  ('perm-devices-manage',     'devices:manage',      'Register and revoke devices'),
  ('perm-devices-view',       'devices:view',        'View registered devices'),
  ('perm-sales-create',       'sales:create',        'Create sales transactions'),
  ('perm-sales-view',         'sales:view',          'View sales records'),
  ('perm-inventory-manage',   'inventory:manage',    'Manage stock levels and products'),
  ('perm-inventory-view',     'inventory:view',      'View inventory'),
  ('perm-reports-view',       'reports:view',        'View analytics and reports'),
  ('perm-settings-manage',    'settings:manage',     'Manage store settings'),
  ('perm-platform-iban',      'platform:iban',       'Manage platform bank accounts (sysadmin only)')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id) VALUES
  ('sysadmin', 'perm-billing-manage'),
  ('sysadmin', 'perm-billing-view'),
  ('sysadmin', 'perm-users-manage'),
  ('sysadmin', 'perm-devices-manage'),
  ('sysadmin', 'perm-devices-view'),
  ('sysadmin', 'perm-sales-create'),
  ('sysadmin', 'perm-sales-view'),
  ('sysadmin', 'perm-inventory-manage'),
  ('sysadmin', 'perm-inventory-view'),
  ('sysadmin', 'perm-reports-view'),
  ('sysadmin', 'perm-settings-manage'),
  ('sysadmin', 'perm-platform-iban'),
  ('owner', 'perm-billing-manage'),
  ('owner', 'perm-billing-view'),
  ('owner', 'perm-users-manage'),
  ('owner', 'perm-devices-manage'),
  ('owner', 'perm-devices-view'),
  ('owner', 'perm-sales-create'),
  ('owner', 'perm-sales-view'),
  ('owner', 'perm-inventory-manage'),
  ('owner', 'perm-inventory-view'),
  ('owner', 'perm-reports-view'),
  ('owner', 'perm-settings-manage'),
  ('manager', 'perm-devices-manage'),
  ('manager', 'perm-devices-view'),
  ('manager', 'perm-sales-create'),
  ('manager', 'perm-sales-view'),
  ('manager', 'perm-inventory-manage'),
  ('manager', 'perm-inventory-view'),
  ('manager', 'perm-reports-view'),
  ('cashier', 'perm-sales-create'),
  ('cashier', 'perm-sales-view'),
  ('cashier', 'perm-inventory-view'),
  ('staff', 'perm-reports-view'),
  ('staff', 'perm-sales-view'),
  ('staff', 'perm-inventory-view')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ── 2. PLANS -- ADD LIMIT COLUMNS ────────────────────────────────────────────
ALTER TABLE plans ADD COLUMN IF NOT EXISTS code VARCHAR(50);
ALTER TABLE plans ADD COLUMN IF NOT EXISTS device_limit INTEGER NOT NULL DEFAULT 1;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS store_limit INTEGER NOT NULL DEFAULT 1;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS user_limit INTEGER NOT NULL DEFAULT 5;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS trial_days INTEGER DEFAULT 30;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_plans_code ON plans(code) WHERE code IS NOT NULL;

UPDATE plans SET code='free',       device_limit=1,  store_limit=1,  user_limit=3,   trial_days=30, is_active=TRUE WHERE id='plan-free';
UPDATE plans SET code='basic',      device_limit=2,  store_limit=1,  user_limit=5,   trial_days=0,  is_active=TRUE WHERE id='plan-basic';
UPDATE plans SET code='pro',        device_limit=5,  store_limit=3,  user_limit=15,  trial_days=0,  is_active=TRUE WHERE id='plan-pro';
UPDATE plans SET code='enterprise', device_limit=99, store_limit=99, user_limit=999, trial_days=0,  is_active=TRUE WHERE id='plan-enterprise';

-- ── 3. COMPANIES -- business_code ─────────────────────────────────────────────
ALTER TABLE companies ADD COLUMN IF NOT EXISTS business_code VARCHAR(20);
CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_business_code ON companies(business_code) WHERE business_code IS NOT NULL;

UPDATE companies
SET business_code = 'SRNTT-' || UPPER(SUBSTRING(MD5(id) FROM 1 FOR 6))
WHERE business_code IS NULL;

-- ── 4. USERS -- username & pin_hash ──────────────────────────────────────────
ALTER TABLE users ADD COLUMN IF NOT EXISTS username VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_company
  ON users(company_id, username)
  WHERE username IS NOT NULL;
