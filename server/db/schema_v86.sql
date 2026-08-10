-- Transaction-scoped proof of pre-information and distance-sales terms acceptance.
CREATE TABLE IF NOT EXISTS billing_legal_acceptances (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  quote_id VARCHAR(100),
  invoice_id VARCHAR(100) REFERENCES invoices(id) ON DELETE RESTRICT,
  channel VARCHAR(30) NOT NULL CHECK (channel IN ('bank_transfer','card')),
  pre_information_version VARCHAR(40) NOT NULL,
  distance_sales_version VARCHAR(40) NOT NULL,
  ip_address VARCHAR(100),
  user_agent VARCHAR(500),
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE billing_legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_legal_acceptances FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS billing_legal_acceptances_tenant ON billing_legal_acceptances;
CREATE POLICY billing_legal_acceptances_tenant ON billing_legal_acceptances
  FOR ALL USING (company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true')
  WITH CHECK (company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true');
CREATE INDEX IF NOT EXISTS idx_billing_legal_acceptances_invoice ON billing_legal_acceptances(invoice_id);
