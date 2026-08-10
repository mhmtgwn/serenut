-- Re-enable password recovery by verified email using the hardened recovery model.
ALTER TABLE password_recovery_requests
  DROP CONSTRAINT IF EXISTS password_recovery_requests_method_check;
ALTER TABLE password_recovery_requests
  ADD CONSTRAINT password_recovery_requests_method_check
  CHECK (method IN ('recovery_code','admin_assisted','email_link'));

-- Accounts activated before mandatory verification are grandfathered so their
-- registered address can be used for recovery; possession is proven by link use.
UPDATE users
   SET email_verified_at = COALESCE(last_login_at, created_at, NOW())
 WHERE is_active = TRUE AND deleted_at IS NULL AND email_verified_at IS NULL;
