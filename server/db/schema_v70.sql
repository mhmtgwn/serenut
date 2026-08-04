-- Immutable payment evidence and invoice-to-entitlement grant linkage.

CREATE TABLE IF NOT EXISTS payment_transactions (
  id VARCHAR(100) PRIMARY KEY,
  invoice_id VARCHAR(100) NOT NULL UNIQUE REFERENCES invoices(id) ON DELETE RESTRICT,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  channel VARCHAR(30) NOT NULL,
  provider_transaction_id VARCHAR(255),
  amount DECIMAL(12,2) NOT NULL,
  currency VARCHAR(10) NOT NULL,
  status VARCHAR(30) NOT NULL,
  evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  verified_by VARCHAR(100),
  verified_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_payment_amount_positive CHECK (amount > 0),
  CONSTRAINT chk_payment_status CHECK (status IN ('succeeded','reversed')),
  CONSTRAINT chk_payment_channel CHECK (channel IN ('card','bank_transfer','admin_grant'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_provider_transaction
  ON payment_transactions(provider_transaction_id)
  WHERE provider_transaction_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS commercial_entitlement_grants (
  invoice_id VARCHAR(100) PRIMARY KEY REFERENCES invoices(id) ON DELETE RESTRICT,
  payment_id VARCHAR(100) NOT NULL UNIQUE REFERENCES payment_transactions(id) ON DELETE RESTRICT,
  subscription_id VARCHAR(100) NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
  entitlement_id VARCHAR(100) NOT NULL UNIQUE REFERENCES license_entitlements(id) ON DELETE RESTRICT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transactions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON payment_transactions;
CREATE POLICY tenant_isolation ON payment_transactions FOR ALL USING (
  company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true'
);
