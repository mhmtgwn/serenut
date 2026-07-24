-- server/db/rollback/rollback_v9.sql
-- Rollback migration version 9
ALTER TABLE users DROP COLUMN IF EXISTS reset_token;
ALTER TABLE users DROP COLUMN IF EXISTS reset_token_expires_at;
