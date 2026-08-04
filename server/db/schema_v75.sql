ALTER TABLE invoices ADD COLUMN IF NOT EXISTS verification_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS next_verification_at TIMESTAMPTZ;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS verification_error TEXT;
CREATE INDEX IF NOT EXISTS idx_invoices_card_verification
  ON invoices(next_verification_at)
  WHERE status='verification_pending';
