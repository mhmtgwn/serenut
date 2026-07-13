-- server/db/schema_v29.sql
-- Add central company profile fields and user token version for instant authorization invalidation

ALTER TABLE companies ADD COLUMN IF NOT EXISTS owner_name VARCHAR(150);
ALTER TABLE companies ADD COLUMN IF NOT EXISTS type VARCHAR(100);
ALTER TABLE companies ADD COLUMN IF NOT EXISTS city VARCHAR(100);
ALTER TABLE companies ADD COLUMN IF NOT EXISTS district VARCHAR(100);
ALTER TABLE companies ADD COLUMN IF NOT EXISTS currency VARCHAR(20) DEFAULT '₺';
ALTER TABLE companies ADD COLUMN IF NOT EXISTS logo_url VARCHAR(500);

ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER DEFAULT 1 NOT NULL;
