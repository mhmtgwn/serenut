-- server/db/schema_v34.sql
-- Add canonical offline grace period configuration

ALTER TABLE plans ADD COLUMN IF NOT EXISTS offline_grace_hours INTEGER DEFAULT 72;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS grace_hours_override INTEGER;
