-- server/db/schema_v18.sql
-- Serenut OS — Add signature column to app_versions for cryptographically signed OTA updates
ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS signature TEXT;
