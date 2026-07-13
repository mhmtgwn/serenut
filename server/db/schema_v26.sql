-- server/db/schema_v26.sql
-- Serenut OS -- Commercial Lifecycle V3 -- Phase 1 (Security Fixes, RLS, Device Token Version, Activation Challenge)

-- ── 1. ENABLE ROW LEVEL SECURITY ─────────────────────────────────────────────
ALTER TABLE license_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE license_entitlements FORCE ROW LEVEL SECURITY;

ALTER TABLE device_activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_activations FORCE ROW LEVEL SECURITY;

ALTER TABLE payment_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_bank_accounts FORCE ROW LEVEL SECURITY;

ALTER TABLE bank_transfer_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_transfer_notifications FORCE ROW LEVEL SECURITY;

-- ── 2. CREATE RLS POLICIES ───────────────────────────────────────────────────

-- Drop existing if any
DROP POLICY IF EXISTS tenant_isolation ON license_entitlements;
DROP POLICY IF EXISTS tenant_isolation ON device_activations;
DROP POLICY IF EXISTS sysadmin_only ON payment_bank_accounts;
DROP POLICY IF EXISTS tenant_isolation ON bank_transfer_notifications;

-- tenant_isolation on license_entitlements
CREATE POLICY tenant_isolation ON license_entitlements
  FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

-- tenant_isolation on device_activations
CREATE POLICY tenant_isolation ON device_activations
  FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

-- sysadmin_only or authenticated read on payment_bank_accounts
CREATE POLICY tenant_isolation ON payment_bank_accounts
  FOR ALL USING (current_setting('app.bypass_rls', true) = 'true' OR current_tenant_id() IS NOT NULL);

-- tenant_isolation on bank_transfer_notifications
CREATE POLICY tenant_isolation ON bank_transfer_notifications
  FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

-- ── 3. COLUMNS FOR TWO-TIER REVOKE & ACTIVATION CHALLENGE ────────────────────
ALTER TABLE device_activations ADD COLUMN IF NOT EXISTS device_token_version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE license_entitlements ADD COLUMN IF NOT EXISTS activation_challenge VARCHAR(64);
ALTER TABLE license_entitlements ADD COLUMN IF NOT EXISTS activation_challenge_expires_at TIMESTAMP WITH TIME ZONE;
