CREATE TABLE IF NOT EXISTS billing_quotes (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  plan_id VARCHAR(100) NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
  billing_period VARCHAR(20) NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  currency VARCHAR(10) NOT NULL,
  snapshot JSONB NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  consumed_by_invoice_id VARCHAR(100) UNIQUE REFERENCES invoices(id) ON DELETE RESTRICT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_quote_period CHECK (billing_period IN ('monthly','yearly')),
  CONSTRAINT chk_quote_amount CHECK (amount >= 0)
);
CREATE INDEX IF NOT EXISTS idx_billing_quotes_company_expiry
  ON billing_quotes(company_id,expires_at DESC);

ALTER TABLE billing_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_quotes FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON billing_quotes;
CREATE POLICY tenant_isolation ON billing_quotes FOR ALL USING (
  company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true'
);
