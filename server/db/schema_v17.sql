-- Migration v17: Add UNIQUE constraint on subscriptions.company_id
-- Required for ON CONFLICT (company_id) DO UPDATE to work in mock-checkout-callback
-- Uses DO $$ block to safely skip if already exists

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'subscriptions_company_id_unique'
      AND conrelid = 'subscriptions'::regclass
  ) THEN
    ALTER TABLE subscriptions
      ADD CONSTRAINT subscriptions_company_id_unique UNIQUE (company_id);
  END IF;
END $$;
