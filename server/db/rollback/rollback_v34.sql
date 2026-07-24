-- server/db/rollback/rollback_v34.sql
-- Revert grace period configuration

ALTER TABLE subscriptions DROP COLUMN IF EXISTS grace_hours_override;
ALTER TABLE plans DROP COLUMN IF EXISTS offline_grace_hours;
