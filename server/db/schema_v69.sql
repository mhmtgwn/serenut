-- Durable commercial/notification invariants.

ALTER TABLE notification_queue
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_notification_outbox_dispatch
  ON notification_queue (status, next_retry_at, created_at)
  WHERE status IN ('pending', 'queued', 'retrying');

-- One provider transaction can settle one invoice only once. This is the
-- durable replay boundary for card callbacks and reconciliation workers.
CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_gateway_reference
  ON invoices (payment_gateway_reference)
  WHERE payment_gateway_reference IS NOT NULL;

ALTER TABLE invoices
  DROP CONSTRAINT IF EXISTS chk_invoice_amount_non_negative;
ALTER TABLE invoices
  ADD CONSTRAINT chk_invoice_amount_non_negative CHECK (amount >= 0) NOT VALID;

ALTER TABLE subscriptions
  DROP CONSTRAINT IF EXISTS chk_subscription_period;
ALTER TABLE subscriptions
  ADD CONSTRAINT chk_subscription_period CHECK (current_period_end > current_period_start) NOT VALID;

ALTER TABLE license_entitlements
  DROP CONSTRAINT IF EXISTS chk_entitlement_period;
ALTER TABLE license_entitlements
  ADD CONSTRAINT chk_entitlement_period CHECK (valid_until > valid_from) NOT VALID;

ALTER TABLE sale_items
  DROP CONSTRAINT IF EXISTS chk_sale_items_amounts;
ALTER TABLE sale_items
  ADD CONSTRAINT chk_sale_items_amounts CHECK (
    quantity > 0 AND unit_price >= 0 AND subtotal >= 0
  ) NOT VALID;
