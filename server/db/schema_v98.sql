-- schema_v98.sql
-- Cash counts (Kasa Sayımı / Gün Sonu mutabakat) table for Sync V4

CREATE TABLE IF NOT EXISTS cash_counts (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
  count_date DATE NOT NULL,
  opening_balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  counted_cash NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  expected_cash NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  difference NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  notes TEXT,
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_cash_counts_company_date ON cash_counts(company_id, count_date);

ALTER TABLE cash_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_counts FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cash_counts' AND policyname = 'tenant_isolation'
  ) THEN
    CREATE POLICY tenant_isolation ON cash_counts
      USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
  END IF;
END $$;
