ALTER TABLE companies ADD COLUMN IF NOT EXISTS logo_url VARCHAR(500);
SELECT column_name FROM information_schema.columns WHERE table_name='companies' AND column_name='logo_url';
