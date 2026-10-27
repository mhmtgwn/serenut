-- schema_v101.sql
-- GİB E-Arşiv Invoices table for Sync V4 cloud replication

CREATE TABLE IF NOT EXISTS gib_invoices (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
  gib_uuid VARCHAR(100),
  invoice_number VARCHAR(100),
  sale_id VARCHAR(100),
  customer_id VARCHAR(100),
  recipient_json JSONB,
  items_json JSONB,
  total_without_vat NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  total_vat NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  invoice_type VARCHAR(50) NOT NULL DEFAULT 'SATIS',
  status VARCHAR(50) NOT NULL DEFAULT 'draft',
  note TEXT,
  html_content TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  signed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_gib_invoices_company ON gib_invoices(company_id);
CREATE INDEX IF NOT EXISTS idx_gib_invoices_sale ON gib_invoices(company_id, sale_id);
CREATE INDEX IF NOT EXISTS idx_gib_invoices_customer ON gib_invoices(company_id, customer_id);

ALTER TABLE gib_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE gib_invoices FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'gib_invoices' AND policyname = 'tenant_isolation'
  ) THEN
    CREATE POLICY tenant_isolation ON gib_invoices
      USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
  END IF;
END $$;
