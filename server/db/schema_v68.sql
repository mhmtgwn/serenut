-- Canonical billing lifecycle metadata and cleanup support.
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS billing_interval VARCHAR(20) NOT NULL DEFAULT 'monthly'
  CHECK (billing_interval IN ('monthly', 'yearly'));
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

UPDATE invoices SET expires_at = COALESCE(expires_at, created_at + INTERVAL '48 hours')
WHERE status = 'pending' AND expires_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_pending_expiry ON invoices(expires_at)
  WHERE status = 'pending';
