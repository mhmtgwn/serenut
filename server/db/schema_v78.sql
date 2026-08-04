-- Legacy email reset tokens are intentionally invalidated. Password recovery
-- now lives exclusively in password_recovery_requests with hashed,
-- single-use authorization material and a complete audit trail.
ALTER TABLE users DROP COLUMN IF EXISTS reset_token;
ALTER TABLE users DROP COLUMN IF EXISTS reset_token_expires_at;
