-- server/db/schema_v31.sql
-- Monotonically increasing version field on companies table for optimistic concurrency control

ALTER TABLE companies ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
