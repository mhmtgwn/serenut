-- Align the canonical financial ledger with the Sync V4 wire contract.
-- These fields are presentation/enrichment metadata; monetary columns remain
-- immutable once a ledger row has been accepted.
ALTER TABLE financial_transactions
  ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE financial_transactions
  ADD COLUMN IF NOT EXISTS metadata JSONB;

ALTER TABLE financial_transactions
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50);

-- Reject non-finite/negative financial facts at the database boundary. NOT
-- VALID keeps the migration deployable on legacy datasets; new writes are
-- checked immediately and the constraints can be validated after remediation.
ALTER TABLE financial_transactions
  DROP CONSTRAINT IF EXISTS chk_financial_amounts_non_negative;
ALTER TABLE financial_transactions
  ADD CONSTRAINT chk_financial_amounts_non_negative CHECK (
    amount >= 0 AND paid_amount >= 0 AND debt_amount >= 0
  ) NOT VALID;

ALTER TABLE sales
  DROP CONSTRAINT IF EXISTS chk_sales_amounts_valid;
ALTER TABLE sales
  ADD CONSTRAINT chk_sales_amounts_valid CHECK (
    total_amount >= 0 AND paid_amount >= 0 AND paid_amount <= total_amount
  ) NOT VALID;
