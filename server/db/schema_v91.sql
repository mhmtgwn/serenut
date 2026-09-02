-- schema_v91.sql
-- Fix: Add missing RLS policies for user_recovery_codes, password_recovery_requests
-- and password_security_events tables introduced in schema_v77.
-- These tables had RLS enabled (with FORCE) but no policies were defined,
-- causing all INSERTs/UPDATEs (including bypass_rls admin paths) to be rejected.

-- user_recovery_codes: user-scoped (no company_id column, access via user_id)
DROP POLICY IF EXISTS rls_user_recovery_codes ON user_recovery_codes;
CREATE POLICY rls_user_recovery_codes ON user_recovery_codes
  FOR ALL
  USING (
    current_setting('app.bypass_rls', true) = 'true'
    OR user_id IN (
      SELECT id FROM users WHERE company_id = current_tenant_id()
    )
  )
  WITH CHECK (
    current_setting('app.bypass_rls', true) = 'true'
    OR user_id IN (
      SELECT id FROM users WHERE company_id = current_tenant_id()
    )
  );

-- password_recovery_requests: has company_id column
DROP POLICY IF EXISTS rls_password_recovery_requests ON password_recovery_requests;
CREATE POLICY rls_password_recovery_requests ON password_recovery_requests
  FOR ALL
  USING (
    company_id = current_tenant_id()
    OR current_setting('app.bypass_rls', true) = 'true'
  )
  WITH CHECK (
    company_id = current_tenant_id()
    OR current_setting('app.bypass_rls', true) = 'true'
  );

-- password_security_events: has company_id column
DROP POLICY IF EXISTS rls_password_security_events ON password_security_events;
CREATE POLICY rls_password_security_events ON password_security_events
  FOR ALL
  USING (
    company_id = current_tenant_id()
    OR current_setting('app.bypass_rls', true) = 'true'
  )
  WITH CHECK (
    company_id = current_tenant_id()
    OR current_setting('app.bypass_rls', true) = 'true'
  );
